# Merge View - Round 1

## Summary
- total findings: 3
- new findings: 3
- updated existing findings: 0
- rejected candidates: 7

## Finding Actions
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex_1 | L1StandardBridge can be reinitialized repeatedly to replace the trusted messenger and seize bridge funds | codex_1:0.64 L1StandardBridge can be reinitialized at any time to swap in an attacker-controlled messenger |
| F-002 | rewritten_agent_signal | High | high | codex_1 | ERC20 deposits over-credit fee-on-transfer and deflationary tokens, creating insolvent bridge accounting | codex_1:0.701 ERC20 deposits are overcredited for fee-on-transfer / deflationary tokens |
| F-003 | rewritten_agent_signal | Medium | high | codex_1,opencode_1 | Unsupported mutable-balance or blocklist-controlled ERC20s can permanently lock bridged withdrawals | opencode_1:0.469 Integer Underflow in finalizeBridgeERC20 Allows Permanent DoS of Withdrawals |

## Rejection Reasons
- duplicate_or_subsumed: 2
- other: 5

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Integer Underflow in finalizeBridgeERC20 Allows Permanent DoS of Withdrawals | Not reportable as described. In Solidity 0.8 the subtraction reverts atomically, so no underflowed state is stored, and the messenger marks the relay as failed/replayable rather than permanently breaking future withdrawals. |
| other | opencode_1 | ETH Can Be Permanently Locked in finalizeBridgeETH Due to Failed Transfer | This is expected bridge behavior, not a contract flaw. A failed ETH delivery causes the cross-domain message to fail and remain replayable; permanent lockup only occurs when the chosen recipient always rejects ETH, which is documented and recipient-driven. |
| duplicate_or_subsumed | opencode_1 | No Validation That Deposits Sufficiently Cover Withdrawal in finalizeBridgeERC20 | Duplicate of the rejected underflow theory. Insufficient deposits cause a normal revert with full state rollback, not a persistent corruption or pair-wide permanent halt by themselves. |
| duplicate_or_subsumed | opencode_1 | initialize() Function Lacks Access Control Allowing Potential Front-Running | Subsumed by F-001. The real issue is stronger: `initialize()` can be called repeatedly at any time because `clearLegacySlot` resets the initializer state. |
| other | opencode_1 | Gas Estimation in CrossDomainMessenger May Cause Message Relay Failures | Documented UX footgun rather than a protocol vulnerability. Failed relays are an intended replayable state in this messenger design. |
| other | opencode_1 | OptimismMintableERC20 Allows Zero Address for Bridge and Remote Token | This is deployer misconfiguration, not an exploitable protocol issue in the audited code. |
| other | opencode_1 | onlyEOA Modifier Bypass Via Recently Created EOAs | Non-reportable. The code explicitly documents that `onlyEOA` is only a best-effort UX guard and is not relied on for security. |
