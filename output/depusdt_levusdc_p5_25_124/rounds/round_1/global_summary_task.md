You maintain a concise global audit memory for future audit agents.

Update the existing global memory by folding in durable observations from the
latest round summary. The goal is an accumulated cross-round audit view, not a
per-round recap.

This memory is optional context only. Findings are stored separately.

Write the updated memory in this exact structure:

# Global Audit Memory

## Scope Touched
- files/contracts/flows that have mattered across rounds, with short issue-direction notes

## Issue Directions Seen
- recurring or promising vulnerability directions seen across the audit

## Useful Context
- compact cross-round observations 

Rules:
- keep it compact
- preserve useful prior context while integrating new durable observations
- prefer stable cross-round patterns over latest-round details
- fold repeated wording into a single clearer observation
- keep the memory descriptive rather than prescriptive

## Existing Global Memory
No global memory yet.

## Latest Round Summary
# Round 1 Summary

## Agent: codex_1
- files touched: `contracts/DepToken.sol`, `contracts/DepositWithdraw.sol`, `contracts/CurveSwap.sol`, `contracts/DepErc20.sol`, `contracts/DepTokenInterfaces.sol`, `contracts/LevTokenInterfaces.sol`, `contracts/CurveContractInterface.sol`, `contracts/MatrixpricerInterface.sol`, `contracts/TensorpricerInterface.sol`, `contracts/ErrorReporter.sol`, `contracts/ExponentialNoError.sol`, `contracts/vendor/interfaces/IRegistry.sol`, `contracts/vendor/interfaces/SafeERC20.sol`, `contracts/import.sol`
- files revisited / highest-attention files: `contracts/DepToken.sol` (explicitly revisited, especially repay/redeem paths), `contracts/DepositWithdraw.sol`, `contracts/CurveSwap.sol`
- main issue directions investigated: public token approval surface on `CurveSwap` inherited into the live market; Compound redeem failure handling during redemptions; zero-min-output Curve swap usage in borrow/repay refund flows; ignored Compound mint errors leading to stale allowance and later supply-path DoS
- promising but not retained directions: none clearly shown beyond the retained set

## Agent: opencode_1
- files touched: `contracts/DepToken.sol`, `contracts/DepositWithdraw.sol`, `contracts/CurveSwap.sol`, `contracts/DepErc20.sol`, `contracts/DepTokenInterfaces.sol`, `contracts/LevTokenInterfaces.sol`, `contracts/CurveContractInterface.sol`, `contracts/MatrixpricerInterface.sol`, `contracts/TensorpricerInterface.sol`, `contracts/ErrorReporter.sol`, `contracts/ExponentialNoError.sol`, `contracts/vendor/interfaces/IRegistry.sol`, `contracts/import.sol`
- files revisited / highest-attention files: `contracts/DepToken.sol` (read twice), then `contracts/DepositWithdraw.sol` and `contracts/CurveSwap.sol`
- main issue directions investigated: Curve slippage exposure around swap calls; redemption behavior when external liquidity retrieval under-delivers; generic external-call / return-value handling around Compound and Curve; admin-controlled integration/pricer configuration; reentrancy/accounting concerns around `updateBorrowLedger`
- promising but not retained directions: `updateBorrowLedger` reentrancy, malicious-admin address-setting / timelock concerns, generic unchecked-return themes, precision / exchange-rate concerns, and “silent partial redemption” as a weaker framing of the retained redemption issue

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `DepToken.sol`, `DepositWithdraw.sol`, and `CurveSwap.sol`, especially Compound interaction paths and Curve swap flows tied to borrow/repay/redeem
- notable differences in attention: `codex_1` uniquely surfaced the public arbitrary-token approval drain and the stale-allowance Compound DoS; `opencode_1` spent more attention on admin/governance risk, reentrancy, and broader accounting/validation themes
- underexplored but suspicious files/functions if clearly supported by the logs: pricing/admin setter surfaces in `DepToken.sol` received some attention from `opencode_1`, but retained findings stayed focused on swap, approval, and Compound cash-management paths

## Retained Findings
- retained after merge: public arbitrary-token approval enabling direct asset theft; full DepToken burn despite failed/short Compound redemption; zero-slippage-protection Curve swaps enabling sandwich extraction; ignored Compound mint errors leaving stale allowance that can break later resupply flows


Output only markdown.
