# Global Audit Memory

## Scope Touched
- `0xf7ef0d57277ad6c2babf87ab64ba61abdd2590d2/Contract.sol`: dominant focus across rounds; transfer path appears to be mediated by a hidden external router/controller with non-standard balance effects
- `Contract.sol::_transfer`: central area for sell-blocking, arbitrary debit/credit control, and possible divergence between ERC-20 expectations and actual storage updates
- `Contract.sol` constructor router setup / controller wiring: suspicious privileged dependency established at deployment and then used inside transfers
- `Contract.sol::addLiquidityETH`: public liquidity bootstrap path tied to forced balance seizure and attacker-directed LP ownership
- `Contract.sol` allowance/approval and helper `decode`: lightly explored side areas; lower-confidence but adjacent to the main external-control pattern

## Issue Directions Seen
- Hidden external controller/router gating transfers, especially enabling honeypot-style denial of sells or selective transfer blocking
- Externalized transfer accounting that can override normal ERC-20 invariants, including confiscatory debits, arbitrary credits, and hidden tax/mint-style effects
- Public liquidity helper functions being abused to seize holder balances and redirect resulting liquidity or LP control
- Recurrent concern that emitted transfer semantics may diverge from actual balance mutations when controller logic is involved
- Secondary but less-developed directions around approval behavior, interface correctness, and validation gaps near the same control surface

## Useful Context
- Audit attention has concentrated on a single Solidity file, with `_transfer` and `addLiquidityETH` consistently the highest-signal functions
- The strongest cross-round pattern is centralized hidden control behind ordinary token flows rather than isolated input-validation mistakes
- Multiple agents independently converged on the router/controller as the main trust-break and on liquidity setup as a parallel asset-seizure path
- Ancillary issues were explored, but the durable signal is the combination of hidden transfer mediation, mutable accounting, and attacker-steerable liquidity outcomes
