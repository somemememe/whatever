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
- strategy_label: direct_or_existing_balance_first
- strategy_instructions: Prefer direct execution using verifier-held assets first. Only use temporary external funding if direct path is infeasible.
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

interface IPresaleV5ProxyView {
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

contract FlawVerifier {
    address public constant TARGET = 0x1F006F43f57C45Ceb3659E543352b4FAe4662dF7;
    uint256 public constant FORK_BLOCK = 17_949_214;
    uint256 public constant EXPECTED_CHAIN_ID = 1;

    address private _profitToken;
    uint256 private _profitAmount;

    bool public executed;
    bool public profitAchieved;
    bool public hypothesisValidated;

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
            "existing TransparentUpgradeableProxy target -> call likely initializer/reinitializer entrypoints and observe they are absent -> read owner/config state and observe owner==address(0) with zero-value configuration -> call onlyOwner admin functions and observe they revert";
        _status = "not executed";
    }

    function executeOnOpportunity() external {
        executed = true;
        profitAchieved = false;
        _profitToken = address(0);
        _profitAmount = 0;

        if (block.chainid != EXPECTED_CHAIN_ID) {
            hypothesisValidated = false;
            _status = "refuted: wrong chain";
            return;
        }

        if (TARGET.code.length == 0) {
            hypothesisValidated = false;
            _status = "refuted: target has no code";
            return;
        }

        IPresaleV5ProxyView target = IPresaleV5ProxyView(TARGET);

        observedOwner = target.owner();
        observedSaleToken = target.saleToken();
        observedPaymentWallet = target.paymentWallet();
        observedUsdt = target.USDTInterface();
        observedStakingContract = target.stakingContract();
        observedRouter = target.router();
        observedStartTime = target.startTime();
        observedEndTime = target.endTime();
        observedClaimStart = target.claimStart();
        observedMaxTokensToSell = target.maxTokensToSell();
        observedStaticTokenPrice = target.staticTokenPrice();
        observedDynamicSaleState = target.dynamicSaleState();

        // Path stage 1:
        // The task provides a fixed deployed proxy target on mainnet. The verifier
        // operates on that existing proxy instance instead of deploying a duplicate.

        // Path stage 2:
        // PresaleV5 exposes no external initializer in the verified source. These
        // calls check the common upgradeable initialization entrypoints directly on
        // the live proxy and should all fail.
        (initializeNoArgsSucceeded, ) = TARGET.call(abi.encodeWithSignature("initialize()"));
        (initializeAddressSucceeded, ) = TARGET.call(abi.encodeWithSignature("initialize(address)", address(this)));
        (reinitializeSucceeded, ) = TARGET.call(abi.encodeWithSignature("reinitialize(uint8)", uint8(1)));

        // Path stage 3:
        // With owner() left at address(0), onlyOwner administration is permanently
        // unreachable through this implementation, so configuration/funding/repair
        // actions revert. startClaim is used because it is one of the core owner
        // configuration paths named in the finding. The dummy arguments do not alter
        // exploit causality because onlyOwner should fail before parameter checks.
        (pauseSucceeded, ) = TARGET.call(abi.encodeWithSignature("pause()"));
        (startClaimSucceeded, ) = TARGET.call(
            abi.encodeWithSignature(
                "startClaim(uint256,uint256,address,address)",
                uint256(1),
                uint256(0),
                address(0),
                address(0)
            )
        );

        bool zeroedCoreConfig = observedSaleToken == address(0)
            && observedPaymentWallet == address(0)
            && observedUsdt == address(0)
            && observedStakingContract == address(0)
            && observedRouter == address(0)
            && observedStartTime == 0
            && observedEndTime == 0
            && observedClaimStart == 0
            && observedMaxTokensToSell == 0
            && observedStaticTokenPrice == 0
            && observedDynamicSaleState == false;

        hypothesisValidated = observedOwner == address(0)
            && zeroedCoreConfig
            && !initializeNoArgsSucceeded
            && !initializeAddressSucceeded
            && !reinitializeSucceeded
            && !pauseSucceeded
            && !startClaimSucceeded;

        if (hypothesisValidated) {
            // Concrete economic result at this fork:
            // the flaw is a liveness/stuck-funds issue, not an attacker-withdrawable
            // path. With ownerless zeroed config, public buy/claim flows are unusable,
            // and no privileged path can be seized by the attacker through this code.
            _status = "validated: ownerless proxy with unreachable admin paths; no attacker profit path";
            return;
        }

        _status = "refuted: target state does not match the ownerless-uninitialized hypothesis";
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
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.60s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 280105)
Traces:
  [280105] FlawVerifierTest::testExploit()
    ├─ [2433] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [271398] FlawVerifier::executeOnOpportunity()
    │   ├─ [9738] 0x1F006F43f57C45Ceb3659E543352b4FAe4662dF7::owner() [staticcall]
    │   │   ├─ [2422] 0xDb0618E0B850CAb3F756d030398bE22929226d5c::owner() [delegatecall]
    │   │   │   └─ ← [Return] 0x6de493dE7F89c77a249Cf44631c60eF67f06D091
    │   │   └─ ← [Return] 0x6de493dE7F89c77a249Cf44631c60eF67f06D091
    │   ├─ [3220] 0x1F006F43f57C45Ceb3659E543352b4FAe4662dF7::saleToken() [staticcall]
    │   │   ├─ [2404] 0xDb0618E0B850CAb3F756d030398bE22929226d5c::saleToken() [delegatecall]
    │   │   │   └─ ← [Return] 0xE86DF1970055e9CaEe93Dae9B7D5fD71595d0e18
    │   │   └─ ← [Return] 0xE86DF1970055e9CaEe93Dae9B7D5fD71595d0e18
    │   ├─ [3265] 0x1F006F43f57C45Ceb3659E543352b4FAe4662dF7::paymentWallet() [staticcall]
    │   │   ├─ [2449] 0xDb0618E0B850CAb3F756d030398bE22929226d5c::paymentWallet() [delegatecall]
    │   │   │   └─ ← [Return] 0x58178A119781df139307572066D5E74704809861
    │   │   └─ ← [Return] 0x58178A119781df139307572066D5E74704809861
    │   ├─ [3264] 0x1F006F43f57C45Ceb3659E543352b4FAe4662dF7::USDTInterface() [staticcall]
    │   │   ├─ [2448] 0xDb0618E0B850CAb3F756d030398bE22929226d5c::USDTInterface() [delegatecall]
    │   │   │   └─ ← [Return] 0xdAC17F958D2ee523a2206206994597C13D831ec7
    │   │   └─ ← [Return] 0xdAC17F958D2ee523a2206206994597C13D831ec7
    │   ├─ [3286] 0x1F006F43f57C45Ceb3659E543352b4FAe4662dF7::stakingContract() [staticcall]
    │   │   ├─ [2470] 0xDb0618E0B850CAb3F756d030398bE22929226d5c::stakingContract() [delegatecall]
    │   │   │   └─ ← [Return] 0xC2FF810b1c486B4e24dbA8dE19D1977C98f6Ab9D
    │   │   └─ ← [Return] 0xC2FF810b1c486B4e24dbA8dE19D1977C98f6Ab9D
    │   ├─ [3219] 0x1F006F43f57C45Ceb3659E543352b4FAe4662dF7::router() [staticcall]
    │   │   ├─ [2403] 0xDb0618E0B850CAb3F756d030398bE22929226d5c::router() [delegatecall]
    │   │   │   └─ ← [Return] 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
    │   │   └─ ← [Return] 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
    │   ├─ [3200] 0x1F006F43f57C45Ceb3659E543352b4FAe4662dF7::startTime() [staticcall]
    │   │   ├─ [2384] 0xDb0618E0B850CAb3F756d030398bE22929226d5c::startTime() [delegatecall]
    │   │   │   └─ ← [Return] 1686824916 [1.686e9]
    │   │   └─ ← [Return] 1686824916 [1.686e9]
    │   ├─ [3202] 0x1F006F43f57C45Ceb3659E543352b4FAe4662dF7::endTime() [staticcall]
    │   │   ├─ [2386] 0xDb0618E0B850CAb3F756d030398bE22929226d5c::endTime() [delegatecall]
    │   │   │   └─ ← [Return] 1703961000 [1.703e9]
    │   │   └─ ← [Return] 1703961000 [1.703e9]
    │   ├─ [3178] 0x1F006F43f57C45Ceb3659E543352b4FAe4662dF7::claimStart() [staticcall]
    │   │   ├─ [2362] 0xDb0618E0B850CAb3F756d030398bE22929226d5c::claimStart() [delegatecall]
    │   │   │   └─ ← [Return] 1691557231 [1.691e9]
    │   │   └─ ← [Return] 1691557231 [1.691e9]
    │   ├─ [3246] 0x1F006F43f57C45Ceb3659E543352b4FAe4662dF7::maxTokensToSell() [staticcall]
    │   │   ├─ [2430] 0xDb0618E0B850CAb3F756d030398bE22929226d5c::maxTokensToSell() [delegatecall]
    │   │   │   └─ ← [Return] 100000 [1e5]
    │   │   └─ ← [Return] 100000 [1e5]
    │   ├─ [1048] 0x1F006F43f57C45Ceb3659E543352b4FAe4662dF7::staticTokenPrice() [staticcall]
    │   │   ├─ [234] 0xDb0618E0B850CAb3F756d030398bE22929226d5c::staticTokenPrice() [delegatecall]
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   └─ ← [Revert] EvmError: Revert
    └─ ← [Revert] exploit call reverted

Backtrace:
  at 0xDb0618E0B850CAb3F756d030398bE22929226d5c.staticTokenPrice
  at 0x1F006F43f57C45Ceb3659E543352b4FAe4662dF7.staticTokenPrice
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 6.42s (3.18s CPU time)

Ran 1 test suite in 6.54s (6.42s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 280105)

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
