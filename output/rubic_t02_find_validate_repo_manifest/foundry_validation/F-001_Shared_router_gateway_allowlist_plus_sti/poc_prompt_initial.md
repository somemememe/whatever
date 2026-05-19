You are operating inside a Foundry workspace to build a real exploit PoC.

Allowed inputs only:
- Hypothesis file: finding:rubic_t02
- RPC: https://eth-mainnet.g.alchemy.com/v2/ugA3TDW3tlXhwhc3SHfuk
- Chain: mainnet mainnet
- Chain ID: 1
- Fork block: 16260580
- Target contract: 0x33388cf69e032c6f60a420b37e44b1f5443d3333
- Target source root: /Users/zhanglongqin/AuditHoundV2/cases/rubic/src

Finding:
- id: F-001
- severity: High
- confidence: high
- title: Shared router/gateway allowlist plus sticky max approvals lets allowlisted spenders drain proxy tokens
- claim: `routerCall` authorizes `_gateway` and `_params.router` from the same shared `availableRouters` set, then `SmartApprove` grants `_gateway` a `type(uint256).max` allowance whenever the current allowance is insufficient. That allowance is never reset after the route finishes, and `removeAvailableRouter` only updates the set membership without revoking existing ERC20 approvals.
- impact: Any current or former allowlisted address that can act as a spender for the token can retain permanent pull rights over the proxy and later drain present and future balances of that token, including later user deposits, stuck funds, and accrued fees. The shared allowlist also means adding a router for call execution implicitly makes it eligible to become such a spender.

Exploit paths:
- Admin allowlists router/spender address `R` via initialization or `addAvailableRouter`.
- A user executes a successful `routerCall` using `_gateway = R`, causing the proxy to grant `R` an unlimited allowance for the route token.
- The route completes, but the token approval remains in place because neither `routerCall` nor `removeAvailableRouter` clears it.
- At any later time, `R` or a compromised/upgraded controller behind `R` calls `transferFrom(proxy, attacker, amount)` and drains the proxy's balance of that token.

Relevant locations:
- onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:66
- onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:81
- onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/libraries/SmartApprove.sol:19
- onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/libraries/SmartApprove.sol:22
- onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/libraries/SmartApprove.sol:30
- onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:48
- onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:111
- onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:368
- onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:380

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
