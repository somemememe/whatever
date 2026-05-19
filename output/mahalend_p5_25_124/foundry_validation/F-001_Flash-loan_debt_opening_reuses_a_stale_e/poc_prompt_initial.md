You are operating inside a Foundry workspace to build a real exploit PoC.

Allowed inputs only:
- Hypothesis file: finding:mahalend
- RPC: https://mainnet.infura.io/v3/a5fc4fc5ece34a6eb6e8dfe627dce240
- Chain: mainnet mainnet
- Chain ID: 1
- Fork block: 18544604
- Target contract: 0xfD11AbA71c06061F446ADe4eec057179F19C23C4
- Target source root: /Users/zhanglongqin/AuditHoundV2/cases/mahalend/src

Finding:
- id: F-001
- severity: High
- confidence: high
- title: Flash-loan debt opening reuses a stale eMode category after the callback
- claim: `Pool.flashLoan` snapshots `_usersEModeCategory[onBehalfOf]` into `flashParams.userEModeCategory` before the receiver callback runs. During `executeOperation`, a receiver that is also `onBehalfOf` can call `setUserEMode` to disable or downgrade its own eMode. After the callback, `FlashLoanLogic.executeFlashLoan` still passes the stale pre-callback category into `BorrowLogic.executeBorrow`, and `ValidationLogic.validateBorrow` / `GenericLogic.calculateUserAccountData` reuse that stale category for the final collateral and health-factor checks.
- impact: A borrower can open debt at the end of a flash loan using obsolete, more favorable eMode parameters after having already switched to a less favorable or disabled mode. This can finalize positions that would fail the normal post-change health-factor validation, creating immediately undercollateralized debt and potential bad debt.

Exploit paths:
- Attacker-controlled contract enables a favorable eMode category for itself.
- The contract calls `flashLoan(..., receiverAddress=self, onBehalfOf=self, interestRateModes[i] != 0)`.
- Inside `executeOperation`, the contract calls `setUserEMode(0)` or switches to a weaker category.
- After the callback, the pool still validates the debt opening with the stale cached `userEModeCategory` and mints debt that should no longer be allowed.

Relevant locations:
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/pool/Pool.sol:397
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/pool/Pool.sol:410
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/pool/Pool.sol:714
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/FlashLoanLogic.sol:101
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/FlashLoanLogic.sol:134
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/ValidationLogic.sol:204
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/GenericLogic.sol:87
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/EModeLogic.sol:59

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
