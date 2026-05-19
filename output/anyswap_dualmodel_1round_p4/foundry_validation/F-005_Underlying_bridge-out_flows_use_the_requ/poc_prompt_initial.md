You are operating inside a Foundry workspace to build a real exploit PoC.

Allowed inputs only:
- Hypothesis file: finding:anyswap
- RPC: https://eth-mainnet.g.alchemy.com/v2/ugA3TDW3tlXhwhc3SHfuk
- Chain: mainnet mainnet
- Chain ID: 1
- Fork block: 14037236
- Target contract: 0x6b7a87899490EcE95443e979cA9485CBE7E71522
- Target source root: /Users/zhanglongqin/AuditHoundV2/cases/anyswap/src/onchain_auto

Finding:
- id: F-005
- severity: High
- confidence: high
- title: Underlying bridge-out flows use the requested amount instead of the amount actually received
- claim: All `Underlying` bridge and trade entrypoints transfer a nominal `amount` of the underlying into the anyToken contract and then immediately call `depositVault(amount, ...)` and burn/bridge the same nominal amount, without measuring how many units actually arrived. Fee-on-transfer, rebasing, or otherwise non-standard underlyings can therefore leave the vault underfunded while the router still bridges the full amount.
- impact: Users can be credited on the destination chain for more value than was actually locked on the source chain, creating undercollateralized wrapped supply and eventual redemption shortfalls. The inverse user-facing effect is also possible: users may pay transfer fees on the source chain but still have the full nominal amount burned/bridged, overcharging them and pushing losses onto vault backing.

Exploit paths:
- `anySwapOutUnderlying` transfers `amount`, then calls `depositVault(amount)` and `_anySwapOut(..., amount, ...)`
- `anySwapOutUnderlyingWithPermit` and `anySwapOutUnderlyingWithTransferPermit` repeat the same nominal-amount accounting
- `anySwapOutExactTokensForTokensUnderlying*` transfer underlying to `path[0]`, then deposit and burn the full `amountIn`
- `anySwapOutExactTokensForNativeUnderlying*` transfer underlying to `path[0]`, then deposit and burn the full `amountIn`

Relevant locations:
- 0x6b7a87899490ece95443e979ca9485cbe7e71522/Contract.sol:256
- 0x6b7a87899490ece95443e979ca9485cbe7e71522/Contract.sol:257
- 0x6b7a87899490ece95443e979ca9485cbe7e71522/Contract.sol:258
- 0x6b7a87899490ece95443e979ca9485cbe7e71522/Contract.sol:274
- 0x6b7a87899490ece95443e979ca9485cbe7e71522/Contract.sol:275
- 0x6b7a87899490ece95443e979ca9485cbe7e71522/Contract.sol:276
- 0x6b7a87899490ece95443e979ca9485cbe7e71522/Contract.sol:290
- 0x6b7a87899490ece95443e979ca9485cbe7e71522/Contract.sol:291
- 0x6b7a87899490ece95443e979ca9485cbe7e71522/Contract.sol:292
- 0x6b7a87899490ece95443e979ca9485cbe7e71522/Contract.sol:379
- 0x6b7a87899490ece95443e979ca9485cbe7e71522/Contract.sol:380
- 0x6b7a87899490ece95443e979ca9485cbe7e71522/Contract.sol:381
- 0x6b7a87899490ece95443e979ca9485cbe7e71522/Contract.sol:400
- 0x6b7a87899490ece95443e979ca9485cbe7e71522/Contract.sol:401
- 0x6b7a87899490ece95443e979ca9485cbe7e71522/Contract.sol:402
- 0x6b7a87899490ece95443e979ca9485cbe7e71522/Contract.sol:428
- 0x6b7a87899490ece95443e979ca9485cbe7e71522/Contract.sol:429
- 0x6b7a87899490ece95443e979ca9485cbe7e71522/Contract.sol:430
- 0x6b7a87899490ece95443e979ca9485cbe7e71522/Contract.sol:473
- 0x6b7a87899490ece95443e979ca9485cbe7e71522/Contract.sol:474
- 0x6b7a87899490ece95443e979ca9485cbe7e71522/Contract.sol:475
- 0x6b7a87899490ece95443e979ca9485cbe7e71522/Contract.sol:494
- 0x6b7a87899490ece95443e979ca9485cbe7e71522/Contract.sol:495
- 0x6b7a87899490ece95443e979ca9485cbe7e71522/Contract.sol:496
- 0x6b7a87899490ece95443e979ca9485cbe7e71522/Contract.sol:522
- 0x6b7a87899490ece95443e979ca9485cbe7e71522/Contract.sol:523
- 0x6b7a87899490ece95443e979ca9485cbe7e71522/Contract.sol:524

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
