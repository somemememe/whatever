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
- Profit-maximization hard requirement:
  - MUST apply progressive loop amplification for repeatable exploit phases.
  - Start at 2 rounds, then increase one-by-one (2 -> 3 -> 4 -> 5 -> 6).
  - Continue increasing only if the new round count improves total net profit.
  - Stop at the first non-improving round count and keep the previous best result.
  - Prefer highest total profit over earliest passing implementation.

Finding:
- title: Fresh debt and replacement borrowers bypass opening collateral-ratio checks
- claim: The protocol defines an opening-collateral safeguard in `RiskLibrary.validateUserIsNotBelowOpeningLimitBorrowCR`, but none of the debt-origination paths invoke it before minting debt and moving cash. `sellCreditMarket` with `creditPositionId == RESERVED_ID` mints debt for `onBehalfOf` and pays out lender cash without checking the borrower's live collateral ratio; `buyCreditMarket` does the same when matching a borrower offer; and `liquidateWithReplacement` reassigns the full debt to `params.borrower` and mints debt tokens for them without enforcing `crOpening` or the user's custom `openingLimitBorrowCR`.
- impact: Borrowers can open or receive new debt while below the protocol's required opening collateral ratio, including with zero effective collateral. This lets them extract fresh borrow-side value that is not economically recoverable, leaving lenders with bad debt and enabling replacement liquidations to convert an otherwise valid liquidation into a newly unsecured loan.
- exploit_paths: ["A borrower calls `sellCreditMarket` with `creditPositionId == RESERVED_ID`, receives cash from a lender's borrow aToken balance, and no opening-CR check runs before `createDebtAndCreditPositions` mints debt.", "A lender calls `buyCreditMarket` against a borrower offer (`creditPositionId == RESERVED_ID`), opening debt for a borrower whose current collateral ratio is already below `crOpening` or their stricter user-defined opening limit.", "A privileged caller uses `liquidateWithReplacement`; after the old borrower is liquidated, the same `futureValue` is reminted onto `params.borrower` even if that replacement borrower has insufficient or no collateral."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface ILeverageUpTarget {
    function MAX_ITERATIONS() external view returns (uint256);
}

contract FlawVerifier {
    address internal constant TARGET = 0xF4a21Ac7e51d17A0e1C8B59f7a98bb7A97806f14;

    enum ValidationState {
        Unknown,
        InfeasibleAtProvidedInputs,
        Validated,
        Refuted
    }

    struct PathResult {
        bool attempted;
        bool feasible;
        bool succeeded;
        string reason;
    }

    event PathEvaluated(uint8 indexed pathId, bool feasible, bool succeeded, string reason);
    event Summary(address profitToken, uint256 profitAmount, ValidationState validationState, string exploitPathUsed);

    address private _profitToken;
    uint256 private _profitAmount;
    string private _exploitPathUsed;
    ValidationState private _validationState;

    PathResult private _sellCreditReservedIdPath;
    PathResult private _buyCreditReservedIdPath;
    PathResult private _liquidateWithReplacementPath;

    constructor() {
        _profitToken = address(0);
        _profitAmount = 0;
        _exploitPathUsed = "none";
        _validationState = ValidationState.Unknown;
    }

    function executeOnOpportunity() external {
        _profitToken = address(0);
        _profitAmount = 0;
        _exploitPathUsed = "none";

        bool targetExists = TARGET.code.length > 0;

        if (targetExists) {
            try ILeverageUpTarget(TARGET).MAX_ITERATIONS() returns (uint256) {
                // no-op: this confirms the supplied target address resolves to the expected LeverageUp contract.
            } catch {
                targetExists = false;
            }
        }

        // Path 1: sellCreditMarket with RESERVED_ID.
        // Concrete on-chain preconditions required for an executable PoC:
        // 1) a concrete Size market address,
        // 2) at least one lender address with a live compatible loan offer,
        // 3) enough lender borrow-aToken balance to fund the market order,
        // 4) the exact order parameters (tenor / APR bounds) for the fork block.
        // The supplied inputs expose only the LeverageUp periphery target source. They do not expose a market or
        // a discoverable registry address, and the Size protocol interfaces in scope do not provide an enumerable
        // user/orderbook surface from a cold start verifier.
        _sellCreditReservedIdPath = PathResult({
            attempted: true,
            feasible: false,
            succeeded: false,
            reason: targetExists
                ? "missing discoverable Size market/factory address and enumerable lender orderbook at fork block"
                : "supplied target address is not reachable on the fork"
        });
        emit PathEvaluated(1, _sellCreditReservedIdPath.feasible, _sellCreditReservedIdPath.succeeded, _sellCreditReservedIdPath.reason);

        // Path 2: buyCreditMarket with RESERVED_ID.
        // Additional concrete preconditions beyond Path 1:
        // 1) a borrower address with a live compatible borrow offer,
        // 2) a lender funding source or authorized operator context,
        // 3) exact matching order parameters at the fork block.
        // Those counterparties are likewise not enumerable from the supplied target-only context.
        _buyCreditReservedIdPath = PathResult({
            attempted: true,
            feasible: false,
            succeeded: false,
            reason: targetExists
                ? "missing discoverable Size market plus borrower-offer counterparty set at fork block"
                : "supplied target address is not reachable on the fork"
        });
        emit PathEvaluated(2, _buyCreditReservedIdPath.feasible, _buyCreditReservedIdPath.succeeded, _buyCreditReservedIdPath.reason);

        // Path 3: liquidateWithReplacement.
        // Concrete on-chain preconditions:
        // 1) a concrete Size market address,
        // 2) a specific ACTIVE liquidatable debtPositionId,
        // 3) a replacement borrower with a matching borrow offer,
        // 4) permission to call the protocol's permissioned liquidateWithReplacement entrypoint.
        // The supplied inputs do not include a market/factory/keeper identity, and the required debt-position set is
        // not discoverable from the target-only artifact set without off-chain enumeration.
        _liquidateWithReplacementPath = PathResult({
            attempted: true,
            feasible: false,
            succeeded: false,
            reason: targetExists
                ? "missing discoverable Size market, liquidatable debtPositionId set, and permissioned replacement-liquidation caller"
                : "supplied target address is not reachable on the fork"
        });
        emit PathEvaluated(
            3,
            _liquidateWithReplacementPath.feasible,
            _liquidateWithReplacementPath.succeeded,
            _liquidateWithReplacementPath.reason
        );

        // Because none of the three mandated paths can be executed from the provided target-only inputs without
        // inventing off-chain addresses or counterparties, this verifier records a concrete infeasibility result.
        _validationState = ValidationState.InfeasibleAtProvidedInputs;

        emit Summary(_profitToken, _profitAmount, _validationState, _exploitPathUsed);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function exploitPathUsed() external view returns (string memory) {
        return _exploitPathUsed;
    }

    function validationState() external view returns (ValidationState) {
        return _validationState;
    }

    function sellCreditReservedIdPath() external view returns (PathResult memory) {
        return _sellCreditReservedIdPath;
    }

    function buyCreditReservedIdPath() external view returns (PathResult memory) {
        return _buyCreditReservedIdPath;
    }

    function liquidateWithReplacementPath() external view returns (PathResult memory) {
        return _liquidateWithReplacementPath;
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.15s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:68:19:
   |
68 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 427970)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 577021548053172
  AUDITHOUND_BALANCE_AFTER_WEI: 577021548053172
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 100000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x0000000000000000000000000000000000000000
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001

Traces:
  [427970] FlawVerifierTest::testExploit()
    ├─ [2359] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [402562] FlawVerifier::executeOnOpportunity()
    │   ├─ [217] 0xF4a21Ac7e51d17A0e1C8B59f7a98bb7A97806f14::MAX_ITERATIONS() [staticcall]
    │   │   └─ ← [Return] 20
    │   ├─ emit PathEvaluated(pathId: 1, feasible: false, succeeded: false, reason: "missing discoverable Size market/factory address and enumerable lender orderbook at fork block")
    │   ├─ emit PathEvaluated(pathId: 2, feasible: false, succeeded: false, reason: "missing discoverable Size market plus borrower-offer counterparty set at fork block")
    │   ├─ emit PathEvaluated(pathId: 3, feasible: false, succeeded: false, reason: "missing discoverable Size market, liquidatable debtPositionId set, and permissioned replacement-liquidation caller")
    │   ├─ emit Summary(profitToken: 0x0000000000000000000000000000000000000000, profitAmount: 0, validationState: 1, exploitPathUsed: "none")
    │   └─ ← [Stop]
    ├─ [359] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 745.05ms (306.62µs CPU time)

Ran 1 test suite in 759.34ms (745.05ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 427970)

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
