# Global Audit Memory

## Scope Touched
- `makina.sol` — recurring focus on the valuation/accounting path centered on `accountForPosition(...)` and the AUM snapshot path through `updateTotalAum()`; main issue direction is externally triggerable repricing and persistence of inflated value
- Curve-/nested-LP-linked pricing dependencies in `makina.sol` — relevant as the market-state input surface behind position re-accounting and protocol AUM updates

## Issue Directions Seen
- Permissionless or arbitrary re-accounting of an existing position using live, manipulable market state
- Permissionless persistence of a temporarily inflated valuation via AUM snapshot/update flows
- Multi-step valuation manipulation path where transient Curve-linked distortion propagates through position accounting into protocol-wide asset value
- Broader concern around nested LP / spot-based valuation sensitivity as the pricing substrate behind the retained exploit chain

## Useful Context
- Audit attention so far is concentrated almost entirely in `makina.sol`; no durable cross-file patterns have emerged yet
- The strongest retained pattern is not a single callsite in isolation but the composition of repricing plus AUM snapshotting
- Retained exploit shape across the round is: distort market-linked pricing, force position re-marking, persist inflated AUM, then realize value against the overstated protocol state
