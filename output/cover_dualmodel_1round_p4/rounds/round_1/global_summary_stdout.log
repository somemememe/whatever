# Global Audit Memory

## Scope Touched
- `Blacksmith.sol` — dominant focus across rounds; repeated concern area is reward accounting around `deposit()`, `claimRewards()`, pool state updates, and bonus-token handling
- `Migrator.sol` — migration-path safety mattered, especially cap enforcement in `migrateSafe2()` and Merkle/claim edge cases that were explored but not retained
- `Vesting.sol` — token-release logic remained noteworthy; `vest()` was examined for overly broad asset withdrawal and possible reentrancy-style issues
- `COVER.sol` — mostly reviewed as supporting token/minting/governance context, especially migrator privilege transitions and reward-token behavior
- ERC20/helpers/utils (`ERC20.sol`, `SafeERC20.sol`, `Ownable.sol`, `Address.sol`, `MerkleProof.sol`, `ReentrancyGuard.sol`) — read mainly to validate accounting, transfer semantics, access control, and claim/reentrancy assumptions
- `Counter.sol`, `FlawVerifier.sol` — in scope and read, but drew little sustained attention

## Issue Directions Seen
- `Blacksmith.sol` reward-accounting weaknesses are the clearest recurring direction: stale accounting on deposit, retroactive parameter application, and misallocation of accrued rewards
- Shared accounting assumptions around token balances are a recurring theme, including cross-pool bonus-token isolation and fee-on-transfer over-crediting
- Migration safety is a secondary direction, centered on insufficient cap/limit enforcement and broader claim-path correctness
- Vesting/release flows show a recurring risk of overly permissive token movement, with reentrancy/griefing ideas explored but not established
- Broader privilege, precision, emergency-withdraw, and third-party-claim concerns were investigated, but have weaker cross-round support so far

## Useful Context
- Cross-agent overlap was strongest on `Blacksmith.sol`; other retained issues were more agent-specific
- Durable retained findings are concentrated in economic/accounting logic rather than classic reentrancy or access-control bugs
- `Blacksmith.sol`, `Migrator.sol`, `Vesting.sol`, and `COVER.sol` form the core audit surface; helper contracts mainly served as dependency context
- Underexplored but previously flagged areas include `COVER.sol` migrator-role transitions and `Vesting.sol:vest()` edge behavior
