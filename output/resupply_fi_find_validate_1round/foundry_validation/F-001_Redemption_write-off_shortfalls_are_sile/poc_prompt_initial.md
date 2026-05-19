You are operating inside a Foundry workspace to build a real exploit PoC.

Allowed inputs only:
- Hypothesis file: finding:resupply_fi
- RPC: https://eth-mainnet.g.alchemy.com/v2/ugA3TDW3tlXhwhc3SHfuk
- Chain: mainnet mainnet
- Chain ID: 1
- Fork block: 22785460
- Target contract: 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6
- Target source root: /Users/zhanglongqin/AuditHoundV2/cases/resupply_fi/src/onchain_auto

Finding:
- id: F-001
- severity: High
- confidence: medium
- title: Redemption write-off shortfalls are silently discarded on undercollateralized borrowers
- claim: `redeemCollateral()` removes real collateral from the pair immediately and only mints non-claimable `redemptionWriteOff` rewards to socialize that loss later. When a borrower is eventually synced, `_syncUserRedemptions()` converts their accrued write-off into a collateral deduction but caps the result at zero. If a borrower has less remaining collateral than the write-off allocated to their borrow shares, the uncovered portion is simply erased instead of being preserved as bad debt or charged elsewhere.
- impact: After a redemption against a pool that already contains undercollateralized borrowers, aggregate user collateral accounting can stay above the pair's real collateral balance. That accounting hole lets earlier withdrawers/liquidations consume collateral that should have absorbed the missing write-off, pushing losses onto later users or protocol insurance and creating hidden insolvency.

Exploit paths:
- A borrower becomes undercollateralized before liquidation, so their `_userCollateralBalance` is already smaller than the collateral haircut implied by their debt share.
- A redemption executes and transfers collateral out of the pair, then mints `redemptionWriteOff` instead of debiting each borrower inline.
- When the undercollateralized borrower is later checkpointed, `_calcRewardIntegral()` allocates write-off rewards by borrow shares and `_syncUserRedemptions()` computes `rTokens`.
- If `rTokens` exceeds that account's remaining collateral, `_userCollateralBalance` is floored to zero and the excess write-off disappears.
- The pair's summed user collateral balances now exceed actual collateral by the discarded amount, enabling over-withdrawal until the shortfall surfaces as protocol bad debt.

Relevant locations:
- 0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/RewardDistributorMultiEpoch.sol:162
- 0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/RewardDistributorMultiEpoch.sol:225
- 0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/pair/ResupplyPairCore.sol:599
- 0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/pair/ResupplyPairCore.sol:604
- 0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/pair/ResupplyPairCore.sol:610
- 0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/pair/ResupplyPairCore.sol:906
- 0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/pair/ResupplyPairCore.sol:965

Hard constraints:
- Do NOT use external answers/PoCs/articles/repos (including DeFiHackLabs).
- Do NOT cheat: no vm.deal, vm.store, vm.etch, vm.mockCall, vm.prank, vm.startPrank, arbitrary balance injection, or arbitrary storage writes.
- Allowed: flashloans and realistic public on-chain actions.
- Work only from finding context (claim/paths/locations) + on-chain state at or before the fork block.
- Hard anti-cheat: profitToken MUST NOT be a token deployed during this PoC/test. Profit token must already exist on-chain at the fork block.
- Hard anti-cheat: do not deploy custom ERC20/token contracts to manufacture profit accounting.
- You MUST implement the exploit aligned with the full `Exploit paths` list.
- Do not ignore any path stage unless it is provably infeasible at this fork state.
- Keep the generated PoC mechanically aligned with `Exploit paths` (same core actions, same causality).
- Path-Strict requirements (all cases):
  - Treat `Exploit paths` as the allowed attack plan.
  - Implement a one-to-one mapping from PoC on-chain actions to path stages.
  - Additional realistic public on-chain economic steps are allowed when required for execution (including flashloans/swaps/mint/burn), but they must preserve the same exploit causality.
  - If an additional step is strictly required for execution, keep it minimal and explain in code comments why it does not change the exploit hypothesis.
- If any path stage is infeasible at this fork state, return concrete infeasibility reasons instead of pivoting to an unrelated route.

Task:
1) Convert the hypothesis into concrete exploit preconditions and a profit path.
2) Build and iterate a Foundry exploit PoC implementation in `src/FlawVerifier.sol`.
3) Ensure the PoC can be validated by a Foundry test harness at `test/ExploitPOC.t.sol`.
4) Iterate until either:
   - positive net attacker profit is achieved after repaying temporary capital, or
   - failure is proven with a clear mechanical/economic reason.

Final response must contain only:
- whether profit was achieved
- profit token and amount
- exploit path used
- whether the original hypothesis was validated or refuted

Harness note:
- This validator performs iterative attempts up to a configured max-attempts.
- The test file is auto-generated by the harness.
- If exploitability is not feasible at this fork state, return best-effort executable logic that fails only for concrete on-chain preconditions.
- If any `Exploit paths` stage is infeasible, state the concrete on-chain reason in code comments and avoid silently changing to an unrelated route.
- Because the harness owns the test execution loop, do not output prose summaries; return Solidity only.

Output format required by this harness:
- Return ONLY COMPLETE Solidity source code for `src/FlawVerifier.sol` (no markdown, no prose).
- Include at least one deployable contract with a zero-argument constructor.
- Define `function executeOnOpportunity() external` or `public` as the fixed exploit entry.
- Expose non-ETH profit metadata via getters:
  - `profitToken() external view returns (address)` (address(0) means native ETH)
  - `profitAmount() external view returns (uint256)` (net realized profit amount in `profitToken` units)
