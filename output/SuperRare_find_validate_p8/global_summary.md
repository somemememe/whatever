# Global Audit Memory

## Scope Touched
- `SuperRare.sol` — repeated attention on the Merkle distribution flow, especially `updateMerkleRoot()` and `claim()`, with issue direction centered on root-manipulation leading to unauthorized claims

## Issue Directions Seen
- Missing or ineffective access control on Merkle root management, enabling self-serving root replacement before claiming
- Trust boundary around the `updateMerkleRoot()` → `claim()` sequence as the main confirmed exploit path
- Leaf/root encoding details were examined as exploit prerequisites, but the durable direction is root-update authority rather than alternate hash-format bugs

## Useful Context
- Audit attention so far is narrowly concentrated on `SuperRare.sol`; no other persistent hotspots have emerged yet
- The retained cross-round pattern is that claim safety depends on who can set the active Merkle root, not on unusual proof complexity
- Empty-proof claiming became relevant only in combination with attacker-controlled root selection, not as a standalone issue
