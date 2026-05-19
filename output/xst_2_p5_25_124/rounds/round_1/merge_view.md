# Merge View - Round 1

## Summary
- total findings: 5
- new findings: 5
- updated existing findings: 0
- rejected candidates: 11

## Finding Actions
- exact_agent_candidate: 1
- rewritten_agent_signal: 4

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex_1,opencode_1 | Upgradeable deployment has no initialization path, leaving owner and core state permanently unset | codex_1:0.76 Upgradeable token has no initializer, leaving ownership and the rebase factor permanently unset |
| F-002 | rewritten_agent_signal | High | high | codex_1 | Unassigned `_mainPool` makes ordinary transfers revert via zero-address pool sync | codex_1:0.756 Uninitialized `_mainPool` makes ordinary transfers revert on address(0) ERC20 calls |
| F-003 | rewritten_agent_signal | Critical | high | codex_1 | Spot-balance rebase logic is flash-loan manipulable and applies an uncapped quadratic mint on buys | codex_1:0.621 Flash-loan manipulable spot balances drive an uncapped quadratic rebase mint |
| F-004 | exact_agent_candidate | Medium | high | codex_1 | Liquidity reserve migration burns and skims treasury funds because it is not performed taxlessly | codex_1:0.862 Liquidity reserve migration burns and skims the reserve because it is not executed taxlessly |
| F-005 | rewritten_agent_signal | Critical | high | opencode_1 | No code path can ever mark the presale as finished, so all transfers remain permanently disabled | opencode_1:0.427 No function to mark presale as done |

## Rejection Reasons
- duplicate_or_subsumed: 2
- factually_incorrect: 1
- other: 4
- trust_or_owner_model: 2
- unsupported_or_speculative: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Uninitialized presale address allows anyone to mint tokens | False positive: no transaction can originate from `address(0)`. A zero `_presaleCon` makes `mint()` unreachable, not publicly callable; that bricking is covered by F-001. |
| duplicate_or_subsumed | opencode_1 | getFactor() calculation broken - token balances become incorrect after transactions | The claim misunderstands the rebase accounting model. Large-balance conversions are intentionally handled via the factor and `_largeTotal`; the concrete bug here is missing initialization, already captured in F-001. |
| factually_incorrect | opencode_1 | setTaxless() lacks access control - anyone can set taxless mode | Incorrect: `setTaxless(bool)` is explicitly protected by the `onlyTaxless` modifier. |
| duplicate_or_subsumed | opencode_1 | Division by zero in getFactor() if totalSupply becomes zero | Too speculative as a standalone issue and not needed to explain realistic harm; the concrete deploy-time bricking from missing initialization is already captured in F-001. |
| other | opencode_1 | createTokenPool uses block.timestamp as deadline - can fail immediately | Using `block.timestamp` as a same-transaction router deadline is standard and does not by itself create a realistic exploit or loss scenario. |
| trust_or_owner_model | opencode_1 | reassignTranche allows assigning to zero address | Privileged misconfiguration/footgun only; no permissionless exploit or protocol-level failure is introduced. |
| other | opencode_1 | silentSyncPair can be called on arbitrary addresses | Public calls mainly expose the caller to a revert; the meaningful protocol issue is the internal use of zero `_mainPool`, captured in F-002. |
| trust_or_owner_model | opencode_1 | addSupportedPool does not validate pairToken address | Owner-only misconfiguration risk without a permissionless exploit path; not a reportable protocol bug on its own. |
| unsupported_or_speculative | opencode_1 | getUpdatedPoolCounters uses address(this) instead of pool address for token balance | `IERC20(address(this)).balanceOf(pool)` is the correct way to read this token's pool balance. Problems from unsupported pools are already covered by F-002. |
| other | opencode_1 | Using outdated Solidity version ^0.6.12 | Generic informational note, not a concrete vulnerability in this codebase. |
| unsupported_or_speculative | opencode_1 | No zero address validation in setLiquidityReserve and setStabilizer | `AddressUpgradeable.isContract(reserve)` already rejects `address(0)`, so the specific zero-address claim is unsupported. |
