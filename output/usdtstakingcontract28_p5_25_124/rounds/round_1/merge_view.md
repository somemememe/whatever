# Merge View - Round 1

## Summary
- total findings: 6
- new findings: 6
- updated existing findings: 0
- rejected candidates: 10

## Finding Actions
- exact_agent_candidate: 2
- rewritten_agent_signal: 4

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex_1,opencode_1 | Anyone can grant themselves unlimited allowance over tokens held by the contract | codex_1:0.773 Anyone can approve themselves to spend all tokens held by the contract |
| F-002 | rewritten_agent_signal | High | high | codex_1 | Interest is paid from pooled deposits with no enforced reward backing, making the pool structurally insolvent | codex_1:0.72 Interest is paid out of depositor principal, making the staking pool structurally insolvent |
| F-003 | rewritten_agent_signal | High | high | codex_1 | Deposits continue accruing rewards indefinitely after maturity | codex_1:0.426 Deposits keep earning forever because interest is never capped at lockup expiry |
| F-004 | exact_agent_candidate | Critical | medium | codex_1,opencode_1 | Owner can drain all staked USDT at any time | codex_1:0.929 Owner can rug all staked USDT at any time |
| F-005 | exact_agent_candidate | High | medium | codex_1,opencode_1 | Owner can arbitrarily freeze user principal and rewards via blacklist | codex_1:1.0 Owner can arbitrarily freeze user principal and rewards via blacklist |
| F-006 | rewritten_agent_signal | Medium | high | merge_review | Withdrawing one deposit can permanently brick reward claims for other deposits in the same tier | opencode_1:0.368 Owner can blacklist users to permanently lock their funds |

## Rejection Reasons
- other: 6
- trust_or_owner_model: 1
- unsupported_or_speculative: 3

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| unsupported_or_speculative | opencode_1 | Interest calculation always returns zero - logic error in calculateInterest | Not supported. `interestClaimed` is dead code that always evaluates to 0, but `calculateInterest` still returns the separately computed time-based `interest`, so rewards are not forced to zero. |
| unsupported_or_speculative | opencode_1 | Syntax error in claimInterestForDeposit prevents compilation | Not supported as a reportable issue. The source only shows whitespace in `msg. sender`; that is not sufficient evidence of a real compilation-blocking defect here. |
| unsupported_or_speculative | opencode_1 | Unchecked lockup period validation leads to zero interest rate | The code does accept unsupported lockup values between 7 and 90 days and assigns 0 interest, but this is a user-parameter footgun rather than an adversarial protocol-level exploit or insolvency vector. |
| other | opencode_1 | No slippage protection in deposit function | Not applicable. `deposit` is a direct token transfer into a staking contract, not a price-sensitive swap or exchange path. |
| other | opencode_1 | Missing Reentrancy Guard on withdraw function | Not a realistic issue in this code path. The staked token is hardcoded to mainnet USDT, so the generic malicious-token callback scenario does not apply. |
| other | opencode_1 | Referral system implemented but never pays rewards | This is incomplete product logic, not a demonstrated security vulnerability causing protocol-level fund loss or denial of service. |
| other | opencode_1 | Unused max function indicates leftover/debug code | Dead code only; no security impact. |
| other | opencode_1 | Hardcoded token address cannot be changed | Deployment rigidity alone is not a security finding in this context. |
| other | opencode_1 | Inconsistent lockup period storage - single value vs array | Redundant bookkeeping is present, but no concrete exploit path or protocol-level harm is shown. |
| trust_or_owner_model | opencode_1 | No event emitted for transferAllFunds | Observability issue only; it does not materially change the owner's ability to move funds or create new loss beyond the accepted drain finding. |
