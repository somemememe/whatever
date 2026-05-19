# Merge View - Round 1

## Summary
- total findings: 5
- new findings: 3
- updated existing findings: 2
- rejected candidates: 3

## Finding Actions
- exact_agent_candidate: 3
- existing_rewritten: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-002 | existing_rewritten | Medium | medium | codex | Positive-balance token mechanics let anyone skim unaccounted surplus from the pair | codex:0.308 Anyone can steal pending withdrawals once LP tokens have been transferred into the pair |
| F-003 | existing_rewritten | Medium | medium | codex | Balance-decreasing tokens can desynchronize reserves, DoS swaps, and force LP losses on sync | codex:0.284 Oracle reserves and TWAP can be forged by malicious tokens that spoof `balanceOf` during `sync`/`_update` |
| F-004 | exact_agent_candidate | Critical | high | codex | Swap accounting trusts untrusted token `balanceOf`, enabling free withdrawal of the honest-side asset | codex:1.0 Swap accounting trusts untrusted token `balanceOf`, enabling free withdrawal of the honest-side asset |
| F-005 | exact_agent_candidate | High | high | codex | Oracle reserves and TWAP can be forged by malicious tokens that spoof `balanceOf` during `sync` and reserve updates | codex:0.918 Oracle reserves and TWAP can be forged by malicious tokens that spoof `balanceOf` during `sync`/`_update` |
| F-008 | exact_agent_candidate | Low | medium | codex | Cached EIP-712 domain separator allows permit replay after a chain split or chain-id change | codex:0.869 Cached EIP-712 domain separator allows permit replay after a chain-id change or fork |

## Rejection Reasons
- other: 2
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex | Anyone can steal already-transferred liquidity deposits by calling `mint` first | This is the intended low-level pair pattern inherited from Uniswap V2: token transfer and `mint` must be finalized atomically, typically through a router. It only affects users or integrations that split the deposit flow across transactions, so it is integration misuse rather than a standalone protocol flaw. |
| other | codex | Anyone can steal pending withdrawals once LP tokens have been transferred into the pair | This is likewise the expected low-level `burn` flow: LP tokens are transferred to the pair and burned in the same transaction. A front-run is only possible for naive multi-transaction integrations or direct misuse, not during the intended atomic interaction pattern. |
| trust_or_owner_model | codex | Pair can be re-initialized by the factory because `initialize` lacks a one-time guard | Only the `factory` address can call `initialize`. Without evidence that the factory itself exposes an attacker-reachable path, this depends on privileged misuse or compromise of a trusted component rather than an independent permissionless vulnerability in the pair. |
