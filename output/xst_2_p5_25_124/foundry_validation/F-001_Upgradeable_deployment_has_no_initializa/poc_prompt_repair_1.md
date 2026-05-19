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
- title: Upgradeable deployment has no initialization path, leaving owner and core state permanently unset
- claim: `XStable2` inherits `Initializable` and `OwnableUpgradeable` but exposes no constructor or initializer, and the codebase contains no assignment path for `_owner`, `_presaleCon`, `_largeTotal`, `_liquidityReserve`, `_stabilizer`, or `_mainPool`. A proxy deployment therefore leaves all of these storage slots at their zero defaults forever: `owner()` remains `address(0)`, `onlyOwner` administration is unreachable, `mint()` cannot be called by any real presale contract because `_presaleCon` stays zero, and the post-presale rebase factor would become unusable if `_presaleDone` were ever flipped because `getFactor()` would then divide by the uninitialized `_largeTotal` of zero.
- impact: The protocol can be deployed into an unrecoverable state with no privileged recovery path and no working presale mint authority. Even if another upgrade later forces `_presaleDone = true`, balance reads and transfer math would fail because the live rebase state was never initialized.
- exploit_paths: ["Deploy behind a proxy -> no initializer exists -> `owner()` stays `address(0)` -> every `onlyOwner` function is permanently inaccessible", "Attempt presale minting -> `onlyPresale` compares caller to zero `_presaleCon` -> no legitimate presale contract can ever call `mint()`", "Any later attempt to activate post-presale mode -> `getFactor()` uses zero `_largeTotal` -> balance-dependent flows revert or become unusable"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IXStable2Like {
    function owner() external view returns (address);
    function getPresaleAddress() external view returns (address);
    function isPresaleDone() external view returns (bool);
    function getLargeTotal() external view returns (uint256);
    function getFactor() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function mint(address to, uint256 amount) external;
    function pauseContract(bool flag) external;
}

contract EmptyInitProxy {
    bytes32 private constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    constructor(address implementation_) payable {
        assembly {
            sstore(IMPLEMENTATION_SLOT, implementation_)
        }
    }

    fallback() external payable {
        _delegate();
    }

    receive() external payable {
        _delegate();
    }

    function _delegate() internal {
        assembly {
            let implementation_ := sload(IMPLEMENTATION_SLOT)
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), implementation_, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}

contract FlawVerifier {
    address public constant TARGET = 0x91383A15C391c142b80045D8b4730C1c37ac0378;
    address public constant IMPLEMENTATION = 0xb276647E70CB3b81a1cA302Cf8DE280fF0cE5799;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint256 public constant FORK_BLOCK = 15310016;

    address private _profitToken = WETH;
    uint256 private _profitAmount;

    bool public executed;
    bool public usedLiveTarget;
    bool public usedFreshBlankProxy;

    address public verificationAddress;

    address public liveOwner;
    address public livePresale;
    bool public livePresaleDone;
    uint256 public liveLargeTotal;
    uint256 public liveFactor;
    bool public liveTargetMatchesBlankDeployment;

    bool public ownerZeroObserved;
    bool public onlyOwnerBlockedObserved;
    bool public presaleAddressZeroObserved;
    bool public mintBlockedObserved;
    bool public presaleNeverDoneObserved;
    bool public largeTotalZeroObserved;
    bool public zeroFactorObserved;
    bool public balancePathBlockedObserved;
    bool public transferPathBlockedObserved;

    bytes public onlyOwnerRevertData;
    bytes public mintRevertData;
    bytes public balanceRevertData;
    bytes public transferRevertData;

    bool public postPresaleStageProvablyInfeasibleAtFork;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;

    constructor() {}

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        _snapshotLiveTarget();

        address subject = TARGET;
        if (liveTargetMatchesBlankDeployment) {
            usedLiveTarget = true;
            verificationAddress = TARGET;
        } else {
            usedFreshBlankProxy = true;
            subject = address(new EmptyInitProxy(IMPLEMENTATION));
            verificationAddress = subject;
        }

        _exercisePath(subject);
        _finalizeOutcome();
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function exploitPathUsed() external pure returns (string memory) {
        return "deploy proxy with empty init data to XStable2 implementation -> owner() remains address(0) so onlyOwner admin is unreachable -> _presaleCon remains address(0) so mint() is unreachable -> _presaleDone remains false and _largeTotal remains zero so balance-dependent flows are unusable and any later post-presale activation is mechanically infeasible at this fork because no code path assigns _presaleDone";
    }

    function findingId() external pure returns (string memory) {
        return "F-001";
    }

    function forkBlock() external pure returns (uint256) {
        return FORK_BLOCK;
    }

    function targetContract() external pure returns (address) {
        return TARGET;
    }

    function _snapshotLiveTarget() internal {
        liveOwner = _readAddress(TARGET, abi.encodeWithSelector(IXStable2Like.owner.selector));
        livePresale = _readAddress(TARGET, abi.encodeWithSelector(IXStable2Like.getPresaleAddress.selector));
        livePresaleDone = _readBool(TARGET, abi.encodeWithSelector(IXStable2Like.isPresaleDone.selector));
        liveLargeTotal = _readUint256(TARGET, abi.encodeWithSelector(IXStable2Like.getLargeTotal.selector));
        liveFactor = _readUint256(TARGET, abi.encodeWithSelector(IXStable2Like.getFactor.selector));

        liveTargetMatchesBlankDeployment =
            liveOwner == address(0) &&
            livePresale == address(0) &&
            !livePresaleDone &&
            liveLargeTotal == 0 &&
            liveFactor == 0;
    }

    function _exercisePath(address subject) internal {
        IXStable2Like token = IXStable2Like(subject);

        ownerZeroObserved = token.owner() == address(0);
        presaleAddressZeroObserved = token.getPresaleAddress() == address(0);
        presaleNeverDoneObserved = !token.isPresaleDone();
        largeTotalZeroObserved = token.getLargeTotal() == 0;
        zeroFactorObserved = token.getFactor() == 0;

        (bool onlyOwnerOk, bytes memory onlyOwnerData_) =
            subject.call(abi.encodeWithSelector(IXStable2Like.pauseContract.selector, true));
        onlyOwnerBlockedObserved = !onlyOwnerOk;
        onlyOwnerRevertData = onlyOwnerData_;

        (bool mintOk, bytes memory mintData_) =
            subject.call(abi.encodeWithSelector(IXStable2Like.mint.selector, address(this), 1));
        mintBlockedObserved = !mintOk;
        mintRevertData = mintData_;

        (bool balanceOk, bytes memory balanceData_) =
            subject.staticcall(abi.encodeWithSelector(IXStable2Like.balanceOf.selector, address(this)));
        balancePathBlockedObserved = !balanceOk;
        balanceRevertData = balanceData_;

        (bool transferOk, bytes memory transferData_) =
            subject.call(abi.encodeWithSelector(IXStable2Like.transfer.selector, address(0xBEEF), 1));
        transferPathBlockedObserved = !transferOk;
        transferRevertData = transferData_;

        // The final exploit-path stage requires a transition into post-presale mode.
        // At this fork and from this codebase, that transition is mechanically unreachable:
        // there is no constructor, no initializer, and no assignment path for `_presaleDone`.
        // We therefore prove the exact blocking preconditions instead: `_presaleDone` is stuck
        // false, `_largeTotal` is stuck zero, and `getFactor()` is already zero under the blank
        // deployment. Any later forced activation would still inherit the same zero `_largeTotal`.
        postPresaleStageProvablyInfeasibleAtFork = presaleNeverDoneObserved && largeTotalZeroObserved;
    }

    function _finalizeOutcome() internal {
        hypothesisValidated =
            ownerZeroObserved &&
            onlyOwnerBlockedObserved &&
            presaleAddressZeroObserved &&
            mintBlockedObserved &&
            presaleNeverDoneObserved &&
            largeTotalZeroObserved &&
            zeroFactorObserved &&
            balancePathBlockedObserved &&
            transferPathBlockedObserved &&
            postPresaleStageProvablyInfeasibleAtFork;

        hypothesisRefuted = !hypothesisValidated;

        // This finding is a deployment-time liveness brick, not a live-fork drain.
        // When the blank-storage deployment is reproduced faithfully, no public action
        // yields transferable value: owner-only recovery is unreachable, presale minting
        // is unreachable, `_presaleDone` cannot be toggled, and balance-dependent paths
        // already fail with zero factor. Net attacker profit therefore remains zero.
        _profitAmount = 0;
    }

    function _readAddress(address target, bytes memory data) internal view returns (address value) {
        (bool ok, bytes memory ret) = target.staticcall(data);
        if (ok && ret.length >= 32) {
            value = abi.decode(ret, (address));
        }
    }

    function _readBool(address target, bytes memory data) internal view returns (bool value) {
        (bool ok, bytes memory ret) = target.staticcall(data);
        if (ok && ret.length >= 32) {
            value = abi.decode(ret, (bool));
        }
    }

    function _readUint256(address target, bytes memory data) internal view returns (uint256 value) {
        (bool ok, bytes memory ret) = target.staticcall(data);
        if (ok && ret.length >= 32) {
            value = abi.decode(ret, (uint256));
        }
    }
}

```

forge stdout (tail):
```
leAddress() [staticcall]
    │   │   ├─ [2602] 0xb276647E70CB3b81a1cA302Cf8DE280fF0cE5799::getPresaleAddress() [delegatecall]
    │   │   │   └─ ← [Return] 0x79D25fB416bd9364F4dc0A9C2839b6Ecd1Fbaa27
    │   │   └─ ← [Return] 0x79D25fB416bd9364F4dc0A9C2839b6Ecd1Fbaa27
    │   ├─ [3197] 0x91383A15C391c142b80045D8b4730C1c37ac0378::isPresaleDone() [staticcall]
    │   │   ├─ [2424] 0xb276647E70CB3b81a1cA302Cf8DE280fF0cE5799::isPresaleDone() [delegatecall]
    │   │   │   └─ ← [Return] true
    │   │   └─ ← [Return] true
    │   ├─ [3239] 0x91383A15C391c142b80045D8b4730C1c37ac0378::getLargeTotal() [staticcall]
    │   │   ├─ [2466] 0xb276647E70CB3b81a1cA302Cf8DE280fF0cE5799::getLargeTotal() [delegatecall]
    │   │   │   └─ ← [Return] 112488119653363441082784080086451339277374397892281855575298865842934054317213 [1.124e77]
    │   │   └─ ← [Return] 112488119653363441082784080086451339277374397892281855575298865842934054317213 [1.124e77]
    │   ├─ [3659] 0x91383A15C391c142b80045D8b4730C1c37ac0378::getFactor() [staticcall]
    │   │   ├─ [2886] 0xb276647E70CB3b81a1cA302Cf8DE280fF0cE5799::getFactor() [delegatecall]
    │   │   │   └─ ← [Return] 30258539532077621033860272997003701307478978766395869218673727 [3.025e61]
    │   │   └─ ← [Return] 30258539532077621033860272997003701307478978766395869218673727 [3.025e61]
    │   ├─ [58569] → new EmptyInitProxy@0x104fBc016F4bb334D775a19E8A6510109AC63E00
    │   │   └─ ← [Return] 181 bytes of code
    │   ├─ [2903] EmptyInitProxy::fallback() [staticcall]
    │   │   ├─ [2602] 0xb276647E70CB3b81a1cA302Cf8DE280fF0cE5799::owner() [delegatecall]
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2903] EmptyInitProxy::fallback() [staticcall]
    │   │   ├─ [2602] 0xb276647E70CB3b81a1cA302Cf8DE280fF0cE5799::getPresaleAddress() [delegatecall]
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2725] EmptyInitProxy::fallback() [staticcall]
    │   │   ├─ [2424] 0xb276647E70CB3b81a1cA302Cf8DE280fF0cE5799::isPresaleDone() [delegatecall]
    │   │   │   └─ ← [Return] false
    │   │   └─ ← [Return] false
    │   ├─ [2767] EmptyInitProxy::fallback() [staticcall]
    │   │   ├─ [2466] 0xb276647E70CB3b81a1cA302Cf8DE280fF0cE5799::getLargeTotal() [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [1115] EmptyInitProxy::fallback() [staticcall]
    │   │   ├─ [814] 0xb276647E70CB3b81a1cA302Cf8DE280fF0cE5799::getFactor() [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [1105] EmptyInitProxy::fallback(true)
    │   │   ├─ [788] 0xb276647E70CB3b81a1cA302Cf8DE280fF0cE5799::pauseContract(true) [delegatecall]
    │   │   │   └─ ← [Revert] Ownable: caller is not the owner
    │   │   └─ ← [Revert] Ownable: caller is not the owner
    │   ├─ [1345] EmptyInitProxy::fallback(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1)
    │   │   ├─ [1025] 0xb276647E70CB3b81a1cA302Cf8DE280fF0cE5799::mint(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1) [delegatecall]
    │   │   │   └─ ← [Revert] not presale
    │   │   └─ ← [Revert] not presale
    │   ├─ [6368] EmptyInitProxy::fallback(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [6051] 0xb276647E70CB3b81a1cA302Cf8DE280fF0cE5799::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Revert] SafeMath: division by zero
    │   │   └─ ← [Revert] SafeMath: division by zero
    │   ├─ [6812] EmptyInitProxy::fallback(0x000000000000000000000000000000000000bEEF, 1)
    │   │   ├─ [6492] 0xb276647E70CB3b81a1cA302Cf8DE280fF0cE5799::transfer(0x000000000000000000000000000000000000bEEF, 1) [delegatecall]
    │   │   │   └─ ← [Revert] SafeMath: division by zero
    │   │   └─ ← [Revert] SafeMath: division by zero
    │   └─ ← [Stop]
    ├─ [499] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [586] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 15310016 [1.531e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3124)
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xb276647E70CB3b81a1cA302Cf8DE280fF0cE5799.transfer
  at EmptyInitProxy.fallback
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 2.41s (68.11ms CPU time)

Ran 1 test suite in 2.44s (2.41s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 741055)

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
