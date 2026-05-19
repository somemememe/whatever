You are operating inside a Foundry workspace to build a real exploit PoC.

Allowed inputs only:
- Hypothesis file: finding:silo_finance
- RPC: https://mainnet.infura.io/v3/a5fc4fc5ece34a6eb6e8dfe627dce240
- Chain: mainnet mainnet
- Chain ID: 1
- Fork block: 17139470
- Target contract: 0xcB3B879aB11F825885d5aDD8Bf3672596d35197C
- Target source root: /Users/zhanglongqin/AuditHoundV2/cases/silo_finance/src

Finding:
- id: F-001
- severity: Critical
- confidence: medium
- title: Transferable share tokens let users separate debt from collateral across addresses
- claim: The protocol treats share-token `balanceOf(user)` as the sole source of truth for collateral ownership, debt ownership, borrow eligibility, deposit eligibility, withdrawal amount, repay amount, and solvency. `IShareToken` is an ERC20-style interface and the notification interface is explicitly transfer-oriented. If the deployed share-token implementations preserve that transferability, a user can move collateral shares or debt shares to another address without any solvency check, breaking the same-account collateral/debt invariant the silo relies on.
- impact: A borrower can strip collateral out of the indebted account or push debt shares onto a different address, then withdraw or re-borrow while leaving naked debt behind. If share transfers are enabled in production, this is a direct bad-debt and insolvency vector.

Exploit paths:
- Account A deposits collateral and borrows another asset.
- A transfers its collateral share tokens to account B, or transfers its debt share tokens to account B.
- Because `borrowPossible`, `depositPossible`, withdrawals, repayments, and solvency all read current share balances only, the protocol now attributes collateral and debt to different addresses.
- Account B withdraws the transferred collateral, or account A appears debt-free enough to withdraw/re-borrow, leaving the silo with uncollectible debt.

Relevant locations:
- 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/interfaces/IShareToken.sol:8
- 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/interfaces/INotificationReceiver.sol:5
- 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:190
- 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:196
- 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:335
- 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:339
- 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:417
- 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:453
- 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:575
- 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/lib/Solvency.sol:180
- 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/lib/Solvency.sol:257

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
