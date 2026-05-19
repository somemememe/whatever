# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 7

## Finding Actions
- exact_agent_candidate: 2
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex_1,opencode_1 | Project funds can be permanently locked because refund progress is compared against NFT count instead of bid-record count | codex_1:0.634 Project funds can be permanently locked by comparing bidder progress to NFT count |
| F-002 | exact_agent_candidate | High | high | codex_1 | Any bidder can permanently block refund processing by reverting on ETH receipt | codex_1:0.889 Any bidder can brick refund processing by reverting on ETH receipt |
| F-003 | exact_agent_candidate | High | medium | codex_1 | Emergency withdrawal can refund bidders in full even after they already received NFTs | codex_1:0.897 Emergency withdrawal can give bidders a full refund even after they already received NFTs |
| F-004 | rewritten_agent_signal | High | high | codex_1 | Zero-amount bids create dummy records that can satisfy the withdrawal gate before all real refunds are processed | codex_1:0.522 Zero-amount bids let sybils create dummy bidder records and unlock premature project withdrawal |

## Rejection Reasons
- duplicate_or_subsumed: 1
- other: 5
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Reentrancy vulnerability in _bid() function | The function writes the bidder record, `totalBids`, and `totalBidValue` before the refund call. Reentry observes updated state and does not bypass bid limits or create a double-refund path. |
| duplicate_or_subsumed | opencode_1 | Reentrancy vulnerability in processRefunds() function | `allBids[i].finalProcess` is set before the external call, so a reentrant invocation cannot reclaim the same refund. Reentry may recurse into already-marked records but does not create duplicate payouts. |
| other | opencode_1 | Reentrancy vulnerability in emergencyWithdraw() function | `finalProcess` is set to `2` before sending ETH, so a reentrant call fails the `finalProcess == 0` check and cannot withdraw multiple times. |
| other | opencode_1 | Integer underflow in processRefunds() refund calculation | This is a descending-price auction, and `getPrice()` is clamped to `expiresAt`, so the final settlement price cannot exceed a bidder's recorded price. `bidData.price - price` therefore does not underflow in normal execution. |
| trust_or_owner_model | opencode_1 | Owner can bypass airdrop completion check | This requires a malicious or compromised owner abusing the explicit `onlyOwner` power to set the NFT contract address. It is a privileged-admin trust issue rather than a permissionless protocol flaw. |
| other | opencode_1 | No deadline extension for last-minute bidders | This is auction design/fairness, not a security vulnerability causing fund loss, insolvency, lockup, or DoS. |
| other | opencode_1 | Potential griefing via front-running bids | This describes ordinary mempool competition without a concrete invariant break or exploit path beyond normal auction ordering risk. |
