You are operating inside a Foundry workspace to build a real exploit PoC.

Allowed inputs only:
- Hypothesis file: finding:luckytiger
- RPC: https://eth-mainnet.g.alchemy.com/v2/ugA3TDW3tlXhwhc3SHfuk
- Chain: mainnet mainnet
- Chain ID: 1
- Fork block: 15403430
- Target contract: 0x9c87A5726e98F2f404cdd8ac8968E9b2C80C0967
- Target source root: /Users/zhanglongqin/AuditHoundV2/cases/luckytiger/src

Finding:
- id: F-002
- severity: Critical
- confidence: high
- title: Contract callers can revert losing mints and keep only winning outcomes
- claim: A wrapper contract can call `freeMint` or `publicMint`, let the mint logic fully determine whether the token is lucky and whether prize ETH was paid, inspect the outcome after the call returns, and revert the outer transaction whenever the outcome is unfavorable. Because a revert rolls back the mint, payment, and whitelist consumption, the attacker can cheaply retry until only profitable outcomes are finalized.
- impact: This turns the lottery into a one-sided option for contract callers. In `publicMint`, the attacker only commits winning mints and loses only gas on failed attempts, allowing extraction from the bonus pool. In `freeMint`, the attacker can repeatedly retry the same whitelist slot until a lucky result appears, then finalize the free NFT plus payout. The bonus pool can be drained and the game becomes economically non-viable.

Exploit paths:
- Attacker deploys a contract implementing `onERC721Received` and a cheap `receive()` function.
- The wrapper calls `publicMint()` or `freeMint(victim)` and waits for the call to return.
- After return, the wrapper inspects whether the minted token is marked lucky or whether it received the ETH payout.
- If the outcome is losing, the wrapper reverts, rolling back the mint and any whitelist consumption; if the outcome is winning, it does not revert and keeps the NFT/payout.

Relevant locations:
- onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:944
- onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:968
- onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:971
- onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:982
- onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1395
- onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1402
- onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1405
- onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1407
- onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1413
- onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1419
- onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1422
- onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1424

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
