# Merge View - Round 1

## Summary
- total findings: 3
- new findings: 3
- updated existing findings: 0
- rejected candidates: 9

## Finding Actions
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex_1,opencode_1 | Nominal reserve accounting breaks with fee-on-transfer, deflationary, or rebasing tokens and can be crystallized with `gulp()` | codex_1:0.673 Nominal-amount reserve accounting lets fee-on-transfer or rebasing tokens drain LP value |
| F-002 | rewritten_agent_signal | High | high | codex_1 | Underlying token transfers are trusted by boolean return value only, so a malicious bound token can fake deposits or payouts | codex_1:0.411 A single paused or blacklisting token can brick finalized pool exits and strand value |
| F-003 | rewritten_agent_signal | Medium | high | codex_1 | Finalized pools have no recovery path if a bound token later blocks transfers, which can strand LP value | codex_1:0.469 A malicious bound token can fake deposits because transfers are trusted by return value only |

## Rejection Reasons
- other: 7
- trust_or_owner_model: 1
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex_1 | BPT `approve` is vulnerable to the standard allowance race | Standard ERC20 allowance race condition; user-side approval workflow issue rather than a Balancer-specific protocol vulnerability. |
| other | codex_1 | BPT `transferFrom` emits an incorrect `Approval` event | Off-chain event/accounting inconsistency only; it does not create an on-chain loss, lockup, or manipulation path. |
| other | opencode_1 | Integer Overflow in bpow Approximation Function | `bpowi()` uses checked `bmul()` arithmetic, so overflow reverts rather than silently corrupting pricing. |
| other | opencode_1 | Unchecked External Call Return Value | The contract does check the returned boolean, and state-changing entrypoints are guarded by `_lock_`; the non-returning-ERC20 compatibility issue is not a separate reportable exploit here. |
| trust_or_owner_model | opencode_1 | Controller Can Manipulate Pool Parameters Arbitrarily | Privileged controller behavior is an explicit trust assumption of the design, not a code vulnerability. |
| unsupported_or_speculative | opencode_1 | Potential Division by Zero in bdiv | `bdiv()` explicitly checks `b != 0` and guards multiplication overflow; the stated silent-failure path is unsupported. |
| other | opencode_1 | Insufficient Slippage Protection in swapExactAmountIn | MEV/sandwich risk is not caused by a missing contract check here; users already supply `minAmountOut` and `maxPrice` bounds. |
| other | opencode_1 | Token Balance Desynchronization During Joins | If `transferFrom()` returns `false`, the `require` reverts and state rolls back; only the distinct 'returns true without transferring' case survives and is captured in F-002. |
| other | opencode_1 | Deprecated floating point in increaseApproval | `increaseApproval()` / `decreaseApproval()` use checked math and the claim does not identify a concrete exploitable path. |
