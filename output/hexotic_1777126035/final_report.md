# Audit Report

**Total findings:** 3

## High (2)

### F-001: Offer creation stores the real order under a hidden ID while every public interface returns and emits `0`

**Confidence:** high | **Locations:** `hex-otc.sol:216, hex-otc.sol:232, hex-otc.sol:239, hex-otc.sol:242, hex-otc.sol:256, hex-otc.sol:263, hex-otc.sol:268, hex-otc.sol:278, hex-otc.sol:287`

`offerETH()` and `offerHEX()` declare a named return variable `id`, but pass it by value into `newOffer()`. `newOffer()` assigns the fresh ID only to its local parameter, stores the order under that hidden nonzero key, and never propagates it back to the caller. As a result, `offerETH()`, `offerHEX()`, and `make()` all return `0`, and `LogMake` also emits `id = 0` for every order even though the order is actually stored under another ID.

**Impact:** Makers and takers receive the wrong identifier for every order. Off-chain order books and integrations collapse all orders onto the same ID, and users cannot reliably cancel or fill their own escrowed orders through the intended public API. This can strand ETH or HEX in escrow until someone reconstructs the hidden storage key out of band, creating protocol-wide denial of service for normal trading workflows.

**Paths:**

- `offerETH()` -> `newOffer(id, ...)` -> `_next_id()` stores order in `offers[realId]` -> function returns default `id = 0` -> `LogMake(bytes32(id))` emits `0`

- `offerHEX()` -> `newOffer(id, ...)` -> `_next_id()` stores order in `offers[realId]` -> function returns default `id = 0` -> `LogMake(bytes32(id))` emits `0`

- `make()` -> `offerETH()` / `offerHEX()` -> integrators receive `bytes32(0)` and cannot target the real order through `take()` / `kill()`

*Round 1 | Agents: codex*

---

### F-003: The OTC blindly binds to a hardcoded HEX address, so a wrong-chain deployment can settle against attacker-controlled token code

**Confidence:** medium | **Locations:** `hex-otc.sol:48, hex-otc.sol:49, hex-otc.sol:88, hex-otc.sol:121, hex-otc.sol:154, hex-otc.sol:185, hex-otc.sol:265`

The constructor unconditionally sets `hexInterface = ERC20(hexAddress)` for a single hardcoded address and never verifies chain context, code presence, or code identity. Every escrow and settlement path then trusts `balanceOf`, `transferFrom`, and `transfer` results from that address. If this contract is deployed on any chain where `0x2b591e99afE9f32eAA6214f7B7629768c40Eeb39` is not the canonical HEX token, a malicious contract at that address can forge balances and successful transfers while moving no real value.

**Impact:** A wrong-chain or misconfigured deployment can become fully compromiseable: attackers can drain ETH-backed offers by making `buyETH()` believe HEX was paid, and can sell nonexistent or undercollateralized "HEX" offers for real ETH because offer creation, settlement, and cancellation all trust the hardcoded token contract's return values. This is deployment-context dependent, but it creates realistic total loss if the bytecode at the fixed address is not the expected HEX implementation.

**Paths:**

- Deploy `HEXOTC` on a network where `0x2b591e99afE9f32eAA6214f7B7629768c40Eeb39` is attacker-controlled -> fake `balanceOf` and `transferFrom` let the attacker call `buyETH(id)` and receive escrowed ETH without paying real HEX

- Same deployment context -> fake `transferFrom` during `offerHEX()` records a HEX-backed order without real token escrow -> a buyer later calls `buyHEX(id)` and pays real ETH for nonexistent HEX

- Same deployment context -> fake `transfer` responses in `buyHEX()` or `cancel()` can report success without moving tokens, breaking refunds and settlement accounting

*Round 3 | Agents: codex*

---

## Medium (1)

### F-002: Using Solidity `transfer` for ETH payouts lets contract wallets permanently lock or DOS ETH-backed trades

**Confidence:** high | **Locations:** `hex-otc.sol:120, hex-otc.sol:155, hex-otc.sol:188`

The contract uses Solidity's fixed-2300-gas `transfer` for every ETH payout. If the maker or taker is a smart contract whose fallback reverts or needs more than 2300 gas, `buyHEX()`, `buyETH()`, or `cancel()` reverts outright.

**Impact:** ETH-backed orders involving contract accounts can become permanently unfillable or unwithdrawable. A contract wallet maker can lock its escrowed ETH by creating an ETH offer that cannot be cancelled, and a HEX seller that is a contract wallet can make its order impossible for anyone to fill because the ETH payout to the seller always reverts. This creates realistic permanent lockup and order-level denial of service for smart-wallet users.

**Paths:**

- contract wallet creates ETH sell order via `offerETH()` -> later `cancel()` hits `offer.owner.transfer(offer.pay_amt)` -> revert -> escrowed ETH stays locked

- contract wallet creates HEX sell order via `offerHEX()` -> buyer calls `buyHEX()` -> `offer.owner.transfer(msg.value)` reverts -> order cannot be filled by anyone

- contract wallet tries to take an ETH order via `buyETH()` -> `msg.sender.transfer(offer.pay_amt)` reverts -> that taker cannot complete the trade

*Round 1 | Agents: codex*

---
