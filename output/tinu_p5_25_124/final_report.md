# Audit Report

**Total findings:** 7

## Critical (1)

### F-001: Broken reflection math mints team-fee tokens out of thin air

**Confidence:** high | **Locations:** `0x2d0e64b6bf13660a4c0de42a0b88144a7c10991f/Contract.sol:1151, 0x2d0e64b6bf13660a4c0de42a0b88144a7c10991f/Contract.sol:1190, 0x2d0e64b6bf13660a4c0de42a0b88144a7c10991f/Contract.sol:1209, 0x2d0e64b6bf13660a4c0de42a0b88144a7c10991f/Contract.sol:1220`

The reflection calculation subtracts only the reflected tax fee from the recipient amount. `_getTValues()` removes both `tFee` and `tteam` from the transfer amount, but `_getRValues()` receives only `tFee` and computes `rTransferAmount = rAmount - rFee`, while `_taketeam()` still credits the contract with `tteam`. This makes each taxed transfer credit the recipient as if no team fee were removed while also crediting the contract with the team fee.

**Impact:** The token supply invariant is broken and team-fee transfers inflate balances. Those extra tokens accumulate in the contract and can later be swapped for ETH and forwarded to the fee wallets, extracting value from AMM liquidity. The issue is especially dangerous on self-transfers when `_teamFee > 0` and `_taxFee == 0`, because the sender's net balance does not decrease by the team fee while the contract still gains fee tokens.

**Paths:**

- Owner enables `_teamFee` through `_setteamFee()` while `_taxFee` is still 0 or low.

- Any non-excluded account performs transfers; on a self-transfer the sender only loses the reflected tax fee, not the team fee.

- `_taketeam()` credits the contract with newly created reflected value.

- Later transfers trigger `swapTokensForEth()` and `sendETHToteam()`, converting the inflated tokens into ETH taken from the pool.

*Round 1 | Agents: codex_1*

---

## High (3)

### F-002: Owner can arbitrarily blacklist holders and freeze both inbound and outbound transfers

**Confidence:** high | **Locations:** `0x2d0e64b6bf13660a4c0de42a0b88144a7c10991f/Contract.sol:964, 0x2d0e64b6bf13660a4c0de42a0b88144a7c10991f/Contract.sol:1020`

The owner can call `addBotToBlackList()` on any address except the Uniswap router, and `_transfer()` reverts whenever either `sender` or `recipient` is blacklisted. The pair itself is not protected from blacklisting.

**Impact:** A malicious owner can selectively trap user funds by preventing victims from selling, transferring out, or even receiving tokens. Because the pair can also be blacklisted, this mechanism can additionally be used to halt all pool trading.

**Paths:**

- Owner calls `addBotToBlackList(victim)` or blacklists the pair address.

- Any later `transfer()` or `transferFrom()` involving that address as sender or recipient hits the blacklist checks and reverts.

- Victims cannot exit positions or receive transfers until the owner removes the blacklist entry.

*Round 1 | Agents: codex_1, opencode_1*

---

### F-003: Owner can disable DEX trading at any time and turn the token into a honeypot

**Confidence:** high | **Locations:** `0x2d0e64b6bf13660a4c0de42a0b88144a7c10991f/Contract.sol:1027, 0x2d0e64b6bf13660a4c0de42a0b88144a7c10991f/Contract.sol:1274`

`LetTradingBegin(bool)` lets the owner freely toggle `tradingEnabled`. In `_transfer()`, any transaction where either side is `uniswapV2Pair` reverts while `tradingEnabled` is false.

**Impact:** After users buy, the owner can shut off pool trading and prevent both buys and sells against the AMM, effectively trapping liquidity and holders. Wallet-to-wallet transfers can still occur, so the restriction is specifically aimed at market exits.

**Paths:**

- Trading is initially enabled and users acquire tokens from the pair.

- Owner later calls `LetTradingBegin(false)`.

- Any subsequent buy or sell involving `uniswapV2Pair` reverts with `Trading is not enabled yet`.

*Round 1 | Agents: codex_1, opencode_1*

---

### F-004: Owner can set max transaction size to zero and freeze all non-owner transfers

**Confidence:** high | **Locations:** `0x2d0e64b6bf13660a4c0de42a0b88144a7c10991f/Contract.sol:1002, 0x2d0e64b6bf13660a4c0de42a0b88144a7c10991f/Contract.sol:1023`

`setMaxTxPercent()` has no lower bound, so the owner can set `_maxTxAmount` to 0. `_transfer()` then requires every transfer between non-owner addresses to satisfy `amount <= _maxTxAmount`, which no positive transfer can satisfy.

**Impact:** This creates a full transfer-freeze backdoor for all regular users, blocking wallet transfers and AMM trading while leaving owner-involved transfers exempt from the check.

**Paths:**

- Owner calls `setMaxTxPercent(0)`.

- A user attempts any positive transfer where neither side is the owner.

- `require(amount <= _maxTxAmount)` fails and the transaction reverts.

*Round 1 | Agents: codex_1, opencode_1*

---

## Medium (3)

### F-005: Unvalidated fee-wallet updates can brick transfers once auto-swap is triggered

**Confidence:** medium | **Locations:** `0x2d0e64b6bf13660a4c0de42a0b88144a7c10991f/Contract.sol:1068, 0x2d0e64b6bf13660a4c0de42a0b88144a7c10991f/Contract.sol:1109, 0x2d0e64b6bf13660a4c0de42a0b88144a7c10991f/Contract.sol:1266, 0x2d0e64b6bf13660a4c0de42a0b88144a7c10991f/Contract.sol:1270`

The owner can set `_teamWalletAddress` and `_marketingWalletAddress` to arbitrary addresses without validation. When auto-swap runs, `sendETHToteam()` forwards ETH using Solidity `transfer()`, so if either wallet is a contract that rejects ETH or needs more than 2300 gas, the forwarding step reverts and so does the user transfer that triggered the swap.

**Impact:** Once enough fee tokens have accumulated, normal sells and many wallet transfers can become unexecutable until the owner repairs the wallet configuration or disables swapping. If ownership is renounced after a bad wallet is configured, the token can be left in a persistent DoS state.

**Paths:**

- Owner sets either fee wallet to a reverting or gas-heavy contract.

- Fee tokens accumulate above `_numOfTokensToExchangeForteam`.

- A later transfer with `sender != uniswapV2Pair` triggers `swapTokensForEth()` followed by `sendETHToteam()`.

- The ETH `transfer()` fails, reverting the whole token transfer.

*Round 1 | Agents: codex_1*

---

### F-006: Owner can set an arbitrary cooldown and trap new buyers for an unbounded period

**Confidence:** medium | **Locations:** `0x2d0e64b6bf13660a4c0de42a0b88144a7c10991f/Contract.sol:1039, 0x2d0e64b6bf13660a4c0de42a0b88144a7c10991f/Contract.sol:1051, 0x2d0e64b6bf13660a4c0de42a0b88144a7c10991f/Contract.sol:1282`

`setCoolDown()` accepts any value and `_transfer()` stamps every buyer with `block.timestamp + _CoolDown` on purchases from the pair, then blocks subsequent transfers from that address until the timestamp expires. There is no upper bound on the enforced wait time.

**Impact:** The owner can impose extremely long cooldowns on new buyers, effectively trapping them from selling or transferring for months or years after purchase. This creates another honeypot-style control, especially because the restriction is applied automatically on buys.

**Paths:**

- Owner keeps `cooldownEnabled` active and sets `_CoolDown` to an extreme value.

- A user buys from `uniswapV2Pair`, so `timestamp[buyer]` is pushed far into the future.

- Any attempt by that buyer to sell or transfer before the deadline reverts with `Cooldown`.

*Round 1 | Agents: opencode_1*

---

### F-007: Owner can raise total transfer fees to 21% at any time

**Confidence:** high | **Locations:** `0x2d0e64b6bf13660a4c0de42a0b88144a7c10991f/Contract.sol:1256, 0x2d0e64b6bf13660a4c0de42a0b88144a7c10991f/Contract.sol:1261`

The owner can set `_taxFee` as high as 10% and `_teamFee` as high as 11%, producing a combined fee of up to 21% on transfers involving non-exempt addresses.

**Impact:** Users can suddenly lose a large fraction of each buy, sell, or transfer to owner-controlled fee flows. While not an outright freeze, this is high-friction value extraction that can materially impair exits and transferability.

**Paths:**

- Owner calls `_setTaxFee(10)` and `_setteamFee(11)`.

- Subsequent transfers between non-exempt accounts are charged up to 21% in combined fees.

- Fee value is redirected via reflection and the contract's fee-collection/swap path.

*Round 1 | Agents: opencode_1*

---
