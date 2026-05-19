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
- files touched: `onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/Zapper.sol`, `onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/interfaces/IBatcher.sol`, `onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/interfaces/IVault.sol`, plus OZ `IERC20.sol`, `SafeERC20.sol`, `Address.sol`, `ReentrancyGuard.sol`
- files revisited / highest-attention files: `src/Zapper.sol` was the clear focus; interfaces and OZ token helpers were used to validate behavior assumptions
- main issue directions investigated: caller-controlled approvals vs arbitrary call targets, unchecked ERC20 return values, non-zero-to-non-zero approval behavior, native ETH overpayment retention, and `zapOut` relying on nominal rather than actually received withdrawal amounts
- promising but not retained directions: no clearly separate non-retained issue direction is visible beyond the final retained set

## Agent: opencode_1
- files touched: `onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/Zapper.sol`, `onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/interfaces/IBatcher.sol`, `onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/interfaces/IVault.sol`
- files revisited / highest-attention files: `src/Zapper.sol` dominated attention; interfaces were read but not deeply expanded in the visible log
- main issue directions investigated: unchecked ERC20 transfers/approvals, approval reset behavior for zero-first tokens, withdrawal/slippage handling in `zapOut`, and excess native ETH retention
- promising but not retained directions: `sweep()` zero-address/governance handling, missing event emission for governance sweeps, low-level call success semantics, and floating pragma concerns were raised but not retained after merge

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `src/Zapper.sol`, especially zap-in/zap-out token movement, approval handling, and residual-fund edge cases
- notable differences in attention: codex_1 widened into OZ helper semantics and the allowanceTarget/swapTarget mismatch; opencode_1 surfaced more governance/sweep hygiene and reporting-style issues that were later dropped
- underexplored but suspicious files/functions if clearly supported by the logs: `IBatcher.completeWithdrawalWithZap` and the `zapOut` handoff around actual-vs-requested amounts remain comparatively lightly explored relative to how much impact they have on retained concerns

## Retained Findings
- retained issues centered on `Zapper.sol`: persistent attacker-planted allowances, unchecked ERC20 return values, zero-first token approval DoS, trapped excess native ETH, and `zapOut` using requested rather than actually delivered withdrawal amounts


Output only markdown.
