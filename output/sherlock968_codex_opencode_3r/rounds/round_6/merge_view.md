# Merge View - Round 6

## Summary
- total findings: 20
- new findings: 1
- updated existing findings: 0
- rejected candidates: 12

## Finding Actions
- existing_preserved: 19
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-021 | rewritten_agent_signal | Low | medium | codex_1 | Direct execution of claim signatures can consume the nonce before locker pool connection | codex_1:0.372 Permissionless signature execution enables nonce-burning frontruns and forced reward snapshot timing |

## Rejection Reasons
- duplicate_or_subsumed: 2
- low_impact_or_operational: 1
- other: 6
- trust_or_owner_model: 3

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex_1 | Batch unit signatures are hash-ambiguous because dynamic array lengths are not committed | The contract enforces `programIds.length == newUnits.length`, and both arrays contain fixed-width `uint256` elements. Any alternate calldata that preserves the same packed bytes and passes the equal-length check has the same boundary and the same semantic mapping, so the proposed collision is not actionable. |
| other | codex_1 | Vesting factory does not validate recipient address, allowing zero-address vesting creation | The path is admin-only and depends on the external vesting scheduler accepting a zero recipient. A compromised or misconfigured admin can already allocate vestings to arbitrary recipients, so this is an admin footgun rather than an adversarial protocol vulnerability. |
| low_impact_or_operational | opencode_1 | Missing event emission in provideLiquidity | Missing event emission is an observability issue and does not by itself cause fund loss, insolvency, lockup, economic manipulation, or permissionless DoS. |
| duplicate_or_subsumed | opencode_1 | Permissionless distributeTaxAdjustment can front-run reward distribution | The permissionless snapshot/timing risk is already captured by F-012. The added sandwich/arbitrage claim is unsupported because `distributeTaxAdjustment()` performs no swap or price-sensitive trade. |
| other | opencode_1 | No Access Control on MacroForwarder.runMacro | `MacroForwarder` is intentionally permissionless, and the candidate does not show a path where arbitrary operations execute with another account's permissions. The macro builds operations for `msg.sender`, so no concrete codebase-specific theft or state-manipulation path is established. |
| trust_or_owner_model | opencode_1 | Vesting emergencyWithdraw can steal unvested tokens | `emergencyWithdraw()` is restricted to the vesting admin and returns remaining funds to the treasury. The candidate describes a privileged emergency/policy action, not an unprivileged exploit or invariant violation supported by the code. |
| duplicate_or_subsumed | opencode_1 | No validation of lpDistributionPool setupLPDistributionPool timing | The claim is vague and does not identify a concrete funds-dependent setup invariant. The meaningful stale-pool deployment timing issue is already captured by F-009. |
| trust_or_owner_model | opencode_1 | Inconsistent access control patterns across contracts | The cited `setLockerFactory()` and `setTreasury()` functions do validate zero addresses, and `setSubsidyRate()` is bounded. Missing events for owner-only configuration changes are not a reportable protocol-level vulnerability. |
| other | opencode_1 | Unlock period validation allows instant unlock bypass | Instant unlock with an 80% penalty is an explicit code path, not a bypass. The candidate does not show violation of a stated invariant or an exploit against other users. |
| other | opencode_1 | No deadline validation in provideLiquidity | `provideLiquidity()` uses a short `block.timestamp + 1 minute` deadline for the Uniswap mint. Lack of user-controlled deadline is a UX tradeoff and the candidate does not show a realistic delayed-execution exploit. |
| trust_or_owner_model | opencode_1 | Tax allocation can be set to zero values | The allocation is owner-controlled and the sum is validated to 100%. Allowing governance to route all tax to one pool is a policy choice unless a stronger invariant says both pools must receive nonzero shares. |
| other | opencode_1 | Factory can create vestings for any recipient without recipient consent | The vesting factory is admin-controlled and allocation to recipients is the admin's role. Recipient consent is not a security boundary, and the candidate does not show an adversarial path beyond trusted-admin misallocation. |
