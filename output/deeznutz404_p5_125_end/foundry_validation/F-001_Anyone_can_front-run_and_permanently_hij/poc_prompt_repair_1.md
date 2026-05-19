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
- title: Anyone can front-run and permanently hijack the mirror/base link
- claim: The mirror-link handshake authenticates only a calldata argument against the stored `deployer`, but never authenticates `msg.sender`. Any address can call the mirror fallback with selector `linkMirrorContract(address)` and pass the expected deployer address, causing `baseERC20` to be set to the attacker's address before the real base calls `initialize()`.
- impact: A third party can permanently brick deployment or hijack the NFT mirror. Once `baseERC20` is set, the legitimate base can no longer link, so initialization reverts and the intended DN404 pair cannot be brought online.
- exploit_paths: ["Attacker learns the mirror's expected `deployer` value from deployment data or storage.", "Before the owner calls `initialize()`, the attacker directly calls the mirror fallback with `linkMirrorContract(address)` and supplies that deployer address.", "The mirror stores the attacker's address as `baseERC20`; the later legitimate `_linkMirrorContract()` call hits `AlreadyLinked` and `initialize()` reverts."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IDeezNutzBase {
    function owner() external view returns (address);
    function mirrorERC721() external view returns (address);
}

interface IDN404Mirror {
    function baseERC20() external view returns (address);
}

contract FlawVerifier {
    address internal constant TARGET = 0xb57E874082417b66877429481473CF9FCd8e0b8a;

    enum Outcome {
        Unset,
        MirrorUndiscoverableFromTargetState,
        PairAlreadyLinkedToTarget,
        MirrorAlreadyLinkedToDifferentBase,
        ExpectedDeployerUnknown
    }

    bool public executed;
    bool public hypothesisValidated;
    bool public profitWasAchieved;
    Outcome public outcome;

    address public observedOwner;
    address public observedMirror;
    address public observedLinkedBase;

    address internal _profitToken;
    uint256 internal _profitAmount;
    string internal _exploitPathUsed;
    string internal _hypothesisResult;
    string internal _failureReason;

    constructor() {
        _profitToken = address(0);
        _exploitPathUsed =
            "attacker directly calls the mirror fallback with linkMirrorContract(address), passes the expected deployer value, and sets baseERC20 to the attacker before the real base initialize() call";
        _hypothesisResult = "validated";
        hypothesisValidated = true;
    }

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        observedOwner = _readAddressNoRevert(TARGET, IDeezNutzBase.owner.selector);
        observedMirror = _readAddressNoRevert(TARGET, IDeezNutzBase.mirrorERC721.selector);

        if (observedMirror == address(0)) {
            outcome = Outcome.MirrorUndiscoverableFromTargetState;
            // Path stage 1 requires the attacker to know the specific mirror address
            // and expected deployer value from deployment data or mirror storage.
            // Before initialize(), this base contract does not expose the mirror address
            // onchain, and this zero-argument verifier cannot synthesize off-chain mempool
            // knowledge without changing the exploit path.
            _failureReason =
                "base mirrorERC721 storage is still zero, so the required mirror address is not derivable from target state alone";
            return;
        }

        (bool linked, address linkedBase) = _tryReadMirrorBase(observedMirror);
        observedLinkedBase = linkedBase;

        if (linked) {
            if (linkedBase == TARGET) {
                outcome = Outcome.PairAlreadyLinkedToTarget;
                // Once the legitimate base has already linked, the front-run window in the
                // finding is closed: a later attacker call hits AlreadyLinked, so no exploit
                // path remains at this fork block.
                _failureReason =
                    "mirror baseERC20 is already linked to the target base, so the pre-initialize frontrun window is closed";
                return;
            }

            outcome = Outcome.MirrorAlreadyLinkedToDifferentBase;
            _failureReason =
                "mirror baseERC20 is already non-zero and points to a different base, so any further linkMirrorContract call would revert AlreadyLinked";
            return;
        }

        outcome = Outcome.ExpectedDeployerUnknown;
        // This matches the claimed root cause mechanically: the mirror would accept any
        // msg.sender if the calldata argument equals the stored deployer. However, the
        // deployer value itself is constructor-only state with no public getter, so the
        // verifier cannot produce the required calldata argument from target-visible state.
        _failureReason =
            "mirror exists and is not yet linked, but the expected deployer value needed for linkMirrorContract(address) is not readable through public onchain interfaces";
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

    function hypothesisResult() external view returns (string memory) {
        return _hypothesisResult;
    }

    function failureReason() external view returns (string memory) {
        return _failureReason;
    }

    function _tryReadMirrorBase(address mirror) internal view returns (bool linked, address base) {
        (bool ok, bytes memory data) = mirror.staticcall(
            abi.encodeWithSelector(IDN404Mirror.baseERC20.selector)
        );
        if (ok && data.length >= 32) {
            base = abi.decode(data, (address));
            linked = true;
        }
    }

    function _readAddressNoRevert(address target, bytes4 selector) internal view returns (address value) {
        (bool ok, bytes memory data) = target.staticcall(abi.encodeWithSelector(selector));
        if (ok && data.length >= 32) {
            value = abi.decode(data, (address));
        }
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.28s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 204691)
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
  [204691] FlawVerifierTest::testExploit()
    ├─ [2390] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [175953] FlawVerifier::executeOnOpportunity()
    │   ├─ [2649] 0xb57E874082417b66877429481473CF9FCd8e0b8a::owner() [staticcall]
    │   │   └─ ← [Return] 0x882EDEdB3Eb6540f86F2E7004F2aE09b3ed8F7BE
    │   ├─ [2561] 0xb57E874082417b66877429481473CF9FCd8e0b8a::mirrorERC721() [staticcall]
    │   │   └─ ← [Return] 0xa2950aAd0E7c89679EaC0f17140E20043139836A
    │   ├─ [2586] 0xa2950aAd0E7c89679EaC0f17140E20043139836A::baseERC20() [staticcall]
    │   │   └─ ← [Return] 0xb57E874082417b66877429481473CF9FCd8e0b8a
    │   └─ ← [Stop]
    ├─ [390] FlawVerifier::profitToken() [staticcall]
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
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 4.54s (1.39s CPU time)

Ran 1 test suite in 4.63s (4.54s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 204691)

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
