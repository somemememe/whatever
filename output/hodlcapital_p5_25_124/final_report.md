# Audit Report

**Total findings:** 4

## High (2)

### F-001: Reflection math omits the team fee from `rTransferAmount`, inflating balances and creating sellable phantom fee tokens

**Confidence:** high | **Locations:** `onchain_auto/0xeda47e13fd1192e32226753dc2261c4a14908fb7/Contract.sol:1241, onchain_auto/0xeda47e13fd1192e32226753dc2261c4a14908fb7/Contract.sol:1325, onchain_auto/0xeda47e13fd1192e32226753dc2261c4a14908fb7/Contract.sol:1386`

`_getRValues()` computes `rTransferAmount = rAmount - rFee` and never subtracts the reflected team portion, but `_takeTeam()` still credits `rTeam` to the contract. Each taxed transfer therefore credits more reflected balance to recipients plus the contract than was removed from the sender, breaking the reflection accounting invariants.

**Impact:** Taxed transfers over-credit non-excluded recipients and continuously accumulate phantom tokens in the contract fee bucket. Those excess tokens can later be swapped out for ETH against the pool, extracting real value from liquidity and holders.

**Paths:**

- `_transfer` -> `_tokenTransfer` -> `_transferStandard` / `_transferToExcluded` / `_transferFromExcluded` / `_transferBothExcluded` -> `_getValues` / `_getRValues` + `_takeTeam`

- Any taxed buy, sell, or wallet-to-wallet transfer where fees are enabled

*Round 1 | Agents: codex_1*

---

### F-002: The Uniswap pair is left reflection-enabled, allowing anyone to skim reflected tokens out of LP

**Confidence:** high | **Locations:** `onchain_auto/0xeda47e13fd1192e32226753dc2261c4a14908fb7/Contract.sol:914, onchain_auto/0xeda47e13fd1192e32226753dc2261c4a14908fb7/Contract.sol:1071, onchain_auto/0xeda47e13fd1192e32226753dc2261c4a14908fb7/Contract.sol:1333`

The constructor creates `uniswapV2Pair`, but the pair is never excluded from reflections. Because `_reflectFee()` reduces `_rTotal`, the pair passively accrues token balance without a corresponding reserve update. Uniswap V2 pairs expose `skim(address)`, so any account can withdraw the excess tokens.

**Impact:** Attackers can repeatedly pull surplus reflected tokens from the pair and sell them, draining LP value and worsening execution for honest traders.

**Paths:**

- Normal taxed trading causes the pair to receive reflections because it remains a reflected holder

- The pair's ERC20 balance grows above its stored reserves

- An attacker calls `IUniswapV2Pair(uniswapV2Pair).skim(attacker)` and sells the skimmed tokens

*Round 1 | Agents: codex_1*

---

## Medium (2)

### F-003: Publicly triggerable swapback sells accumulated fees with `amountOutMin = 0`, making treasury dumps sandwichable

**Confidence:** high | **Locations:** `onchain_auto/0xeda47e13fd1192e32226753dc2261c4a14908fb7/Contract.sol:1153, onchain_auto/0xeda47e13fd1192e32226753dc2261c4a14908fb7/Contract.sol:1179, onchain_auto/0xeda47e13fd1192e32226753dc2261c4a14908fb7/Contract.sol:1188`

Once the contract's token balance crosses `_numOfTokensToExchangeForTeam`, any transfer with `sender != uniswapV2Pair` can force `swapTokensForEth()`. That swap uses `swapExactTokensForETHSupportingFeeOnTransferTokens(..., amountOutMin = 0, ...)`, so searchers can manipulate the pool price immediately before the trigger and make the contract sell at an arbitrarily poor rate.

**Impact:** A measurable portion of the ETH value in accumulated fee tokens can be extracted by MEV bots instead of reaching the fee wallets, directly harming protocol treasury value and token holders.

**Paths:**

- Fee tokens accumulate in the contract above `_numOfTokensToExchangeForTeam`

- An attacker moves the pool price against the token

- The attacker or a victim submits any non-buy transfer that enters `_transfer` and triggers `swapTokensForEth`

- The contract dumps with no slippage protection, then the attacker back-runs to capture the spread

*Round 1 | Agents: codex_1*

---

### F-004: Fee-wallet ETH forwarding via `.transfer()` can brick swapback and block sells/transfers once the threshold is reached

**Confidence:** high | **Locations:** `onchain_auto/0xeda47e13fd1192e32226753dc2261c4a14908fb7/Contract.sol:902, onchain_auto/0xeda47e13fd1192e32226753dc2261c4a14908fb7/Contract.sol:1155, onchain_auto/0xeda47e13fd1192e32226753dc2261c4a14908fb7/Contract.sol:1197, onchain_auto/0xeda47e13fd1192e32226753dc2261c4a14908fb7/Contract.sol:1445`

`sendETHToTeam()` forwards ETH with Solidity `.transfer()` to `_HODLWalletAddress` and `_marketingWalletAddress`. If either recipient is a contract whose fallback reverts or requires more than 2300 gas, every automatic swapback reverts. Because swapback is executed inside `_transfer()` whenever the token threshold is met, ordinary sells and transfers can become unexecutable.

**Impact:** If either fee wallet is a non-plain-EOA recipient, accumulated fees can permanently lock token movement once swapback starts triggering, trapping holders until the configuration is changed or ownership is unavailable.

**Paths:**

- A fee recipient is deployed or configured as a contract wallet that cannot accept `.transfer()`

- The contract accumulates at least `_numOfTokensToExchangeForTeam` tokens

- A non-buy transfer enters `_transfer`, reaches `sendETHToTeam()`, and reverts, blocking the enclosing token transfer

*Round 1 | Agents: codex_1*

---
