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
- title: Upgradeable presale exposes no initializer, leaving proxy owner and all core configuration permanently unset
- claim: PresaleV5 inherits Initializable, OwnableUpgradeable, PausableUpgradeable, and ReentrancyGuardUpgradeable, but the contract defines no external initializer that calls __Ownable_init, __Pausable_init, __ReentrancyGuard_init, or sets required sale configuration. The constructor only consumes the initializer slot on the implementation, so a proxy instance starts with owner == address(0) and every configurable dependency/value left at its zero default.
- impact: All onlyOwner administration paths are permanently unreachable on the proxy, so the sale cannot be configured, paused, funded for claims, or repaired through this implementation. Any assets later routed into the proxy can become stuck behind an ownerless contract until the proxy admin deploys and upgrades to a different implementation.
- exploit_paths: ["Deploy PresaleV5 behind a proxy", "Observe that no external initialize/reinitialize function exists to set owner or core parameters", "Any call guarded by onlyOwner reverts forever because owner() remains address(0)"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPresaleV5Like {
    function owner() external view returns (address);
    function saleToken() external view returns (address);
    function startTime() external view returns (uint256);
    function endTime() external view returns (uint256);
    function claimStart() external view returns (uint256);
    function paymentWallet() external view returns (address);
    function dynamicSaleState() external view returns (bool);
    function maxTokensToSell() external view returns (uint256);
    function USDTInterface() external view returns (address);
    function stakingContract() external view returns (address);
    function router() external view returns (address);
    function staticTokenPrice() external view returns (uint256);
}

contract MinimalERC1967Proxy {
    bytes32 private constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    constructor(address implementation, bytes memory data) payable {
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly {
            sstore(slot, implementation)
        }

        if (data.length != 0) {
            (bool ok, bytes memory ret) = implementation.delegatecall(data);
            if (!ok) {
                assembly {
                    revert(add(ret, 0x20), mload(ret))
                }
            }
        }
    }

    fallback() external payable {
        _delegate();
    }

    receive() external payable {
        _delegate();
    }

    function _delegate() internal {
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly {
            let implementation := sload(slot)
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())

            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}

contract FlawVerifier {
    address public constant TARGET = 0x1F006F43f57C45Ceb3659E543352b4FAe4662dF7;
    address public constant IMPLEMENTATION = 0xE69be7d6B306b4FbCe516e3f07C8f438a6860084;
    uint256 public constant FORK_BLOCK = 17_949_214;
    uint256 public constant EXPECTED_CHAIN_ID = 1;

    address private _profitToken;
    uint256 private _profitAmount;

    bool public executed;
    bool public profitAchieved;
    bool public hypothesisValidated;

    address public deployedProxy;

    bool public observedOwnerReadable;
    bool public observedSaleTokenReadable;
    bool public observedPaymentWalletReadable;
    bool public observedUsdtReadable;
    bool public observedStakingContractReadable;
    bool public observedRouterReadable;
    bool public observedStartTimeReadable;
    bool public observedEndTimeReadable;
    bool public observedClaimStartReadable;
    bool public observedMaxTokensToSellReadable;
    bool public observedStaticTokenPriceReadable;
    bool public observedDynamicSaleStateReadable;

    address public observedOwner;
    address public observedSaleToken;
    address public observedPaymentWallet;
    address public observedUsdt;
    address public observedStakingContract;
    address public observedRouter;
    uint256 public observedStartTime;
    uint256 public observedEndTime;
    uint256 public observedClaimStart;
    uint256 public observedMaxTokensToSell;
    uint256 public observedStaticTokenPrice;
    bool public observedDynamicSaleState;

    bool public initializeNoArgsSucceeded;
    bool public initializeAddressSucceeded;
    bool public reinitializeSucceeded;
    bool public pauseSucceeded;
    bool public startClaimSucceeded;

    string private _exploitPath;
    string private _status;

    constructor() {
        _profitToken = address(0);
        _exploitPath =
            "deploy PresaleV5 behind a proxy using the existing on-chain implementation -> observe no external initialize/reinitialize entrypoint exists to populate proxy storage -> read owner/core sale configuration from the fresh proxy and observe zero defaults -> call onlyOwner administration on that proxy and observe permanent failure because owner remains address(0)";
        _status = "not executed";
    }

    function executeOnOpportunity() external {
        executed = true;
        hypothesisValidated = false;
        profitAchieved = false;
        _profitToken = address(0);
        _profitAmount = 0;
        _status = "running";

        if (block.chainid != EXPECTED_CHAIN_ID) {
            _status = "refuted: wrong chain";
            return;
        }

        if (TARGET.code.length == 0) {
            _status = "refuted: provided proxy target has no code";
            return;
        }

        if (IMPLEMENTATION.code.length == 0) {
            _status = "refuted: implementation has no code";
            return;
        }

        // Path stage 1:
        // Deploy a fresh proxy against the already-deployed PresaleV5 implementation.
        // This keeps the exploit root cause unchanged while avoiding false negatives
        // from the separately managed live proxy at TARGET, which is already configured
        // on this fork.
        MinimalERC1967Proxy proxy = new MinimalERC1967Proxy(IMPLEMENTATION, bytes(""));
        deployedProxy = address(proxy);

        IPresaleV5Like freshProxy = IPresaleV5Like(address(proxy));

        // Path stage 2:
        // The implementation exposes no external initializer/reinitializer entrypoint
        // that can populate the new proxy's storage, so the common upgradeable init
        // selectors should fail when called on the fresh proxy.
        (initializeNoArgsSucceeded, ) = address(proxy).call(abi.encodeWithSignature("initialize()"));
        (initializeAddressSucceeded, ) =
            address(proxy).call(abi.encodeWithSignature("initialize(address)", address(this)));
        (reinitializeSucceeded, ) = address(proxy).call(abi.encodeWithSignature("reinitialize(uint8)", uint8(1)));

        // Read the freshly deployed proxy state without assuming every getter is safe
        // on arbitrary live deployments. On this new proxy all expected public getters
        // should resolve against the current implementation.
        (observedOwnerReadable, observedOwner) = _readAddress(address(freshProxy), abi.encodeWithSignature("owner()"));
        (observedSaleTokenReadable, observedSaleToken) =
            _readAddress(address(freshProxy), abi.encodeWithSignature("saleToken()"));
        (observedPaymentWalletReadable, observedPaymentWallet) =
            _readAddress(address(freshProxy), abi.encodeWithSignature("paymentWallet()"));
        (observedUsdtReadable, observedUsdt) =
            _readAddress(address(freshProxy), abi.encodeWithSignature("USDTInterface()"));
        (observedStakingContractReadable, observedStakingContract) =
            _readAddress(address(freshProxy), abi.encodeWithSignature("stakingContract()"));
        (observedRouterReadable, observedRouter) =
            _readAddress(address(freshProxy), abi.encodeWithSignature("router()"));
        (observedStartTimeReadable, observedStartTime) =
            _readUint(address(freshProxy), abi.encodeWithSignature("startTime()"));
        (observedEndTimeReadable, observedEndTime) =
            _readUint(address(freshProxy), abi.encodeWithSignature("endTime()"));
        (observedClaimStartReadable, observedClaimStart) =
            _readUint(address(freshProxy), abi.encodeWithSignature("claimStart()"));
        (observedMaxTokensToSellReadable, observedMaxTokensToSell) =
            _readUint(address(freshProxy), abi.encodeWithSignature("maxTokensToSell()"));
        (observedStaticTokenPriceReadable, observedStaticTokenPrice) =
            _readUint(address(freshProxy), abi.encodeWithSignature("staticTokenPrice()"));
        (observedDynamicSaleStateReadable, observedDynamicSaleState) =
            _readBool(address(freshProxy), abi.encodeWithSignature("dynamicSaleState()"));

        // Path stage 3:
        // With owner left at address(0) on the fresh proxy, onlyOwner-controlled
        // administration stays permanently unreachable. Dummy parameters are only to
        // satisfy ABI shape; exploit causality remains the missing initializer.
        (pauseSucceeded, ) = address(proxy).call(abi.encodeWithSignature("pause()"));
        (startClaimSucceeded, ) = address(proxy).call(
            abi.encodeWithSignature(
                "startClaim(uint256,uint256,address,address)",
                uint256(1),
                uint256(0),
                address(1),
                address(1)
            )
        );

        bool readableCoreSurface = observedOwnerReadable
            && observedSaleTokenReadable
            && observedPaymentWalletReadable
            && observedUsdtReadable
            && observedStakingContractReadable
            && observedRouterReadable
            && observedStartTimeReadable
            && observedEndTimeReadable
            && observedClaimStartReadable
            && observedMaxTokensToSellReadable;

        bool zeroedCoreConfig = observedSaleToken == address(0)
            && observedPaymentWallet == address(0)
            && observedUsdt == address(0)
            && observedStakingContract == address(0)
            && observedRouter == address(0)
            && observedStartTime == 0
            && observedEndTime == 0
            && observedClaimStart == 0
            && observedMaxTokensToSell == 0;

        bool optionalConfigStillZero = (!observedStaticTokenPriceReadable || observedStaticTokenPrice == 0)
            && (!observedDynamicSaleStateReadable || observedDynamicSaleState == false);

        hypothesisValidated = readableCoreSurface
            && observedOwner == address(0)
            && zeroedCoreConfig
            && optionalConfigStillZero
            && !initializeNoArgsSucceeded
            && !initializeAddressSucceeded
            && !reinitializeSucceeded
            && !pauseSucceeded
            && !startClaimSucceeded;

        if (hypothesisValidated) {
            // This finding is a liveness / stuck-funds condition, not a withdrawable
            // attacker profit path. No external funding is needed for validation.
            _status = "validated: fresh proxy remains ownerless and unconfigurable because PresaleV5 exposes no initializer";
            return;
        }

        _status = "refuted: fresh proxy did not remain ownerless-uninitialized";
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function exploitPath() external view returns (string memory) {
        return _exploitPath;
    }

    function status() external view returns (string memory) {
        return _status;
    }

    function _readAddress(address target, bytes memory data) internal view returns (bool ok, address value) {
        bytes memory ret;
        (ok, ret) = target.staticcall(data);
        if (!ok || ret.length < 32) {
            return (false, address(0));
        }
        value = abi.decode(ret, (address));
    }

    function _readUint(address target, bytes memory data) internal view returns (bool ok, uint256 value) {
        bytes memory ret;
        (ok, ret) = target.staticcall(data);
        if (!ok || ret.length < 32) {
            return (false, 0);
        }
        value = abi.decode(ret, (uint256));
    }

    function _readBool(address target, bytes memory data) internal view returns (bool ok, bool value) {
        bytes memory ret;
        (ok, ret) = target.staticcall(data);
        if (!ok || ret.length < 32) {
            return (false, false);
        }
        value = abi.decode(ret, (bool));
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 3.44s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 107275)
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
  [107275] FlawVerifierTest::testExploit()
    ├─ [2543] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [79989] FlawVerifier::executeOnOpportunity()
    │   └─ ← [Stop]
    ├─ [543] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [652] FlawVerifier::profitAmount() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.08s (1.04s CPU time)

Ran 1 test suite in 1.12s (1.08s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 107275)

Encountered a total of 1 failing tests, 0 tests succeeded

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
