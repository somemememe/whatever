# Audit Report

**Total findings:** 5

## Critical (1)

### F-001: Positive rebases desynchronize the AMM pair balance and let sellers extract excess ETH

**Confidence:** high | **Locations:** `0xc9fa8f4cfd11559b50c5c7f6672b9eea2757e1bd/Contract.sol:235, 0xc9fa8f4cfd11559b50c5c7f6672b9eea2757e1bd/Contract.sol:268, 0xc9fa8f4cfd11559b50c5c7f6672b9eea2757e1bd/Contract.sol:301, 0xc9fa8f4cfd11559b50c5c7f6672b9eea2757e1bd/Contract.sol:313`

`balanceOf(uniswapV2Pair)` returns the shadow variable `uniswapV2PairAmount` instead of `_gonBalances[pair] / _gonsPerFragment`. When `rebasePlus()` increases `_totalSupply`, it reduces `_gonsPerFragment` for every holder, including the pair, so the pair's real spendable token balance grows while `balanceOf(pair)` stays stale. On the next swap, the Uniswap pair reads an understated token balance and accepts too little token input for the ETH it pays out.

**Impact:** An attacker can trigger positive rebases with qualifying buys, then sell tokens back into the pool against understated token reserves and extract excess ETH/WETH, draining LP value.

**Paths:**

- Seed liquidity so the pair holds both QTN and ETH/WETH.

- Buy from the pair with amounts that satisfy the rebase condition, causing `rebasePlus(amount)` to run.

- The pair's actual token balance increases in fragment terms after the rebase, but `balanceOf(pair)` remains at the stale `uniswapV2PairAmount`.

- Sell QTN back into the pair; because the pair underestimates its token balance, it overpays ETH/WETH to the seller.

*Round 1 | Agents: codex_1, opencode_1*

---

## High (1)

### F-002: Pre-live buys can permanently blacklist arbitrary victim addresses

**Confidence:** high | **Locations:** `0xc9fa8f4cfd11559b50c5c7f6672b9eea2757e1bd/Contract.sol:284, 0xc9fa8f4cfd11559b50c5c7f6672b9eea2757e1bd/Contract.sol:293, 0xc9fa8f4cfd11559b50c5c7f6672b9eea2757e1bd/Contract.sol:340`

While `_live` is false, every transfer from the pair blindly executes `blacklist[to] = true`. Because Uniswap routers let the buyer choose an arbitrary recipient, any outsider can buy a dust amount to a victim address and blacklist that victim without consent.

**Impact:** Targeted wallets become unable to transfer or sell through the normal transfer path because non-buy transfers require both endpoints to be unblacklisted. This enables targeted freezing of users, market makers, treasury wallets, or integrations until the owner manually unblocks them.

**Paths:**

- Wait until liquidity exists while `_live == false`.

- Buy a dust amount of QTN through the router with `to` set to the victim address.

- The pair-to-victim transfer sets `blacklist[victim] = true`.

- Subsequent transfers or sells from that victim revert until `unblockWallet(victim)` is called by the owner.

*Round 1 | Agents: codex_1*

---

## Medium (2)

### F-003: Dust buys can repeatedly reset a holder's cooldown and block timely sells

**Confidence:** high | **Locations:** `0xc9fa8f4cfd11559b50c5c7f6672b9eea2757e1bd/Contract.sol:285, 0xc9fa8f4cfd11559b50c5c7f6672b9eea2757e1bd/Contract.sol:298`

Every buy sets `_buyInfo[to] = now`, and every later non-pair transfer from that address requires `_buyInfo[from] + 5 minutes < now`. Since a router buy can name any recipient, an attacker can keep sending dust buys to a victim and continuously reset the victim's 5-minute cooldown.

**Impact:** A low-cost attacker can permissionlessly grief specific holders by repeatedly preventing them from selling or transferring during important market windows, creating a realistic targeted denial of service.

**Paths:**

- Identify a victim that already holds QTN.

- Buy a dust amount through the router with `to` equal to the victim address.

- The contract updates `_buyInfo[victim]` to the current timestamp.

- Any immediate transfer or sell by the victim reverts for 5 minutes; the attacker can repeat the dust buy indefinitely.

*Round 1 | Agents: codex_1*

---

### F-004: Anyone can permanently disable the intended pre-launch protection

**Confidence:** medium | **Locations:** `0xc9fa8f4cfd11559b50c5c7f6672b9eea2757e1bd/Contract.sol:334`

`updateLive()` is externally callable by anyone and irreversibly sets `_live = true`. That permanently disables the contract's only special pre-live buy handling (`blacklist[to] = true` on pair buys), so outsiders can decide when the launch protection ends instead of the owner.

**Impact:** A third party can front-run the planned launch sequence, remove the anti-bot/pre-live behavior before the owner is ready, and leave initial liquidity exposed to unrestricted sniping and launch manipulation.

**Paths:**

- After deployment, but before the owner intends to end the pre-live phase, an outsider calls `updateLive()`.

- `_live` becomes `true` permanently.

- When liquidity is added and trading begins, buys no longer go through the intended pre-live blacklist path.

- Bots and snipers can trade without the owner-controlled launch window the contract appears to rely on.

*Round 1 | Agents: codex_1, opencode_1*

---

## Low (1)

### F-005: The max-wallet check uses the pre-buy balance, so buyers can exceed the cap

**Confidence:** high | **Locations:** `0xc9fa8f4cfd11559b50c5c7f6672b9eea2757e1bd/Contract.sol:296, 0xc9fa8f4cfd11559b50c5c7f6672b9eea2757e1bd/Contract.sol:299`

On buys, the contract checks `require(balanceOf(to) <= txLimitAmount)` before transferring the purchased tokens and never validates the recipient's post-transfer balance. A wallet already at or near the limit can therefore buy additional tokens and end above the supposed max-wallet threshold.

**Impact:** The anti-whale distribution control is bypassable, allowing larger-than-intended positions that can amplify price impact and make rebase/launch manipulation easier.

**Paths:**

- Accumulate tokens up to the configured `txLimitAmount` threshold.

- Execute another buy from the pair with `amount <= txLimitAmount`.

- The pre-transfer balance check passes.

- After `_tokenTransfer`, the wallet holds more than the intended cap.

*Round 1 | Agents: codex_1*

---
