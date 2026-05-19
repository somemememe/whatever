# Merge View - Round 1

## Summary
- total findings: 6
- new findings: 6
- updated existing findings: 0
- rejected candidates: 10

## Finding Actions
- exact_agent_candidate: 4
- new_unmatched: 1
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex_1 | CryptoPunks can be pledged with `nftType=1155`, permanently locking wrapped collateral and enabling bad debt | codex_1:1.0 CryptoPunks can be pledged with `nftType=1155`, permanently locking wrapped collateral and enabling bad debt |
| F-002 | rewritten_agent_signal | High | high | codex_1 | ETH settlement paths use `transfer`, so malicious contract recipients can permanently brick auctions and withdrawals | codex_1:0.743 ETH payouts use `transfer`, letting contract bidders or liquidators permanently brick auctions and withdrawals |
| F-003 | exact_agent_candidate | Medium | medium | codex_1 | Liquidated collateral continues routing airdrop value to the defaulted borrower until the auction fully ends | codex_1:0.953 Liquidated collateral keeps routing airdrop value to the defaulted borrower until the auction fully ends |
| F-004 | exact_agent_candidate | High | high | codex_1 | Admin can sweep escrowed auction and redemption funds, not just protocol income | codex_1:1.0 Admin can sweep escrowed auction and redemption funds, not just protocol income |
| F-005 | exact_agent_candidate | High | high | codex_1,opencode_1 | Admin `claim()` is an unrestricted arbitrary call that can transfer pledged NFTs and tokens out of escrow | codex_1:0.945 Admin `claim()` is an unrestricted arbitrary call that can transfer pledged NFTs out of escrow |
| F-006 | new_unmatched | Medium | low |  | `notifyRepayBorrow()` authenticates with `tx.origin`, which can block repayment-and-claim for contract wallets or third-party payers | codex_1:0.339 ETH payouts use `transfer`, letting contract bidders or liquidators permanently brick auctions and withdrawals |

## Rejection Reasons
- duplicate_or_subsumed: 1
- factually_incorrect: 3
- other: 3
- trust_or_owner_model: 2
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| unsupported_or_speculative | opencode_1 | airDrop function allows NFT theft via malicious xAirDrop contract | Unsupported: `airDrop()` is atomic, so if `xAirDrop` fails to return the NFT the final transfer reverts and the initial transfer to `xAirDrop` is rolled back. |
| duplicate_or_subsumed | opencode_1 | setXAirDrop allows admin to set malicious contract to steal all NFTs | Unsupported as written: a malicious `xAirDrop` alone cannot keep NFTs because the full `airDrop()` transaction reverts unless the NFT is returned; remaining admin-risk is already captured by the broader arbitrary-call finding. |
| other | opencode_1 | Missing nonReentrant modifier in notifyOrderLiquidated allows reentrancy attack | Not substantiated: the function is controller-only, updates liquidation state before the transfer, and no realistic callback path was found that lets the recipient steal assets or corrupt accounting. |
| trust_or_owner_model | opencode_1 | Missing nonReentrant modifier in notifyRepayBorrow allows reentrancy attack | Not substantiated: although the transfer happens before `isWithdraw` is set, ownership has already moved during the ERC721 callback, so a reentrant second withdrawal/transfer would fail rather than extract extra assets. |
| trust_or_owner_model | opencode_1 | setPunks allows admin to set malicious punk contracts to steal user NFTs | Primarily a privileged configuration/trust issue and weaker than the accepted admin arbitrary-call/withdraw findings, which already let the admin extract escrowed assets directly. |
| factually_incorrect | opencode_1 | No minimum price protection in auction allows unfair liquidation | This describes protocol auction design rather than a concrete implementation bug; no incorrect accounting or broken invariant was identified. |
| factually_incorrect | opencode_1 | No slippage protection in doTransferIn for ERC20 tokens | Incorrect: `doTransferIn()` explicitly checks that the balance delta equals `amount`, so fee-on-transfer/deflationary tokens revert instead of causing silent accounting drift. |
| factually_incorrect | opencode_1 | Division before multiplication can cause precision loss in auctionAllowed | Incorrect: the code computes `lastPrice.mul(_increasingMin).div(1e18)`, so multiplication already occurs before division. |
| other | opencode_1 | Fixed gas limit in ETH transfer may cause transfer failures | As framed, this only affects the caller-controlled ETH change refund path in `doTransferIn()`; the reportable protocol-level DoS is the separate accepted finding about `doTransferOut()` using `transfer` for settlement payouts. |
| other | opencode_1 | No validation that collection whitelist settings are reasonable | This is an admin-parameterization concern, not a standalone implementation vulnerability. |
