# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 13

## Finding Actions
- rewritten_agent_signal: 4

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | High | high | codex_1,opencode_1 | Hard-delisting a live market removes its debt from solvency checks and bricks normal resolution flows | codex_1:0.722 Hard-delisting a live market makes its debt disappear from solvency checks while blocking all settlement |
| F-002 | rewritten_agent_signal | High | medium | codex_1 | `_supportMarket` can list an incompatible BToken from another comptroller as valid collateral | codex_1:0.455 Any contract returning `isBToken()` can be listed as collateral even if it belongs to another comptroller |
| F-003 | rewritten_agent_signal | High | high | codex_1 | Lowering a credit limit below existing debt preserves credit-account immunity and can freeze bad debt in place | codex_1:0.45 Reducing a credit limit does not reconcile existing debt, but still blocks third-party repayment and liquidation |
| F-004 | rewritten_agent_signal | Medium | medium | codex_1 | Soft-delisting a collateral-cap market clears its controller-side version flag and skips `unregisterCollateral` on exit | codex_1:0.718 Soft-delisting a collateral-cap market wipes its version flag, so users exit without running `unregisterCollateral` |

## Rejection Reasons
- other: 10
- trust_or_owner_model: 3

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex_1 | Listed markets can rewrite their own `version` in the Comptroller without admin approval | `updateBTokenVersion` is callable only by the listed BToken itself and only changes the controller-side enter/exit hook selection. In this snapshot that is not a standalone user-triggerable exploit; it depends on a trusted market contract or its upgrade/admin path already acting maliciously. |
| other | opencode_1 | Flash Loan Missing Liquidity and Collateral Checks | Flash loans are intentionally uncollateralized, and the provided code does not include a flash-loan implementation showing an unpaid-loan path. The Comptroller pause hook alone is not evidence of a drain. |
| other | opencode_1 | Soft-Delisted Markets Still Allow Critical Operations | Soft delisting intentionally preserves unwind flows. `mintAllowed` and `borrowAllowed` require `isMarketListed`, so new supply/borrows are blocked; allowing redeem/repay/liquidation on soft-delisted markets is expected behavior, not a bug. |
| trust_or_owner_model | opencode_1 | Unchecked Liquidation Incentive Allows Zero Value | This is an admin-only parameter choice, not a permissionless flaw. Governance can always make liquidation uneconomic by misconfiguring incentives. |
| trust_or_owner_model | opencode_1 | Unbounded Credit Limits Allow Infinite Borrowing | Unsecured credit lines are an explicit privileged feature here. The meaningful bug is the inability to resolve debt after reducing a still-positive limit, which is captured in F-003. |
| other | opencode_1 | Market Delisting Doesn't Check Outstanding Borrows | Merged into F-001. The reportable issue is specifically the hard-delist path, which both hides live debt from liquidity checks and blocks normal resolution. |
| trust_or_owner_model | opencode_1 | Guardian Can Permanently Pause Markets Without Oversight | Guardian/admin pause powers are explicit trusted-role emergency controls. This is governance/operational risk, not a protocol bug. |
| other | opencode_1 | No Price Freshness Validation in Oracle | Price freshness is delegated to the oracle implementation. No stale-price exploit is provable from the Comptroller code alone. |
| other | opencode_1 | Zero Supply/Borrow Caps Lock Markets Permanently | Zero caps are documented admin/guardian configuration semantics, not an unintended code defect. |
| other | opencode_1 | No Protection Against Sandwich Attacks in Liquidation | This is a generic MEV concern affecting public liquidations, not a protocol-specific vulnerability in the audited code. |
| other | opencode_1 | Interest Accrual Can Be Delayed Indefinitely | Lazy interest accrual on interaction is standard lending-market behavior and not, by itself, a vulnerability. |
| other | opencode_1 | Missing Access Control on Credit Limit Manager | Access control exists: only admin sets `creditLimitManager`, and only admin or that manager can change limits. The candidate describes trusted-role abuse, not missing access control. |
| other | opencode_1 | RedeemAllowed Allows Redemption from Delisted Markets Without Liquidity Check | If an account is not in the market, that asset is not being used as collateral, so bypassing the liquidity check is intentional. Market cash sufficiency is enforced on the BToken side, not here. |
