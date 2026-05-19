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
- title: Hard-coded Ethereum mainnet endpoints can burn the treasury on the wrong chain
- claim: The contract hard-codes Ethereum mainnet token and router addresses but never verifies `block.chainid` or that those endpoints are the intended contracts before sending value and interacting with them. In particular, `_tryCycle()` sends native currency to the hard-coded `WETH` address through `deposit()` with no code or chain check.
- impact: If `FlawVerifier` is deployed or replayed on a different EVM network, its funded native-token treasury can be irreversibly transferred to an unrelated EOA or noncanonical contract at the same address, or otherwise routed through arbitrary endpoints instead of real WETH/Uniswap infrastructure.
- exploit_paths: ["Deploy `FlawVerifier` on any non-Ethereum-mainnet EVM chain.", "Fund it with native currency and call `executeOnOpportunity()`.", "`_tryCycle()` executes `IWETH(WETH).deposit{value: ethIn}()` against the hard-coded address, sending treasury funds to whatever exists there on that chain."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
}

interface IWETH is IERC20Minimal {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

contract FlawVerifier {
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint256 internal constant EXPECTED_CHAIN_ID = 1;

    address private _profitToken;
    uint256 private _profitAmount;

    bool private _hypothesisValidated;
    bool private _hypothesisRefuted;

    uint256 private _ethBefore;
    uint256 private _ethSentToHardcodedEndpoint;
    uint256 private _wethBefore;
    uint256 private _wethAfter;
    uint256 private _redeemableValueAfter;
    bool private _hardcodedEndpointHasCode;
    bool private _depositCallSucceeded;

    constructor() {}

    receive() external payable {}

    fallback() external payable {}

    function executeOnOpportunity() external {
        _resetReport();

        _ethBefore = address(this).balance;
        _wethBefore = _balanceOf(WETH, address(this));
        _hardcodedEndpointHasCode = WETH.code.length != 0;

        // Path stage 1: deploy FlawVerifier on the current chain.
        // Path stage 2: fund it with native currency.
        // Path stage 3: call executeOnOpportunity().
        // Path stage 4: _tryCycle() executes IWETH(WETH).deposit{value: ethIn}() against the hard-coded endpoint.
        //
        // This is the exact exploit path from the finding. On a non-mainnet deployment, the same hard-coded
        // address could resolve to an EOA or arbitrary contract and misdirect/burn treasury value. On the
        // provided fork, block.chainid == 1 and the endpoint is canonical mainnet WETH, so ETH is wrapped
        // 1:1 into redeemable WETH instead of being irreversibly lost.
        _tryCycle();

        _wethAfter = _balanceOf(WETH, address(this));
        _redeemableValueAfter = address(this).balance + _wethAfter;

        _profitToken = address(0);
        _profitAmount = 0;

        if (block.chainid != EXPECTED_CHAIN_ID || !_hardcodedEndpointHasCode) {
            _hypothesisValidated = _depositCallSucceeded && _ethSentToHardcodedEndpoint != 0;
            _hypothesisRefuted = !_hypothesisValidated;
        } else {
            // Concrete fork-state refutation:
            // 1. chainid is 1, so the hard-coded address is on its intended network.
            // 2. the endpoint has runtime code, so the value is not sent to a blank account / EOA.
            // 3. the post-call WETH balance increases by the ETH sent to deposit, preserving redeemable value.
            bool wrappedOneForOne = _depositCallSucceeded && _wethAfter >= _wethBefore + _ethSentToHardcodedEndpoint;
            _hypothesisValidated = false;
            _hypothesisRefuted = wrappedOneForOne;
        }
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

    function hypothesisRefuted() external view returns (bool) {
        return _hypothesisRefuted;
    }

    function exploitPath() external pure returns (string memory) {
        return "deploy FlawVerifier on current chain -> fund with native currency -> call executeOnOpportunity() -> _tryCycle() calls IWETH(WETH).deposit{value:ethIn}() against the hard-coded endpoint";
    }

    function ethBefore() external view returns (uint256) {
        return _ethBefore;
    }

    function ethSentToHardcodedEndpoint() external view returns (uint256) {
        return _ethSentToHardcodedEndpoint;
    }

    function wethBefore() external view returns (uint256) {
        return _wethBefore;
    }

    function wethAfter() external view returns (uint256) {
        return _wethAfter;
    }

    function redeemableValueAfter() external view returns (uint256) {
        return _redeemableValueAfter;
    }

    function hardcodedEndpointHasCode() external view returns (bool) {
        return _hardcodedEndpointHasCode;
    }

    function depositCallSucceeded() external view returns (bool) {
        return _depositCallSucceeded;
    }

    function _tryCycle() internal {
        uint256 ethIn = address(this).balance;
        _ethSentToHardcodedEndpoint = ethIn;

        if (ethIn == 0) {
            _depositCallSucceeded = false;
            return;
        }

        // Minimal path-strict action from the finding.
        // No balance injection, storage editing, mocking, or privileged impersonation is used.
        try IWETH(WETH).deposit{value: ethIn}() {
            _depositCallSucceeded = true;
        } catch {
            _depositCallSucceeded = false;
        }
    }

    function _resetReport() internal {
        _profitToken = address(0);
        _profitAmount = 0;
        _hypothesisValidated = false;
        _hypothesisRefuted = false;
        _ethBefore = 0;
        _ethSentToHardcodedEndpoint = 0;
        _wethBefore = 0;
        _wethAfter = 0;
        _redeemableValueAfter = 0;
        _hardcodedEndpointHasCode = false;
        _depositCallSucceeded = false;
    }

    function _balanceOf(address token, address owner) internal view returns (uint256 balance) {
        (bool ok, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, owner)
        );

        if (ok && data.length >= 32) {
            balance = abi.decode(data, (uint256));
        }
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.24s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:74:19:
   |
74 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 202201)
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
  [202201] FlawVerifierTest::testExploit()
    ├─ [2389] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [175571] FlawVerifier::executeOnOpportunity()
    │   ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [21974] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::deposit{value: 1000000000000000000000000}()
    │   │   ├─  emit topic 0: 0xe1fffcc4923d04b559f4d29a8bfc6cda04eb5b0d3c460751c2402c5c5cc9109c
    │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │           data: 0x00000000000000000000000000000000000000000000d3c21bcecceda1000000
    │   │   └─ ← [Stop]
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 1000000000000000000000000 [1e24]
    │   └─ ← [Return]
    ├─ [389] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [410] FlawVerifier::profitAmount() [staticcall]
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
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 114.89ms (2.33ms CPU time)

Ran 1 test suite in 186.17ms (114.89ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 202201)

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
