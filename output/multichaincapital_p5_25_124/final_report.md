# Audit Report

**Total findings:** 4

## Critical (1)

### F-001: Team fee is never removed from reflected transfers, minting unbacked tokens on every taxed transfer

**Confidence:** high | **Locations:** `onchain_auto/0x1a7981d87e3b6a95c1516eb820e223fe979896b3/Contract.sol:971, onchain_auto/0x1a7981d87e3b6a95c1516eb820e223fe979896b3/Contract.sol:975, onchain_auto/0x1a7981d87e3b6a95c1516eb820e223fe979896b3/Contract.sol:1011, onchain_auto/0x1a7981d87e3b6a95c1516eb820e223fe979896b3/Contract.sol:1027, onchain_auto/0x1a7981d87e3b6a95c1516eb820e223fe979896b3/Contract.sol:1041`

`_getTValues()` subtracts both `tFee` and `tTeam` from the visible transfer amount, but `_getRValues()` subtracts only `rFee` from `rAmount` and never removes the reflected team portion. Each taxed transfer path then credits `rTransferAmount` to the recipient and separately credits `rTeam` to the contract in `_takeTeam()`, so the team portion is counted twice in reflected balances.

**Impact:** Taxed transfers inflate aggregate token balances beyond the fixed supply accounting. The contract accumulates unbacked MCC that can later be swapped for ETH and forwarded to project wallets, draining AMM liquidity with tokens that were never fully debited from senders. Because self-transfers are allowed, an attacker can repeatedly cycle taxed transfers to manufacture team inventory with only the reflection fee as cost.

**Paths:**

- Any taxed transfer executes `_transfer*()` -> `_getValues()` -> `_getRValues()` and overcredits the recipient while `_takeTeam()` also credits the contract.

- A user can loop transfers between controlled addresses, or even self-transfer, to grow `address(this)` token balance without losing the full advertised team fee.

- Once enough synthetic MCC accumulates, auto-swap or `manualSwap()` sells it for ETH and extracts value from the pool.

*Round 1 | Agents: codex_1*

---

## High (2)

### F-002: The Uniswap pair is left reflection-eligible, allowing surplus LP tokens to be skimmed

**Confidence:** high | **Locations:** `onchain_auto/0x1a7981d87e3b6a95c1516eb820e223fe979896b3/Contract.sol:718, onchain_auto/0x1a7981d87e3b6a95c1516eb820e223fe979896b3/Contract.sol:724, onchain_auto/0x1a7981d87e3b6a95c1516eb820e223fe979896b3/Contract.sol:748, onchain_auto/0x1a7981d87e3b6a95c1516eb820e223fe979896b3/Contract.sol:820, onchain_auto/0x1a7981d87e3b6a95c1516eb820e223fe979896b3/Contract.sol:1053`

The pair is created in the constructor but is not excluded from reflections by default. Since non-excluded accounts use `tokenFromReflection(_rOwned[account])` in `balanceOf()`, the pair accrues reflected MCC over time while Uniswap's stored reserves remain unchanged until a syncing action occurs.

**Impact:** The pair's actual MCC balance can drift above its recorded reserve balance. Anyone can then call the pair's `skim()` function to withdraw the surplus tokens and dump them, extracting value from LP and breaking price integrity for traders.

**Paths:**

- Trading and taxed transfers generate reflections while `uniswapV2Pair` remains a normal reflected holder.

- The pair's token balance increases above its last recorded reserve value.

- An attacker calls `skim(attacker)` on the pair and sells the skimmed MCC back into the pool.

*Round 1 | Agents: codex_1*

---

### F-003: Auto-swaps are trivially sandwichable because contract sells use `amountOutMin = 0`

**Confidence:** high | **Locations:** `onchain_auto/0x1a7981d87e3b6a95c1516eb820e223fe979896b3/Contract.sol:889, onchain_auto/0x1a7981d87e3b6a95c1516eb820e223fe979896b3/Contract.sol:892, onchain_auto/0x1a7981d87e3b6a95c1516eb820e223fe979896b3/Contract.sol:912, onchain_auto/0x1a7981d87e3b6a95c1516eb820e223fe979896b3/Contract.sol:921`

When the contract's token balance reaches the swap threshold, any qualifying transfer from a non-pair sender triggers `swapTokensForEth(contractTokenBalance)`. That swap routes through `swapExactTokensForETHSupportingFeeOnTransferTokens` with `amountOutMin` hardcoded to zero, so the contract accepts any execution price.

**Impact:** MEV searchers can front-run the triggering transaction to push the MCC price down, let the contract dump fee inventory at a manipulated price, then back-run the rebound. This extracts treasury/holder value and makes the triggering user transaction materially worse.

**Paths:**

- Wait until `balanceOf(address(this)) >= _numOfTokensToExchangeForTeam`.

- Front-run the next eligible transfer with a price-depressing trade.

- The victim transfer triggers the contract's zero-slippage sale at the manipulated price.

- Back-run with a buy or arbitrage trade to capture the spread.

*Round 1 | Agents: codex_1, opencode_1*

---

## Medium (1)

### F-004: ETH payouts use `.transfer()`, so a reverting team wallet can block auto-swaps and non-buy transfers at the threshold

**Confidence:** medium | **Locations:** `onchain_auto/0x1a7981d87e3b6a95c1516eb820e223fe979896b3/Contract.sol:890, onchain_auto/0x1a7981d87e3b6a95c1516eb820e223fe979896b3/Contract.sol:896, onchain_auto/0x1a7981d87e3b6a95c1516eb820e223fe979896b3/Contract.sol:930, onchain_auto/0x1a7981d87e3b6a95c1516eb820e223fe979896b3/Contract.sol:942`

After auto-swapping fees to ETH, `sendETHToTeam()` forwards ETH with Solidity `.transfer()` to `_MCCWalletAddress` and `_marketingWalletAddress`. If either recipient reverts or requires more than the 2300 gas stipend, the payout reverts and so does the entire outer token transfer that triggered the swap.

**Impact:** Once the contract balance is above the swap threshold, wallet-to-wallet transfers and sells from non-pair senders can start reverting whenever they try to execute the payout path. This creates a partial liveness failure that can freeze normal outbound trading until `swapEnabled` is disabled or the payout destination is fixed.

**Paths:**

- A payout wallet is a smart contract, proxy, or otherwise cannot accept plain `.transfer()` ETH sends.

- The contract accumulates enough MCC to enter the auto-swap branch in `_transfer()`.

- An eligible non-buy transfer triggers `swapTokensForEth()` and then `sendETHToTeam()`, which reverts and bubbles the failure up to the token transfer.

*Round 1 | Agents: codex_1*

---
