# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 10

## Finding Actions
- exact_agent_candidate: 4

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex_1 | Anyone can reinitialize the NFT contracts and seize deposit/funding token ownership | codex_1:1.0 Anyone can reinitialize the NFT contracts and seize deposit/funding token ownership |
| F-002 | exact_agent_candidate | High | high | codex_1 | Vested MPH rewards can make depositor withdrawals impossible unless users source extra MPH | codex_1:0.917 Vested MPH rewards can make depositor withdrawals impossible unless the user buys extra MPH |
| F-003 | exact_agent_candidate | High | high | codex_1 | `fundMultiple()` can charge new funders for stale deficits from already-withdrawn deposits that carry no recoverable claim | codex_1:1.0 `fundMultiple()` can charge new funders for stale deficits from already-withdrawn deposits that carry no recoverable claim |
| F-004 | exact_agent_candidate | Medium | high | codex_1 | Zero-coupon bond redemption is first-come-first-served instead of pro-rata when collateral is short | codex_1:1.0 Zero-coupon bond redemption is first-come-first-served instead of pro-rata when collateral is short |

## Rejection Reasons
- low_impact_or_operational: 1
- other: 5
- trust_or_owner_model: 4

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | opencode_1 | MPHMinter allows ownership transfer of MPH token to any address | This is an explicit `onlyOwner` governance/admin capability, not a permissionless vulnerability in the contract logic. |
| other | opencode_1 | DInterest early withdraw allows same-block attack via flash loan | The guard is `now > depositTimestamp`; transactions in the same block share the same timestamp, so a flash loan cannot bypass it within that block. |
| other | opencode_1 | ZeroCouponBond grants unlimited ERC20 approval to factory | This depends on compromise or malice of a trusted immutable factory, and no standalone permissionless exploit path was identified. |
| trust_or_owner_model | opencode_1 | YVaultMarket withdraw returns entire balance instead of actual amount | `withdraw()` is `onlyOwner`, so external users cannot directly exploit it; the code can sweep pre-existing dust, but no realistic user-profit or protocol-drain path was supported from source alone. |
| trust_or_owner_model | opencode_1 | DInterest owner can change critical contract addresses without timelock | This is a governance/trust-model concern about owner powers, not a code vulnerability. |
| other | opencode_1 | ZapCurve has hardcoded zapper address that cannot be updated | This is a rigidity/maintainability issue rather than a reportable security bug. |
| other | opencode_1 | DInterestWithDepositFee sends full deposit amount to money market despite fee deduction | The fee-adjusted accounting appears intentional and is paired with `_unapplyDepositFee()` when funders recapitalize deficits; no concrete loss or exploit was supported. |
| other | opencode_1 | Vesting contract has no access control on vest function | The caller provides the vested tokens via `transferFrom`, so third parties cannot spend someone else's tokens or steal funds through this function. |
| low_impact_or_operational | opencode_1 | Rewards contract lacks pause mechanism for emergency | Missing pause functionality is an operational design choice, not a concrete exploitable vulnerability. |
| trust_or_owner_model | opencode_1 | NFTFactory lacks access control allowing anyone to mint NFTs | `NFTFactory` only deploys new NFT clones; minting and burning on live pool position NFTs remain `onlyOwner`, so this does not let attackers mint real deposit/funding positions. |
