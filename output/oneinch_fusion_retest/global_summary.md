# Global Audit Memory

## Scope Touched
- `FlawVerifier.sol` — primary audit surface; repeated focus on `executeOnOpportunity()`, forged settlement/trailer parsing, swap execution, ERC1271 auth, token approvals, and one-shot execution/finalization paths
- `FlawVerifier.sol` settlement payload builder / terminal interaction handling — important for issues where attacker-controlled offsets, lengths, or historical trailer bytes can steer downstream settlement context
- `FlawVerifier.sol` `isValidSignature()` / `resolveOrders()` — auth and resolver-validation surface; `resolveOrders()` drew suspicion but remains comparatively underexplored
- `FlawVerifier.sol` `_prepareMakerCapital()` and swap paths — capital preparation and external swap flow are relevant to approval exposure and low-min-output execution risk
- `Counter.sol` — only lightly inspected so far; peripheral compared with verifier logic

## Issue Directions Seen
- Forged settlement parsing via attacker-controlled interaction metadata or historical trailer data, letting execution/finalization consume attacker-shaped context
- Overbroad authorization: unconditional or universal ERC1271 approval combined with standing token allowances, especially USDT, creating drain potential from contract-held balances
- Permissionless swap execution with negligible output protection, exposing held assets to bad pricing or sandwich-style extraction
- Public one-shot execution/finalization paths that can be prematurely triggered, permanently consumed, or griefed by arbitrary callers
- Weak or unclear resolver validation around `resolveOrders()` remains a lower-confidence but recurring direction

## Useful Context
- Audit attention is highly concentrated in `FlawVerifier.sol`; durable risk patterns cluster around the boundary between parsed settlement data, signature/auth checks, token approvals, and external swap execution
- Multiple investigated angles collapsed into a smaller set of core themes rather than separate bugs; in particular, replay-style ideas were effectively part of the broader forged-settlement/context-confusion direction
- The most stable cross-round signal is unsafe composition: permissive auth plus persistent approvals plus permissionless execution amplifies impact when settlement parsing can be influenced
- `Counter.sol` and parts of `resolveOrders()` remain less explored than the main execution/auth/parsing surfaces
