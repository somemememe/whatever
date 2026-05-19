# Audit Report

**Total findings:** 3

## High (1)

### F-001: Curve deposits and exits execute with zero slippage protection, enabling MEV extraction

**Confidence:** high | **Locations:** `0xaf274e912243b19b882f02d731dacd7cd13072d0/Contract.sol:204, 0xaf274e912243b19b882f02d731dacd7cd13072d0/Contract.sol:250, 0xaf274e912243b19b882f02d731dacd7cd13072d0/Contract.sol:259, 0xaf274e912243b19b882f02d731dacd7cd13072d0/Contract.sol:264, 0xaf274e912243b19b882f02d731dacd7cd13072d0/Contract.sol:269`

The strategy hardcodes zero minimum outputs for every Curve interaction: `add_liquidity(..., 0)`, `remove_liquidity(..., [0,0,0,0])`, and all three `exchange(..., 0)` calls. As a result, deposits, partial withdrawals, and full migrations will accept whatever execution price exists in the Curve y-pool at that moment.

**Impact:** A searcher can temporarily skew the Curve pool immediately before `deposit()`, `withdraw(uint)`, or `withdrawAll()`, force the strategy to mint or unwind at a severely unfavorable rate, then back-run the pool to keep the difference. This can extract a material portion of TVL from a single large deposit, withdrawal, or migration.

**Paths:**

- deposit() -> add_liquidity([_y,0,0,0], 0)

- withdraw(uint) -> _withdrawSome() -> withdrawUnderlying() -> remove_liquidity(_amount, [0,0,0,0]) -> exchange(..., 0)

- withdrawAll() -> _withdrawAll() -> withdrawUnderlying() -> remove_liquidity(_amount, [0,0,0,0]) -> exchange(..., 0)

*Round 1 | Agents: codex_1*

---

## Medium (1)

### F-002: Partial withdrawals can return less DAI than requested because unwind sizing assumes frictionless prices

**Confidence:** medium | **Locations:** `0xaf274e912243b19b882f02d731dacd7cd13072d0/Contract.sol:222, 0xaf274e912243b19b882f02d731dacd7cd13072d0/Contract.sol:226, 0xaf274e912243b19b882f02d731dacd7cd13072d0/Contract.sol:289, 0xaf274e912243b19b882f02d731dacd7cd13072d0/Contract.sol:291, 0xaf274e912243b19b882f02d731dacd7cd13072d0/Contract.sol:295`

`_withdrawSome` estimates how much `yycrv` to burn from `get_virtual_price()` and `getPricePerFullShare()` as if yCRV could be converted back to DAI at model value. The real exit path is `remove_liquidity` followed by up to three spot swaps, so the realized DAI can be materially lower than `_amount`. `withdraw(uint)` does not enforce the requested amount and instead forwards only the amount actually realized.

**Impact:** During pool imbalance or active price manipulation, a vault/controller requesting a specific DAI amount can receive less than expected. That can underpay withdrawals or cause upstream withdrawal fulfillment to fail unpredictably, especially when combined with the zero-slippage execution in the unwind path.

**Paths:**

- controller calls withdraw(requestedAmount)

- if idle DAI is insufficient, _withdrawSome(requestedAmount - idleWant) computes yyCRV burn from virtual prices

- actual remove_liquidity + exchanges realize less DAI than requested, and withdraw(uint) transfers only the reduced amount

*Round 1 | Agents: codex_1*

---

## Low (1)

### F-003: Strategy accounting marks yyCRV to model value instead of executable DAI exit value

**Confidence:** low | **Locations:** `0xaf274e912243b19b882f02d731dacd7cd13072d0/Contract.sol:306, 0xaf274e912243b19b882f02d731dacd7cd13072d0/Contract.sol:311, 0xaf274e912243b19b882f02d731dacd7cd13072d0/Contract.sol:322, 0xaf274e912243b19b882f02d731dacd7cd13072d0/Contract.sol:324`

`balanceOf()` values `yycrv` as `yyCRV balance * getPricePerFullShare() * get_virtual_price()`, but realizing DAI from that position requires removing Curve liquidity and swapping the non-DAI legs back into yDAI. In stressed or manipulated pool conditions, executable exit value can diverge materially from this model-based mark.

**Impact:** If an upstream vault/controller uses `balanceOf()` for share pricing, solvency checks, or withdrawal planning, the strategy can overstate assets during pool stress. That can dilute users, mask losses, or cause accounting to drift from realizable value.

**Paths:**

- upstream system queries strategy.balanceOf()

- balanceOf() marks yyCRV using yyCRV PPS and Curve virtual price

- actual unwind through remove_liquidity + exchanges returns materially less DAI than the reported balance

*Round 1 | Agents: codex_1*

---
