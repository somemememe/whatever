# Merge View - Round 1

## Summary
- total findings: 5
- new findings: 5
- updated existing findings: 0
- rejected candidates: 13

## Finding Actions
- rewritten_agent_signal: 5

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | High | high | codex_1 | Governance rotation leaves former avatar with permanent reserve minting and helper admin powers | opencode_1:0.344 Missing Zero Address Validation in setDistributionHelper |
| F-002 | rewritten_agent_signal | Medium | high | codex_1 | Public address refresh makes the hardcoded guardian effectively irrevocable | codex_1:0.463 A hardcoded guardian can always be re-granted by any caller |
| F-003 | rewritten_agent_signal | High | high | codex_1,opencode_1 | Anyone can trigger zero-slippage fee-restocking sales of protocol-owned G$ | codex_1:0.446 Public fee-restocking path sells protocol G$ with zero slippage protection |
| F-004 | rewritten_agent_signal | Medium | medium | codex_1,opencode_1 | Contract recipients can re-enter `onDistribution` during `transferAndCall` | codex_1:0.683 Reentrant contract recipients can recursively re-distribute funds via `transferAndCall` |
| F-005 | rewritten_agent_signal | Medium | high | codex_1,opencode_1 | Unchecked oracle answers can halt `collectInterest` and misprice keeper rewards | opencode_1:0.423 Unchecked cDai Redeem and Mint Return Values |

## Rejection Reasons
- duplicate_or_subsumed: 1
- other: 9
- trust_or_owner_model: 2
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Unchecked Call Return Value in ERC20 transferFrom | Not a practical issue here: the reserve buy path uses fixed cDAI/DAI integrations rather than arbitrary ERC20s, so generic non-standard token compatibility does not create an exploitable protocol vulnerability. |
| other | opencode_1 | Missing Access Control on onDistribution Function | Public triggering is explicitly intended by the contract comments. Standalone timing control is not reportable by itself; the real issue is the merged zero-slippage fee sale that public callers can trigger. |
| other | opencode_1 | Unlimited Token Approvals Set by Anyone | `setAddresses()` only refreshes approvals to addresses resolved from `NameService`, which is avatar-controlled. The public refresh function alone does not let an attacker redirect approvals to themselves. |
| trust_or_owner_model | opencode_1 | Division by Zero in GoodMarketMaker.calculateMintInterest | The reported path depends on privileged misconfiguration or an undeveloped reserve-depletion scenario. The agent did not demonstrate a concrete, realistic permissionless exploit from the current code. |
| trust_or_owner_model | opencode_1 | Missing Input Validation in GoodMarketMaker.initializeToken | This is a governance-parameter sanity concern, not a demonstrated exploit path or user-reachable vulnerability. |
| unsupported_or_speculative | opencode_1 | Potential Integer Overflow in BancorFormula | Too speculative. Solidity 0.8 has checked arithmetic, and no concrete overflow-triggering input path or profit mechanism was shown. |
| other | opencode_1 | Missing Pausable in DistributionHelper | Absence of an emergency pause is a design preference, not a concrete security bug in itself. |
| other | opencode_1 | Unchecked cDai Redeem and Mint Return Values | The contract does check the Compound return codes and reverts on failure. Generic error strings are not a security issue. |
| other | opencode_1 | Missing Zero Address Validation in setDistributionHelper | This is a recoverable avatar misconfiguration, not an exploitable vulnerability path. |
| other | opencode_1 | Missing Deadline Check in Uniswap Swaps | Using `block.timestamp` as a same-transaction deadline is standard router usage and does not trap user funds in this flow. |
| other | opencode_1 | Hardcoded Oracle Address in DistributionHelper | This is a maintainability/centralization concern rather than a concrete exploit that causes realistic protocol harm by itself. |
| duplicate_or_subsumed | opencode_1 | Missing Validation of Array Length in collectInterest | Duplicate staking addresses were not shown to create double-crediting, theft, or a realistic protocol-level failure from the current logic. |
| other | opencode_1 | Inconsistent NonReentrant Implementation | Implementation style only. The presence of custom reentrancy guards instead of OpenZeppelin's library is not a reportable vulnerability. |
