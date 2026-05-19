# Merge View - Round 1

## Summary
- total findings: 1
- new findings: 1
- updated existing findings: 0
- rejected candidates: 6

## Finding Actions
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | High | high | codex_1,opencode_1 | Full-balance NFT enumeration makes claims unscalable and lets attackers dust wallets into permanent out-of-gas failure | codex_1:0.73 Unbounded NFT enumeration lets attackers dust wallets into permanent claim failure |

## Rejection Reasons
- duplicate_or_subsumed: 1
- low_impact_or_operational: 1
- other: 1
- trust_or_owner_model: 2
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex_1 | Any temporary holder can capture the one-time airdrop because eligibility is based on live balances | The contract clearly keys eligibility to the current holder at claim time, and no snapshot or different intended beneficiary is specified in the code. Without an external specification, this is a design choice rather than a code-level vulnerability. |
| trust_or_owner_model | codex_1 | The drop becomes first-come-first-served if the contract is underfunded | Insufficient ERC20 funding is an external/admin provisioning issue. Failed claims revert before any claim state is burned, so users can retry if the owner later tops up before the deadline. |
| unsupported_or_speculative | codex_1 | Fee-on-transfer or non-standard GRAPES tokens permanently underpay claimants | This depends on the configured GRAPES token being fee-on-transfer or otherwise non-standard. The repository does not include such a token or evidence that this deployment uses one, so the issue is too integration-specific and speculative here. |
| trust_or_owner_model | opencode_1 | Owner can permanently pause claims | This is an owner-trust/centralization property of the design, not a distinct exploitable vulnerability. The owner already controls when claims start and can sweep leftovers after the period ends. |
| low_impact_or_operational | opencode_1 | Missing event for pauseClaimablePeriod | Missing observability does not create realistic protocol-level harm such as loss, theft, insolvency, or denial of service. |
| duplicate_or_subsumed | opencode_1 | Inefficient iteration over NFT collections | The missing early break in the Gamma loop is only a gas inefficiency and is already subsumed by the broader unbounded-enumeration denial-of-service finding. |
