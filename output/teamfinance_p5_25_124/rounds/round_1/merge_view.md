# Merge View - Round 1

## Summary
- total findings: 5
- new findings: 5
- updated existing findings: 0
- rejected candidates: 14

## Finding Actions
- exact_agent_candidate: 3
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | High | medium | codex_1 | Uninitialized proxy deployment can be seized by the first caller | codex_1:0.951 Uninitialized deployment can be seized by the first caller |
| F-002 | exact_agent_candidate | Critical | high | codex_1,opencode_1 | Owner backdoor can reassign any user's locked assets to an arbitrary recipient | codex_1:1.0 Owner backdoor can reassign any user's locked assets to an arbitrary recipient |
| F-003 | rewritten_agent_signal | Medium | medium | codex_1 | Arbitrary-recipient dust locks can bloat a victim's deposit list and make some exits gas-prohibitive | codex_1:0.521 Anyone can grief a victim with arbitrary dust locks and make withdrawals gas-prohibitive |
| F-004 | exact_agent_candidate | Medium | high | codex_1 | The contract accepts arbitrary ERC721 transfers and permanently blackholes untracked NFTs | codex_1:1.0 The contract accepts arbitrary ERC721 transfers and permanently blackholes untracked NFTs |
| F-005 | rewritten_agent_signal | Medium | high | codex_1 | Referral fee math charges the discount percentage as the final fee | codex_1:0.753 Referral fee math undercharges by using the discount as the final fee percentage |

## Rejection Reasons
- duplicate_or_subsumed: 2
- other: 8
- trust_or_owner_model: 2
- unsupported_or_speculative: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | opencode_1 | Proxy Admin Can Hijack Implementation to Malicious Contract | Standard privileged upgradeability behavior; the admin's ability to upgrade implementation is an explicit trust assumption, not a distinct code bug. |
| other | opencode_1 | NFT Burned Before Token Transfer - Potential Loss of NFT | If the downstream `safeTransferFrom` reverts, the entire transaction reverts and the prior burn/state changes are rolled back; this is not a permanent-loss path. |
| other | opencode_1 | NFT Burned Before ERC20 Transfer in Partial Withdrawal | The ERC20 transfer uses `safeTransfer`, so any failure reverts the whole transaction and undoes the preceding burn/state updates. |
| unsupported_or_speculative | opencode_1 | Missing Validation Prevents Recovery of Stuck NFTs | `IERC721.safeTransferFrom` does not fail silently; a failed transfer reverts and rolls back `withdrawn = true`, so the described stuck state is unsupported. |
| other | opencode_1 | Inconsistent Unlock Time Enforcement in splitLock | After a split, the original and new locks are independent positions; extending one without extending the other is expected behavior, not a vulnerability. |
| other | opencode_1 | No Zero Address Validation for priceEstimator in setFeeParams | `setFeeParams()` gates `_priceEstimator` with `onlyContract`, so `address(0)` cannot be set through this function. |
| other | opencode_1 | No Validation of referrer Address in _chargeFeesReferral | The caller chooses the referrer for their own transaction, so an unpayable or bad referrer only causes self-inflicted failure rather than a protocol-level vulnerability. |
| other | opencode_1 | Unchecked Return Value in Fee Collection | The transfer return value is checked, and both `setFeeParams()` and `setCompanyWallet()` forbid `companyWallet == address(0)`. |
| unsupported_or_speculative | opencode_1 | Potential Integer Overflow in getFeesInETH Calculation | Arithmetic uses SafeMath in Solidity 0.6.2, so the claimed overflow path is not supported. |
| duplicate_or_subsumed | opencode_1 | Missing Event Emission in recoverAssets | Lack of an event is an observability issue, not a standalone reportable vulnerability beyond the underlying asset-seizure backdoor already captured. |
| other | opencode_1 | No Validation of tokenAddress in lockToken Function | Supplying an invalid token address mainly causes the caller's own transaction to revert; this is user error rather than protocol harm. |
| trust_or_owner_model | opencode_1 | Inconsistent Access Control for whitelistAdmins | Allowing owner-designated whitelist admins is an intentional governance choice, not a security flaw by itself. |
| duplicate_or_subsumed | opencode_1 | Potential Array Length Mismatch in depositsByWithdrawalAddress | A deposit id has a single current owner, so `recoverAssets()` cannot naturally duplicate an existing id in `newRecipient`'s array under normal state transitions. |
| other | opencode_1 | Missing Initialization Check in Contract Constructor | The proxy constructor already checks `delegatecall` success with `require(success)`; only intentionally skipped init data leaves the proxy uninitialized, which is covered by F-001. |
