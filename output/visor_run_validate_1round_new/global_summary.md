# Global Audit Memory

## Scope Touched
- `contracts/RewardsHypervisor.sol` — dominant audit focus; deposit and share-accounting paths repeatedly surfaced as the main issue area, with `withdraw` adjacent to exploit realization
- `contracts/vVISR.sol` — supporting context for reward/share interactions; reviewed without separate durable issue direction yet
- `contracts/interfaces/IVisor.sol` — important trust boundary for contract-based deposits and external balance assertions
- `FlawVerifier.sol` — used for exploit validation context rather than as an independent issue source
- OpenZeppelin `ERC20` / `ERC20Snapshot` — referenced to ground token/snapshot behavior during validation, not as a primary issue source

## Issue Directions Seen
- `RewardsHypervisor.deposit` authorization weakness around EOA callers using existing allowances rather than depositor-owned intent
- Trust in visor-style contract depositors can enable unbacked or attacker-controlled share minting if external balance assumptions are too weak
- Share pricing / initialization edge cases matter, especially first-depositor capture when VISR is already present before proper share initialization
- Donation-driven balance inflation can distort share pricing, causing severe dilution or zero-share outcomes for later depositors
- Deposit-side accounting has been more heavily explored than withdrawal-side behavior, though some exploit paths depend on `withdraw`

## Useful Context
- The audit has concentrated far more on `RewardsHypervisor` than any other contract
- Durable risk pattern: external token balances and externally supplied depositor identity interact dangerously with internal share minting logic
- Multiple retained directions are variations of the same broader theme: mismatches between assets actually contributed and shares minted
- Supporting reads of `vVISR`, `FlawVerifier`, and OpenZeppelin contracts have so far served validation and scoping roles rather than opening new standalone issue families
