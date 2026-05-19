# Global Audit Memory

## Scope Touched
- `Staking.sol` — dominant hotspot across deposit/withdraw, emergency withdraw, epoch accounting, pool-size tracking, and Compound integration; repeated concern is accounting drift versus real assets/state
- Stablecoin deposit/reinvestment + Compound-facing helpers — internal balances depend on `mint`/`redeem` success assumptions and approval lifecycle behavior
- Emergency-withdraw and reward checkpoint flows — stake removal appears able to bypass full cleanup of epoch/checkpoint views
- Non-stable ERC20 deposit paths — credited stake can follow requested input rather than actual tokens received
- `SafeERC20.sol` / approval handling — relevant mainly for non-zero allowance residue and `safeApprove` brittleness after failed external interactions
- `CTokenInterface.sol` usage — notable through Compound return-code semantics rather than standalone logic review

## Issue Directions Seen
- External protocol return codes not being enforced can desync staking/accounting state from actual Compound positions
- Approval state can become sticky after failed stablecoin-side operations, creating flow-bricking conditions on later deposits/reinvestments
- Emergency exit logic may remove principal without fully clearing reward-era/checkpoint/pool accounting views
- Deposit accounting repeatedly looks vulnerable where nominal requested amounts are trusted over observed token receipts, especially for fee-on-transfer or non-standard ERC20 behavior
- Broader pattern: staking state transitions are most suspect where they span token transfer, Compound interaction, and epoch bookkeeping in one flow

## Useful Context
- Review attention is concentrated overwhelmingly in `Staking.sol`; embedded utility libraries were supporting context, not independent issue sources
- Durable audit theme is state divergence: contract-side balances, epoch snapshots, and external asset positions can move out of sync
- Stablecoin paths and reward/epoch paths are the main cross-cutting hotspots rather than isolated single functions
- Compound integration risk is less about market logic and more about unchecked error-style interfaces interacting with local accounting assumptions
