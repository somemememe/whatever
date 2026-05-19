# Merge View - Round 1

## Summary
- total findings: 3
- new findings: 3
- updated existing findings: 0
- rejected candidates: 12

## Finding Actions
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-005 | rewritten_agent_signal | High | high | codex_1 | Underlying bridge-out flows use the requested amount instead of the amount actually received | codex_1:0.739 Underlying bridge-out flows assume nominal transfer amount instead of actual received amount |
| F-004 | rewritten_agent_signal | High | medium | codex_1 | Router ignores token and vault return values, so bridge events can be emitted after failed accounting | codex_1:0.514 Router ignores failure return values from mint, burn, and vault operations |
| F-006 | rewritten_agent_signal | High | low | codex_1 | Router has no on-chain allowlist for bridge assets, so arbitrary token contracts can generate canonical bridge logs | codex_1:0.684 No on-chain token allowlist lets arbitrary contracts emit canonical bridge events |

## Rejection Reasons
- duplicate_or_subsumed: 1
- low_impact_or_operational: 1
- other: 9
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex_1,opencode_1 | Inbound bridge executions have no replay protection / unverified transaction hash allows fake cross-chain swaps | `anySwapIn*` is already fully gated by `onlyMPC`, and the contract intentionally relies on MPC authorization rather than on-chain source-tx verification. The unused `txs` value is informational only, so missing replay tracking does not materially expand power beyond the trusted MPC role. |
| other | codex_1,opencode_1 | anySwapFeeTo can mint arbitrary tokens and drain the entire underlying vault | This is not a distinct contract bug from the router's trust model: `onlyMPC` can already mint and redeem arbitrary amounts through `anySwapInUnderlying`/`anySwapInAuto`. `anySwapFeeTo` does not grant meaningfully more power than the already trusted bridge operator. |
| other | codex_1 | changeVault lets MPC instantly redirect custody of bridged assets | This is an explicit `onlyMPC` administrative function for vault configuration. A malicious MPC changing vaults is within the router's trust assumption rather than an unintended privilege escalation introduced by the code. |
| other | opencode_1 | Missing initialization of _oldMPC in constructor | False positive. The constructor sets `_newMPCEffectiveTime = block.timestamp`, so `mpc()` returns `_newMPC` immediately after deployment because `block.timestamp >= _newMPCEffectiveTime` is true. |
| other | opencode_1 | Unchecked array lengths in batch anySwapOut | Mismatched array lengths only cause an out-of-bounds revert in Solidity 0.8+, reverting the whole transaction. This is input validation/UX debt, not a reportable protocol vulnerability. |
| other | opencode_1 | No validation of _mpc address in constructor | This is deployment misconfiguration risk rather than a runtime vulnerability. If the deployer sets an invalid MPC address, the contract is simply misconfigured at launch. |
| other | opencode_1 | Slippage protection can be bypassed via reserve manipulation | This is ordinary AMM execution risk, not a router-specific flaw. The contract already enforces `amountOutMin` and `deadline`, and reserve movement before execution is inherent to public on-chain swaps. |
| other | opencode_1 | No deadline for anySwapIn functions | The plain inbound bridge functions (`anySwapIn`, `anySwapInUnderlying`, `anySwapInAuto`) do not perform price discovery, so omitting a deadline is not a distinct smart-contract vulnerability. The price-sensitive swap-in paths already enforce `deadline`. |
| trust_or_owner_model | opencode_1 | No pausable mechanism for emergency stop | Missing pause functionality is a governance/design choice, not a concrete vulnerability in this code. |
| other | opencode_1 | Insufficient input validation on path array | The library already reverts on invalid paths via `require(path.length >= 2)`. This is only error-message/UX quality, not a security issue. |
| low_impact_or_operational | opencode_1 | No event emitted for anySwapFeeTo | Lack of an event affects observability only and does not create protocol-level harm. |
| duplicate_or_subsumed | opencode_1 | Reentrancy risk in anySwapInUnderlying and anySwapInAuto | No concrete reentrant path was shown that bypasses `onlyMPC`, duplicates accounting, or steals funds. The candidate is speculative and unsupported by the reachable call graph in this router. |
