# Merge View - Round 1

## Summary
- total findings: 5
- new findings: 5
- updated existing findings: 0
- rejected candidates: 14

## Finding Actions
- exact_agent_candidate: 4
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex_1,opencode_1 | Reentrancy can reuse an uncommitted FNFT id and merge distinct positions into one series | codex_1:1.0 Reentrancy can reuse an uncommitted FNFT id and merge distinct positions into one series |
| F-002 | exact_agent_candidate | High | high | codex_1 | ETH sent for WETH-backed mints is wrapped into Revest and never forwarded to the vault | codex_1:1.0 ETH sent for WETH-backed mints is wrapped into Revest and never forwarded to the vault |
| F-003 | exact_agent_candidate | High | high | codex_1,opencode_1 | Fee-on-transfer tokens can mint or top up FNFTs with less collateral than accounting assumes | codex_1:1.0 Fee-on-transfer tokens can mint or top up FNFTs with less collateral than accounting assumes |
| F-004 | exact_agent_candidate | Low | high | codex_1 | Additional-deposit deadline is enforced backwards | codex_1:1.0 Additional-deposit deadline is enforced backwards |
| F-005 | rewritten_agent_signal | Low | high | codex_1 | Address-lock mints accept non-compliant trigger addresses and can permanently lock funds | codex_1:0.645 Address-lock mints do not reject non-compliant trigger contracts |

## Rejection Reasons
- other: 12
- unsupported_or_speculative: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Integer Overflow in ERC20 Fee Calculation | Rejected because the contracts compile with Solidity `^0.8.0`, so arithmetic overflow reverts rather than silently wrapping. |
| other | opencode_1 | Missing Underflow Protection in FNFT Burn | Rejected because any underflow on `supply[id] -= amount` reverts in Solidity 0.8; this is not an exploitable accounting bug by itself. |
| other | opencode_1 | Address Lock Can Block Legitimate Unlocks | Rejected as stated because choosing a malicious lock implementation is user-controlled behavior; the reportable protocol issue is the separate accepted finding that non-compliant triggers are accepted without validation. |
| other | opencode_1 | Value Lock Oracle Price Manipulation | Rejected because the provided code only stores a caller-supplied oracle address and contains no oracle implementation or specific manipulable pricing logic to support the flash-loan claim. |
| unsupported_or_speculative | opencode_1 | Split Function Burns FNFT Without Proportional Asset Distribution | Rejected as speculative because the proportional distribution logic lives in the unseen `TokenVault` implementation; the supplied source does not support this claim. |
| other | opencode_1 | No Access Control Check on extendFNFTMaturity | Rejected because `extendFNFTMaturity()` requires `balance == supply`, so only an account holding the entire outstanding supply can extend maturity. |
| other | opencode_1 | Unchecked Return Value from External Call | Rejected because `IAddressLock.createLock()` has no return value; failures revert rather than returning an unchecked status. |
| unsupported_or_speculative | opencode_1 | Potential Division by Zero | Rejected because `erc20multiplierPrecision` is a hard-coded constant `1000`, so the division-by-zero scenario is unsupported. |
| other | opencode_1 | Missing Zero Address Validation for Asset | Rejected because `asset == address(0)` is explicitly treated as a special case by skipping the ERC20 transfer path; the claimed unsafe `safeTransferFrom(address(0), ...)` path is not present. |
| other | opencode_1 | Race Condition in ERC20 Approval | Rejected because granting a standing allowance to the configured rewards handler is a trust/configuration choice, not a concrete protocol exploit in the provided code. |
| other | opencode_1 | Inconsistent fnftsCreated Counter | Rejected as a standalone issue because the counter increments once per new series as intended in normal flow; the real exploitability is the accepted reentrancy/id-reuse finding. |
| other | opencode_1 | depositAdditionalToFNFT Allows Partial Deposit Without Proportional Fee | Rejected because the cited code computes the ERC20 fee directly from `quantity * amount`; no concrete under-collection path for new-series deposits is shown. |
| other | opencode_1 | No Validation of endTime in mintTimeLock | Rejected because allowing an already-mature time lock is at most a user-footgun and does not create realistic protocol-level harm by itself. |
| other | opencode_1 | Potential Griefing via Non-Transferable FNFTs | Rejected because `nontransferrable` is an explicit FNFT configuration choice, not an unintended permissionless exploit. |
