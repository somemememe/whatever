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
- title: Emergency exits permanently invalidate LinearPool virtual-supply accounting, yet the pool auto-resumes normal operation after the buffer period
- claim: LinearPool optimizes all normal pricing and rate paths around `_getApproximateVirtualSupply`, which assumes total BPT supply always equals `_INITIAL_BPT_SUPPLY`. Emergency exits explicitly break that invariant by burning BPT, and the contract comments acknowledge the approximation becomes inaccurate. Nevertheless, `getRate()` remains callable and continues using the approximation immediately after emergency burns, and after the buffer period `whenNotPaused` starts passing again automatically, re-enabling swap logic that also relies on the stale approximation.
- impact: Once any emergency exit burns BPT, the pool can no longer safely quote `getRate()` and, after automatic unpause, can reopen with permanently wrong BPT pricing or broken math. Remaining LPs and downstream integrations can suffer fund loss, bad accounting, or denial of service, and the pool can become effectively unrecoverable without external migration.
- exploit_paths: ["Governance pauses the pool during an incident", "LPs use `EMERGENCY_EXACT_BPT_IN_FOR_TOKENS_OUT`, and `BasePool.onExitPool` burns BPT", "`getRate()` keeps dividing by `_getApproximateVirtualSupply`, so its rate becomes inconsistent with real supply", "After the buffer period expires, `TemporarilyPausable` automatically treats the pool as unpaused again", "Normal `onSwap()` paths resume and keep using the stale virtual-supply approximation on a post-burn state"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint8);
}

interface ILinearPoolLike {
    function getPoolId() external view returns (bytes32);
    function getVault() external view returns (address);
    function getMainToken() external view returns (address);
    function getWrappedToken() external view returns (address);
    function getBptIndex() external view returns (uint256);
    function getTargets() external view returns (uint256 lowerTarget, uint256 upperTarget);
    function getSwapFeePercentage() external view returns (uint256);
    function getPausedState() external view returns (bool paused, uint256 pauseWindowEndTime, uint256 bufferPeriodEndTime);
    function getWrappedTokenRate() external view returns (uint256);
    function getRate() external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

interface IVaultLike {
    function getPoolTokens(bytes32 poolId)
        external
        view
        returns (address[] memory tokens, uint256[] memory balances, uint256 lastChangeBlock);
}

contract FlawVerifier {
    address public constant TARGET = 0x9210F1204b5a24742Eba12f710636D76240dF3d0;
    uint256 private constant INITIAL_BPT_SUPPLY = type(uint112).max;
    uint256 private constant ONE = 1e18;

    enum Outcome {
        Uninitialized,
        NoHistoricalEmergencyBurnAtFork,
        HistoricalBurnDetectedButStillPaused,
        HistoricalBurnDetectedButNotAutoResumed,
        HistoricalBurnDetectedAutoResumed,
        HistoricalBurnDetectedAutoResumedButNoTargetOnlyProfitPath
    }

    struct Snapshot {
        bool paused;
        uint256 pauseWindowEndTime;
        uint256 bufferPeriodEndTime;
        uint256 totalSupply;
        uint256 vaultBptBalance;
        uint256 burnedSupply;
        uint256 approximateVirtualSupply;
        uint256 realVirtualSupply;
        uint256 reportedRate;
        uint256 trueRate;
        uint256 lowerTarget;
        uint256 upperTarget;
        uint256 swapFeePercentage;
        uint256 wrappedTokenRate;
        uint256 mainBalance;
        uint256 wrappedBalance;
        address mainToken;
        address wrappedToken;
        address vault;
    }

    bool private _attempted;
    bool private _hypothesisValidated;
    address private _profitToken;
    uint256 private _profitAmount;
    Outcome private _outcome;
    Snapshot private _snapshot;

    constructor() {}

    function executeOnOpportunity() external {
        require(!_attempted, "already-attempted");
        _attempted = true;

        Snapshot memory snap = _captureSnapshot();
        _snapshot = snap;
        _profitToken = snap.mainToken;
        _profitAmount = 0;

        // Exploit path stage 1: governance pauses the pool during an incident.
        // This step is permissioned by `setPaused(bool)` and cannot be induced by an arbitrary attacker from this
        // verifier. The only path-strict way to continue is if the fork already reflects the historical pause +
        // emergency-exit aftermath.
        if (snap.burnedSupply == 0) {
            _outcome = Outcome.NoHistoricalEmergencyBurnAtFork;
            _hypothesisValidated = false;
            return;
        }

        // Exploit path stage 2 is now historically satisfied on the fork:
        // BPT was burned by emergency exits iff totalSupply() dropped below the premint constant.
        //
        // Exploit path stage 3 is mechanically observable:
        // `reportedRate` uses approximate virtual supply while `trueRate` recomputes the same invariant over real
        // virtual supply.
        bool staleRateObserved = snap.reportedRate < snap.trueRate;

        if (snap.paused) {
            _outcome = Outcome.HistoricalBurnDetectedButStillPaused;
            return;
        }

        // Exploit path stage 4 is stricter than merely "not paused": the bug description requires the automatic
        // unpause after the buffer period. If the fork is before `bufferPeriodEndTime`, a manual unpause could explain
        // the state and the required stage is not met.
        if (block.timestamp <= snap.bufferPeriodEndTime) {
            _outcome = Outcome.HistoricalBurnDetectedButNotAutoResumed;
            return;
        }

        // Exploit path stage 5: swap logic is re-enabled on a post-burn state. That is true once the pool is not
        // paused and the buffer has expired.
        _outcome = Outcome.HistoricalBurnDetectedAutoResumed;
        _hypothesisValidated = staleRateObserved;

        // Attempt strategy: direct_or_existing_balance_first.
        // This verifier first checks for direct verifier-held inventory. It intentionally does not escalate to a
        // flashloan-only round trip against the same LinearPool because the target's own BPT mint/burn swap math uses
        // the same stale approximate virtual supply on both sides:
        // - main/wrapped -> BPT mints too much BPT because `bptSupply` is overstated
        // - BPT -> main/wrapped redeems too little underlying for the same reason
        // Those target-local legs cancel economically up to rounding and fees, so temporary capital alone does not
        // create positive net profit against the target pool in isolation.
        //
        // A monetizable route would require a known downstream integration or external market that still treats the
        // target BPT using real backing or blindly consumes `getRate()`. With only the target pool address supplied to
        // this verifier, there is no on-chain enumeration primitive that lets the contract discover and trade every
        // external consumer of this stale rate.
        _outcome = Outcome.HistoricalBurnDetectedAutoResumedButNoTargetOnlyProfitPath;
        _profitAmount = 0;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function outcome() external view returns (Outcome) {
        return _outcome;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function exploitPathUsed() external pure returns (string memory) {
        return
            "historical governance pause -> emergency BPT burn detection -> stale getRate check -> auto-unpause check -> target-only swap path assessed";
    }

    function snapshot()
        external
        view
        returns (
            bool paused,
            uint256 pauseWindowEndTime,
            uint256 bufferPeriodEndTime,
            uint256 totalSupply,
            uint256 vaultBptBalance,
            uint256 burnedSupply,
            uint256 approximateVirtualSupply,
            uint256 realVirtualSupply,
            uint256 reportedRate,
            uint256 trueRate,
            address mainToken,
            address wrappedToken,
            address vault
        )
    {
        Snapshot memory snap = _snapshot;
        return (
            snap.paused,
            snap.pauseWindowEndTime,
            snap.bufferPeriodEndTime,
            snap.totalSupply,
            snap.vaultBptBalance,
            snap.burnedSupply,
            snap.approximateVirtualSupply,
            snap.realVirtualSupply,
            snap.reportedRate,
            snap.trueRate,
            snap.mainToken,
            snap.wrappedToken,
            snap.vault
        );
    }

    function _captureSnapshot() internal view returns (Snapshot memory snap) {
        ILinearPoolLike pool = ILinearPoolLike(TARGET);

        snap.mainToken = pool.getMainToken();
        snap.wrappedToken = pool.getWrappedToken();
        snap.vault = pool.getVault();
        snap.totalSupply = pool.totalSupply();
        snap.swapFeePercentage = pool.getSwapFeePercentage();
        snap.wrappedTokenRate = pool.getWrappedTokenRate();
        (snap.lowerTarget, snap.upperTarget) = pool.getTargets();
        (snap.paused, snap.pauseWindowEndTime, snap.bufferPeriodEndTime) = pool.getPausedState();

        bytes32 poolId = pool.getPoolId();
        (address[] memory tokens, uint256[] memory balances,) = IVaultLike(snap.vault).getPoolTokens(poolId);
        uint256 bptIndex = pool.getBptIndex();
        snap.vaultBptBalance = balances[bptIndex];

        uint256 mainIndex = type(uint256).max;
        uint256 wrappedIndex = type(uint256).max;
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (tokens[i] == snap.mainToken) {
                mainIndex = i;
            } else if (tokens[i] == snap.wrappedToken) {
                wrappedIndex = i;
            }
        }

        require(mainIndex != type(uint256).max, "missing-main");
        require(wrappedIndex != type(uint256).max, "missing-wrapped");

        snap.mainBalance = balances[mainIndex];
        snap.wrappedBalance = balances[wrappedIndex];

        snap.burnedSupply = snap.totalSupply >= INITIAL_BPT_SUPPLY ? 0 : INITIAL_BPT_SUPPLY - snap.totalSupply;
        snap.approximateVirtualSupply = INITIAL_BPT_SUPPLY - snap.vaultBptBalance;
        snap.realVirtualSupply = snap.totalSupply > snap.vaultBptBalance ? snap.totalSupply - snap.vaultBptBalance : 0;
        snap.reportedRate = pool.getRate();
        snap.trueRate = _computeTrueRate(snap);
    }

    function _computeTrueRate(Snapshot memory snap) internal view returns (uint256) {
        if (snap.realVirtualSupply == 0) {
            return 0;
        }

        uint256 mainScaled = snap.mainBalance * _scalingFactor(IERC20Like(snap.mainToken).decimals());
        uint256 wrappedScaled = snap.wrappedBalance * _scalingFactor(IERC20Like(snap.wrappedToken).decimals());
        wrappedScaled = (wrappedScaled * snap.wrappedTokenRate) / ONE;

        uint256 nominalMain = _toNominal(mainScaled, snap.lowerTarget, snap.upperTarget, snap.swapFeePercentage);
        uint256 invariant = nominalMain + wrappedScaled;

        return _divUp(invariant, snap.realVirtualSupply);
    }

    function _toNominal(
        uint256 realMain,
        uint256 lowerTarget,
        uint256 upperTarget,
        uint256 fee
    ) internal pure returns (uint256) {
        if (realMain < lowerTarget) {
            uint256 fees = _mulDown(lowerTarget - realMain, fee);
            return realMain - fees;
        }

        if (realMain <= upperTarget) {
            return realMain;
        }

        uint256 fees = _mulDown(realMain - upperTarget, fee);
        return realMain - fees;
    }

    function _scalingFactor(uint8 decimals_) internal pure returns (uint256) {
        if (decimals_ >= 18) {
            return 1;
        }
        return 10 ** (18 - uint256(decimals_));
    }

    function _mulDown(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * b) / ONE;
    }

    function _divUp(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        return ((a - 1) / b) + 1;
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: emergency_exact_bpt_in_for_tokens_out, basepool.onexitpool, _getapproximatevirtualsupply, temporarilypausable, onswap(); generated code does not cover paths indexes: 1, 3, 4
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
