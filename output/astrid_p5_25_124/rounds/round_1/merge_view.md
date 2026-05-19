# Merge View - Round 1

## Summary
- total findings: 5
- new findings: 5
- updated existing findings: 0
- rejected candidates: 20

## Finding Actions
- exact_agent_candidate: 5

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex_1 | Arbitrary `IRestakedETH` contracts can redeem real pool assets with fake tokens | codex_1:1.0 Arbitrary `IRestakedETH` contracts can redeem real pool assets with fake tokens |
| F-002 | exact_agent_candidate | High | high | codex_1 | 1:1 minting lets new depositors capture rewards accrued before a manual rebase | codex_1:1.0 1:1 minting lets new depositors capture rewards accrued before a manual rebase |
| F-003 | exact_agent_candidate | High | high | codex_1 | A single oversized withdrawal can indefinitely block every later withdrawal | codex_1:1.0 A single oversized withdrawal can indefinitely block every later withdrawal |
| F-004 | exact_agent_candidate | High | medium | codex_1 | Legacy queued withdrawals can become permanently unclaimable after redelegation | codex_1:1.0 Legacy queued withdrawals can become permanently unclaimable after redelegation |
| F-005 | exact_agent_candidate | Medium | medium | codex_1 | Deposits mint against the requested amount instead of the actual tokens received | codex_1:1.0 Deposits mint against the requested amount instead of the actual tokens received |

## Rejection Reasons
- duplicate_or_subsumed: 2
- low_impact_or_operational: 1
- other: 14
- trust_or_owner_model: 3

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | opencode_1 | Missing slippage protection in deposit function | The function is atomic and always mints exactly `amount` in the same transaction; there is no intra-transaction rebase window. The real issue is stale 1:1 mint pricing before an admin-triggered rebase, which is already captured separately. |
| other | opencode_1 | Missing slippage protection in withdraw function | Queued withdrawals intentionally track rebasing shares via `requestedRestakedTokenShares` and convert them at processing time. Amount drift from later rebases is the designed accounting model, not a distinct slippage bug. |
| other | opencode_1 | Unbounded loop in _delegatorExists causes DoS | The loop is bounded by the admin-controlled `maxDelegators` cap and is only exercised from admin-only delegator management. No permissionless protocol-level DoS is shown. |
| trust_or_owner_model | opencode_1 | Unbounded loop in rebaseInfo causes DoS | This iteration is likewise bounded by `maxDelegators`, which governance sets before adding delegators. It is an administrative scalability limit, not a reportable permissionless DoS on users. |
| other | opencode_1 | Unchecked return value in payDirect | `Utils.payDirect` uses `SafeERC20.safeTransfer`, which reverts on failure. The returned `true` is redundant but does not mask failed transfers. |
| trust_or_owner_model | opencode_1 | Missing validation allows setting staked token to non-whitelisted | Changing whitelist status is a privileged configuration action, and existing holders are not locked by this alone because `withdraw()` does not check the whitelist flag. |
| other | opencode_1 | Incorrect access control on processWithdrawals | `processWithdrawals()` is explicitly protected by `onlyRole(DEFAULT_ADMIN_ROLE)`. |
| other | opencode_1 | Integer overflow in totalWithdrawalRequests | The contract is compiled with Solidity 0.8.9, so arithmetic overflow reverts instead of wrapping. |
| other | opencode_1 | Missing underflow protection in claim function | The subtraction uses Solidity 0.8 checked arithmetic and will revert on underflow. No independent manipulation path was shown. |
| other | opencode_1 | Missing zero address check in setStakedTokenMapping | `Utils.contractExists()` is required for all configured addresses, and the zero address fails that check. |
| other | opencode_1 | Potential reentrancy through token callback | `deposit()` is protected by `nonReentrant`, and the candidate does not show a viable callback path that bypasses it. |
| other | opencode_1 | Insufficient validation of delegator index in critical functions | `removeDelegator()` already checks `_delegatorIndex < delegators.length` before mutating the array. |
| other | opencode_1 | Missing deadline parameter in deposit/withdraw | A missing deadline is generic transaction UX/slippage hygiene, not a concrete protocol vulnerability in this codebase. |
| duplicate_or_subsumed | opencode_1 | Missing validation for duplicate delegator addition attempt | Duplicate delegators are explicitly rejected by `_delegatorExists()`. The remaining concern is only loop cost, which is bounded by `maxDelegators`. |
| trust_or_owner_model | opencode_1 | Admin can change eigenLayerStrategyManagerAddress to malicious contract | This is ordinary trusted-governance risk under an existing admin role, not a vulnerability in the permission model or implementation. |
| other | opencode_1 | No access control on completeQueuedWithdrawal legacy function | The function only reads `withdrawals[msg.sender]` and also checks `withdrawalInfo.withdrawer == msg.sender`, so callers cannot complete arbitrary other users' withdrawals. |
| other | opencode_1 | Missing check for stale data in claim function | `claim()` loads the caller's stored request, requires `PROCESSED` status, and updates both storage copies before transferring funds. No realistic stale-data exploitation path was demonstrated. |
| other | opencode_1 | Inconsistent token balance validation in restakeDelegator | The arithmetic is checked under Solidity 0.8, so a bad balance condition reverts instead of creating silent corruption. This is not a distinct exploitable issue. |
| low_impact_or_operational | opencode_1 | Missing event for critical initialization values | Event coverage is an observability concern, not a reportable security finding. |
| other | opencode_1 | Inconsistent revert messages | Inconsistent revert strings are not a security issue. |
