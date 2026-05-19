# Global Audit Memory

## Scope Touched
- `FlawVerifier.sol` — dominant audit surface; settlement execution, nested interaction payload construction, replay/call-data reconstruction, and settlement token movement drive most review
- `executeOnOpportunity` flow — repeatedly examined for gaps between signed order intent and externally supplied interaction bytes, including payer/source semantics and historical attack call shaping
- `_buildReplayOrder` / replay path / calldata-corruption helpers — recurring focus on offset/length handling, reuse of prior order material, and malformed replay construction
- Settlement payout / drain helpers such as `_drainSettlementToken` — tied to whether live `SETTLEMENT` or omnibus-style balances can be spent under weak order-scoped accounting assumptions
- Resolver / callback path (`NoopResolver`) — explored as a place where callback success may be satisfied by inert, self-targeted, or no-code targets rather than meaningful validation
- Swap/conversion helpers and settlement plumbing — lightly but repeatedly surveyed as adjacent surface around exploit execution
- `Counter.sol` — occasional peripheral review only; not part of the main accumulated risk picture

## Issue Directions Seen
- Unsigned or weakly bound external interaction data being executed inside settlement flows
- Divergence between signed-order fields and interaction-supplied payer/source or resolver-controlled execution context
- Self-targeted or nested settlement execution weakening callback or authorization assumptions
- Unsafe parsing of dynamic calldata offsets/lengths causing corruption, replay reconstruction, or reuse of historical order calldata
- Callback success conditions that may accept no-op, inert, or no-code resolver targets
- Token-accounting trust assumptions around maker assets and settlement inventory, especially where real omnibus balances can be spent without strict order-scoped accounting

## Useful Context
- Cross-round attention remains overwhelmingly concentrated on `FlawVerifier.sol`, especially `executeOnOpportunity`, replay builders, and settlement payload encoding
- The stable audit theme is compositional mismatch: signed order intent, encoded settlement payloads, resolver callbacks, and settlement-side balance/accounting may not be tightly aligned
- Replay corruption, settlement inventory usage, and callback validation now form the enduring core narrative; swap-helper behavior has been examined mainly as adjacent context rather than a standalone issue track
- `Counter.sol` remains a low-confidence side path and has not meaningfully joined the main cross-round risk story
