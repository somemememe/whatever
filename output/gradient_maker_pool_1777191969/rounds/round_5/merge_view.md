# Merge View - Round 5

## Summary
- total findings: 12
- new findings: 1
- updated existing findings: 0
- rejected candidates: 2

## Finding Actions
- existing_preserved: 11
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-103 | rewritten_agent_signal | High | medium | codex | The first depositor after a zero-share state can seize stranded pool assets and later orderbook repayments | codex:0.726 The first depositor after a zero-share state can capture assets later returned by the orderbook |

## Rejection Reasons
- trust_or_owner_model: 1
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | codex | Owner emergency functions can rug all pooled ETH and tokens at any time | `emergencyWithdraw` and `emergencyWithdrawETH` are explicit, documented `onlyOwner` rescue powers. This is a centralization/trust assumption rather than an unintended protocol flaw. |
| unsupported_or_speculative | codex | Blocked tokens still accept new liquidity, letting users deposit into already-frozen pools | `provideLiquidity` lacks the blocklist guard, but blocked status by itself does not stop LP withdrawals or prove new deposits become stuck or stealable. The standalone harm is too speculative without a separate insolvency condition. |
