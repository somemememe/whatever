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

Finding:
- title: Unchecked ERC20 transfer return values allow phantom deposits and silent failed withdrawals
- claim: `deposit`, `withdraw`, and `emergencyWithdraw` call `transferFrom`/`transfer` directly and ignore the returned boolean. For any accepted token that returns `false` instead of reverting, the contract still updates `balances`, checkpoints, pool sizes, and stable-coin accounting as if tokens moved successfully.
- impact: An attacker can create or use a token whose `transferFrom` silently fails for them, obtain stake credit without funding the pool, and later withdraw real liquidity deposited by other users of the same token. Failed outbound transfers can also leave users debited without actually receiving tokens.
- exploit_paths: ["Use a non-stable token that returns `false` on `transferFrom` for the attacker but still allows normal transfers for other users.", "Call `deposit(token, amount, referrer)`; the contract records `amount` as staked even though it received nothing.", "After honest users deposit the same token, call `withdraw` to receive real tokens from the contract while your original deposit was never funded."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract FlawVerifier {
    address public constant TARGET = 0x245a551ee0F55005e510B239c917fA34b41B3461;

    // Unchecked ERC20 transfer return values allow phantom deposits and silent failed withdrawals
    function executeOnOpportunity() external {
        revert("POC generation failed for F-001");
    }

    receive() external payable {}
}

```

forge stdout (tail):
```
No files changed, compilation skipped

Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 7843)
Traces:
  [7843] FlawVerifierTest::testExploit()
    ├─ [142] FlawVerifier::49343624() [staticcall]
    │   └─ ← [Revert] unrecognized function selector 0x49343624 for contract 0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f, which has no fallback function.
    ├─ [142] FlawVerifier::6236fa78() [staticcall]
    │   └─ ← [Revert] unrecognized function selector 0x6236fa78 for contract 0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f, which has no fallback function.
    ├─ [142] FlawVerifier::fe87c375() [staticcall]
    │   └─ ← [Revert] unrecognized function selector 0xfe87c375 for contract 0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f, which has no fallback function.
    ├─ [208] FlawVerifier::executeOnOpportunity()
    │   └─ ← [Revert] POC generation failed for F-001
    └─ ← [Revert] exploit call reverted

Backtrace:
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 19.34ms (126.36µs CPU time)

Ran 1 test suite in 24.14ms (19.34ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 7843)

Encountered a total of 1 failing tests, 0 tests succeeded

Tip: Run `forge test --rerun` to retry only the 1 failed test

```

forge stderr (tail):
```

```

Requirements:
1. pragma ^0.8.20
2. include at least one deployable contract with zero-arg constructor
3. include at least one callable no-arg external/public exploit entry function
4. no imports
5. keep exploit logic aligned to exploit_paths (same core actions and ordering intent)
6. expose `profitToken()` and `profitAmount()` getters for net realized profit
7. additional realistic public on-chain economic steps are allowed when required for execution, but keep exploit_paths core causality and justify in comments
8. output ONLY Solidity code
