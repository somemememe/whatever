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

Finding:
- title: Verifier has no withdrawal path, permanently locking the prefunded bankroll and any recovered assets
- claim: `FlawVerifier` is designed to be prefunded with a very large native-token balance and can accumulate additional ETH and ERC20 balances during `executeOnOpportunity()`, but the contract exposes no owner-controlled withdrawal, sweep, or destruction path to return those assets to an operator.
- impact: All prefunded native tokens, any profit realized by the strategy, and any residual ERC20 balances can become permanently inaccessible inside the contract, resulting in total loss of control over the verifier treasury.
- exploit_paths: ["Fund `FlawVerifier` with native tokens before execution", "Call `executeOnOpportunity()`; the contract receives/retains ETH and AAVE", "No function exists to transfer native tokens or ERC20 balances back to an operator"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
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
        if (purchaseSize > address(this).balance) {
            purchaseSize = address(this).balance;
        }

        if (purchaseSize > 0) {
            address[] memory path = new address[](2);
            path[0] = WETH;
            path[1] = aaveToken;

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

        // Positive net attacker profit is mechanically infeasible for this finding:
        // even when this verifier is prefunded and then retains ETH and/or AAVE,
        // the contract intentionally exposes no withdrawal, sweep, or destruction path.
        // Therefore any balance increase remains trapped here instead of becoming
        // externalizable attacker profit.
    }

    function profitToken() external pure returns (address) {
        return address(0);
    }

    function profitAmount() external pure returns (uint256) {
        return 0;
    }

    function profitAchieved() external pure returns (bool) {
        return false;
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

```

forge stdout (tail):
```
└─ ← [Return] 0
    │   │   ├─ [2504] 0xDFC14d2Af169B0D36C4EFF567Ada9b2E0CAE044f::getReserves() [staticcall]
    │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000f4c03d75130a5b104000000000000000000000000000000000000000000000001a8a3348600b6a3ba00000000000000000000000000000000000000000000000000000000684a3883
    │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0xDFC14d2Af169B0D36C4EFF567Ada9b2E0CAE044f) [staticcall]
    │   │   │   └─ ← [Return] 31598358043427513274 [3.159e19]
    │   │   ├─ [64482] 0xDFC14d2Af169B0D36C4EFF567Ada9b2E0CAE044f::swap(8904222043510717715 [8.904e18], 0, FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x)
    │   │   │   ├─ [31252] 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 8904222043510717715 [8.904e18])
    │   │   │   │   ├─ [30482] 0x5D4Aa78B08Bc7C530e21bf7447988b1Be7991322::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 8904222043510717715 [8.904e18]) [delegatecall]
    │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │        topic 1: 0x000000000000000000000000dfc14d2af169b0d36c4eff567ada9b2e0cae044f
    │   │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000007b9226c5a0a8bd13
    │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   ├─ [1373] 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9::balanceOf(0xDFC14d2Af169B0D36C4EFF567Ada9b2E0CAE044f) [staticcall]
    │   │   │   │   ├─ [638] 0x5D4Aa78B08Bc7C530e21bf7447988b1Be7991322::balanceOf(0xDFC14d2Af169B0D36C4EFF567Ada9b2E0CAE044f) [delegatecall]
    │   │   │   │   │   └─ ← [Return] 273274397377653699569 [2.732e20]
    │   │   │   │   └─ ← [Return] 273274397377653699569 [2.732e20]
    │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0xDFC14d2Af169B0D36C4EFF567Ada9b2E0CAE044f) [staticcall]
    │   │   │   │   └─ ← [Return] 31598358043427513274 [3.159e19]
    │   │   │   ├─  emit topic 0: 0x1c411e9a96e071241c2f21f7726b17ae89e3cab4c78be50e062b03a9fffbbad1
    │   │   │   │           data: 0x00000000000000000000000000000000000000000000000ed071b08b8ffcf3f1000000000000000000000000000000000000000000000001b683eb39a81aa3ba
    │   │   │   ├─  emit topic 0: 0xd78ad95fa46c994b6551d0da85fc275fe613ce37657fb8d5e3d130840159d822
    │   │   │   │        topic 1: 0x0000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d
    │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000007b9226c5a0a8bd130000000000000000000000000000000000000000000000000000000000000000
    │   │   │   └─ ← [Stop]
    │   │   ├─ [1373] 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   ├─ [638] 0x5D4Aa78B08Bc7C530e21bf7447988b1Be7991322::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   │   └─ ← [Return] 8904222043510717715 [8.904e18]
    │   │   │   └─ ← [Return] 8904222043510717715 [8.904e18]
    │   │   └─ ← [Stop]
    │   ├─ [1373] 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [638] 0x5D4Aa78B08Bc7C530e21bf7447988b1Be7991322::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 8904222043510717715 [8.904e18]
    │   │   └─ ← [Return] 8904222043510717715 [8.904e18]
    │   ├─ [1373] 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [638] 0x5D4Aa78B08Bc7C530e21bf7447988b1Be7991322::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 8904222043510717715 [8.904e18]
    │   │   └─ ← [Return] 8904222043510717715 [8.904e18]
    │   └─ ← [Return]
    ├─ [252] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [274] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 1000000000000000000000000 [1e24])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 999999000000000000000000 [9.999e23])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 921.59ms (4.53ms CPU time)

Ran 1 test suite in 1.01s (921.59ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 258906)

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
