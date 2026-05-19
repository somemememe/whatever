# Global Audit Memory

## Scope Touched
- `0x79a7d3559d73ea032120a69e59223d4375deb595/Contract.sol`: dominant audit surface so far; ERC721 transfer/approval lifecycle, burn/restore state transitions, and interface-signaling behavior have carried most of the risk
- scope is effectively single-contract; no secondary file hotspot has emerged beyond metadata/index listing

## Issue Directions Seen
- ERC721 approval lifecycle inconsistencies: approval clearing across transfer, safe transfer, burn, and restore paths is a central recurring direction
- ERC721 standards conformance drift: claimed ERC165 support versus actual enumerable/receiver behavior remains a strong compatibility/integration concern
- event/state mismatch: emitted approval logs may not reflect true ownership/state transitions, creating off-chain observability risk
- mint/burn/restore validation was explored repeatedly, but the durable cross-round signal is mainly where those flows interact with lingering approvals

## Useful Context
- both agents converged on the same single-file hotspot, with strongest overlap around transfer-related ERC721 behavior
- retained risk themes are mostly standards and lifecycle correctness issues rather than arithmetic or constructor/setup faults
- under current evidence, the most durable pattern is stale authorization surviving state transitions that should reset or invalidate it
