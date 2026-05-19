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
- title: ETH and residual token balances can be permanently trapped in FlawVerifier
- claim: The contract can receive native tokens through `receive`/`fallback` and can accumulate ERC20 balances during probing and liquidation, but `executeOnOpportunity()` only unwraps WETH back into ETH held by the same contract. There is no code path anywhere in the contract that transfers ETH or ERC20 balances out to an operator or recovery address.
- impact: Any ETH used to fund the verifier, together with any profits or residual ERC20 balances it acquires, can become permanently unrecoverable. In the documented deployment model, the pre-funded treasury can be locked forever inside the contract.
- exploit_paths: ["Fund `FlawVerifier` with native tokens.", "Call `executeOnOpportunity()` so the contract probes, swaps, and may end with ETH/WETH or other ERC20 balances.", "Observe that no withdrawal or sweep function exists to move those assets out of the contract."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWETHLike is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

contract ForceETH {
    constructor() payable {}

    function destroy(address payable to) external {
        selfdestruct(to);
    }
}

contract FlawVerifier {
    address internal constant TARGET = 0x35D8949372D46B7a3D5A56006AE77B215fc69bC0;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    bytes4 internal constant EXECUTE_ON_OPPORTUNITY = 0x3c2448ed;
    bytes4 internal constant RECONSTRUCTED_ENTRY = 0xa0712d68;

    address private _profitToken;
    uint256 private _profitAmount;
    bool private _hypothesisValidated;
    uint256 private _donatedEth;
    uint256 private _donatedWeth;
    bool private _targetEntryReached;

    constructor() {}

    function executeOnOpportunity() external {
        _profitToken = address(0);
        _profitAmount = 0;
        _hypothesisValidated = false;
        _donatedEth = 0;
        _donatedWeth = 0;
        _targetEntryReached = false;

        uint256 attackerEthBefore = address(this).balance;
        uint256 targetEthBefore = TARGET.balance;
        uint256 targetWethBefore = _balanceOf(WETH, TARGET);

        // Path stage 1: fund the live FlawVerifier with native ETH.
        // This finding is non-extractive: without external prefunding there is no realistic way to
        // recover the donation or repay temporary capital, so positive attacker profit is mechanically
        // impossible. If the harness prefunds this PoC, it forwards that real ETH into the target.
        uint256 ethToDonate = address(this).balance / 2;
        if (ethToDonate == 0 && address(this).balance != 0) {
            ethToDonate = address(this).balance;
        }
        if (ethToDonate != 0) {
            _fundTargetNative(ethToDonate);
            _donatedEth = ethToDonate;
        }

        // Path stage 2: leave the target with a residual ERC20 balance as well.
        // Any ETH left in this PoC is wrapped into canonical on-chain WETH and donated to the target.
        uint256 remainingEth = address(this).balance;
        if (remainingEth != 0) {
            IWETHLike(WETH).deposit{value: remainingEth}();
        }

        uint256 wethToDonate = _balanceOf(WETH, address(this));
        if (wethToDonate != 0) {
            _safeTransfer(WETH, TARGET, wethToDonate);
            _donatedWeth = wethToDonate;
        }

        // Path stage 3: call the target entry so it can probe/swap/unwrap using its own balances.
        _targetEntryReached = _callTarget(EXECUTE_ON_OPPORTUNITY) || _callTarget(RECONSTRUCTED_ENTRY);

        // Path stage 4: observe that nothing is transferred back out to the operator. The best-effort
        // mechanical proof here is that after funding + entry execution, the target still retains at least
        // the donated ETH/WETH value while this PoC realizes zero profit.
        uint256 targetEthAfter = TARGET.balance;
        uint256 targetWethAfter = _balanceOf(WETH, TARGET);
        uint256 attackerEthAfter = address(this).balance;

        _profitToken = address(0);
        _profitAmount = attackerEthAfter > attackerEthBefore ? attackerEthAfter - attackerEthBefore : 0;

        uint256 retainedBefore = targetEthBefore + targetWethBefore;
        uint256 retainedAfter = targetEthAfter + targetWethAfter;
        uint256 donatedValue = _donatedEth + _donatedWeth;

        _hypothesisValidated = donatedValue != 0 && _profitAmount == 0 && retainedAfter >= retainedBefore + donatedValue;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function exploitPath() external pure returns (string memory) {
        return "fund target with ETH, donate residual WETH, call executeOnOpportunity, observe assets remain trapped";
    }

    function donatedEth() external view returns (uint256) {
        return _donatedEth;
    }

    function donatedWeth() external view returns (uint256) {
        return _donatedWeth;
    }

    function targetEntryReached() external view returns (bool) {
        return _targetEntryReached;
    }

    function _fundTargetNative(uint256 amount) internal {
        (bool ok,) = TARGET.call{value: amount}("");
        if (!ok) {
            ForceETH helper = new ForceETH{value: amount}();
            helper.destroy(payable(TARGET));
        }
    }

    function _callTarget(bytes4 selector) internal returns (bool ok) {
        (ok,) = TARGET.call(abi.encodePacked(selector));
    }

    function _balanceOf(address token, address owner) internal view returns (uint256 bal) {
        (bool ok, bytes memory ret) = token.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, owner));
        if (!ok || ret.length < 32) return 0;
        bal = abi.decode(ret, (uint256));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "transfer failed");
    }

    receive() external payable {}
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 696.79ms
Compiler run successful with warnings:
Warning (5159): "selfdestruct" has been deprecated. Note that, starting from the Cancun hard fork, the underlying opcode no longer deletes the code and data associated with an account and only transfers its Ether to the beneficiary, unless executed in the same transaction in which the contract was created (see EIP-6780). Any use in newly deployed contracts is strongly discouraged even if the new behavior is taken into account. Future changes to the EVM might further reduce the functionality of the opcode.
  --> src/FlawVerifier.sol:18:9:
   |
18 |         selfdestruct(to);
   |         ^^^^^^^^^^^^

Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:74:19:
   |
74 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 249947)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 1000000000000000000000000
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 100000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x0000000000000000000000000000000000000000
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001

Traces:
  [249947] FlawVerifierTest::testExploit()
    ├─ [2318] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [223550] FlawVerifier::executeOnOpportunity()
    │   ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x35D8949372D46B7a3D5A56006AE77B215fc69bC0) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [4978] 0x35D8949372D46B7a3D5A56006AE77B215fc69bC0::fallback{value: 500000000000000000000000}()
    │   │   ├─ [44] 0xe025d17562A62159E6731298c5A51ad444529354::fallback{value: 500000000000000000000000}() [delegatecall]
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [24266] → new ForceETH@0x104fBc016F4bb334D775a19E8A6510109AC63E00
    │   │   └─ ← [Return] 121 bytes of code
    │   ├─ [5147] ForceETH::destroy(0x35D8949372D46B7a3D5A56006AE77B215fc69bC0)
    │   │   └─ ← [SelfDestruct]
    │   ├─ [23974] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::deposit{value: 500000000000000000000000}()
    │   │   ├─  emit topic 0: 0xe1fffcc4923d04b559f4d29a8bfc6cda04eb5b0d3c460751c2402c5c5cc9109c
    │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │           data: 0x0000000000000000000000000000000000000000000069e10de76676d0800000
    │   │   └─ ← [Stop]
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 500000000000000000000000 [5e23]
    │   ├─ [23162] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::transfer(0x35D8949372D46B7a3D5A56006AE77B215fc69bC0, 500000000000000000000000 [5e23])
    │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │        topic 2: 0x00000000000000000000000035d8949372d46b7a3d5a56006ae77b215fc69bc0
    │   │   │           data: 0x0000000000000000000000000000000000000000000069e10de76676d0800000
    │   │   └─ ← [Return] true
    │   ├─ [5194] 0x35D8949372D46B7a3D5A56006AE77B215fc69bC0::executeOnOpportunity()
    │   │   ├─ [257] 0xe025d17562A62159E6731298c5A51ad444529354::executeOnOpportunity() [delegatecall]
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [5206] 0x35D8949372D46B7a3D5A56006AE77B215fc69bC0::a0712d68()
    │   │   ├─ [269] 0xe025d17562A62159E6731298c5A51ad444529354::a0712d68() [delegatecall]
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x35D8949372D46B7a3D5A56006AE77B215fc69bC0) [staticcall]
    │   │   └─ ← [Return] 500000000000000000000000 [5e23]
    │   └─ ← [Return]
    ├─ [318] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [319] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 1000000000000000000000000 [1e24])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xe025d17562A62159E6731298c5A51ad444529354
  at 0x35D8949372D46B7a3D5A56006AE77B215fc69bC0
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 78.62ms (3.08ms CPU time)

Ran 1 test suite in 109.77ms (78.62ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 249947)

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
