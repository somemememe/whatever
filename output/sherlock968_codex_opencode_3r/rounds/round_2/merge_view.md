# Merge View - Round 2

## Summary
- total findings: 12
- new findings: 4
- updated existing findings: 0
- rejected candidates: 8

## Finding Actions
- exact_agent_candidate: 1
- existing_preserved: 8
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-009 | rewritten_agent_signal | Medium | medium | codex_1 | Locker and Fontaine implementations snapshot pool addresses before setup can complete | codex_1:0.439 Locker hard-caches distribution pool addresses as immutables, enabling permanent unlock/LP DoS from stale setup |
| F-010 | exact_agent_candidate | Medium | low | codex_1 | Permissionless base program manager allows irreversible program ID squatting | codex_1:0.871 Permissionless `createProgram` allows irreversible program-ID squatting |
| F-011 | rewritten_agent_signal | Medium | high | codex_1 | Zero-unit tax pools freeze instant and short unlocks | codex_1:0.375 Unlock liveness depends on third-party pool participation; zero-unit pools freeze fast exits |
| F-012 | rewritten_agent_signal | Low | medium | opencode_1 | Permissionless tax adjustment distribution can force an unfavorable reward snapshot | opencode_1:0.446 Permissionless distributeTaxAdjustment allows front-running and untracked execution |

## Rejection Reasons
- duplicate_or_subsumed: 1
- low_impact_or_operational: 1
- other: 3
- trust_or_owner_model: 2
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | codex_1 | Program `totalAmount` cap is not enforced on-chain after end date | Superfluid streams require an explicit transaction to stop, and this contract makes `stopFunding()` permissionless once the early-end window opens. Delayed stopping is primarily keeper/operator liveness, while concrete exploitable stop-timing and repeated-start issues are already captured in F-002 and F-004. |
| other | codex_1 | Unchecked uint256→uint128 downcasts can silently corrupt unit accounting | The casts exist, but the practical inputs are trusted signer/admin values or locker balances/liquidity values that would need to exceed unrealistic `uint128` bounds. No realistic untrusted path was identified that causes protocol-level harm. |
| other | opencode_1 | Vesting cliffAmount equals totalAmount traps all tokens in contract | The code explicitly reverts when `cliffAmount >= amount`, so the equality case cannot be created. |
| low_impact_or_operational | opencode_1 | Missing event emission prevents liquidity provision tracking | Missing events are an observability/indexing issue. The Uniswap position NFT, locker state, and token movements remain on-chain, so this is not a protocol-level vulnerability. |
| trust_or_owner_model | opencode_1 | Owner can drain program funds via emergencyWithdraw without accounting | `emergencyWithdraw()` is `onlyOwner` and sends funds to the configured treasury. The owner already controls program creation, funding, cancellation, and treasury settings, so this is a privileged-admin risk rather than an untrusted exploit. |
| trust_or_owner_model | opencode_1 | Vesting emergencyWithdraw can steal recipient vested tokens | The function is restricted to the factory admin and returns remaining funds to the treasury as an emergency/revocation path. This is a centralization or trust-model concern, not a permissionless protocol bug. |
| unsupported_or_speculative | opencode_1 | lpDistributionPool not validated before distributeTaxAdjustment | The useful timing aspect was folded into F-012. The standalone claim that funds are silently lost to `address(0)` is not supported; calls to an unset pool would revert rather than complete as a silent loss. |
| other | opencode_1 | Liquidity removal lacks slippage protection in withdrawal path | `_decreasePosition()` does set `amount0Min` and `amount1Min` before calling Uniswap. Later `collect()` only collects owed principal/fees and does not bypass those minimums; fee accrual variance is not a slippage-protection vulnerability. |
