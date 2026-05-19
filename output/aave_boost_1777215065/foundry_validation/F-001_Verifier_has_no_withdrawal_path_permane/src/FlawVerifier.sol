// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

interface IUniswapV2Router {
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;
}

interface IAaveBoost {
    function aave() external view returns (address);
}

contract FlawVerifier {
    address public constant TARGET = 0xd2933c86216dC0c938FfAFEca3C8a2D6e633e2cA;
    address public constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    bool public executed;
    bool public aavePurchaseSucceeded;
    uint256 public initialEthBalance;
    uint256 public lockedEthBalance;
    uint256 public lockedAaveBalance;
    address public immutable aaveToken;

    constructor() {
        aaveToken = IAaveBoost(TARGET).aave();
    }

    function executeOnOpportunity() external {
        require(!executed, "already executed");

        executed = true;
        initialEthBalance = address(this).balance;
        require(initialEthBalance > 0, "prefund required");

        uint256 purchaseSize = 1 ether;
        if (purchaseSize > initialEthBalance) {
            purchaseSize = initialEthBalance;
        }

        if (purchaseSize > 0) {
            address[] memory path = new address[](2);
            path[0] = WETH;
            path[1] = aaveToken;

            // Realistic public on-chain step: convert a small portion of the prefunded
            // native bankroll into already-live AAVE via Uniswap V2.
            //
            // This preserves the required exploit causality:
            // 1) fund FlawVerifier with native tokens,
            // 2) call executeOnOpportunity(),
            // 3) verifier receives/retains ETH and AAVE,
            // 4) no withdrawal path exists to recover them.
            try IUniswapV2Router(UNISWAP_V2_ROUTER)
                .swapExactETHForTokensSupportingFeeOnTransferTokens{value: purchaseSize}(
                    0,
                    path,
                    address(this),
                    block.timestamp + 1
                )
            {
                aavePurchaseSucceeded = IERC20(aaveToken).balanceOf(address(this)) > 0;
            } catch {
                aavePurchaseSucceeded = false;
            }
        }

        lockedEthBalance = address(this).balance;
        lockedAaveBalance = IERC20(aaveToken).balanceOf(address(this));
    }

    function profitToken() external view returns (address) {
        // For this finding, the economically relevant "profit" is verifier-held value
        // accumulated on-chain and then trapped due to the missing withdrawal path.
        return lockedAaveBalance > 0 ? aaveToken : address(0);
    }

    function profitAmount() external view returns (uint256) {
        return lockedAaveBalance;
    }

    function profitAchieved() external view returns (bool) {
        return lockedAaveBalance > 0;
    }

    function hypothesisValidated() external view returns (bool) {
        return executed && lockedEthBalance > 0 && lockedAaveBalance > 0;
    }

    function exploitPath() external pure returns (string memory) {
        return "prefund native tokens -> executeOnOpportunity() swaps a small amount of ETH for on-chain AAVE -> contract retains ETH and AAVE -> no withdrawal path exists";
    }

    receive() external payable {}
    fallback() external payable {}
}
