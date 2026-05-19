# Audit Report

**Total findings:** 4

## High (1)

### F-001: Direct underlying donations can inflate the exchange rate until later minters receive zero shares

**Confidence:** high | **Locations:** `0x9dcb6bc351ab416f35aeab1351776e2ad295abc4/Contract.sol:1625, 0x9dcb6bc351ab416f35aeab1351776e2ad295abc4/Contract.sol:1638, 0x9dcb6bc351ab416f35aeab1351776e2ad295abc4/Contract.sol:1783, 0x9dcb6bc351ab416f35aeab1351776e2ad295abc4/Contract.sol:1814, 0x9dcb6bc351ab416f35aeab1351776e2ad295abc4/Contract.sol:1821, 0x9dcb6bc351ab416f35aeab1351776e2ad295abc4/Contract.sol:2909`

The market prices shares from the raw underlying balance via `getCashPrior()`, so unsolicited token transfers raise the exchange rate without minting new oTokens. `mintFresh()` then computes `mintTokens = floor(actualMintAmount / exchangeRate)` and never rejects `mintTokens == 0`, allowing a seeded holder to donate enough underlying that a later depositor transfers assets in but receives no shares.

**Impact:** A permissionless attacker can steal later deposits on thin or freshly seeded markets. After becoming the only shareholder and donating underlying directly to the market, the attacker can force a victim mint to round to zero and then redeem the victim's deposited assets together with the donation.

**Paths:**

- Attacker mints a minimal amount to become the only oToken holder

- Attacker transfers underlying directly to the oToken contract, increasing `getCashPrior()` without increasing `totalSupply`

- Victim calls `mint()` and `mintTokens` truncates to 0

- Attacker redeems their existing shares and withdraws both their donation and the victim's deposit

*Round 1 | Agents: codex_1*

---

## Medium (2)

### F-002: When total supply resets to zero, the next minter can capture stranded underlying at the initial exchange rate

**Confidence:** high | **Locations:** `0x9dcb6bc351ab416f35aeab1351776e2ad295abc4/Contract.sol:1625, 0x9dcb6bc351ab416f35aeab1351776e2ad295abc4/Contract.sol:1627, 0x9dcb6bc351ab416f35aeab1351776e2ad295abc4/Contract.sol:1632, 0x9dcb6bc351ab416f35aeab1351776e2ad295abc4/Contract.sol:1783, 0x9dcb6bc351ab416f35aeab1351776e2ad295abc4/Contract.sol:1821, 0x9dcb6bc351ab416f35aeab1351776e2ad295abc4/Contract.sol:2909`

`exchangeRateStoredInternal()` ignores the contract's actual underlying balance whenever `totalSupply == 0` and returns `initialExchangeRateMantissa` instead. If any underlying remains stranded in the market after all shares are redeemed, the first new minter buys in at the reset price and receives claims on both their own deposit and the pre-existing residual cash.

**Impact:** Residual underlying left behind by direct transfers, dust, or accounting edge cases can be swept by the first post-reset minter. This lets an attacker appropriate stranded value whenever a market's share supply is fully emptied.

**Paths:**

- All oTokens are redeemed so `totalSupply` becomes 0

- Underlying remains in the contract due to direct transfers, dust, or other stranded balances

- Attacker performs the first new mint at `initialExchangeRateMantissa`

- Attacker redeems and captures the previously stranded underlying

*Round 1 | Agents: codex_1*

---

### F-003: Liquidation treats any zero-decimal collateral market as NFT collateral

**Confidence:** medium | **Locations:** `0x9dcb6bc351ab416f35aeab1351776e2ad295abc4/Contract.sol:2241, 0x9dcb6bc351ab416f35aeab1351776e2ad295abc4/Contract.sol:2279, 0x9dcb6bc351ab416f35aeab1351776e2ad295abc4/Contract.sol:2285, 0x9dcb6bc351ab416f35aeab1351776e2ad295abc4/Contract.sol:2291, 0x9dcb6bc351ab416f35aeab1351776e2ad295abc4/Contract.sol:2307`

The liquidation path uses `oTokenCollateral.decimals() == 0` as the discriminator for NFT collateral. Token decimals are not a reliable asset-type check, so any listed fungible market with 0 decimals is forced into the NFT-specific `ComptrollerEx` repay-cap path instead of the normal fungible liquidation flow.

**Impact:** A zero-decimal ERC20 collateral market can become mis-liquidated or non-liquidatable, allowing unhealthy debt to persist and increasing the risk of bad debt or insolvency if such a market is listed.

**Paths:**

- A fungible underlying with 0 decimals is listed as collateral

- A borrower opens a position against that market

- A liquidator calls `liquidateBorrow()`

- The call enters the NFT-specific branch solely because `decimals() == 0`, depending on incompatible liquidation logic

*Round 1 | Agents: codex_1*

---

## Low (1)

### F-004: Any account can force-sweep arbitrary non-underlying tokens from a market to the admin

**Confidence:** high | **Locations:** `0x9dcb6bc351ab416f35aeab1351776e2ad295abc4/Contract.sol:2887, 0x9dcb6bc351ab416f35aeab1351776e2ad295abc4/Contract.sol:2889, 0x9dcb6bc351ab416f35aeab1351776e2ad295abc4/Contract.sol:2890, 0x5fdbcd61bc9bd4b6d3fd1f49a5d253165ea11750/contracts/OErc20Delegator.sol:339, 0x5fdbcd61bc9bd4b6d3fd1f49a5d253165ea11750/contracts/OErc20Delegator.sol:340`

`sweepToken()` only checks that the token is not the market's underlying asset; it does not restrict the caller. Because the delegator exposes this method directly, any external account can trigger transfer of the entire balance of any other ERC20 held by the market to `admin`.

**Impact:** Third parties can front-run or grief token recovery by irreversibly redirecting accidentally sent or auxiliary tokens to the admin before the original owner or operators coordinate a rescue. This creates a permissionless loss-of-control vector around non-underlying assets held by the market.

**Paths:**

- A user or integration accidentally transfers a non-underlying ERC20 to the market

- Any external account calls `sweepToken(token)`

- The market transfers the entire token balance to `admin` without requiring admin authorization

*Round 1 | Agents: codex_1, opencode_1*

---
