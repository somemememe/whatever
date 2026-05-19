You are operating inside a Foundry workspace to build a real exploit PoC.

Allowed inputs only:
- Hypothesis file: finding:particletrade
- RPC: https://mainnet.infura.io/v3/a5fc4fc5ece34a6eb6e8dfe627dce240
- Chain: mainnet mainnet
- Chain ID: 1
- Fork block: 19231445
- Target contract: 0xE4764f9cd8ECc9659d3abf35259638B20ac536E4
- Target source root: /Users/zhanglongqin/AuditHoundV2/cases/particletrade/src/onchain_auto

Finding:
- id: F-001
- severity: Critical
- confidence: high
- title: `multicall` reuses one `msg.value` across multiple payable delegatecalls, allowing unbacked loans and bid margins
- claim: OpenZeppelin `Multicall.multicall()` delegatecalls back into `ParticleExchange`, so every batched subcall observes the original transaction `msg.value`. The exchange then treats that same ETH as fresh funding in each payable path that calls `_balanceAccount(...)` with `msg.value` or `amount + msg.value`, including `swapWithEth`, `sellNftToMarket*`, `refinanceLoan`, `offerBid`, and `updateBid`. Because no per-subcall value accounting is performed, a single ETH payment can collateralize multiple independent state transitions.
- impact: An attacker can create multiple loans or bid margins backed by only one actual payment, leaving the protocol insolvent. This can let the attacker withdraw more ETH than was deposited, or leave lenders with supposedly collateralized positions that cannot all be honored, causing direct fund loss to other users once withdrawals or liquidations occur.

Exploit paths:
- Call `multicall([swapWithEth(lienA), swapWithEth(lienB)])` with `msg.value` sufficient for only one loan. Each delegatecall sees the full `msg.value`, so both liens become active and two NFTs are released even though only one ETH collateral payment was made.
- Call `multicall([offerBid(collection, margin, ...), offerBid(collection, margin, ...), cancelBid(lien1), cancelBid(lien2), withdrawAccountBalance()])` with ETH sufficient for one margin. Both bids are created as if funded, both cancellations credit the stored margin back, and the attacker withdraws more ETH than entered the contract in that transaction.

Relevant locations:
- 0xe4764f9cd8ecc9659d3abf35259638b20ac536e4/lib/openzeppelin-contracts/contracts/utils/Multicall.sol:17
- 0xe4764f9cd8ecc9659d3abf35259638b20ac536e4/contracts/protocol/ParticleExchange.sol:202
- 0xe4764f9cd8ecc9659d3abf35259638b20ac536e4/contracts/protocol/ParticleExchange.sol:215
- 0xe4764f9cd8ecc9659d3abf35259638b20ac536e4/contracts/protocol/ParticleExchange.sol:466
- 0xe4764f9cd8ecc9659d3abf35259638b20ac536e4/contracts/protocol/ParticleExchange.sol:569
- 0xe4764f9cd8ecc9659d3abf35259638b20ac536e4/contracts/protocol/ParticleExchange.sol:650
- 0xe4764f9cd8ecc9659d3abf35259638b20ac536e4/contracts/protocol/ParticleExchange.sol:685
- 0xe4764f9cd8ecc9659d3abf35259638b20ac536e4/contracts/protocol/ParticleExchange.sol:724
- 0xe4764f9cd8ecc9659d3abf35259638b20ac536e4/contracts/protocol/ParticleExchange.sol:1068

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
