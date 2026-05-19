# Global Audit Memory

## Scope Touched
- `0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol` — dominant hotspot across review; recurring attention on swap accounting, pool status/lifecycle, LP removal/locks, and callback/reentrancy edges
- `0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/libraries/MonoXLibrary.sol` — supporting pricing/math context for Monoswap behaviors; reviewed but not yet a standalone finding source
- `0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/interfaces/IMonoXPool.sol` / `IWETH.sol` — interface-level context around pool and asset handling, mainly to reason about Monoswap flows
- `0xc36a7887786389405ea8da0b87602ae3902b88a1/contracts/test/Proxiable.sol` and related proxy/test path — briefly examined UUPS authorization surface, but only in test-tree and not retained

## Issue Directions Seen
- Swap-path invariant breaks in `Monoswap.sol`, especially self-swap, exact-output, and fee-on-transfer accounting interactions
- Pool pricing/state desynchronization risks around token transfers, callbacks, and late pool sync
- Liquidity-removal authorization/lock enforcement mismatches between caller and LP owner
- Pool lifecycle / relisting behavior that can overwrite or strand prior pool/LP state
- Owner/admin-controlled status, fee, and pricing knobs were repeatedly examined as an economic-control direction, but without retained issues so far
- Proxy/UUPS upgrade authorization surfaced once in the test subtree, but remains a low-signal, non-retained direction

## Useful Context
- Cross-round attention is heavily concentrated in `Monoswap.sol`; most durable risk signals originate there rather than in peripheral files
- Retained findings so far cluster around accounting/state-transition mistakes, not pure access control
- Adjacent library and interface reads have mainly served to validate Monoswap assumptions rather than expose independent bugs
- The proxy/test subtree drew limited, single-agent attention and should be treated as lower-confidence context unless revisited in production-relevant code
