# Audit Report

**Total findings:** 3

## Critical (1)

### F-001: Liquidity accounting can settle against mixed stale/fresh asset rates

**Confidence:** medium | **Locations:** `yETH.sol:38, yETH.sol:104, yETH.sol:106, yETH.sol:109, yETH.sol:159, yETH.sol:161, yETH.sol:179, yETH.sol:181, yETH.sol:193, yETH.sol:195, yETH.sol:223, yETH.sol:232, yETH.sol:236, yETH.sol:241`

The exploit harness shows that pool pricing is cached behind a separate `update_rates(uint256[] _assets)` call rather than being enforced inside `add_liquidity`/`remove_liquidity`, and that callers can refresh only selected asset indexes. The sequence performs many mint/burn operations while rates are stale, then updates only asset 6 or 7, so liquidity operations can be priced against a basket containing a mix of stale and fresh rates.

**Impact:** If LP shares are minted or burned from an inconsistent basket valuation, an attacker can acquire yETH while liabilities are understated and then redeem after a targeted sync for more underlying than they paid in, leading to pool insolvency and potentially full drain.

**Paths:**

- Allow basket rates to drift while repeatedly calling `add_liquidity` and `remove_liquidity` without a full refresh

- Refresh only the attacker-chosen asset index that makes the basket valuation more favorable

- Redeem inflated yETH against the now-repriced pool to extract excess underlying

*Round 1 | Agents: codex*

---

## High (2)

### F-003: `remove_liquidity(0)` may expose a free accounting-transition primitive

**Confidence:** low | **Locations:** `yETH.sol:24, yETH.sol:159, yETH.sol:160, yETH.sol:164, yETH.sol:179, yETH.sol:180, yETH.sol:184, yETH.sol:193, yETH.sol:194, yETH.sol:232`

The exploit repeatedly calls `remove_liquidity(0, ...)` immediately before profitable single-asset rate updates and follow-on withdrawals, which indicates zero-LP burns are accepted and may still execute meaningful withdrawal-side accounting even when no shares are burned.

**Impact:** If a zero-amount withdrawal is not a strict no-op, an attacker gains a free state-transition or checkpointing step that can be chained with targeted repricing to magnify over-withdrawal and reduce the capital needed to drain the pool.

**Paths:**

- Skew the basket with imbalanced deposits and withdrawals

- Call `remove_liquidity(0)` to trigger any withdrawal-side accounting without spending LP

- Apply a targeted rate update and execute the next oversized withdrawal

*Round 1 | Agents: codex*

---

### F-004: Rebasing OETH can change pool balances out-of-band from cached accounting

**Confidence:** medium | **Locations:** `yETH.sol:43, yETH.sol:54, yETH.sol:168, yETH.sol:169, yETH.sol:171, yETH.sol:172, yETH.sol:248`

The exploit explicitly triggers `OETH.rebase()` mid-sequence and then immediately resumes liquidity additions while the harness tracks separate pool-side virtual-balance accounting via `vb_prod_sum()`. This implies the pool can hold a rebasing asset whose actual token balance changes exogenously relative to cached rate/virtual-balance state.

**Impact:** If rebases are not fully synchronized before minting or redemption, the attacker can capture value created by the rebase or use the temporary mismatch to withdraw unrelated assets, causing direct theft from LPs.

**Paths:**

- Trigger `OETH.rebase()` so the pool's token balance changes without a corresponding full accounting sync

- Add or remove liquidity while internal basket accounting still reflects the pre-rebase state

- Redeem after the mismatch has been converted into favorable yETH pricing

*Round 1 | Agents: codex*

---
