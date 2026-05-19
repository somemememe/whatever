# Merge View - Round 4

## Summary
- total findings: 9
- new findings: 2
- updated existing findings: 0
- rejected candidates: 1

## Finding Actions
- existing_preserved: 7
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-010 | rewritten_agent_signal | High | high | codex | Excess redemption write-offs are silently discarded, leaving phantom collateral in borrower accounting | codex:0.707 Excess redemption write-offs are silently discarded, letting users borrow and withdraw against collateral that no longer exists |
| F-012 | rewritten_agent_signal | Low | medium | codex | Allowing `minimumLeftoverDebt = 0` can preserve stale global borrow shares after full redemption | codex:0.788 Setting `minimumLeftoverDebt` to zero can leave stale borrow shares alive after a full redemption |

## Rejection Reasons
- other: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex | The pair releases collateral and clears debt before verifying that redemption or liquidation payment was actually settled | `redeemCollateral` and `liquidate` are explicitly restricted to registry-selected handler addresses, so the pair is intentionally trusting protocol-controlled components to perform the corresponding burn/settlement. Without a permissionless path or evidence that those handlers are untrusted in this codebase, this is a trust-boundary/design assumption rather than a standalone reportable pair bug. |
