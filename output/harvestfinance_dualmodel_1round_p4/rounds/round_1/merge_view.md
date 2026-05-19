# Merge View - Round 1

## Summary
- total findings: 5
- new findings: 5
- updated existing findings: 0
- rejected candidates: 1

## Finding Actions
- exact_agent_candidate: 1
- rewritten_agent_signal: 4

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex_1 | Vault proxy is deployed uninitialized and can be taken over by the first caller | codex_1:1.0 Vault proxy is deployed uninitialized and can be taken over by the first caller |
| F-002 | rewritten_agent_signal | High | high | codex_1 | First depositor can steal assets already sitting in a zero-supply vault | codex_1:0.803 First depositor can drain any underlying sitting in a zero-supply vault |
| F-003 | rewritten_agent_signal | High | high | codex_1 | ERC4626 `mint()` can charge assets for fewer than the requested shares, including zero shares | codex_1:0.644 ERC4626 `mint()` double-rounds down and can charge assets for fewer or even zero shares |
| F-004 | rewritten_agent_signal | High | high | codex_1 | ERC4626 `withdraw()` can burn too few shares and return fewer assets than requested | codex_1:0.616 ERC4626 `withdraw()` rounds required shares down and can underpay exact-asset withdrawals |
| F-005 | rewritten_agent_signal | Low | high | codex_1 | ERC4626 empty-vault helpers revert because `assetsOf()` divides by zero | codex_1:0.797 ERC4626 view helpers revert on an empty vault because `assetsOf()` divides by zero |

## Rejection Reasons
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | codex_1 | Share pricing blindly trusts strategy-reported NAV, enabling deposit/withdraw mispricing if that view is manipulable | Too speculative as stated. The vault does read `investedUnderlyingBalance()` for pricing, but this repository does not include any concrete strategy showing a permissionless or realistically exploitable way to manipulate that value. Without a manipulable strategy implementation, this is a generic trust assumption about governance-selected strategies rather than a standalone reportable vault bug. |
