You are operating inside a Foundry workspace to build a real exploit PoC.

Allowed inputs only:
- Hypothesis file: finding:rubic_t01_clean
- RPC: https://eth-mainnet.g.alchemy.com/v2/ugA3TDW3tlXhwhc3SHfuk
- Chain: mainnet mainnet
- Chain ID: 1
- Fork block: 16260580
- Target contract: 0x3335a88bb18fd3b6824b59af62b50ce494143333
- Target source root: /Users/zhanglongqin/AuditHoundV2/cases/rubic/src

Finding:
- id: F-001
- severity: Critical
- confidence: high
- title: `routerCallNative` can be abused as an arbitrary approved-token spender to drain users with live proxy allowances
- claim: The in-scope exploit harnesses consistently show that Rubic proxy `routerCallNative` entrypoints accept attacker-controlled `router` and raw calldata even when all swap fields are zeroed. By setting `router` to the USDC token contract and `_data` to `transferFrom(victim, attacker, amount)`, the proxy itself acts as the spender and can pull funds from any account that previously approved that proxy. The PoCs rank victims by `min(balance, allowance)` and then invoke the proxy to execute the token pull, which is strong evidence that the underlying proxy path lacks validation that `router` is safe and that the calldata corresponds to a legitimate bridge/swap flow.
- impact: Any user with a lingering ERC20 allowance to the affected Rubic proxy can be permissionlessly drained for up to their approved balance. This is direct theft of user funds and can be repeated across many victims in a single transaction, causing protocol-wide loss.

Exploit paths:
- Victim grants or leaves an ERC20 allowance to a Rubic proxy.
- Attacker crafts `BaseCrossChainParams` with `srcInputToken = address(0)`, `srcInputAmount = 0`, and `router = address(USDC)`.
- Attacker encodes `_data` as `transferFrom(victim, attacker, amount)` where `amount = min(victimBalance, victimAllowanceToProxy)`.
- Attacker calls the relevant `routerCallNative` entrypoint on the proxy.
- Because the proxy performs the external call as the already-approved spender, the victim's tokens are transferred to the attacker and can then be liquidated.

Relevant locations:
- FlawVerifier.sol:99
- FlawVerifier.sol:180
- FlawVerifier.sol:203
- FlawVerifier.sol:223
- FlawVerifier.sol:308
- Contract.sol.disabled_exp_poc:88
- Contract.sol.disabled_exp_poc:116
- Contract.sol.disabled_exp_poc:118
- Contract.sol.disabled_exp_poc:127
- Contract.sol.disabled_exp_poc:129

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
