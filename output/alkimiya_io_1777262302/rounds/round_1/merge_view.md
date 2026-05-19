# Merge View - Round 1

## Summary
- total findings: 2
- new findings: 2
- updated existing findings: 0
- rejected candidates: 4

## Finding Actions
- exact_agent_candidate: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | High | high | codex | Recovered bounty proceeds are permanently locked in the contract | codex:1.0 Recovered bounty proceeds are permanently locked in the contract |
| F-002 | exact_agent_candidate | High | high | codex | All token liquidations are sandwichable because `amountOutMin` is hardcoded to zero | codex:1.0 All token liquidations are sandwichable because `amountOutMin` is hardcoded to zero |

## Rejection Reasons
- duplicate_or_subsumed: 2
- unsupported_or_speculative: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | codex | Anyone can trigger the strategy and force irreversible sweeps and liquidations | Not independently reportable from the available code. Because the final profit check reverts the whole transaction when the threshold is not met, a third party cannot force a lasting bad execution unless combined with the zero-slippage liquidation issue already captured in F-002. |
| duplicate_or_subsumed | codex | Profit accounting can be spoofed with pre-existing WETH or ERC20 balances | Supported as a misleading accounting quirk, but it mainly requires the operator or attacker to pre-donate their own assets and does not by itself create realistic theft, insolvency, lockup, or durable protocol-level harm beyond the stranded-funds issue already captured in F-001. |
| unsupported_or_speculative | codex | The brute-force 900-combination sweep creates a denial-of-service risk on the only entrypoint | Too speculative on current evidence. The loop is large, but there is no proof from the repository that the aggregate gas cost exceeds practical transaction or block limits, so a concrete permissionless DoS cannot be established. |
| unsupported_or_speculative | codex | Ignored return values from low-level `call` hide complete or partial failure of the sweep | This is primarily an observability/debuggability issue from the code shown. Concrete protocol harm from partial `startPool`/`endPool` failure depends on the external Silica implementation, which is not available here, so the impact is too speculative to report. |
