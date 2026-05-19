You are operating inside a Foundry workspace to build a real exploit PoC.

Allowed inputs only:
- Hypothesis file: finding:sturdy_t01
- RPC: https://eth-mainnet.g.alchemy.com/v2/ugA3TDW3tlXhwhc3SHfuk
- Chain: mainnet mainnet
- Chain ID: 1
- Fork block: 17460609
- Target contract: 0x9f72dc67cec672bb99e3d02cbea0a21536a2b657
- Target source root: /Users/zhanglongqin/AuditHoundV2/cases/sturdy/src

Finding:
- id: F-001
- severity: Critical
- confidence: high
- title: Transient Balancer `exitPool` state can inflate Balancer-LP collateral prices and bypass collateral-removal solvency checks
- claim: The PoC and verifier show that `SturdyOracle.getAssetPrice(cB_stETH_STABLE)` is materially higher from inside the ETH payout callback of `Balancer.exitPool(...)` than it is immediately before or after the exit. That same callback can invoke lending-pool entrypoints, and the exploit uses it to call `setUserUseReserveAsCollateral(CSTECRV, false)` while solvency checks observe the transiently inflated Balancer-LP price rather than a finalized pool state. Once `steCRV` has been switched off during that fake-health window, it can then be withdrawn after the LP price normalizes.
- impact: An attacker can temporarily overvalue Balancer LP collateral inside one transaction, make an unsafe account appear healthy, disable honest collateral, and then withdraw that honest collateral after prices revert. The included forked exploit completes this sequence and extracts substantial profit, so the issue is directly fund-threatening.

Exploit paths:
- Flash-loan `wstETH` and `WETH`, mint `B_STETH_STABLE`, and deposit both `B_STETH_STABLE` and `steCRV` as collateral before borrowing `WETH`.
- Call `Balancer.exitPool(...)`; during the first ETH callback, read the inflated `cB_stETH_STABLE` oracle price and call `setUserUseReserveAsCollateral(CSTECRV, false)` while solvency checks use the transient price.
- After control returns and the oracle price normalizes, call `withdrawCollateral(steCRV, ...)` to remove the real collateral and leave the debt backed only by the previously overvalued LP position.

Relevant locations:
- Contract.sol:288
- Contract.sol:291
- Contract.sol:302
- Contract.sol:306
- Contract.sol:318
- FlawVerifier.sol:320
- FlawVerifier.sol:322
- FlawVerifier.sol:324
- FlawVerifier.sol:382
- FlawVerifier.sol:386

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
- Profit-maximization hard requirement:
  - MUST apply progressive loop amplification for repeatable exploit phases.
  - Start at 2 rounds, then increase one-by-one (2 -> 3 -> 4 -> 5 -> 6).
  - Continue increasing only if the new round count improves total net profit.
  - Stop at the first non-improving round count and keep the previous best result.
  - Prefer highest total profit over earliest passing implementation.

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
