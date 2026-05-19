# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 11

## Finding Actions
- exact_agent_candidate: 3
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | High | medium | codex_1 | Balance-delta accounting can over-credit deposits and repayments for mutable underlyings | codex_1:1.0 Balance-delta accounting can over-credit deposits and repayments for mutable underlyings |
| F-002 | exact_agent_candidate | High | medium | codex_1 | Live-balance exchange-rate accounting lets external balance increases inflate collateral value | codex_1:0.906 Raw-balance exchange-rate math lets external balance increases inflate collateral value |
| F-003 | exact_agent_candidate | High | medium | codex_1 | Negative underlying balance changes can underflow exchange-rate math and freeze the market | codex_1:1.0 Negative underlying balance changes can underflow exchange-rate math and freeze the market |
| F-004 | rewritten_agent_signal | High | medium | codex_1 | Underlying transfer controls can permanently lock redemptions, borrows, repayments, and liquidations | codex_1:0.773 Centralized transfer controls on the underlying can permanently lock redemptions, borrows, and liquidations |

## Rejection Reasons
- other: 6
- trust_or_owner_model: 4
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| unsupported_or_speculative | codex_1 | Most Comptroller post-operation verify hooks are disabled or omitted | The missing `*Verify` calls do not create a present exploit in this codebase; harm requires a future or replacement Comptroller that incorrectly assumes these optional post-hooks run, which is too speculative for a reportable protocol bug here. |
| trust_or_owner_model | opencode_1 | Admin can set reserve factor to 100% and steal all interest | This is intended governance behavior: reserves are protocol-owned by design, and `reserveFactorMaxMantissa` explicitly allows up to 100%. |
| other | opencode_1 | Implementation upgrade can steal all funds | This is the standard explicit trust model of an upgradeable proxy/admin, not an unintended vulnerability in the implementation. |
| trust_or_owner_model | opencode_1 | Unlimited admin control over interest rate model can cause DoS | Relies on a malicious or compromised admin choosing a bad model; that is governance trust, not a distinct permissionless bug. |
| trust_or_owner_model | opencode_1 | No timelock on admin actions creates centralization risk | Centralization/governance-risk observation only; no code defect or unintended exploit path is shown. |
| other | opencode_1 | Liquidator can be set to arbitrary address via Comptroller | Liquidation authorization is intentionally delegated to the Comptroller; this does not identify a flaw in the market contract itself. |
| other | opencode_1 | Floating pragma allows different compiler versions | Build-hygiene concern only; no concrete exploit or protocol-level harm is demonstrated from the pragma ranges used here. |
| other | opencode_1 | Integer division precision loss in exchange rate calculation | Normal fixed-point rounding/truncation in Compound-style math; no material loss or exploitable imbalance is shown. |
| other | opencode_1 | sweepToken function vulnerable to ERC-777 reentrancy | `sweepToken` is admin-only, excludes the underlying, and the proposed reentrancy path does not yield a realistic protocol-level exploit. |
| other | opencode_1 | Missing return value check in ERC-20 transfer operations | Contradicted by the code: both `doTransferIn` and `doTransferOut` inspect returndata and revert on `false` via `require(success, ...)`. |
| trust_or_owner_model | opencode_1 | No panic/pause mechanism for emergencies | Absence of an emergency stop is a governance/design choice, not a concrete vulnerability in the implemented logic. |
