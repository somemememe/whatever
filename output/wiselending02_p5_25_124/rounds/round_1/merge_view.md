# Merge View - Round 1

## Summary
- total findings: 6
- new findings: 6
- updated existing findings: 0
- rejected candidates: 14

## Finding Actions
- exact_agent_candidate: 2
- rewritten_agent_signal: 4

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | High | high | codex_1 | depositExactAmountETHMint skips pool synchronization and mints WETH shares at stale prices | codex_1:1.0 depositExactAmountETHMint skips pool synchronization and mints WETH shares at stale prices |
| F-002 | rewritten_agent_signal | High | high | codex_1,opencode_1 | Inbound ERC20 accounting uses the requested amount instead of the actual tokens received | codex_1:0.847 Inbound ERC20 accounting trusts `_amount` instead of actual tokens received |
| F-003 | exact_agent_candidate | High | high | codex_1 | ERC20 transfer helpers treat `false` return values as success | codex_1:0.92 ERC20 helpers treat `false` return values as success |
| F-004 | rewritten_agent_signal | Medium | high | codex_1 | Low-liquidity liquidation records seized lending shares under the victim NFT instead of the liquidator NFT | codex_1:0.607 Low-liquidity liquidation credits seized shares to the liquidator but records the token under the victim NFT |
| F-005 | rewritten_agent_signal | Low | medium | codex_1 | Position-token cleanup can break once a position tracks more than 256 assets | codex_1:0.77 Position token removal uses a `uint8` index and breaks once a position tracks more than 255 assets |
| F-006 | rewritten_agent_signal | Low | medium | codex_1 | Any verified isolation pool can arbitrarily lock or unlock unrelated positions | opencode_1:0.463 AaveHub and IsolationPool can bypass all security checks |

## Rejection Reasons
- other: 9
- trust_or_owner_model: 4
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Master can drain excess tokens from any pool via skim function | `skim()` only transfers unaccounted excess to the fixed `master` address and does not let an external attacker redirect accounted pool funds; this is an intentional admin rescue/design path, not an exploit. |
| trust_or_owner_model | opencode_1 | No emergency stop mechanism - unfixable critical bugs lead to permanent loss | Lack of a pause switch is a governance/design choice, not a concrete vulnerability in the implemented logic. |
| unsupported_or_speculative | opencode_1 | Approval front-running vulnerability - no increaseAllowance function | The described attack is not supported by this custom allowance model; a third party cannot front-run to grant themselves approval. |
| other | opencode_1 | Oracle price manipulation leading to incorrect liquidations | This is a generic oracle-risk claim without source-level evidence that the integrated oracle logic here is manipulable or missing required freshness protections. |
| trust_or_owner_model | opencode_1 | AaveHub and IsolationPool can bypass all security checks | These are explicitly privileged/trusted roles by design. The report does not show an untrusted path that grants this bypass capability. |
| other | opencode_1 | Share price manipulation via large deposits/withdrawals | No concrete exploit path is shown beyond normal share-accounting behavior; the cited code does not support a standalone manipulation bug. |
| other | opencode_1 | Rounding up in paybackAmount causes users to overpay | Ceiling division in `paybackAmount()` is expected when repaying an exact number of borrow shares and does not by itself create an exploitable loss-of-funds bug. |
| other | opencode_1 | Missing zero address validation in setSecurity allows setting zero address | `setSecurity()` is one-time, `onlyMaster`, and a zero or non-contract address would fail initialization rather than silently disable security for attackers. |
| other | opencode_1 | Missing validation on collateral factor upper bound in createPool | This is an admin-only misconfiguration risk, not an externally exploitable vulnerability. |
| trust_or_owner_model | opencode_1 | Position NFT ID not validated - possible array out of bounds | The cited storage uses mappings, not arrays, and ownership-sensitive flows are checked through `WISE_SECURITY`; no out-of-bounds condition is supported. |
| other | opencode_1 | Flash loan attack vector on liquidation rewards | This is another generic oracle-manipulation claim without code-specific evidence that liquidation pricing can be flash-loan manipulated here. |
| other | opencode_1 | Unchecked return value in receive function | `receive()` forwards ETH via `_sendValue()`, which explicitly reverts on failure; it does not fail silently. |
| other | opencode_1 | Potential integer overflow in fee share calculation | Solidity 0.8.x checked arithmetic would revert on overflow, so this is not a silent overflow vulnerability. |
| trust_or_owner_model | opencode_1 | No timelock on master actions - immediate effect | Absence of a timelock is a governance/trust-model issue, not a code-exploitable vulnerability by untrusted actors. |
