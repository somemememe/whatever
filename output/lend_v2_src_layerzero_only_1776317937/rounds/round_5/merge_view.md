# Merge View - Round 5

## Summary
- total findings: 20
- new findings: 1
- updated existing findings: 0
- rejected candidates: 10

## Finding Actions
- exact_agent_candidate: 1
- existing_preserved: 19

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-020 | exact_agent_candidate | High | high | codex_1,merge_layer | Borrowed-asset tracking can be cleared while debt still exists, hiding liabilities from liquidity checks | codex_1:0.956 Borrowed-asset set can be cleared while debt still exists, hiding liabilities from liquidity checks |

## Rejection Reasons
- duplicate_or_subsumed: 2
- low_impact_or_operational: 2
- other: 3
- trust_or_owner_model: 1
- unsupported_or_speculative: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | opencode_1 | Cross-chain borrow trusts unverified collateral snapshot from source chain | Duplicate of existing F-002 (same stale-collateral TOCTOU root cause and exploit path). |
| duplicate_or_subsumed | opencode_1 | Cross-chain liquidation allows seize without confirmed repayment on destination chain | Duplicate of existing F-007 (seize-before-repay ordering flaw). |
| low_impact_or_operational | opencode_1 | Gas griefing in claimLend via unbounded iterator arrays | Primarily caller self-grief: attacker supplies arrays and pays gas; does not create a realistic protocol-level exploit by itself. |
| trust_or_owner_model | opencode_1 | Protocol reward update lacks cap and access control beyond owner | Assumes compromise/malicious behavior of already-authorized contracts; not a distinct permissionless vulnerability. |
| unsupported_or_speculative | opencode_1 | LayerZero message options use hardcoded gas limit that may be insufficient | Too speculative/configuration-dependent as presented; no concrete, reproducible protocol-harm path established from current code alone. |
| other | opencode_1 | Borrow index validation missing for edge case in liquidation calculation | Relies on corrupted/impossible-by-normal-flow state (`storedBorrowIndex == 0`) rather than a realistic reachable condition. |
| other | opencode_1 | Cross-chain repay state update uses inconsistent index source | Using current borrow index on partial repay is expected debt normalization behavior; no concrete accounting break demonstrated. |
| low_impact_or_operational | codex_1 | Cross-chain borrow market-entry check is self-fulfilling and can skip actual Comptroller entry | Logic mismatch exists, but exploit impact is not clearly protocol-level (primarily operational/availability behavior and may only cause caller-side borrow failure). |
| unsupported_or_speculative | codex_1 | Liquidation execute handler can hard-revert on unchecked collateral subtraction | Underflow revert is possible for bad liquidation parameters, but this is mainly per-call failure by caller-selected inputs and not shown as a persistent protocol-level exploit independent of already-tracked issues. |
| other | codex_1 | Same-chain liquidation path can revert by division-by-zero when no local borrow index exists | Occurs when attempting same-chain liquidation without same-chain borrow state; this is an invalid-path revert with limited security impact, not a realistic exploitable protocol vulnerability. |
