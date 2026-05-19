# Global Audit Memory

## Scope Touched
- `onchain/0x5f58058c0ec971492166763c8c22632b583f667f/Contract.sol` — dominant audit surface; repeated focus on `BancorNetwork` router/conversion flows, inherited `TokenHandler` helpers, ETH / EtherToken handling, and `completeXConversion`
- Conversion path construction / execution in `BancorNetwork` — recurring concern around user-influenced routing, anchor/converter trust, and multi-hop value propagation
- BancorX completion path (`completeXConversion`) — cross-chain completion flow repeatedly examined for broken fund sourcing / settlement behavior
- Registry / affiliate / deprecated wrapper branches in `Contract.sol` — reviewed multiple times, but so far secondary to router and settlement-path issues

## Issue Directions Seen
- Externally reachable inherited token-transfer helpers creating direct asset-movement risk
- ETH accounting mismatches across multi-hop conversions, especially stale `msg.value` reuse and incomplete ETH↔EtherToken normalization
- User-controlled path / anchor selection influencing which token handlers or converters receive funds
- Cross-chain completion logic divergence, where BancorX-related completion paths do not align with intended bridged-fund sourcing
- Secondary recurring but currently weaker directions: registry update trust, affiliate-fee handling, allowance / approve edge cases, deprecated wrapper validation

## Useful Context
- Audit scope has effectively collapsed to a single large `Contract.sol`, with most meaningful attention concentrated in externally callable router logic rather than isolated helper modules
- Cross-round signal is strongest where token movement, path interpretation, and ETH-special-case handling intersect inside conversion execution
- Both agents repeatedly revisited late-stage conversion / completion logic, suggesting the highest-yield areas are execution handoff boundaries rather than broad surface enumeration
- Several administrative or wrapper-related suspicions were explored and deprioritized, while router-flow and settlement-path inconsistencies remained the durable pattern
