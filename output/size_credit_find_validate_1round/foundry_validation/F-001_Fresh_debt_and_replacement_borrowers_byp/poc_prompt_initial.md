You are operating inside a Foundry workspace to build a real exploit PoC.

Allowed inputs only:
- Hypothesis file: finding:size_credit
- RPC: https://eth-mainnet.g.alchemy.com/v2/ugA3TDW3tlXhwhc3SHfuk
- Chain: mainnet mainnet
- Chain ID: 1
- Fork block: 23145763
- Target contract: 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14
- Target source root: /Users/zhanglongqin/AuditHoundV2/cases/size_credit/src/onchain_auto

Finding:
- id: F-001
- severity: Critical
- confidence: high
- title: Fresh debt and replacement borrowers bypass opening collateral-ratio checks
- claim: The protocol defines an opening-collateral safeguard in `RiskLibrary.validateUserIsNotBelowOpeningLimitBorrowCR`, but none of the debt-origination paths invoke it before minting debt and moving cash. `sellCreditMarket` with `creditPositionId == RESERVED_ID` mints debt for `onBehalfOf` and pays out lender cash without checking the borrower's live collateral ratio; `buyCreditMarket` does the same when matching a borrower offer; and `liquidateWithReplacement` reassigns the full debt to `params.borrower` and mints debt tokens for them without enforcing `crOpening` or the user's custom `openingLimitBorrowCR`.
- impact: Borrowers can open or receive new debt while below the protocol's required opening collateral ratio, including with zero effective collateral. This lets them extract fresh borrow-side value that is not economically recoverable, leaving lenders with bad debt and enabling replacement liquidations to convert an otherwise valid liquidation into a newly unsecured loan.

Exploit paths:
- A borrower calls `sellCreditMarket` with `creditPositionId == RESERVED_ID`, receives cash from a lender's borrow aToken balance, and no opening-CR check runs before `createDebtAndCreditPositions` mints debt.
- A lender calls `buyCreditMarket` against a borrower offer (`creditPositionId == RESERVED_ID`), opening debt for a borrower whose current collateral ratio is already below `crOpening` or their stricter user-defined opening limit.
- A privileged caller uses `liquidateWithReplacement`; after the old borrower is liquidated, the same `futureValue` is reminted onto `params.borrower` even if that replacement borrower has insufficient or no collateral.

Relevant locations:
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/libraries/actions/SellCreditMarket.sol:72
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/libraries/actions/SellCreditMarket.sol:231
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/libraries/actions/BuyCreditMarket.sol:71
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/libraries/actions/BuyCreditMarket.sol:231
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/libraries/actions/LiquidateWithReplacement.sol:48
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/libraries/actions/LiquidateWithReplacement.sol:148
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/libraries/RiskLibrary.sol:136

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
