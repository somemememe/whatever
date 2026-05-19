# Global Audit Memory

## Scope Touched
- `0x800cfd4a2ba8ce93ea2cc814fce26c3635169017/Contract.sol` bundled source, with `BUSD staking.sol` as the persistent focus and `SafeERC20.sol` checked mainly to confirm token transfer/approval behavior
- `BUSD staking.sol` core user/owner fund flow areas repeatedly examined: `withdraw`, `claimInterestForDeposit`, `calculateInterest`, `tokenAllowAll`, `transferAllFunds`, and blacklist-gated paths
- Cross-round attention centers on pooled-funds staking mechanics, owner-controlled escape hatches, and per-deposit accounting interactions within the same staking tier

## Issue Directions Seen
- Unrestricted approval / allowance surfaces that let the contract grant spend rights over pooled tokens
- Explicit owner drain authority over contract-held staking funds
- Blacklist-controlled denial of access that can freeze principal or rewards
- Reward solvency risk from paying yields out of the shared deposit pool rather than isolated reward funding
- Reward accrual/accounting edge cases, including post-maturity over-accrual and same-tier deposit interactions that can break later claims
- General theme of strong admin power and weak separation between user balances, reward accounting, and emergency/owner controls

## Useful Context
- The audit has converged on `BUSD staking.sol` as the only materially relevant logic surface so far; dependency review was mainly supportive rather than a separate source of issues
- Durable risk pattern: user funds appear economically and operationally dependent on centralized owner actions plus global pooled accounting, not isolated per-user safety boundaries
- `withdraw` and `claimInterestForDeposit` form an especially important interaction surface because tier-level state coupling can affect other deposits beyond the one being withdrawn
