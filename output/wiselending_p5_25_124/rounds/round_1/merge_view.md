# Merge View - Round 1

## Summary
- total findings: 6
- new findings: 6
- updated existing findings: 0
- rejected candidates: 12

## Finding Actions
- exact_agent_candidate: 6

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex_1 | Exact-amount borrows and withdrawals can round to zero shares and bypass accounting | codex_1:1.0 Exact-amount borrows and withdrawals can round to zero shares and bypass accounting |
| F-002 | exact_agent_candidate | High | high | codex_1 | Repeated syncs can re-accrue the same interest window whenever fee rounding yields zero | codex_1:1.0 Repeated syncs can re-accrue the same interest window whenever fee rounding yields zero |
| F-003 | exact_agent_candidate | High | high | codex_1 | depositExactAmountETHMint bypasses WETH pool synchronization and over-mints shares | codex_1:1.0 depositExactAmountETHMint bypasses WETH pool synchronization and over-mints shares |
| F-004 | exact_agent_candidate | Medium | medium | codex_1 | Accounting assumes full token transfers and breaks for fee-on-transfer or deflationary assets | codex_1:1.0 Accounting assumes full token transfers and breaks for fee-on-transfer or deflationary assets |
| F-005 | exact_agent_candidate | Low | high | codex_1 | Illiquid liquidation share payouts are registered on the debtor NFT instead of the liquidator NFT | codex_1:0.896 Illiquid liquidation payouts register the token on the debtor NFT instead of the liquidator NFT |
| F-006 | exact_agent_candidate | Medium | medium | codex_1 | Position token arrays hard-fail once a position accumulates 256 entries | codex_1:0.921 Position token arrays hard-fail once a position accumulates more than 255 entries |

## Rejection Reasons
- low_impact_or_operational: 1
- other: 6
- trust_or_owner_model: 5

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | opencode_1 | Unverified setSecurity allows arbitrary contract assignment | `setSecurity()` is an `onlyMaster` governance action; this is a trust-model issue, not a permissionless protocol vulnerability. |
| other | opencode_1 | Liquidation state inconsistency - token transfer after state update | If `_safeTransferFrom()` fails, the EVM reverts the whole call and all earlier state changes are rolled back, so no persistent inconsistency is created. |
| trust_or_owner_model | opencode_1 | Division by zero in fee share calculation | With non-malicious fees at or below 100%, the denominator stays positive because `pseudoTotalPool` is increased before the division; reaching zero requires privileged fee misconfiguration. |
| other | opencode_1 | Missing reentrancy protection in receive function | `receive()` mutates no lending state and only forwards ETH with `transfer`; forced ETH acceptance is not an exploitable protocol bug here. |
| other | opencode_1 | Missing zero address validation in approve function | Approving the zero address is at most a harmless user mistake and does not create protocol-level harm. |
| trust_or_owner_model | opencode_1 | No emergency stop mechanism | This is a best-practice/governance observation rather than a concrete vulnerability in the current code. |
| other | opencode_1 | Liquidation transaction can be delayed indefinitely | Mempool delay is not controlled by contract code and no concrete exploit path is created by the implementation. |
| trust_or_owner_model | opencode_1 | Collateral factor allows 100% | The collateral factor is a governance-set risk parameter; allowing exactly 100% is a configuration choice, not a permissionless exploit. |
| low_impact_or_operational | opencode_1 | Missing event emissions for critical functions | Missing events affect observability only and do not directly endanger funds or protocol solvency. |
| trust_or_owner_model | opencode_1 | Renounce ownership is permanent with no recovery | Permanent ownership renunciation is expected behavior and a governance/trust-model decision, not a code vulnerability. |
| other | opencode_1 | Fee manager NFT ID assumption | This code intentionally hardcodes fee accounting to NFT id 0, and no evidence in the provided code shows that assumption is invalid. |
| other | opencode_1 | Potential storage collision with isolated pools | `positionLocked` is intentionally reused as the isolation-pool registration/lock bit; no unintended conflicting storage use was found. |
