# Audit Report

**Total findings:** 2

## High (2)

### F-001: `redeemUnderlying` can transfer underlying while burning zero cTokens after exchange-rate inflation

**Confidence:** medium | **Locations:** `onchain_auto/0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/CToken.sol:339, onchain_auto/0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/CToken.sol:352, onchain_auto/0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/CToken.sol:585, onchain_auto/0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/CToken.sol:644, onchain_auto/0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/CToken.sol:668, onchain_auto/0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/CToken.sol:693, onchain_auto/0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/CErc20.sol:128`

`redeemUnderlyingInternal` routes to `redeemFresh(msg.sender, 0, redeemAmount)`, and `redeemFresh` computes `redeemTokens = floor(redeemAmount * 1e18 / exchangeRateMantissa)` without enforcing `redeemTokens > 0`. Because `exchangeRateStoredInternal()` derives the rate from raw contract cash (`underlying.balanceOf(address(this))`) divided by `totalSupply`, a dust holder can first keep supply extremely small and then donate underlying directly to raise the zero-burn threshold (`exchangeRateMantissa / 1e18`) above a chosen withdrawal size. Once `redeemTokens` rounds to zero, both supply and the redeemer balance are decremented by zero and `doTransferOut` still sends the requested underlying.

**Impact:** A dominant or sole dust holder can repeatedly call `redeemUnderlying` for sub-threshold amounts and drain market cash without surrendering any cTokens. If the external comptroller also permits zero-token redemptions for accounts with no balance, the drain becomes permissionless for any caller.

**Paths:**

- Mint the minimum nonzero cToken position so `totalSupply` stays tiny.

- Donate underlying directly to the cToken contract so `getCashPrior()` and `exchangeRateStoredInternal()` jump without minting new cTokens.

- Call `redeemUnderlying(redeemAmount)` with `redeemAmount < exchangeRateMantissa / 1e18`, making `redeemTokens` truncate to zero.

- Receive underlying while `totalSupply` and `accountTokens[redeemer]` remain unchanged, then repeat until cash is exhausted.

*Round 1 | Agents: codex_1*

---

### F-002: `mint` can accept deposits that mint zero cTokens after exchange-rate inflation

**Confidence:** high | **Locations:** `onchain_auto/0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/CToken.sol:339, onchain_auto/0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/CToken.sol:352, onchain_auto/0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/CToken.sol:511, onchain_auto/0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/CToken.sol:528, onchain_auto/0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/CToken.sol:535, onchain_auto/0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/CToken.sol:550, onchain_auto/0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/CErc20.sol:128`

`mintFresh` computes `mintTokens = floor(actualMintAmount * 1e18 / exchangeRateMantissa)` and never checks that the result is nonzero. Since the exchange rate comes from raw market cash over `totalSupply`, and there is no minimum-liquidity or dead-shares defense, an attacker can mint a dust-sized initial position, donate underlying directly to the market, and raise the zero-mint threshold (`exchangeRateMantissa / 1e18`) high enough that later deposits are accepted while minting 0 cTokens.

**Impact:** Victim deposits below the inflated threshold are effectively confiscated: the underlying is transferred into the market, no cTokens are minted to the depositor, and the added cash accrues entirely to the attacker’s existing cToken position. This enables theft of later deposits once the attacker controls essentially all outstanding supply.

**Paths:**

- Acquire the entire or overwhelming majority of cToken supply by minting the minimum nonzero amount while supply is tiny.

- Donate underlying directly to the cToken contract to inflate `exchangeRateStoredInternal()` without issuing more shares.

- Wait for a victim to call `mint(mintAmount)` with `actualMintAmount < exchangeRateMantissa / 1e18`, so `mintTokens` truncates to zero.

- Redeem the victim’s deposited underlying through the attacker’s pre-existing cTokens.

*Round 1 | Agents: codex_1*

---
