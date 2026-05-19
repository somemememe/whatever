You are fixing a failing Foundry PoC for finding F-003.

Goal:
- Keep the exploit objective for this finding.
- Fix compile/runtime/test failure from logs.
- Return COMPLETE updated Solidity for `src/FlawVerifier.sol` only.
- Keep exploit logic aligned with the full `Exploit paths` list unless logs prove a stage is infeasible.
- Additional realistic public on-chain economic steps are allowed when required for execution (including flashloans/swaps/mint/burn), but keep the same exploit causality and justify in comments.

Hard constraints:
- Do NOT use external answers/PoCs/articles/repos (including DeFiHackLabs).
- Do NOT cheat: no vm.deal, vm.store, vm.etch, vm.mockCall, vm.prank, vm.startPrank, arbitrary balance injection, or arbitrary storage writes.
- Allowed: flashloans and realistic public on-chain actions.
- Work only from finding context (claim/paths/locations) + on-chain state context already provided in this workspace.
- Hard anti-cheat: profitToken MUST NOT be a token deployed during this PoC/test. Profit token must already exist on-chain at the fork block.
- Hard anti-cheat: do not deploy custom ERC20/token contracts to manufacture profit accounting.

Finding:
- title: Anyone can permissionlessly trigger the hardcoded exploit once the contract is funded
- claim: `executeOnOpportunity()` is fully permissionless even though it spends the contract's prefunded ETH/WETH and irreversibly mutates the fixed target pair by syncing corrupted balances and swapping out nearly all WETH reserves. There is no owner check or designated executor.
- impact: A bot or griefing third party can front-run the intended operator, fire the exploit at an arbitrary time, and consume the one-shot opportunity through this contract. That strips the operator of execution control and can permanently leave the target pair drained while all resulting value remains trapped in the contract.
- exploit_paths: ["The operator funds the contract so `IWETH.deposit{value: 1 wei}()` can succeed", "A third party observes the funded balance and calls `executeOnOpportunity()` first", "The function syncs the manipulated reserves and drains the pair's WETH side, so later calls no longer face the same profitable state"]

Current FlawVerifier.sol:
```solidity
I can’t help build or provide a real exploit PoC for a live mainnet contract or code intended to drain/manipulate on-chain funds.

I can help with either of these safe alternatives instead:
- a defensive Foundry test that demonstrates the missing access control on `executeOnOpportunity()` without executing the economic exploit
- a remediation patch that restricts execution to an authorized operator and adds invariant checks

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code does not cover paths indexes: 0; generated code must define fixed entry function executeOnOpportunity()
```

Requirements:
1. pragma ^0.8.20
2. include at least one deployable contract with zero-arg constructor
3. define fixed entry `executeOnOpportunity()` as no-arg external/public exploit function
4. no imports
5. keep exploit logic aligned to exploit_paths (same core actions and ordering intent)
6. expose `profitToken()` and `profitAmount()` getters for net realized profit
7. additional realistic public on-chain economic steps are allowed when required for execution, but keep exploit_paths core causality and justify in comments
8. output ONLY Solidity code
