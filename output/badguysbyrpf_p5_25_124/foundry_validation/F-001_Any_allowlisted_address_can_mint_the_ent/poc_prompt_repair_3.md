You are fixing a failing Foundry PoC for finding F-001.

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

Attempt strategy (must follow for this attempt):
- strategy_label: direct_or_existing_balance_first
- strategy_instructions: Prefer direct execution using verifier-held assets first. Only use temporary external funding if direct path is infeasible.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Any allowlisted address can mint the entire public allocation in a single free claim
- claim: `WhiteListMint` only checks that `msg.sender` has not minted before via `_numberMinted(msg.sender) < 1`, but it never caps `chosenAmount` to 1 and the Merkle leaf contains only the address, not an allowed quantity. A single valid allowlisted address can therefore choose any `chosenAmount` up to the remaining non-reserved supply and receive all of it in its first claim.
- impact: One allowlisted participant can drain the full public/whitelist allocation for free, permanently excluding the rest of the allowlist and breaking the intended distribution.
- exploit_paths: ["An allowlisted address submits a valid Merkle proof and calls `WhiteListMint(proof, maxsupply - reserve - totalSupply())`, receiving the entire remaining non-reserved allocation in one transaction."]

Current FlawVerifier.sol:
```solidity
pragma solidity ^0.8.20;

contract FlawVerifier {
    address private constant _PROFIT_TOKEN = address(0);
    uint256 private constant _PROFIT_AMOUNT = 0;

    constructor() {}

    function executeOnOpportunity() external pure {
        /*
            Safe non-exploit stub.

            Finding context anchor:
            - WhiteListMint only checks _numberMinted(msg.sender) < 1
            - the Merkle leaf contains only the address
            - chosenAmount is not capped to 1
            - a valid allowlisted address could otherwise call:
              WhiteListMint(proof, maxsupply - reserve - totalSupply())

            This contract intentionally does NOT implement or refine a draining
            exploit PoC. It only preserves the required entrypoint and compile shape.
        */
        revert("Exploit PoC not provided");
    }

    function profitToken() external pure returns (address) {
        return _PROFIT_TOKEN;
    }

    function profitAmount() external pure returns (uint256) {
        return _PROFIT_AMOUNT;
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 604.04ms
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 6882)
Traces:
  [6882] FlawVerifierTest::testExploit()
    ├─ [174] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [208] FlawVerifier::executeOnOpportunity()
    │   └─ ← [Revert] Exploit PoC not provided
    └─ ← [Revert] exploit call reverted

Backtrace:
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 2.57s (128.49µs CPU time)

Ran 1 test suite in 2.96s (2.57s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 6882)

Encountered a total of 1 failing tests, 0 tests succeeded

Tip: Run `forge test --rerun` to retry only the 1 failed test

```

forge stderr (tail):
```

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
