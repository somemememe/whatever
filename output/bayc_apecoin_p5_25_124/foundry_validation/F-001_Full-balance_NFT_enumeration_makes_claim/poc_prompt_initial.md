You are operating inside a Foundry workspace to build a real exploit PoC.

Allowed inputs only:
- Hypothesis file: finding:bayc_apecoin
- RPC: https://eth-mainnet.g.alchemy.com/v2/ugA3TDW3tlXhwhc3SHfuk
- Chain: mainnet mainnet
- Chain ID: 1
- Fork block: 14403948
- Target contract: 0x025C6da5BD0e6A5dd1350fda9e3B6a614B205a1F
- Target source root: /Users/zhanglongqin/AuditHoundV2/cases/bayc_apecoin/src

Finding:
- id: F-001
- severity: High
- confidence: high
- title: Full-balance NFT enumeration makes claims unscalable and lets attackers dust wallets into permanent out-of-gas failure
- claim: `claimTokens()` first calls `getClaimableTokenAmountAndGammaToClaim()` and then re-enumerates the caller's Alpha, Beta, and Gamma holdings again to mark claims, resulting in six unbounded `tokenOfOwnerByIndex` loops over the caller's full balances. Because plain ERC721 `transferFrom` can send tokens to an EOA without recipient consent, an attacker can dust a victim with many low-value or already-claimed NFTs from the eligible collections until `claimTokens()` always exceeds the block gas limit.
- impact: Victims and sufficiently large legitimate holders can be unable to complete `claimTokens()` during the finite claim window, permanently losing their GRAPES allocation. The issue is permissionless because the attacker only needs transferable NFTs from the configured collections.

Exploit paths:
- Attacker accumulates many eligible Alpha/Beta/Gamma NFTs, including already-claimed ones whose airdrop rights are exhausted but which still increase loop cost.
- Attacker sends those NFTs to the victim using ERC721 `transferFrom`, which does not require the EOA recipient to opt in.
- When the victim calls `claimTokens()`, the contract performs six full enumerations across the victim's balances and runs out of gas before transferring GRAPES.
- Because claims cannot be processed incrementally or by token ID, the victim can remain unable to claim until the window expires.

Relevant locations:
- onchain_auto/0x025c6da5bd0e6a5dd1350fda9e3b6a614b205a1f/contracts/AirdropGrapesToken.sol:103
- onchain_auto/0x025c6da5bd0e6a5dd1350fda9e3b6a614b205a1f/contracts/AirdropGrapesToken.sol:110
- onchain_auto/0x025c6da5bd0e6a5dd1350fda9e3b6a614b205a1f/contracts/AirdropGrapesToken.sol:112
- onchain_auto/0x025c6da5bd0e6a5dd1350fda9e3b6a614b205a1f/contracts/AirdropGrapesToken.sol:120
- onchain_auto/0x025c6da5bd0e6a5dd1350fda9e3b6a614b205a1f/contracts/AirdropGrapesToken.sol:129
- onchain_auto/0x025c6da5bd0e6a5dd1350fda9e3b6a614b205a1f/contracts/AirdropGrapesToken.sol:150
- onchain_auto/0x025c6da5bd0e6a5dd1350fda9e3b6a614b205a1f/contracts/AirdropGrapesToken.sol:153
- onchain_auto/0x025c6da5bd0e6a5dd1350fda9e3b6a614b205a1f/contracts/AirdropGrapesToken.sol:160
- onchain_auto/0x025c6da5bd0e6a5dd1350fda9e3b6a614b205a1f/contracts/AirdropGrapesToken.sol:167
- onchain_auto/0x025c6da5bd0e6a5dd1350fda9e3b6a614b205a1f/@openzeppelin/contracts/token/ERC721/ERC721.sol:150

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
