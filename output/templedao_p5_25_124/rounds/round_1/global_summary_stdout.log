# Global Audit Memory

## Scope Touched
- `onchain_auto/0xd2869042e12a3506100af1d192b5b04d65137941/contracts/StaxLPStaking.sol` — dominant audit surface; repeated attention on staking/withdrawal, reward scheduling, and migration logic
- `StaxLPStaking.sol::migrateStake` — migration path remains the clearest high-risk flow, especially around arbitrary source/target assumptions and stake minting without matching assets
- `StaxLPStaking.sol` reward flows — reward funding, rate calculation, rounding/truncation, and iteration across `rewardTokens` repeatedly matter
- Token transfer interaction paths in `StaxLPStaking.sol` — stake/reward accounting depends on nominal transfer amounts rather than guaranteed received amounts
- Included OZ token helpers (`SafeERC20`, `Address`, `IERC20`, `ERC20`) — reviewed mainly to validate transfer/callback assumptions; no durable library-local issue direction retained

## Issue Directions Seen
- Migration trust boundaries are the strongest recurring direction: migrator-controlled or arbitrary-source flows can create unbacked accounting
- Accounting-vs-balance mismatches recur for both staking and reward funding when token transfers may deliver less than requested
- Reward math edge cases remain promising: integer truncation/dust can strand value or skew reward distribution over time
- Unbounded `rewardTokens` growth is a repeated denial-of-service direction because core flows iterate the full list
- Reentrancy/token-callback and admin/configuration edge cases were explored repeatedly, but so far remain secondary compared with the accounting and migration issues

## Useful Context
- Cross-agent attention heavily converges on `StaxLPStaking.sol`; this contract is the stable center of risk for the audit
- The most durable pattern is unsafe reliance on external token behavior and trusted migration configuration while internal accounting assumes ideal transfers
- Reward handling issues appear in multiple forms but cluster into two themes: precision loss and scalability of per-token bookkeeping
- Configuration setters such as migrator/distributor admission paths drew some scrutiny, though they have not yet produced retained cross-round conclusions on their own
