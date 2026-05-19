# Audit Report

**Total findings:** 1

## High (1)

### F-002: Target vault's `swapToWETH` can be sandwiched at a manipulated price, draining vault value

**Confidence:** medium | **Locations:** `DRLVaultV3.sol:94, DRLVaultV3.sol:108, DRLVaultV3.sol:119`

The exploit flow first executes a large price-moving swap, then calls `swapToWETH` on the target vault at `VAULT_ADDR`, and finally unwinds the market move. Together with the in-file note referencing a slippage exploit, this strongly suggests the target vault's `swapToWETH` relies on manipulable live pool pricing and/or lacks an effective minimum-output check. A caller can therefore force the vault to trade at an attacker-controlled rate.

**Impact:** An attacker can temporarily distort the USDC/WETH market, trigger the vault's swap while the distorted price is live, and then unwind the manipulation to keep the spread. The vault realizes the bad execution as a direct loss of treasury assets.

**Paths:**

- Source enough capital to move the relevant USDC/WETH pool price.

- Execute a large swap that skews the price seen by the vault.

- Call the target vault's `swapToWETH` while the manipulated price is active.

- Reverse the initial trade and keep the profit created by the vault's slippage loss.

*Round 1 | Agents: codex*

---
