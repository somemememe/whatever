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
        uint256 verifierMainBalance;
        uint256 verifierWrappedBalance;
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

        // Stage 1 from the finding:
        // governance pauses the pool during an incident.
        //
        // This verifier cannot permissionlessly invoke governance-only pause controls, so this attempt can only
        // continue if the fork already reflects the historical pause + exit aftermath described by the finding.
        if (snap.burnedSupply == 0) {
            _outcome = Outcome.NoHistoricalEmergencyBurnAtFork;
            _hypothesisValidated = false;
            return;
        }

        // Stage 2 from the finding is the emergency exit path:
        // emergency_exact_bpt_in_for_tokens_out -> basepool.onexitpool burns BPT.
        //
        // On the mirrored Balancer LinearPool source, the emergency exit is the only path that explicitly documents
        // the post-burn approximation problem. At a fork, the permissionless verifier can observe the same aftermath
        // by checking that totalSupply() is now below the immutable premint constant.
        //
        // That historical supply reduction is the state transition needed for Stage 3.
        bool historicalEmergencyExitBurnObserved = snap.burnedSupply != 0;

        // Stage 3 from the finding:
        // getRate() still uses _getapproximatevirtualsupply after the emergency burn.
        //
        // We recompute the rate with the real post-burn virtual supply and compare it with the pool's live getRate().
        bool staleApproximationObserved = historicalEmergencyExitBurnObserved && (snap.reportedRate < snap.trueRate);

        if (snap.paused) {
            _outcome = Outcome.HistoricalBurnDetectedButStillPaused;
            _hypothesisValidated = staleApproximationObserved;
            return;
        }

        // Stage 4 from the finding:
        // temporarilypausable automatically treats the pool as unpaused once the buffer period has expired.
        //
        // Merely observing `paused == false` is not strict enough because governance could have manually unpaused
        // during the buffer. The finding specifically requires the auto-resume behavior after the buffer period.
        if (block.timestamp <= snap.bufferPeriodEndTime) {
            _outcome = Outcome.HistoricalBurnDetectedButNotAutoResumed;
            _hypothesisValidated = staleApproximationObserved;
            return;
        }

        _outcome = Outcome.HistoricalBurnDetectedAutoResumed;
        _hypothesisValidated = staleApproximationObserved;

        // Stage 5 from the finding:
        // onswap(); resumes and continues using the stale approximation after the TemporarilyPausable buffer elapses.
        //
        // Realistic execution policy for this attempt:
        // direct_or_existing_balance_first. We inspect verifier-held main/wrapped balances before considering any
        // external capital. No flashloan is taken here because the target-only path remains economically symmetric:
        // mint-side pricing and burn-side pricing both depend on the same stale _getapproximatevirtualsupply term.
        //
        // Without a separately supplied downstream consumer that blindly trusts the stale getRate(), a direct swap
        // round-trip against this single LinearPool does not realize net profit in an already-burned state; it only
        // demonstrates that normal onSwap() execution has reopened on invalid accounting.
        if (snap.verifierMainBalance == 0 && snap.verifierWrappedBalance == 0) {
            _outcome = Outcome.HistoricalBurnDetectedAutoResumedButNoTargetOnlyProfitPath;
            return;
        }

        // Even with verifier-held inventory, the same target-only causality still fails to monetize for the reasons
        // above. We therefore do not spend the inventory on a loss-making round trip.
        _outcome = Outcome.HistoricalBurnDetectedAutoResumedButNoTargetOnlyProfitPath;
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
            "governance pause -> emergency_exact_bpt_in_for_tokens_out -> basepool.onexitpool burn -> getRate/_getapproximatevirtualsupply stale quote -> temporarilypausable auto-unpause -> onswap(); resumes on post-burn state";
    }

    function exploitPathAnchors() external pure returns (string memory) {
        return
            "emergency_exact_bpt_in_for_tokens_out basepool.onexitpool _getapproximatevirtualsupply temporarilypausable onswap();";
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
        snap.verifierMainBalance = IERC20Like(snap.mainToken).balanceOf(address(this));
        snap.verifierWrappedBalance = IERC20Like(snap.wrappedToken).balanceOf(address(this));

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
000000000 [2e14]
    │   ├─ [16327] 0x9210F1204b5a24742Eba12f710636D76240dF3d0::getWrappedTokenRate() [staticcall]
    │   │   ├─ [12856] 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9::d15e0053(000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48) [staticcall]
    │   │   │   ├─ [7745] 0xC6845a5C768BF8D7681249f8927877Efda425baf::d15e0053(000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48) [delegatecall]
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000038e4206594ad1520da6032a
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000038e4206594ad1520da6032a
    │   │   └─ ← [Return] 1100434289151831555 [1.1e18]
    │   ├─ [597] 0x9210F1204b5a24742Eba12f710636D76240dF3d0::getTargets() [staticcall]
    │   │   └─ ← [Return] 2900000000000000000000000 [2.9e24], 10000000000000000000000000 [1e25]
    │   ├─ [547] 0x9210F1204b5a24742Eba12f710636D76240dF3d0::getPausedState() [staticcall]
    │   │   └─ ← [Return] false, 1646765220 [1.646e9], 1649357220 [1.649e9]
    │   ├─ [296] 0x9210F1204b5a24742Eba12f710636D76240dF3d0::getPoolId() [staticcall]
    │   │   └─ ← [Return] 0x9210f1204b5a24742eba12f710636d76240df3d00000000000000000000000fc
    │   ├─ [21557] 0xBA12222222228d8Ba445958a75a0704d566BF2C8::getPoolTokens(0x9210f1204b5a24742eba12f710636d76240df3d00000000000000000000000fc) [staticcall]
    │   │   └─ ← [Return] [0x9210F1204b5a24742Eba12f710636D76240dF3d0, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 0xd093fA4Fb80D09bB30817FDcd442d4d02eD3E5de], [5192296858428306686809548346588505 [5.192e33], 108375769187 [1.083e11], 970495 [9.704e5]], 18002136 [1.8e7]
    │   ├─ [296] 0x9210F1204b5a24742Eba12f710636D76240dF3d0::getBptIndex() [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [9815] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [2529] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [9889] 0xd093fA4Fb80D09bB30817FDcd442d4d02eD3E5de::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [2654] 0x7B6e135e8881580Bcc818178De863BD0be1360D0::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [14594] 0x9210F1204b5a24742Eba12f710636D76240dF3d0::getRate() [staticcall]
    │   │   ├─ [5557] 0xBA12222222228d8Ba445958a75a0704d566BF2C8::getPoolTokens(0x9210f1204b5a24742eba12f710636d76240df3d00000000000000000000000fc) [staticcall]
    │   │   │   └─ ← [Return] [0x9210F1204b5a24742Eba12f710636D76240dF3d0, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 0xd093fA4Fb80D09bB30817FDcd442d4d02eD3E5de], [5192296858428306686809548346588505 [5.192e33], 108375769187 [1.083e11], 970495 [9.704e5]], 18002136 [1.8e7]
    │   │   ├─ [2356] 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9::d15e0053(000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48) [staticcall]
    │   │   │   ├─ [1745] 0xC6845a5C768BF8D7681249f8927877Efda425baf::d15e0053(000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48) [delegatecall]
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000038e4206594ad1520da6032a
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000038e4206594ad1520da6032a
    │   │   └─ ← [Return] 1012181366076016326 [1.012e18]
    │   ├─ [3164] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::decimals() [staticcall]
    │   │   ├─ [2381] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::decimals() [delegatecall]
    │   │   │   └─ ← [Return] 6
    │   │   └─ ← [Return] 6
    │   ├─ [3234] 0xd093fA4Fb80D09bB30817FDcd442d4d02eD3E5de::decimals() [staticcall]
    │   │   ├─ [2502] 0x7B6e135e8881580Bcc818178De863BD0be1360D0::decimals() [delegatecall]
    │   │   │   └─ ← [Return] 6
    │   │   └─ ← [Return] 6
    │   └─ ← [Stop]
    ├─ [354] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    ├─ [344] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [1315] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   ├─ [529] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 18004651 [1.8e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 2186)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 7.30s (1.43s CPU time)

Ran 1 test suite in 7.34s (7.30s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 575595)

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
