# Merge View - Round 1

## Summary
- total findings: 5
- new findings: 5
- updated existing findings: 0
- rejected candidates: 12

## Finding Actions
- exact_agent_candidate: 3
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | High | high | codex_1 | Legacy mint accounting overissues cTokens for fee-on-transfer deposits | codex_1:1.0 Legacy mint accounting overissues cTokens for fee-on-transfer deposits |
| F-002 | exact_agent_candidate | High | high | codex_1 | Legacy repay path clears debt using the nominal amount instead of cash actually received | codex_1:1.0 Legacy repay path clears debt using the nominal amount instead of cash actually received |
| F-003 | exact_agent_candidate | High | high | codex_1 | Legacy liquidation over-seizes collateral from the requested repay amount | codex_1:1.0 Legacy liquidation over-seizes collateral from the requested repay amount |
| F-004 | rewritten_agent_signal | Medium | medium | codex_1 | Missing `maxAssets` enforcement allows asset-list bloat to gas-grief liquidity checks | codex_1:0.675 Missing `maxAssets` enforcement allows liquidation-denial via asset-list bloat |
| F-006 | rewritten_agent_signal | Medium | high | codex_1 | `fixBadAccruals` records COMP debt that future claims never honor | codex_1:0.551 COMP debt recorded by `fixBadAccruals` is never enforced on future claims |

## Rejection Reasons
- other: 2
- trust_or_owner_model: 9
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| unsupported_or_speculative | codex_1 | Borrow and redeem paths expose stale-liquidity reentrancy across markets | Only the abstract base contracts are in scope here; no concrete `doTransferOut` implementation is present that shows an attacker-controlled callback path. Without a concrete market implementation that can reenter, the claim is too speculative to report. |
| trust_or_owner_model | opencode_1 | Close Factor Not Validated on _setCloseFactor | This is an admin-only parameter-setting path. Any harm depends on privileged misconfiguration by the trusted admin, which is not a standalone protocol vulnerability in this codebase. |
| trust_or_owner_model | opencode_1 | Oracle Price Manipulation Risk | The report describes the trusted admin's ability to replace the oracle. That is a governance/control assumption, not an exploitable bug by unprivileged actors. |
| trust_or_owner_model | opencode_1 | No Timelock on Critical Admin Functions | Absence of a timelock is a governance design choice rather than a code vulnerability. The candidate does not identify an unprivileged exploit path. |
| trust_or_owner_model | opencode_1 | Liquidation Incentive Not Validated | This is another admin-only misconfiguration scenario. Since the same admin can already make broader privileged changes, the missing bound is not a distinct reportable vulnerability here. |
| trust_or_owner_model | opencode_1 | Interest Rate Model Can Be Changed Instantly | Changing the interest rate model is an intended admin power guarded by `msg.sender == admin` plus interface checks. This is governance trust, not a protocol bug. |
| trust_or_owner_model | opencode_1 | Comptroller Can Be Changed on CTokens | `_setComptroller` is an explicit admin hook and verifies the new target implements the comptroller marker. The candidate is a generic privileged-upgrade concern, not a vulnerability. |
| trust_or_owner_model | opencode_1 | Borrow Cap Guardian Can Disable Borrowing | The claim is factually incorrect for this code: `_setMarketBorrowCaps` documents and implements `0` as unlimited borrowing, not disabled borrowing. More generally, borrow-cap setting is an intended privileged control. |
| other | opencode_1 | COMP Accrual Fix Function Allows Arbitrary Adjustment | The function is a one-off admin-only remediation hook and the candidate relies on trusted-admin abuse. The reportable issue in this area is instead that recorded `compReceivable` debt is never enforced. |
| other | opencode_1 | Unitroller Delegatecall Reentrancy Risk | This is the standard upgradeable proxy delegation pattern. The candidate does not show a distinct exploit beyond compromising the trusted implementation/admin path. |
| trust_or_owner_model | opencode_1 | Market Deprecation Can Be Abused for Immediate Liquidation | `isDeprecated` is an explicit admin-controlled deprecation mechanism. The ability to deprecate a market is an intended governance action, not an accidental bypass. |
| trust_or_owner_model | opencode_1 | Pause Guardian Can Pause Critical Functions | The pause guardian is an intentional emergency-control role documented in storage comments. This is a trust/governance feature, not a bug. |
