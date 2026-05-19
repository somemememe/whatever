# Merge View - Round 1

## Summary
- total findings: 8
- new findings: 8
- updated existing findings: 0
- rejected candidates: 10

## Finding Actions
- exact_agent_candidate: 5
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex_1 | Stale depositor authorization lets a previous owner reclaim transferred deposited NFTs and their staking proceeds | codex_1:0.897 Stale depositor authorization lets the previous owner reclaim sold/liquidated deposited NFTs and their staking proceeds |
| F-002 | exact_agent_candidate | High | high | codex_1 | Pair withdrawals authenticate only the BAKC leg and ignore current BAYC/MAYC ownership | codex_1:1.0 Pair withdrawals authenticate only the BAKC leg and ignore current BAYC/MAYC ownership |
| F-003 | exact_agent_candidate | High | medium | codex_1 | Partial unstake silently strands accrued ApeCoin rewards inside ApeStaking | codex_1:1.0 Partial unstake silently strands accrued ApeCoin rewards inside ApeStaking |
| F-004 | rewritten_agent_signal | Medium | low | codex_1 | Reward claims follow current ownership instead of the recorded staker when ownership drift exists | codex_1:0.663 Rewards can be claimed by the current NFT owner instead of the recorded staker |
| F-005 | exact_agent_candidate | High | medium | codex_1 | Borrow and liquidation decisions use the last configured rewards range instead of the active one | codex_1:1.0 Borrow and liquidation decisions use the last configured rewards range instead of the active one |
| F-006 | exact_agent_candidate | Medium | high | codex_1,opencode_1 | Per-NFT iToken balances are floor-split, which can lock withdrawals and strand residual collateral | codex_1:1.0 Per-NFT iToken balances are floor-split, which can lock withdrawals and strand residual collateral |
| F-007 | rewritten_agent_signal | Medium | medium | opencode_1 | Ignoring non-zero iToken mint error codes can strand newly deposited NFTs | codex_1:0.398 Per-NFT iToken balances are floor-split, which can lock withdrawals and strand residual collateral |
| F-008 | rewritten_agent_signal | Medium | low | codex_1,merge_review | One ownership-mismatched NFT flips the entire withdrawal batch into redeem mode | codex_1:0.384 Per-NFT iToken balances are floor-split, which can lock withdrawals and strand residual collateral |

## Rejection Reasons
- duplicate_or_subsumed: 1
- factually_incorrect: 1
- low_impact_or_operational: 1
- other: 6
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Missing zero address validation for fee recipient | This is an admin misconfiguration risk only. Setting `feeTo` to `address(0)` burns protocol fees but does not create a permissionless exploit or user-funds vulnerability in the audited logic. |
| other | opencode_1 | Potential integer overflow in exchange rate calculation | The contract is compiled with Solidity 0.8.10, so arithmetic overflow reverts automatically. This is not a live vulnerability. |
| other | opencode_1 | Permissionless liquidation can be triggered by anyone | `unstakeAndRepay` is intentionally public and pays a liquidation reward. It is gated by a health check on the victim position, so this is expected protocol behavior rather than an access-control flaw. |
| other | opencode_1 | Unlimited ERC20 token approvals | Granting max approvals to trusted core integrations is standard and not reportable on its own without a concrete compromise or malicious-upgrade path in scope. |
| other | opencode_1 | Missing input validation for NFT asset in staking | `depositAndBorrowApeAndStake` immediately calls `_getPTokenStaking(stakingInfo.nftAsset)`, which already restricts `nftAsset` to BAYC or MAYC via `require`. |
| low_impact_or_operational | opencode_1 | Missing array length validation in withdraw function | Supplying very large arrays only risks the caller's own gas usage. This is not a protocol-level vulnerability. |
| other | opencode_1 | Missing validation for stakingInfo borrowAmount | Borrow sizing is already constrained by the staking-rate check in ApeStaking and by downstream `apePool.borrowBehalf` logic. The candidate does not identify a concrete bypass. |
| duplicate_or_subsumed | opencode_1 | No check for duplicate NFT IDs in deposit arrays | Duplicate IDs would cause the second `safeTransferFrom` to fail because the caller no longer owns the NFT, reverting the transaction rather than creating exploitable incorrect accounting. |
| factually_incorrect | opencode_1 | No access control on claimAndRestake | The function does have access control: `msg.sender` must be `userAddr` or hold `REINVEST_ROLE`. The reported title is factually incorrect. |
| unsupported_or_speculative | opencode_1 | Division by zero in getStakeInfo when poolId is invalid | `getStakeInfo` performs no division at all. The candidate is unsupported by the source code. |
