# Global Audit Memory

## Scope Touched
- `onchain_auto/0xb84cbaf116eb90fd445dd5aeadfab3e807d2cbac/Contract.sol` — sole cross-round focus; attention clusters around whitelist mint flow, reserve/admin mint accounting, ERC721A `_safeMint` internals, and metadata/reveal administration
- Whitelist/proof path in `Contract.sol` — repeatedly examined for allocation enforcement, per-user sizing, and owner-controlled root updates
- Supply/reserve logic in `Contract.sol` — recurring concern that reserve handling can bypass or reshape the stated max supply boundary
- Metadata/reveal controls in `Contract.sol` — repeated focus on mutable URI / reversible reveal behavior and centralized post-mint control

## Issue Directions Seen
- Whitelist mint design appears structurally weak around per-address allocation enforcement, allowing an allowlisted participant to consume disproportionate supply
- Reserve/admin mint accounting is a recurring direction, especially where mutable reserve state can undermine advertised cap assumptions
- ERC721A `_safeMint` reentrancy/accounting risk is a notable contract-specific direction due to stale mint-state assumptions during receiver callbacks
- Metadata and reveal remain a persistent centralization/trust direction because owner-controlled URI state can alter post-sale token presentation
- Lower-confidence side directions that surfaced but were not retained: mutable whitelist root governance, `withdraw()` behavior, and zero-quantity mint guard/comment drift

## Useful Context
- Cross-round attention is highly concentrated in a single contract; no broader multi-file attack surface has emerged yet
- The strongest repeated patterns combine project-specific mint/admin logic with inherited ERC721A behavior rather than isolated syntax or tooling findings
- Retained themes so far converge on four durable areas: whitelist allocation control, reserve/max-supply integrity, ERC721A reentrancy-side accounting, and reversible metadata administration
- Non-retained observations mostly orbit admin mutability and implementation hygiene, making them secondary context unless later evidence strengthens them
