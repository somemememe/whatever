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

Finding:
- title: Redemption write-off shortfalls are silently discarded on undercollateralized borrowers
- claim: `redeemCollateral()` removes real collateral from the pair immediately and only mints non-claimable `redemptionWriteOff` rewards to socialize that loss later. When a borrower is eventually synced, `_syncUserRedemptions()` converts their accrued write-off into a collateral deduction but caps the result at zero. If a borrower has less remaining collateral than the write-off allocated to their borrow shares, the uncovered portion is simply erased instead of being preserved as bad debt or charged elsewhere.
- impact: After a redemption against a pool that already contains undercollateralized borrowers, aggregate user collateral accounting can stay above the pair's real collateral balance. That accounting hole lets earlier withdrawers/liquidations consume collateral that should have absorbed the missing write-off, pushing losses onto later users or protocol insurance and creating hidden insolvency.
- exploit_paths: ["A borrower becomes undercollateralized before liquidation, so their `_userCollateralBalance` is already smaller than the collateral haircut implied by their debt share.", "A redemption executes and transfers collateral out of the pair, then mints `redemptionWriteOff` instead of debiting each borrower inline.", "When the undercollateralized borrower is later checkpointed, `_calcRewardIntegral()` allocates write-off rewards by borrow shares and `_syncUserRedemptions()` computes `rTokens`.", "If `rTokens` exceeds that account's remaining collateral, `_userCollateralBalance` is floored to zero and the excess write-off disappears.", "The pair's summed user collateral balances now exceed actual collateral by the discarded amount, enabling over-withdrawal until the shortfall surfaces as protocol bad debt."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
}

interface IResupplyRegistryMinimal {
    function token() external view returns (address);
    function liquidationHandler() external view returns (address);
    function redemptionHandler() external view returns (address);
}

interface IResupplyPairMinimal {
    function registry() external view returns (address);
    function collateral() external view returns (address);
    function underlying() external view returns (address);
    function maxLTV() external view returns (uint256);
    function mintFee() external view returns (uint256);
    function minimumRedemption() external view returns (uint256);
    function protocolRedemptionFee() external view returns (uint256);
    function totalBorrow() external view returns (uint128 amount, uint128 shares);
    function exchangeRateInfo() external view returns (address oracle, uint96 lastTimestamp, uint256 exchangeRate);
}

contract FlawVerifier {
    uint256 private constant LTV_PRECISION = 1e5;
    uint256 private constant LIQ_PRECISION = 1e5;

    address public constant TARGET_PAIR = 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6;

    address private _profitToken;
    uint256 private _profitAmount;
    bool public executed;
    bool public hypothesisValidated;

    address public registry;
    address public debtToken;
    address public collateralToken;
    address public underlyingToken;
    address public liquidationHandler;
    address public redemptionHandler;

    uint256 public observedMaxLTV;
    uint256 public observedMintFee;
    uint256 public observedMinimumRedemption;
    uint256 public observedProtocolRedemptionFee;
    uint256 public observedExchangeRate;
    uint256 public observedTotalBorrowAmount;
    uint256 public observedTotalBorrowShares;

    uint256 public maxSelfRedeemCollateralPerUnitCollateralNum;
    uint256 public maxSelfRedeemCollateralPerUnitCollateralDen;

    string public outcome;

    constructor() {}

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        IResupplyPairMinimal pair = IResupplyPairMinimal(TARGET_PAIR);
        registry = pair.registry();
        collateralToken = pair.collateral();
        underlyingToken = pair.underlying();
        observedMaxLTV = pair.maxLTV();
        observedMintFee = pair.mintFee();
        observedMinimumRedemption = pair.minimumRedemption();
        observedProtocolRedemptionFee = pair.protocolRedemptionFee();
        (, , observedExchangeRate) = pair.exchangeRateInfo();
        (uint128 borrowAmount, uint128 borrowShares) = pair.totalBorrow();
        observedTotalBorrowAmount = uint256(borrowAmount);
        observedTotalBorrowShares = uint256(borrowShares);

        IResupplyRegistryMinimal reg = IResupplyRegistryMinimal(registry);
        debtToken = reg.token();
        liquidationHandler = reg.liquidationHandler();
        redemptionHandler = reg.redemptionHandler();
        _profitToken = debtToken;

        // Path stage 1 from the finding requires an already-undercollateralized borrower before liquidation.
        // A fresh attacker cannot manufacture that state using only the pair's public borrow/remove paths:
        // - `borrow()` and `leveragedPosition()` are guarded by `isSolvent(msg.sender)` after execution.
        // - `removeCollateral()` and `removeCollateralVault()` are also guarded by `isSolvent(msg.sender)`.
        // Therefore a new attacker account must remain solvent after any self-created position.
        //
        // Let posted collateral be C collateral-shares and borrowed debt tokens be B.
        // The pair enforces:
        //      B * (LIQ_PRECISION + mintFee) / LIQ_PRECISION * exchangeRate <= C * maxLTV / LTV_PRECISION.
        // Even if the attacker later redeems *all* self-borrowed debt tokens and assumes 100% of borrow shares,
        // redeemed collateral cannot exceed B * exchangeRate. Combining both inequalities gives:
        //      redeemedCollateral / C <= maxLTV * LIQ_PRECISION / (LTV_PRECISION * (LIQ_PRECISION + mintFee)) <= 1.
        // Strict inequality holds whenever `maxLTV < 1e5` or `mintFee > 0`, which is enough to prevent
        // `_syncUserRedemptions()` from flooring the attacker's own collateral to zero with excess write-off.
        // So the required stage-1 precondition cannot be self-created from a fresh account.
        maxSelfRedeemCollateralPerUnitCollateralNum = observedMaxLTV * LIQ_PRECISION;
        maxSelfRedeemCollateralPerUnitCollateralDen = LTV_PRECISION * (LIQ_PRECISION + observedMintFee);

        if (observedTotalBorrowAmount < observedMinimumRedemption) {
            outcome = "refuted: pair debt below minimum redemption; exploit path cannot start";
            hypothesisValidated = false;
            _profitAmount = 0;
            return;
        }

        if (maxSelfRedeemCollateralPerUnitCollateralNum <= maxSelfRedeemCollateralPerUnitCollateralDen) {
            outcome = "refuted: fresh attacker cannot create the required undercollateralized borrower state";
            hypothesisValidated = false;
            _profitAmount = 0;
            return;
        }

        // This branch is unreachable for standard pair parameters, but remains for completeness.
        // The finding's remaining stages still require a concrete undercollateralized borrower address whose
        // accrued write-off exceeds remaining collateral. The pair stores no enumerable borrower set, so with
        // only the provided target-pair input and no historical-log oracle inside Solidity, the PoC cannot
        // deterministically identify such an address on-chain.
        outcome = "refuted: required borrower target is not discoverable from pair state alone";
        hypothesisValidated = false;
        _profitAmount = 0;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function profitAchieved() external view returns (bool) {
        return _profitAmount > 0;
    }

    function exploitPath() external pure returns (string memory) {
        return "Path-strict attempt: self-create undercollateralized borrower -> redeem -> sync write-off -> realize shortfall; mechanically infeasible because solvency guards cap self-redeem write-off below posted collateral";
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: _usercollateralbalance, redemptionwriteoff, _calcrewardintegral(), rtokens, withdraw; generated code does not cover paths indexes: 3, 4
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
