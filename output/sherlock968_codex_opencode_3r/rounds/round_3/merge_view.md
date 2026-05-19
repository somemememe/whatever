# Merge View - Round 3

## Summary
- total findings: 13
- new findings: 1
- updated existing findings: 1
- rejected candidates: 10

## Finding Actions
- existing_preserved: 11
- existing_support_added: 1
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-005 | existing_support_added | Medium | high | codex_1,opencode_1 | Pumponomics swap has no slippage bound | opencode_1:0.629 Pumponomics swap has zero minimum output protection |
| F-013 | rewritten_agent_signal | High | high | codex_1 | Funding streams are not automatically terminated at program end | codex_1:0.707 Funding streams are not auto-terminated at program end, so rewards can run indefinitely |

## Rejection Reasons
- duplicate_or_subsumed: 3
- low_impact_or_operational: 2
- other: 3
- trust_or_owner_model: 1
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | opencode_1 | Pumponomics swap has zero minimum output protection | Duplicate of F-005. The supporting observation is valid, but the accumulated finding already covers `_pump()` using `amountOutMinimum = 0` and the lack of swap-level slippage protection. |
| duplicate_or_subsumed | opencode_1 | Permissionless stopFunding allows griefing of legitimate programs | Duplicate of F-002. The missing access control on `stopFunding()` during the early-end window is already captured with the same protocol impact. |
| duplicate_or_subsumed | opencode_1 | Permissionless distributeTaxAdjustment enables timing manipulation | Duplicate of F-012. The candidate restates the existing permissionless tax-adjustment snapshot/timing issue. |
| other | codex_1 | Proxy ownership can be seized via public initializers if deployment is not atomic | Rejected as deployment hygiene rather than a demonstrated source-level vulnerability. Implementations call `_disableInitializers()`, locker and Fontaine proxies are initialized in the same transaction that deploys them, and no in-scope deployment script shows core proxies being left uninitialized. |
| trust_or_owner_model | codex_1 | Third parties can force locker claims and consume signed nonces for users | Rejected as low-impact griefing. A copied or leaked signature updates the victim locker to the signer-authorized units and rewards still accrue to that locker; the main effect is gas grief or off-chain nonce inconvenience rather than realistic protocol-level loss. |
| other | codex_1 | Vesting creation allows zero-address recipient, enabling irreversible token burn | Rejected because the harm depends on an admin mistake and is not clearly irreversible from the in-scope code: funds are first transferred to the vesting contract, and the admin has an emergency withdrawal path for remaining funds. The external scheduler may also reject zero-address recipients. |
| low_impact_or_operational | codex_1 | Factory ETH withdrawals can be DoSed by gas-stipend-limited `transfer` | Rejected as non-reportable operational friction. The issue only affects governor-controlled fee withdrawal, is not permissionlessly triggerable, and a contract governor that cannot receive via `transfer` can still call `setGovernor()` to route withdrawals elsewhere. |
| other | opencode_1 | Instant unlock penalty distribution can be griefed via front-running | Rejected because the candidate describes normal current-unit distribution behavior without a concrete exploit beyond participants changing their own staking or LP units before a distribution. The code already requires pool units and distributes penalties to the current tax pools as designed. |
| low_impact_or_operational | opencode_1 | No event emission on provideLiquidity creates observability gap | Rejected as non-security observability/UX debt. Missing event emission does not by itself cause fund loss, insolvency, lockup, economic manipulation, or permissionless DoS. |
| unsupported_or_speculative | opencode_1 | Potential division truncation in flow rate calculations | Rejected as minor accounting dust. Integer truncation can slightly underfund the intended flow rate, but the undistributed amount is not shown to be stolen or locked, and the impact is bounded to rounding residue. |
