# Merge View - Round 1

## Summary
- total findings: 5
- new findings: 5
- updated existing findings: 0
- rejected candidates: 11

## Finding Actions
- exact_agent_candidate: 5

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | High | low | codex_1 | Existing-loan wrapper authorization depends on caller-supplied borrower/trader values | codex_1:0.907 Existing-loan authorization relies on caller-supplied borrower/trader values |
| F-002 | exact_agent_candidate | High | medium | codex_1 | Nominal-amount accounting overcredits deposits and collateral for fee-on-transfer assets | codex_1:1.0 Nominal-amount accounting overcredits deposits and collateral for fee-on-transfer assets |
| F-003 | exact_agent_candidate | Medium | high | codex_1 | iToken transfers can be globally frozen by an external interest-query failure | codex_1:1.0 iToken transfers can be globally frozen by an external interest-query failure |
| F-004 | exact_agent_candidate | Low | medium | codex_1 | marginTrade forwards undeclared excess ETH downstream | codex_1:1.0 marginTrade forwards undeclared excess ETH downstream |
| F-005 | exact_agent_candidate | Low | high | codex_1 | Proxy silently accepts low-gas ETH transfers and can trap native ETH | codex_1:1.0 Proxy silently accepts low-gas ETH transfers and can trap native ETH |

## Rejection Reasons
- other: 9
- trust_or_owner_model: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | opencode_1 | Arbitrary External Call in updateSettings Allows Complete Contract Takeover | `updateSettings` is a privileged admin mechanism, not an untrusted user entrypoint: owner can choose any target, and non-owner callers are restricted to a preconfigured lower-admin contract target. |
| trust_or_owner_model | opencode_1 | Missing Non-Reentrant Protection on updateSettings | The reviewed code shows only an admin-gated maintenance path here; no concrete unprivileged reentrancy primitive or exploitable intermediate state was identified. |
| other | opencode_1 | Flash Loan Allows Arbitrary External Calls to Any Target | This is the intended flash-loan callback design; the function snapshots balances before the callback and requires both ether and underlying balances to be restored afterward. |
| other | opencode_1 | No Validation of Price Feed Return Values | `_totalDeposit` already rejects zero rate and zero precision; remaining stale/manipulated oracle concerns are generic trust assumptions, not a code-specific bug demonstrated here. |
| other | opencode_1 | Token Price Calculation Vulnerable to Flash Loan Manipulation | `flashBorrow` snapshots `_flTotalAssetSupply` for the duration of the flash loan, specifically preventing intra-transaction supply/price distortion from the borrowed assets. |
| other | opencode_1 | No Deadline Parameter in Borrow and Margin Trade Functions | Missing deadlines are a generic UX/MEV consideration, not a concrete protocol vulnerability in this code. |
| other | opencode_1 | Unchecked Return Value in Token TransferFrom | `_callOptionalReturn` requires the low-level call to succeed and also decodes and requires the returned boolean when return data is present. |
| other | opencode_1 | Potential Integer Overflow in Interest Calculation | The arithmetic in the cited interest calculation uses `SafeMath`; overflows revert rather than silently wrapping. |
| other | opencode_1 | Hardcoded Gas Token Addresses Could Become Invalid | This is configuration brittleness, but it does not by itself create a realistic exploit or protocol-level loss scenario. |
| other | opencode_1 | Miner Front-Running Risk Due to Missing Access Control on Pause | The cited code only reads pause flags from storage; no public pause-setting function or missing access control was shown in the reviewed source. |
| other | opencode_1 | Floating Pragma Solidity Version | The pragma is pinned to `0.5.17`, and compiler pinning/version choice is not a reportable vulnerability here. |
