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
pragma solidity ^0.8.20;

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

    bool public pathStage1RequiresExistingUndercollateralizedBorrower;
    bool public pathStage2RedeemCollateralRemovesRealAssets;
    bool public pathStage3CheckpointUsesCalcRewardIntegral;
    bool public pathStage4ExcessWriteOffCanDisappear;
    bool public pathStage5HoleNeedsLaterWithdraw;

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

        pathStage1RequiresExistingUndercollateralizedBorrower = true;
        pathStage2RedeemCollateralRemovesRealAssets = true;
        pathStage3CheckpointUsesCalcRewardIntegral = true;
        pathStage4ExcessWriteOffCanDisappear = true;
        pathStage5HoleNeedsLaterWithdraw = true;

        // Exploit path alignment, in the same causal order as the finding:
        // 1) An already-underwater borrower must exist such that _usercollateralbalance is
        //    already smaller than the redemption haircut allocated by debt shares.
        // 2) redeemCollateral() removes real collateral immediately, then mints redemptionwriteoff
        //    instead of debiting every borrower inline.
        // 3) When that borrower is checkpointed, _calcrewardintegral() updates claimable rewards;
        //    _syncUserRedemptions() then converts the non-claimable reward into rtokens.
        // 4) If rtokens exceeds remaining _usercollateralbalance, the assignment floors the borrower
        //    to zero and the excess write-off disappears instead of persisting as bad debt.
        // 5) The accounting hole is only monetized by a later user action such as removeCollateral /
        //    vault withdraw / liquidation consuming collateral before the hidden shortfall is socialized.
        //
        // This verifier keeps that ordering intact. It does not claim a profit path unless the required
        // pre-existing underwater borrower can be created or discovered using only realistic public actions.

        // A fresh attacker cannot self-create stage 1 using only public pair entrypoints.
        // Solvency checks after borrow()/leveragedPosition() and after collateral-removal paths prevent
        // the attacker from ending with a position where later self-redemption makes rtokens exceed the
        // attacker's own _usercollateralbalance.
        //
        // Let posted collateral be C and borrowed debt be B.
        // Pair solvency enforces:
        //   B * (LIQ_PRECISION + mintFee) / LIQ_PRECISION * exchangeRate <= C * maxLTV / LTV_PRECISION.
        // Even if the attacker later redeems all self-created debt and all redemptionwriteoff accrues back
        // to the same borrower, freed collateral is at most B * exchangeRate, so:
        //   freedCollateral / C <= maxLTV * LIQ_PRECISION / (LTV_PRECISION * (LIQ_PRECISION + mintFee)).
        // For standard pair parameters this ratio is <= 1, so the self-created borrower cannot reach the
        // stage where rtokens exceeds remaining collateral and gets floored.
        maxSelfRedeemCollateralPerUnitCollateralNum = observedMaxLTV * LIQ_PRECISION;
        maxSelfRedeemCollateralPerUnitCollateralDen = LTV_PRECISION * (LIQ_PRECISION + observedMintFee);

        if (observedTotalBorrowAmount < observedMinimumRedemption) {
            outcome = "refuted: redeemCollateral cannot start because total debt is below minimumRedemption";
            hypothesisValidated = false;
            _profitAmount = 0;
            return;
        }

        if (maxSelfRedeemCollateralPerUnitCollateralNum <= maxSelfRedeemCollateralPerUnitCollateralDen) {
            // Stages 2-5 are real protocol mechanics, but stage 1 is not attacker-creatable from a fresh account.
            // Without that precursor borrower, there is no honest path to later withdraw value from the accounting hole.
            outcome = "refuted: stages redeemCollateral -> redemptionWriteOff -> _calcRewardIntegral() -> rTokens -> withdraw exist, but a fresh attacker cannot create the required pre-existing undercollateralized borrower";
            hypothesisValidated = false;
            _profitAmount = 0;
            return;
        }

        // Completeness branch:
        // If pair parameters ever made self-creation algebraically possible, a concrete borrower whose
        // checkpoint would floor _userCollateralBalance would still be needed. That address is not enumerable
        // from the exposed pair interface, and this verifier is constrained to on-chain state already present
        // in the workspace without off-chain borrower discovery. Therefore the later monetization step
        // (another account's removeCollateral / vault withdraw / liquidation) cannot be targeted deterministically.
        outcome = "refuted: full path remains non-executable here because the qualifying underwater borrower needed for the later withdraw realization is not discoverable from exposed pair state alone";
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
        return "Ordered path: existing underwater borrower with low _usercollateralbalance -> redeemCollateral transfers out real collateral and mints redemptionwriteoff -> checkpoint calls _calcRewardIntegral() and converts rewards into rtokens -> excess rtokens are floored away at zero -> a later withdraw/liquidation can over-consume collateral; this verifier refutes exploitability from a fresh attacker because stage 1 cannot be self-created and the needed borrower is not discoverable from exposed pair state alone";
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.26s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:68:19:
   |
68 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 491772)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 577021548053172
  AUDITHOUND_BALANCE_AFTER_WEI: 577021548053172
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 100000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x57aB1E0003F623289CD798B1824Be09a793e4Bec
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 11171

Traces:
  [491772] FlawVerifierTest::testExploit()
    ├─ [2499] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [451161] FlawVerifier::executeOnOpportunity()
    │   ├─ [1007] 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6::registry() [staticcall]
    │   │   └─ ← [Return] 0x10101010E0C3171D894B71B3400668aF311e7D94
    │   ├─ [1909] 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6::collateral() [staticcall]
    │   │   └─ ← [Return] 0x01144442fba7aDccB5C9DC9cF33dd009D50A9e1D
    │   ├─ [853] 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6::underlying() [staticcall]
    │   │   └─ ← [Return] 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E
    │   ├─ [4145] 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6::maxLTV() [staticcall]
    │   │   └─ ← [Return] 95000 [9.5e4]
    │   ├─ [2429] 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6::mintFee() [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [3331] 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6::minimumRedemption() [staticcall]
    │   │   └─ ← [Return] 100000000000000000000 [1e20]
    │   ├─ [3573] 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6::protocolRedemptionFee() [staticcall]
    │   │   └─ ← [Return] 500000000000000000 [5e17]
    │   ├─ [6380] 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6::exchangeRateInfo() [staticcall]
    │   │   └─ ← [Return] 0xcb7E25fbbd8aFE4ce73D7Dac647dbC3D847F3c82, 1750897127 [1.75e9], 1000000000000000000000 [1e21]
    │   ├─ [3241] 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6::totalBorrow() [staticcall]
    │   │   └─ ← [Return] 0, 0
    │   ├─ [1244] 0x10101010E0C3171D894B71B3400668aF311e7D94::token() [staticcall]
    │   │   └─ ← [Return] 0x57aB1E0003F623289CD798B1824Be09a793e4Bec
    │   ├─ [3198] 0x10101010E0C3171D894B71B3400668aF311e7D94::liquidationHandler() [staticcall]
    │   │   └─ ← [Return] 0x88888888c227c36401493Ed9F3e3Dcc3800B2634
    │   ├─ [3267] 0x10101010E0C3171D894B71B3400668aF311e7D94::redemptionHandler() [staticcall]
    │   │   └─ ← [Return] 0x9999999b8ce70322b021EFe340759B7958af43C8
    │   └─ ← [Stop]
    ├─ [499] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x57aB1E0003F623289CD798B1824Be09a793e4Bec
    ├─ [2891] 0x57aB1E0003F623289CD798B1824Be09a793e4Bec::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x57aB1E0003F623289CD798B1824Be09a793e4Bec)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 22785460 [2.278e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 11171 [1.117e4])
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 2.59s (142.11ms CPU time)

Ran 1 test suite in 2.62s (2.59s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 491772)

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
