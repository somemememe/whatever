# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 11

## Finding Actions
- exact_agent_candidate: 3
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-002 | exact_agent_candidate | High | high | codex_1 | Minting trusts the requested ERC20 deposit amount instead of the amount actually received | codex_1:1.0 Minting trusts the requested ERC20 deposit amount instead of the amount actually received |
| F-003 | exact_agent_candidate | High | medium | codex_1 | Borrow and margin-trade accounting can overstate user deposits for fee-on-transfer tokens | codex_1:0.853 Borrow and margin-trade accounting can overstate collateral and user contribution for fee-on-transfer tokens |
| F-004 | exact_agent_candidate | Medium | high | codex_1 | The first minter can capture assets already present in the pool | codex_1:0.969 The first minter can capture any assets already present in the pool |
| F-005 | rewritten_agent_signal | Low | high | codex_1 | The proxy silently accepts low-gas ETH transfers and bypasses logic execution | codex_1:0.8 The proxy silently accepts low-gas ETH transfers and leaves the ETH stuck |

## Rejection Reasons
- low_impact_or_operational: 1
- other: 7
- trust_or_owner_model: 3

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex_1 | ETH mints create unbacked shares on non-WETH loan pools | In this source, `mint` is not payable. The ETH-handling branch inside `_mintToken` is therefore unreachable through the normal proxy/implementation dispatch, so the reported exploit path does not execute. |
| trust_or_owner_model | opencode_1 | Arbitrary Call in updateSettings Allows Fund Theft | `updateSettings` is an owner or designated lower-admin control surface for upgrades/configuration. That is a privileged trust assumption, not a permissionless vulnerability in the protocol logic. |
| trust_or_owner_model | opencode_1 | Malicious Target Contract Can Drain Proxy Funds | Owner-controlled upgradeability is the intended proxy design. A malicious owner or compromised governance key is a trust-model risk, not a code flaw specific to this contract. |
| other | opencode_1 | Flash Borrow Allows Arbitrary External Calls | Executing an arbitrary callback is the normal flash-loan design. The function is `nonReentrant` and enforces post-call balance restoration before returning. |
| other | opencode_1 | Hardcoded Critical Addresses Create Single Points of Failure | This is a centralization and maintainability concern, not a concrete exploitable vulnerability demonstrated by the code. |
| trust_or_owner_model | opencode_1 | LowerAdmin Role Has Full Control Without Timelock | This is a governance/trust-model observation about privileged administration rather than a protocol bug. |
| other | opencode_1 | Missing Return Value Check on Token Transfer in burn | False positive. `burn` uses `_safeTransfer`, which checks low-level call success and decodes the returned boolean when present. |
| other | opencode_1 | Oracle Price Feed Dependency Without Validation | Generic oracle dependency alone is not a reportable finding here. No contract-specific validation bypass or exploit path was substantiated from this code. |
| other | opencode_1 | Floating Pragma Solidity Version | False positive. The source uses a fixed pragma `solidity 0.5.17`, not a floating pragma. |
| low_impact_or_operational | opencode_1 | Insufficient Event Emissions for Sensitive Operations | Operational visibility issue only; it does not by itself create realistic protocol-level harm. |
| other | opencode_1 | IERC20 Interface Missing Return Value for transfer/transferFrom | Not a reportable vulnerability in this implementation. The transfer helpers already tolerate optional return data and revert on explicit false returns. |
