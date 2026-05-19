You are operating inside a Foundry workspace to build a real exploit PoC.

Allowed inputs only:
- Hypothesis file: finding:balancer
- RPC: https://mainnet.infura.io/v3/a5fc4fc5ece34a6eb6e8dfe627dce240
- Chain: mainnet mainnet
- Chain ID: 1
- Fork block: 18004651
- Target contract: 0x9210F1204b5a24742Eba12f710636D76240dF3d0
- Target source root: /Users/zhanglongqin/AuditHoundV2/cases/balancer/src

Finding:
- id: F-001
- severity: High
- confidence: high
- title: Emergency exits permanently invalidate LinearPool virtual-supply accounting, yet the pool auto-resumes normal operation after the buffer period
- claim: LinearPool optimizes all normal pricing and rate paths around `_getApproximateVirtualSupply`, which assumes total BPT supply always equals `_INITIAL_BPT_SUPPLY`. Emergency exits explicitly break that invariant by burning BPT, and the contract comments acknowledge the approximation becomes inaccurate. Nevertheless, `getRate()` remains callable and continues using the approximation immediately after emergency burns, and after the buffer period `whenNotPaused` starts passing again automatically, re-enabling swap logic that also relies on the stale approximation.
- impact: Once any emergency exit burns BPT, the pool can no longer safely quote `getRate()` and, after automatic unpause, can reopen with permanently wrong BPT pricing or broken math. Remaining LPs and downstream integrations can suffer fund loss, bad accounting, or denial of service, and the pool can become effectively unrecoverable without external migration.

Exploit paths:
- Governance pauses the pool during an incident
- LPs use `EMERGENCY_EXACT_BPT_IN_FOR_TOKENS_OUT`, and `BasePool.onExitPool` burns BPT
- `getRate()` keeps dividing by `_getApproximateVirtualSupply`, so its rate becomes inconsistent with real supply
- After the buffer period expires, `TemporarilyPausable` automatically treats the pool as unpaused again
- Normal `onSwap()` paths resume and keep using the stale virtual-supply approximation on a post-burn state

Relevant locations:
- 0x9210f1204b5a24742eba12f710636d76240df3d0/contracts/LinearPool.sol:62
- 0x9210f1204b5a24742eba12f710636d76240df3d0/contracts/LinearPool.sol:211
- 0x9210f1204b5a24742eba12f710636d76240df3d0/contracts/LinearPool.sol:463
- 0x9210f1204b5a24742eba12f710636d76240df3d0/contracts/LinearPool.sol:489
- 0x9210f1204b5a24742eba12f710636d76240df3d0/contracts/LinearPool.sol:546
- 0x9210f1204b5a24742eba12f710636d76240df3d0/contracts/LinearPool.sol:665
- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-pool-utils/contracts/BasePool.sol:279
- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-solidity-utils/contracts/helpers/TemporarilyPausable.sol:61
- 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-solidity-utils/contracts/helpers/TemporarilyPausable.sol:122

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

Attempt strategy (must follow for this attempt):
- strategy_label: direct_or_existing_balance_first
- strategy_instructions: Prefer direct execution using verifier-held assets first. Only use temporary external funding if direct path is infeasible.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Output format required by this harness:
- Return ONLY COMPLETE Solidity source code for `src/FlawVerifier.sol` (no markdown, no prose).
- Include at least one deployable contract with a zero-argument constructor.
- Define `function executeOnOpportunity() external` or `public` as the fixed exploit entry.
- Expose non-ETH profit metadata via getters:
  - `profitToken() external view returns (address)` (address(0) means native ETH)
  - `profitAmount() external view returns (uint256)` (net realized profit amount in `profitToken` units)
