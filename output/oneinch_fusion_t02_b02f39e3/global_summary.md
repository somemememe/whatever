# Global Audit Memory

## Scope Touched
- `FlawVerifier.sol` — primary audit focus; settlement payload construction, trailer/context parsing, and interaction offset/length handling are central risk areas
- `FlawVerifier.sol:isValidSignature()` — reviewed as part of signature/authorization surface; broad `ERC1271` acceptance was explored but not retained
- `FlawVerifier.sol:executeOnOpportunity()` — reviewed as part of execution/approval surface; permissionless abuse was explored but not retained
- `Counter.sol` — only lightly inspected so far; comparatively underexplored versus settlement logic

## Issue Directions Seen
- Settlement parser confusion from attacker-controlled offsets/lengths, especially wraparound-driven reinterpretation of forged trailer bytes as trusted settlement context
- Forged or replayed historical settlement context as an authorization vector around victim/resolver semantics
- Recursive/self-referential interaction handling and state-isolation concerns during settlement execution
- Broad signature or execution authorization surfaces around verifier/executor entrypoints, even where specific theories were not retained

## Useful Context
- Audit attention has been concentrated heavily on `FlawVerifier.sol`; cross-round memory should treat it as the main contract of interest
- The durable retained issue is a critical parser flaw tied to interaction length/offset arithmetic and forged settlement context interpretation
- Several adjacent theories clustered around the same trust boundary: parsing settlement bytes into authenticated historical context
- `Counter.sol` remains a low-context area and was not a meaningful source of retained conclusions in this round
