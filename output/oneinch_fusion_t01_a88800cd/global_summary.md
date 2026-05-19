# Global Audit Memory

## Scope Touched
- `FlawVerifier.sol` — dominant review hotspot; issues cluster around `executeOnOpportunity()`, `isValidSignature()`, `resolveOrders()`, `_prepareMakerCapital()`, and crafted interaction / payload assembly
- `Counter.sol` — only lightly reviewed so far; brief unrestricted-mutation concern surfaced but did not persist

## Issue Directions Seen
- `FlawVerifier.sol` repeatedly presents authorization-collapse patterns: unconditional ERC-1271 acceptance, public execution of a replay/theft path, and overly trusting resolver-callback assumptions
- External approval / integration risk remains a theme in `FlawVerifier.sol`, especially standing unlimited token approval to the limit-order protocol
- Stateful griefing / availability loss is also present in `FlawVerifier.sol`, with a one-shot execution latch able to permanently brick the main path

## Useful Context
- Audit attention is overwhelmingly concentrated in `FlawVerifier.sol`; retained findings to date all come from that contract
- Cross-round memory should treat `FlawVerifier.sol` as the primary attack surface around signature validation, settlement callbacks, order resolution, and execution gating
- `Counter.sol` has not emerged as a durable hotspot yet, mainly reflecting low review coverage rather than confirmed safety
