# Audit Report

**Total findings:** 3

## Critical (2)

### F-002: External controller fully controls transfer debits and credits, enabling confiscation and hidden minting

**Confidence:** high | **Locations:** `0xf7ef0d57277ad6c2babf87ab64ba61abdd2590d2/Contract.sol:467, 0xf7ef0d57277ad6c2babf87ab64ba61abdd2590d2/Contract.sol:468, 0xf7ef0d57277ad6c2babf87ab64ba61abdd2590d2/Contract.sol:470, 0xf7ef0d57277ad6c2babf87ab64ba61abdd2590d2/Contract.sol:471, 0xf7ef0d57277ad6c2babf87ab64ba61abdd2590d2/Contract.sol:472, 0xf7ef0d57277ad6c2babf87ab64ba61abdd2590d2/Contract.sol:474, 0xf7ef0d57277ad6c2babf87ab64ba61abdd2590d2/Contract.sol:609`

`_transfer` does not enforce normal ERC-20 invariants. Instead, it blindly trusts the external controller to return `subBal` and `addBal`, then subtracts `subBal` from the sender and adds `addBal` to the recipient without requiring either value to equal `amount` or each other. This lets the controller arbitrarily reduce victim balances, under-credit recipients, or mint unbacked balances to chosen accounts while still emitting a normal-looking `Transfer(sender, recipient, amount)` event.

**Impact:** The controller can confiscate holder balances, impose hidden taxes, or fabricate arbitrary balances for privileged accounts and dump them, causing direct theft, severe price manipulation, and supply/accounting corruption.

**Paths:**

- On a victim transfer, return `(true, senderBalance, 0)` to wipe the sender while the event still reports the requested amount.

- On an attacker transfer, return `(true, 0, largeValue)` to mint spendable tokens to the recipient without increasing `totalSupply`.

- Use the fabricated balance to dump into liquidity or transfer value from honest holders.

*Round 1 | Agents: codex_1, opencode_1*

---

### F-003: Anyone can seize 80% of any holder balance through `addLiquidityETH` and route the stolen tokens to arbitrary recipients

**Confidence:** high | **Locations:** `0xf7ef0d57277ad6c2babf87ab64ba61abdd2590d2/Contract.sol:552, 0xf7ef0d57277ad6c2babf87ab64ba61abdd2590d2/Contract.sol:553, 0xf7ef0d57277ad6c2babf87ab64ba61abdd2590d2/Contract.sol:554, 0xf7ef0d57277ad6c2babf87ab64ba61abdd2590d2/Contract.sol:555, 0xf7ef0d57277ad6c2babf87ab64ba61abdd2590d2/Contract.sol:557, 0xf7ef0d57277ad6c2babf87ab64ba61abdd2590d2/Contract.sol:558, 0xf7ef0d57277ad6c2babf87ab64ba61abdd2590d2/Contract.sol:560`

`addLiquidityETH` is externally callable by anyone and takes fully user-supplied `routeraddr`, `lpraddr`, and `devaddr`. It directly debits `devaddr` by 80% of its current balance with no approval or ownership check, moves those tokens into the contract, approves the chosen router for `_totalSupply`, and then forwards the seized tokens into `addLiquidityETH` for LP minting to `lpraddr`. Because the router address is caller-chosen, an attacker can also supply a malicious router and use the approval to pull the seized tokens directly instead of adding real liquidity.

**Impact:** Any attacker can repeatedly confiscate most of any holder's tokens, seize launch/liquidity control by directing LP tokens to themselves, or directly siphon the seized tokens through a malicious router. This enables straightforward holder theft and permanent loss of control over pooled liquidity.

**Paths:**

- Pick a victim address as `devaddr` and call `addLiquidityETH` with attacker-controlled parameters.

- The function subtracts 80% of the victim's token balance and places those tokens in the contract without consent.

- Either use a real router and send resulting LP tokens to an attacker-chosen `lpraddr`, or pass a malicious router that uses the fresh `_totalSupply` approval to `transferFrom` the seized tokens out of the contract.

*Round 1 | Agents: codex_1, opencode_1*

---

## High (1)

### F-001: Hidden external controller can selectively block transfers and sells

**Confidence:** high | **Locations:** `0xf7ef0d57277ad6c2babf87ab64ba61abdd2590d2/Contract.sol:259, 0xf7ef0d57277ad6c2babf87ab64ba61abdd2590d2/Contract.sol:318, 0xf7ef0d57277ad6c2babf87ab64ba61abdd2590d2/Contract.sol:468, 0xf7ef0d57277ad6c2babf87ab64ba61abdd2590d2/Contract.sol:469, 0xf7ef0d57277ad6c2babf87ab64ba61abdd2590d2/Contract.sol:609`

The constructor stores an arbitrary `_router` address in `routerbyt`, then every `_transfer` decodes that address and calls its non-standard `swapExactTokensForETHSupportingFeeOnTransferTokens(address,address,uint256)` hook before updating balances. Because `_transfer` requires the returned `allow` flag to be true, whoever controls `_router` can revert or return `false` for selected senders or recipients and thereby deny specific transfers.

**Impact:** A deployer-controlled controller can turn the token into a honeypot by allowing buys or inbound transfers while blocking sells or withdrawals later, trapping user funds and permissionlessly DoSing transfers.

**Paths:**

- Deploy the token with an attacker-controlled contract passed as `_router`.

- Let users acquire tokens normally.

- When a victim tries to sell or transfer out, have the controller revert or return `allow = false`, causing `_transfer` to fail.

*Round 1 | Agents: codex_1, opencode_1*

---
