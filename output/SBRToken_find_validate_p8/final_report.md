# Audit Report

**Total findings:** 1

## Critical (1)

### F-001: Pair self-transfer via `skim(pair)` appears to inflate SBR balances and enables AMM liquidity theft

**Confidence:** medium | **Locations:** `SBRToken.sol:59, SBRToken.sol:63, SBRToken.sol:65, SBRToken.sol:67, SBRToken.sol:71, SBRToken.sol:75`

The provided exploit harness shows an attacker can buy only a dust amount of SBR, call `UniswapV2Pair.skim(UniswapV2Pair)`, then observe a very large SBR balance before selling it back through the pool. This supports a token-accounting flaw in SBR that is triggered by the pair transferring tokens to itself during `skim(pair)`, causing balances to be created or duplicated at negligible cost. The subsequent `transfer(..., 1)` and `sync()` steps let the attacker align pool reserves with the manipulated token balance and realize the fabricated balance against the paired asset.

**Impact:** An external attacker can manufacture a large sellable SBR position from negligible capital and dump it into the SBR/WETH pool, draining most or all of the paired ETH liquidity, collapsing the market, and inflicting direct loss on LPs and traders.

**Paths:**

- Swap a dust amount of ETH for SBR

- Call `UniswapV2Pair.skim(UniswapV2Pair)` so the pair performs a self-transfer

- Leverage the resulting inflated SBR balance held by the attacker

- Transfer a dust token amount to the pair and call `sync()` to update reserves

- Swap the inflated SBR balance back to WETH/ETH and extract pool liquidity

*Round 1 | Agents: codex*

---
