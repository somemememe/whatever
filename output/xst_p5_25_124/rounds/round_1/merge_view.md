# Merge View - Round 1

## Summary
- total findings: 6
- new findings: 6
- updated existing findings: 0
- rejected candidates: 11

## Finding Actions
- exact_agent_candidate: 3
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex_1,opencode_1 | Missing initializer leaves ownership and core token state unset, permanently bricking the token | codex_1:0.978 Missing initializer leaves owner and core token state unset, permanently bricking the token |
| F-002 | exact_agent_candidate | High | high | codex_1,opencode_1 | `_mainPool` is never assigned, so ordinary transfers and unsupported-recipient sells revert | codex_1:0.918 Main pool is never assigned, so ordinary transfers and unsupported sells revert |
| F-003 | rewritten_agent_signal | Critical | medium | codex_1,merge_review | Mint and burn logic is manipulable because it trusts raw instantaneous pair balances and public counter sync | codex_1:0.485 Buy-side supply expansion is flash-loan manipulable through instantaneous AMM balances |
| F-004 | rewritten_agent_signal | High | medium | codex_1 | Epoch rollover snapshots stale counters before refreshing pool state, allowing poisoned baselines for an entire epoch | codex_1:0.602 Epoch baselines can be poisoned because rollover snapshots stale cached counters before refreshing pool state |
| F-005 | exact_agent_candidate | High | high | codex_1 | Pool creation is fully sandwichable because swap and liquidity add both use zero slippage protection | codex_1:0.888 Pool creation is fully sandwichable because both swap and liquidity add use zero slippage bounds |
| F-006 | rewritten_agent_signal | Medium | high | merge_review | Updating the liquidity reserve burns and strands protocol funds because the migration transfer is taxed | opencode_1:0.417 Reentrancy Vulnerability in setLiquidityReserve and setStabilizer |

## Rejection Reasons
- other: 9
- trust_or_owner_model: 1
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Reentrancy Vulnerability in setLiquidityReserve and setStabilizer | Rejected. ERC20 balance moves in `_transfer()` do not invoke recipient callbacks, and the function makes no attacker-controlled external state-changing calls before updating storage. |
| unsupported_or_speculative | opencode_1 | Division by Zero in getFactor when _totalSupply becomes 0 | Rejected. This is a speculative terminal-state edge case without a concrete practical path in the reviewed source, and the contract is already bricked much earlier by missing initialization. |
| other | opencode_1 | Arbitrary External Calls via Owner-Controlled Addresses | Rejected. Setting reserve or stabilizer to a contract address does not by itself create arbitrary callback execution; token transfers only update internal accounting. |
| trust_or_owner_model | opencode_1 | Taxless Setter Privilege Escalation Allows Fee Bypass | Rejected. This is an intended owner-controlled privilege model, not a separate vulnerability absent compromise of a privileged role. |
| other | opencode_1 | No Validation on Lock Box Unlock Time Bounds | Rejected. The reviewed source contains no tranche-creation path, so there is no supported way to create a zero-unlock-time tranche from this code alone. |
| other | opencode_1 | Owner Can Remap Lock Box Beneficiary After Vesting Period | Rejected. `reassignTranche()` explicitly requires `unlockTime > now`, so reassignment after vesting is not allowed. |
| other | opencode_1 | Missing Bounds Check on Tranche Index in getLockBoxes | Rejected. Solidity array access reverts on out-of-bounds indices; it does not return default values. |
| other | opencode_1 | Silent Pool State Updates Enable Price Manipulation | Rejected as a standalone issue. The lack of an event is not the root bug; the real reportable problem is the manipulable balance-based oracle captured in F-003. |
| other | opencode_1 | Out of Bounds Access in getSupportedPools | Rejected. Solidity array indexing reverts on out-of-bounds access; it does not return `address(0)`. |
| other | opencode_1 | Unlimited Minting During Presale Phase | Rejected. The token does not itself enforce a presale cap, but presale authorization/cap logic may live in the external presale contract, and in this source presale minting is currently unreachable due to missing initialization. |
| other | opencode_1 | Block Timestamp Dependency for Epoch Updates | Rejected. This is ordinary timestamp-based epoch logic and does not rise to a realistic reportable issue on its own. |
