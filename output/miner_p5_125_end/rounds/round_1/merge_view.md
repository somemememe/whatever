# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 6

## Finding Actions
- exact_agent_candidate: 1
- new_unmatched: 1
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | High | high | codex_1 | ERC721-style `transferFrom` debits two NFT-worths of ERC20 balance for one NFT transfer | codex_1:0.921 ERC721-style `transferFrom` moves two NFT-worths of ERC20 balance for a single NFT transfer |
| F-002 | rewritten_agent_signal | High | high | codex_1 | Per-token approvals survive `safeTransferFrom` and `safeBatchTransferFrom`, leaving a latent theft backdoor on transferred NFTs | codex_1:0.755 Per-token approvals survive `safeTransferFrom` and `safeBatchTransferFrom`, letting old approvees steal from future owners |
| F-003 | rewritten_agent_signal | Medium | high | codex_1,opencode_1 | Small ERC20 approvals are reinterpreted as NFT approvals | codex_1:0.762 Small ERC20 approvals are reinterpreted as NFT approvals, enabling phishing-style NFT theft |
| F-004 | new_unmatched | Medium | high |  | Transfer-delay hook self-reverts ERC20 transfers that both burn and mint NFTs in one transaction | opencode_1:0.471 Transfer Delay Can Be Bypassed via NFT Transfer Functions |

## Rejection Reasons
- duplicate_or_subsumed: 1
- other: 4
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | NFT Burning Logic Incorrectly Calculates Burn Amount Leading to Token/NFT Loss | The cited formula in `_update` correctly counts how many whole `tokensPerNFT` thresholds the sender crossed during an ERC20 transfer; by itself it does not miscompute burns. |
| other | opencode_1 | Max Wallet Limit Can Be Bypassed via NFT Transfer Functions | `safeTransferFrom` and `safeBatchTransferFrom` both reach `_afterTokenTransfer`, and the `ERC_X` override enforces the `maxWallet` check there. |
| other | opencode_1 | Transfer Delay Can Be Bypassed via NFT Transfer Functions | The NFT transfer paths also hit `_afterTokenTransfer`; the supported issue is the opposite one, where the delay hook can self-revert certain ERC20 transfers. |
| other | opencode_1 | _burnBatch Search from _nextTokenId() Fails When Tokens Have Been Burned | `findLastSet(before)` is a backward scan, so starting from `_nextTokenId()` and then updating `searchFrom = id` correctly walks down previously owned token ids even when gaps exist. |
| duplicate_or_subsumed | opencode_1 | ERC20/NFT ID Space Collision Creates Ambiguity | Too generic as stated; the concrete, reportable consequences are already captured by the approval-confusion and broken NFT `transferFrom` findings. |
| unsupported_or_speculative | opencode_1 | Missing Verification of NFT Ownership Before transferFrom NFT Path | Unsupported speculation: the path checks `_owned[from].get(value)` before proceeding, and no concrete race or reentrancy-based exploit was demonstrated. |
