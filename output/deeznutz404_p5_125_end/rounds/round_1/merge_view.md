# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 12

## Finding Actions
- exact_agent_candidate: 4

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | High | high | codex_1 | Anyone can front-run and permanently hijack the mirror/base link | codex_1:1.0 Anyone can front-run and permanently hijack the mirror/base link |
| F-003 | exact_agent_candidate | Medium | high | codex_1,opencode_1 | NFT transfers bypass the configured transfer tax for every whole-`_WAD` chunk | codex_1:1.0 NFT transfers bypass the configured transfer tax for every whole-`_WAD` chunk |
| F-004 | exact_agent_candidate | Medium | high | codex_1 | Excluded accounts cannot ever be re-included into reflections | codex_1:1.0 Excluded accounts cannot ever be re-included into reflections |
| F-005 | exact_agent_candidate | Medium | high | codex_1,opencode_1 | Ownership is assigned to `tx.origin`, not the actual deployer | codex_1:1.0 Ownership is assigned to `tx.origin`, not the actual deployer |

## Rejection Reasons
- other: 9
- trust_or_owner_model: 2
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex_1 | Large inactive holders can be frozen once reflections shrink `rTotal` below their stale `rOwned` | Rejected: the implemented transfer and `reflect()` paths preserve the reflected-supply invariant, so an individual holder's `rOwned` does not naturally grow past global `rTotal` under the code shown. |
| other | codex_1 | `reflect()` can leave excess NFTs outstanding and temporarily untransferable | Rejected: the stale NFT count is real after self-`reflect()`, but it is self-inflicted and can be reconciled by a later ERC20 transfer path; this does not clear the reportability bar for protocol-level harm. |
| other | opencode_1 | Reflection fee calculation bug causes underflow for excluded recipients | Rejected: the excluded-recipient branch credits `rOwnedTo` with `rTransferAmount` and `tOwnedTo` with `tTransferAmount`, which is the correct post-fee accounting. |
| trust_or_owner_model | opencode_1 | Backdoor allows Uniswap router to transfer from owner when trading is disabled | Rejected: this is an explicit owner-only launch exception, and the owner is already separately allowed to transfer while trading is disabled; it is not an unauthorized bypass. |
| other | opencode_1 | _transferFromNFT doesn't check tradingEnabled flag | Rejected: the `DeezNutz` override does enforce a trading check. In fact, because NFT calls arrive from the mirror contract, pre-trading NFT transfers are blocked rather than bypassed. |
| other | opencode_1 | Owner can manipulate reflection rate through includeAccount | Rejected: `includeAccount()` is already unusable because of the inverted `isExcluded` check, and `renounceFunctions()` never claims to renounce that function. |
| other | opencode_1 | reflect function has no access control | Rejected: `reflect()` is an intentional self-burn primitive that only affects the caller's own reflected balance and does not create a standalone exploit. |
| other | opencode_1 | Uniswap router address cannot be updated after deployment | Rejected: router immutability is a deployment/configuration choice, not a security vulnerability. |
| trust_or_owner_model | opencode_1 | Incomplete renounceFunctions leaves admin functions accessible | Rejected: the function comment explicitly says it renounces only `setTaxFee` and `excludeAccount`; retaining other owner powers is the documented design. |
| unsupported_or_speculative | opencode_1 | Missing return value in ERC20 approve function | Rejected: `approve()` explicitly returns `true`, so the claimed ERC20 incompatibility is unsupported. |
| other | opencode_1 | NFT transfer doesn't verify tradingEnabled status in mirror | Rejected: the mirror delegates into the base contract, and the base override applies the trading gate there; there is no mirror-side bypass. |
| other | opencode_1 | includeAccount lacks functionsRenounced check but excludeAccount has it | Rejected: the asymmetry is not independently exploitable, and `includeAccount()` is already broken by the inverted exclusion check. |
