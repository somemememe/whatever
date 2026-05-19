# Global Audit Memory

## Scope Touched
- `test/ExploitPOC.t.sol` — main audit focus; exercises staking `deposit()` / `withdraw()` accounting, liquidity-drain, and token-behavior edge cases
- `FlawVerifier.sol` — repeatedly inspected around verifier helper paths, round execution/drain logic, and epoch checks/init, but no retained issue yet
- staking / `MockStaking` deposit-withdraw flow — durable hotspot where internal balance changes diverge from real token transfers
- epoch / `manualEpochInit` and token-onboarding surfaces — seen as suspicious but still comparatively underexplored

## Issue Directions Seen
- Staking accounting over-trusts requested amounts and ERC20 call behavior, enabling phantom credits on deposit and unpaid or destructive withdrawals
- The core recurring risk is internal accounting becoming decoupled from actual token movement, especially with soft-failing or non-standard tokens
- Insolvency / theft paths depend on creating bad accounting state first and realizing value later when honest liquidity is present
- Reentrancy, arbitrary-token onboarding, and verifier execution/configuration misuse were explored as plausible extensions, but not retained so far

## Useful Context
- Audit attention remains concentrated on staking balance accounting rather than verifier or epoch logic
- Multiple variants collapse into one broader cross-round pattern: unsafe token integration assumptions break staking invariants without necessarily reverting
- Retained findings now cover both sides of the same accounting mismatch: over-credit on `deposit()` and balance burn before confirmed payout on `withdraw()`
- No cross-agent divergence yet; current memory reflects a single-agent audit path centered on staking flows
