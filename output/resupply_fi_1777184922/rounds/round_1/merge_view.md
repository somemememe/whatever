# Merge View - Round 1

## Summary
- total findings: 2
- new findings: 2
- updated existing findings: 0
- rejected candidates: 3

## Finding Actions
- exact_agent_candidate: 1
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | High | high | codex | Oracle decimal scaling is ignored, so non-18-decimal feeds misprice collateral by orders of magnitude | codex:1.0 Oracle decimal scaling is ignored, so non-18-decimal feeds misprice collateral by orders of magnitude |
| F-003 | rewritten_agent_signal | Medium | medium | codex | Unchecked Convex staking results can leave credited collateral unstaked and later lock withdrawals/liquidations | codex:0.468 Unchecked Convex deposits can strand collateral while accounting assumes everything was staked |

## Rejection Reasons
- other: 2
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | codex | Collateral is released and debt is written off before redemption/liquidation settlement is verified | `redeemCollateral()` and `liquidate()` are explicitly restricted to registry-configured handler contracts. The missing local settlement check is a trusted-module assumption about privileged handlers, not a permissionless pair-level exploit supported by the code alone. |
| other | codex | Share refactors leave `currentRateInfo.lastShares` stale across epochs | `currentRateInfo.lastShares` is initialized from `IERC4626(_collateral).convertToShares(1e18)` and passed to the rate calculator as collateral-vault share data, not borrow-share supply. Borrow-share refactoring during redemption therefore does not make this value stale in the way claimed. |
| other | codex | Raw oracle responses are accepted without zero, freshness, or sanity checks | Aside from the separate decimal-normalization bug, this report mostly describes oracle-layer failures or trust assumptions. A zero/stale/manipulated price would come from the configured oracle itself, and the code does not show that the pair is expected to enforce freshness/deviation validation independently. |
