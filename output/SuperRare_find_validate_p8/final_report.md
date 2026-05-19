# Audit Report

**Total findings:** 1

## Critical (1)

### F-001: Unrestricted `updateMerkleRoot()` lets any caller self-authorize arbitrary token claims

**Confidence:** high | **Locations:** `SuperRare.sol:52, SuperRare.sol:68, SuperRare.sol:70, SuperRare.sol:72, SuperRare.sol:77`

The reproduced exploit shows the target contract exposing `updateMerkleRoot(bytes32)` as an unrestricted external function. An attacker can set the Merkle root to a leaf they control, here `keccak256(abi.encodePacked(attacker, amount))`, and then call `claim(amount, [])`. Because the attacker-controlled leaf equals the whole tree root, an empty proof is sufficient and the claim succeeds for an arbitrary amount up to the contract's full token balance.

**Impact:** Any external account can overwrite the active distribution root and immediately drain all RARE held by the distribution/staking contract, causing direct theft of funds intended for legitimate recipients.

**Paths:**

- `testExploit()` computes `stakingContractBalance`, uses `fakeRoot`, then calls `AttackContract.attack(fakeRoot, stakingContractBalance)`

- `AttackContract.attack()` -> `IERC1967Proxy.updateMerkleRoot(newRoot)` -> `IERC1967Proxy.claim(amount, new bytes32[](0))`

- `fakeRoot` matches `keccak256(abi.encodePacked(ATTACK_CONTRACT, stakingContractBalance))`, so the attacker leaf is also the Merkle root and validates with an empty proof

*Round 1 | Agents: codex*

---
