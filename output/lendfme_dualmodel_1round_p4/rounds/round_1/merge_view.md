# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 8

## Finding Actions
- exact_agent_candidate: 4

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex_1 | External token callbacks can reenter before balances and market totals are updated | codex_1:1.0 External token callbacks can reenter before balances and market totals are updated |
| F-002 | exact_agent_candidate | Critical | high | codex_1 | Self-liquidation aliases borrower and liquidator collateral balances, minting collateral to the caller | codex_1:1.0 Self-liquidation aliases borrower and liquidator collateral balances, minting collateral to the caller |
| F-003 | exact_agent_candidate | High | high | codex_1 | Incoming-token accounting trusts the requested amount instead of the amount actually received | codex_1:1.0 Incoming-token accounting trusts the requested amount instead of the amount actually received |
| F-004 | exact_agent_candidate | Medium | high | codex_1 | Suspending a borrow market makes solvent positions immediately liquidatable | codex_1:1.0 Suspending a borrow market makes solvent positions immediately liquidatable |

## Rejection Reasons
- other: 4
- trust_or_owner_model: 4

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | opencode_1 | Oracle price manipulation allows stealing all protocol funds | Admin-only oracle replacement is an explicit privileged governance power, not a permissionless code flaw or privilege escalation. |
| trust_or_owner_model | opencode_1 | Unrestricted interest rate model enables rate manipulation | Setting the interest model is an explicit admin control; this is governance trust/centralization, not a standalone vulnerability in the implementation. |
| other | opencode_1 | No maximum cap on origination fee allows 100%+ fees | This is an admin misconfiguration/griefing risk rather than a realistic permissionless exploit or invariant break. |
| trust_or_owner_model | opencode_1 | All supported markets automatically become collateral | Market support and collateral admission are both admin-controlled configuration choices; without a separate privilege bypass, this is governance design rather than a code bug. |
| other | opencode_1 | Suspended markets still count for collateral calculations | This behavior is explicitly documented in `_suspendMarket`; the report does not show an independent exploit beyond the kept finding that suspended borrow markets become liquidatable. |
| trust_or_owner_model | opencode_1 | No timelock on admin actions allows instant privileged changes | Lack of a timelock is a governance-centralization concern, not a contract vulnerability by itself. |
| other | opencode_1 | Floating pragma version may cause compatibility issues | Best-practice concern only; no concrete exploit path or protocol-level harm is shown. |
| other | opencode_1 | Self-destruct possible through admin-controlled equity withdrawal | `_withdrawEquity` is an explicit admin function limited to protocol equity and does not constitute an unintended exploit path. |
