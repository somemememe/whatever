# Global Audit Memory

## Scope Touched
- `onchain_auto/0x1c91af03a390b4c619b444425b3119e553b5b44b/Contract.sol` — primary audit surface across rounds; rewards/claims accounting, round funding state, staking lifecycle, and governance proposal mechanics concentrated here
- `onchain_auto/0x4deca517d6817b6510798b7328f2314d3003abac/Contract.sol` — proxy/governance validation surface; relevant for code-hash assumptions and upgradeability semantics, but comparatively less directly reviewed
- Reward round lifecycle / claim flow — recurring focus on snapshot mutability, ordering sensitivity, temporary ineligibility, and stake-timing interactions
- Governance / proposal flow — recurring focus on liveness degradation, slot pressure, low-stake edge cases, and proxy-aware integrity checks

## Issue Directions Seen
- Reward distribution depends on mutable per-round state, creating replay/reordering and in-progress round integrity risk
- Claim eligibility and stake-removal timing interact in ways that can break assumptions about finalized reward entitlement
- Permissionless claim paths expose griefing angles even when direct reward theft is not retained
- Governance proposal mechanics show liveness pressure from dust/zero-stake edge cases rather than classic privilege takeover
- Governance integrity checks depend on implementation identity assumptions that weaken under proxy upgrade patterns
- Broad privilege/initialization/registry concerns were explored, but the stronger recurring signal is state-machine fragility in rewards and governance flows

## Useful Context
- Cross-agent attention heavily converged on rewards/claims and governance, making those the most validated risk areas so far
- The most durable pattern is not missing access control, but mutable state being read across multi-step workflows with timing-sensitive behavior
- Proxy semantics matter mainly as a trust/integrity mismatch for governance validation, not as a broadly reviewed standalone upgradeability surface
- Zero-value or low-value actions still matter because they can consume slots, lock progression, or grief users without obvious fund theft
- The proxy contract remains comparatively underexplored despite being relevant to a retained governance integrity issue
