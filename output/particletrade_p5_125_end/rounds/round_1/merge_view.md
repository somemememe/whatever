# Merge View - Round 1

## Summary
- total findings: 3
- new findings: 3
- updated existing findings: 0
- rejected candidates: 1

## Finding Actions
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex_1 | `multicall` reuses one `msg.value` across multiple payable delegatecalls, allowing unbacked loans and bid margins | codex_1:0.829 Multicall reuses one `msg.value` across multiple payable delegatecalls, creating unbacked collateral and phantom balances |
| F-002 | rewritten_agent_signal | Critical | high | codex_1 | `refinanceLoan` rewrites the old lien to the new lender's token, letting the old lender withdraw the replacement collateral | codex_1:0.702 Refinancing aliases the new lender's NFT into the old lien, allowing the old lender to steal the replacement collateral |
| F-003 | rewritten_agent_signal | High | medium | codex_1 | Loan closeout paths treat NFTs as collection-fungible, allowing replacement of a rare escrowed token with any cheaper token from the same collection | codex_1:0.403 Loan closure paths accept any token ID from the same collection, enabling rare-NFT substitution with a cheap floor token |

## Rejection Reasons
- other: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex_1 | Lenders can liquidate immediately because auctions have no maturity, delinquency, or health check | `startLoanAuction` is intentionally permissioned to the lender on any active loan and the interface exposes no promised minimum term, delinquency threshold, or solvency invariant. In the code available here this is a protocol design choice, not a broken accounting, authorization, or collateral invariant. |
