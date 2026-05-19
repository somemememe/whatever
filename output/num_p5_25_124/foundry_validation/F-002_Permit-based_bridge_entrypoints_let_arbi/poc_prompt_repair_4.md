You are fixing a failing Foundry PoC for finding F-002.

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
- strategy_label: alternate_public_liquidity_route
- strategy_instructions: Prefer an alternate public-liquidity venue/route while preserving the same exploit root cause and exploit-path causality.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Permit-based bridge entrypoints let arbitrary callers redirect a signer’s funds to attacker-chosen recipients, chains, and routes
- claim: The `*WithPermit` and `*WithTransferPermit` bridge entrypoints use the signature only to authorize token movement into the router/token vault, but they never require `msg.sender == from` and do not authenticate bridge-critical fields such as destination recipient, destination chain, or swap path. A third party who obtains a valid permit-style signature can therefore submit the transaction themselves and choose where the bridged value ultimately goes.
- impact: A malicious frontend, relayer, or signature collector can steal a victim’s funds by consuming the victim’s permit and bridging the value to an attacker-controlled address or chain. In the swap variants, the attacker can also choose the output route and asset, converting the victim’s funds into attacker-preferred destination assets.
- exploit_paths: ["Victim signs a permit for `anySwapOutUnderlyingWithPermit`; attacker submits the call first with `to` set to the attacker and `toChainID` set to the attacker\u2019s preferred chain.", "Victim signs for a cross-chain swap permit; attacker calls `anySwapOutExactTokensForTokensUnderlyingWithPermit` or `anySwapOutExactTokensForNativeUnderlyingWithPermit` with attacker-chosen `path` and `to`, causing the victim\u2019s value to be bridged into attacker-selected assets.", "The same redirection works through the `*WithTransferPermit` variants because the signed transfer only covers moving funds into the bridge token, not the final bridge recipient or chain."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IAnyswapV4RouterLike {
    function anySwapOutUnderlyingWithPermit(
        address from,
        address token,
        address to,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        uint256 toChainID
    ) external;

    function anySwapOutUnderlyingWithTransferPermit(
        address from,
        address token,
        address to,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        uint256 toChainID
    ) external;

    function anySwapOutExactTokensForTokensUnderlyingWithPermit(
        address from,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        uint256 toChainID
    ) external;

    function anySwapOutExactTokensForTokensUnderlyingWithTransferPermit(
        address from,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        uint256 toChainID
    ) external;

    function anySwapOutExactTokensForNativeUnderlyingWithPermit(
        address from,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        uint256 toChainID
    ) external;

    function anySwapOutExactTokensForNativeUnderlyingWithTransferPermit(
        address from,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        uint256 toChainID
    ) external;
}

contract FlawVerifier {
    address public constant TARGET = 0x765277EebeCA2e31912C9946eAe1021199B39C61;

    string public constant STRICT_PATH =
        "obtain victim permit-style signature -> submit *WithPermit/*WithTransferPermit before the intended victim flow -> redirect bridge recipient/chain/path to attacker-controlled values -> realize bridged proceeds as attacker profit";

    address private _profitToken;
    uint256 private _profitAmount;

    bool public executed;
    bool public profitWasAchieved;
    bool public originalHypothesisValidated;
    bool public originalHypothesisRefuted;

    string private _outcome;

    uint256 public directBalanceFirstChecks;
    uint256 public flashswapFundingChecks;
    uint256 public permitPathChecks;
    uint256 public transferPermitPathChecks;
    uint256 public tokenSwapPathChecks;
    uint256 public nativeSwapPathChecks;

    bytes32 public lastObservedStage;

    constructor() {
        _profitToken = address(0);
        _outcome = "not-run";
    }

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        _profitToken = address(0);
        _profitAmount = 0;
        profitWasAchieved = false;
        originalHypothesisValidated = false;
        originalHypothesisRefuted = false;

        // Required attempt strategy: v2_flashswap_funding.
        // A UniswapV2/Sushi-like flashswap is a realistic way to avoid attacker prefunding while
        // racing a signed bridge submission, but it does not alter the bug's causality: the attack
        // still begins with a victim-issued permit or transferPermit that authorizes token movement
        // into the bridge while leaving destination recipient/chain/path attacker-controlled.
        directBalanceFirstChecks = 1;
        flashswapFundingChecks = 1;

        // Exploit path 1:
        // Victim signs anySwapOutUnderlyingWithPermit(...).
        // Attacker submits first and rewrites `to` and `toChainID`.
        // The router source confirms those bridge-critical fields are not bound by the signature.
        // On this provided fork, however, no reusable unconsumed victim signature artifact is
        // bundled for a live underlying, so the redirection cannot be executed honestly.
        permitPathChecks = 1;
        lastObservedStage = keccak256("missing-unconsumed-underlying-permit-signature");

        // Exploit path 2:
        // Victim signs for a cross-chain swap permit.
        // Attacker submits anySwapOutExactTokensForTokensUnderlyingWithPermit(...) or
        // anySwapOutExactTokensForNativeUnderlyingWithPermit(...) with attacker-chosen `path`,
        // `to`, and `toChainID`.
        // Flashswap funding could cover temporary route inventory if needed, but it cannot create
        // the required victim signature authorizing the initial pull into path[0].
        tokenSwapPathChecks = 1;
        nativeSwapPathChecks = 1;

        // Exploit path 3:
        // The same recipient/chain/path redirection exists in the *WithTransferPermit variants,
        // because transferWithPermit only authorizes movement into the bridge token/router and does
        // not authenticate the final bridge destination fields.
        // The same fork-state blocker applies: no victim-side transferPermit artifact is provided.
        transferPermitPathChecks = 1;

        // Conclusion for this fork-bound verifier run:
        // - The source-level finding remains valid: these entrypoints let arbitrary callers redirect
        //   a signer's funds once a valid permit-style signature exists.
        // - The workspace/on-chain context provided to this PoC does not include any such usable
        //   victim signature, and the rules forbid impersonation, storage writes, or fake balances.
        // - Because the exploit cannot reach the first executable signed-transfer stage, no honest
        //   source-chain realized profit can be produced in this isolated snapshot.
        originalHypothesisRefuted = true;
        _outcome = "source-valid-bug-but-poc-infeasible-on-provided-fork-without-victim-permit-artifact";
    }

    function outcome() external view returns (string memory) {
        return _outcome;
    }

    function exploitPath() external pure returns (string memory) {
        return STRICT_PATH;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 950.27ms
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 277894)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x0000000000000000000000000000000000000000
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001

Traces:
  [277894] FlawVerifierTest::testExploit()
    ├─ [2425] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [251028] FlawVerifier::executeOnOpportunity()
    │   └─ ← [Stop]
    ├─ [425] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [468] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 14.44ms (287.62µs CPU time)

Ran 1 test suite in 19.78ms (14.44ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 277894)

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
