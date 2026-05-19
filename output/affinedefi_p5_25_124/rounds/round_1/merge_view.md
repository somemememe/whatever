# Merge View - Round 1

## Summary
- total findings: 5
- new findings: 5
- updated existing findings: 0
- rejected candidates: 16

## Finding Actions
- rewritten_agent_signal: 5

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | High | high | codex_1,opencode_1 | Curve near-par minimum output plus swallowed divest reverts can permissionlessly DoS strategy exits | codex_1:0.632 Curve price skew or stETH depeg can permissionlessly DoS all strategy exits |
| F-002 | rewritten_agent_signal | High | high | codex_1 | Balancer flash-loan fees are ignored, so any nonzero fee bricks flash-loan-dependent flows | codex_1:0.795 Balancer flash-loan fees are ignored, so any nonzero fee bricks the strategy |
| F-003 | rewritten_agent_signal | Medium | medium | codex_1 | `totalLockedValue()` underflows instead of flooring at zero, blocking distressed-strategy recovery flows | codex_1:0.41 A slightly underwater Aave position makes `totalLockedValue()` revert and bricks vault recovery flows |
| F-004 | rewritten_agent_signal | Medium | medium | codex_1 | TVL and divest sizing treat stETH collateral as if it exits at par, overstating withdrawable WETH during discounts | codex_1:0.58 TVL and divest math assume 1 stETH = 1 ETH, overstating real withdrawable value |
| F-005 | rewritten_agent_signal | Medium | low | opencode_1 | `createAaveDebt()` authorizes any active strategy, enabling cross-strategy debt siphoning if another strategy is compromised | opencode_1:0.392 createAaveDebt can be called by any strategy without proper validation |

## Rejection Reasons
- duplicate_or_subsumed: 2
- other: 9
- trust_or_owner_model: 4
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Unchecked WSTETH wrapping return value allows loss of funds | The low-level payable call is followed by `require(success, ...)`, so the wrap path does not fail silently. The candidate also ignores that mainnet wstETH's payable entrypoint is intentionally used for ETH staking/wrapping. |
| other | opencode_1 | No slippage protection when wrapping ETH to WSTETH | Wrapping/staking into wstETH is not a market trade against external liquidity; it follows Lido's deterministic conversion rate. This is not a realistic slippage bug. |
| other | opencode_1 | Incorrect slippage calculation in _endPosition uses STETH balance instead of expected ETH | The important bug is the opposite of the candidate's claim: the code is over-strict and near-par, causing reverts/DoS, not permissive low-min-output value leakage. That issue is merged into F-001. |
| other | codex_1 | Strategy reports more liquidated WETH than it actually transfers back to the vault | `_divest()` can over-report `assetsReceived`, but in the in-scope code this only pollutes events and `_liquidate()`'s returned accounting value. No visible withdrawal or settlement path releases extra assets based on that inflated number. |
| trust_or_owner_model | opencode_1 | Unbounded array in updateStrategyAllocations allows gas griefing | `updateStrategyAllocations()` is restricted to `HARVESTER`. A privileged caller can always waste its own gas; there is no permissionless griefing vector here. |
| other | opencode_1 | setSlippageBps lacks proper access control and validation | This is a strategist-controlled risk parameter. Missing bounds may permit operator error, but not a permissionless or trust-boundary-breaking vulnerability in the current model. |
| other | opencode_1 | setBorrowBps lacks bounds validation allowing excessive leverage | This is also a strategist-controlled configuration knob. Abuse requires trusted-role misconfiguration or compromise, which is outside normal reportable scope here. |
| trust_or_owner_model | opencode_1 | Rebalance can be called by any harvester without proper sequencing | `HARVESTER` is an explicitly privileged role. The candidate does not identify a concrete state corruption or fund-loss path beyond normal privileged misuse. |
| duplicate_or_subsumed | opencode_1 | No slippage protection in Curve exchange in _rebalancePosition | The rebalance path does have a minimum output check (`min_dy = ethBorrowed`). The real problem is that this threshold is again near-par and can revert during discounts, which is already captured by F-001. |
| trust_or_owner_model | opencode_1 | Sweep function can extract any ERC20 from strategy including asset tokens | `sweep()` is governance-only. Governance can already fully control strategy allocation and removal, so this is a trust-model concern rather than a distinct vulnerability. |
| trust_or_owner_model | opencode_1 | Harvest can be called repeatedly to grief profit locking | The described issue is just competition among privileged harvesters for who submits the permitted transaction. It does not create protocol insolvency, theft, lockup, or meaningful DoS. |
| unsupported_or_speculative | opencode_1 | Missing reentrancy guard in receiveFlashLoan callback | The candidate is speculative and does not show a concrete reentrant call path that can violate invariants in the current code. External integrations alone do not make this reportable. |
| other | opencode_1 | No slippage protection on AAVE deposit in _addToPosition | Aave deposits mint aTokens deterministically against the deposited amount; this is not an AMM trade and does not need swap-style slippage checks. |
| other | opencode_1 | Strategy upgrade lacks deadline allowing stuck upgrades | If the upgrade handshake fails, the Balancer flash loan reverts the entire transaction atomically. There is no partial stuck state from a missing deadline in the shown flow. |
| other | opencode_1 | Potential integer overflow in _increaseTVLBps | Solidity 0.8.x checked arithmetic already reverts on overflow, so the claimed bug does not exist in this codebase. |
| duplicate_or_subsumed | opencode_1 | Fixed slippageBps value may be insufficient during market stress | This is a weaker restatement of the concrete exit-DoS issue already captured in F-001, not a separate vulnerability. |
