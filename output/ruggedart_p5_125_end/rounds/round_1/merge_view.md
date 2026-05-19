# Merge View - Round 1

## Summary
- total findings: 7
- new findings: 7
- updated existing findings: 0
- rejected candidates: 13

## Finding Actions
- exact_agent_candidate: 1
- rewritten_agent_signal: 6

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-003 | rewritten_agent_signal | Critical | high | codex_1 | Any user can buy staked NFTs out of the shared pool at a fixed 1.1-token price | codex_1:0.614 Any user can purchase other users' staked NFTs from the pooled inventory at a flat price |
| F-002 | rewritten_agent_signal | High | high | codex_1 | NFT staking destroys asset identity and only returns a fungible balance claim | codex_1:0.596 NFT staking irreversibly converts unique NFTs into fungible balance claims |
| F-004 | rewritten_agent_signal | High | medium | codex_1,opencode_1 | Rugged transfers are never validated, so failed or short transfers can desynchronize market accounting | codex_1:0.368 Swap-based purchases can permanently trap refunded or unspent ETH inside the market |
| F-006 | exact_agent_candidate | High | high | codex_1 | The unbounded incentives array can eventually gas-DoS staking, claiming, and withdrawals | codex_1:0.926 The unbounded incentives array can eventually freeze staking, claiming, and withdrawals |
| F-005 | rewritten_agent_signal | Medium | high | codex_1 | Successful swap purchases can strand refunded or unused ETH in the market contract | codex_1:0.691 Swap-based purchases can permanently trap refunded or unspent ETH inside the market |
| F-001 | rewritten_agent_signal | High | low | codex_1 | Missing lower-bound token ID validation may allow zero-ID free staking | opencode_1:0.515 Inverted validation logic in stake allows minimal stake amount |
| F-008 | rewritten_agent_signal | Medium | high | merge_review | Incentives that elapse while nobody is staked become permanently stranded | codex_1:0.447 Any user can purchase other users' staked NFTs from the pooled inventory at a flat price |

## Rejection Reasons
- duplicate_or_subsumed: 1
- factually_incorrect: 1
- other: 10
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex_1 | An uninitialized proxy can be seized by the first external caller | This deployment is not a proxy (`_etherscan_meta.json` shows `proxy: 0`), and the constructor calls `_disableInitializers()`, so the verified deployed instance is not exposed to first-caller initialization takeover. |
| unsupported_or_speculative | opencode_1 | Missing nonReentrant on targetedPurchase allows reentrancy | The report does not show a concrete reentrant asset-drain path. The function’s external calls are to the configured Rugged token/router, and the claimed callback mechanism is unsupported by the code shown. |
| other | opencode_1 | No slippage protection in swap execution enables sandwich attacks | Slippage bounds belong in the user-supplied Universal Router calldata. This contract also enforces a minimum Rugged amount sufficient to fund the purchase, so the claimed issue is not an inherent protocol flaw here. |
| other | opencode_1 | Inverted validation logic in stake allows minimal stake amount | `stake()` intentionally accepts amounts above `10_000` and rejects values in the NFT-ID range. That is consistent with the hybrid token design implied elsewhere in the contract, not a vulnerability by itself. |
| factually_incorrect | opencode_1 | Incorrect balance check causes DoS and potential fund loss | `afterSwapBalance - beforeSwapBalance` correctly measures the swap’s net Rugged inflow even when the contract already has an existing Rugged balance. The candidate’s stated failure mode is incorrect. |
| other | opencode_1 | No refund on swap failure causes permanent fund loss | If `UNIVERSAL_ROUTER.execute` reverts, the whole transaction reverts, including the ETH transfer. The real issue is only successful-call leftover ETH becoming trapped, which is already retained separately. |
| other | opencode_1 | Incentive rewards not validated before recording | This is not a distinct finding from the broader unchecked-transfer/accounting issue already retained; the same root cause affects incentives, staking, purchases, and payouts. |
| other | opencode_1 | Missing initializer on immutable variable declaration | The verified contract compiled and deployed successfully, and the immutable declaration/assignment pattern used here is valid Solidity. |
| other | opencode_1 | stakeNFTs allows double-staking of same NFT tokenIds | After the first transfer, the NFT is owned by the market contract, so the original user cannot simply stake the same token ID again unless the token implementation is already broken in a broader way. |
| duplicate_or_subsumed | opencode_1 | Non-standard IRugged interface lacks safe transfer handling | As written, this is too generic to stand alone. The concrete protocol risk from unchecked Rugged transfer semantics is already captured in the retained accounting finding. |
| other | opencode_1 | executeSwap reverts without error message for zero value | This is developer-experience feedback, not a protocol-level security issue. |
| other | opencode_1 | No deadline validation on swap parameters | The Universal Router enforces the supplied deadline; duplicating that check locally would not change protocol safety. |
| other | opencode_1 | Inconsistent ether unit conversion in stakeNFTs | This describes confusing accounting conventions, not a standalone exploit or realistic protocol-harm issue. |
