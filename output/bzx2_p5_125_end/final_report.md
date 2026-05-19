# Audit Report

**Total findings:** 4

## High (2)

### F-002: Minting trusts the requested ERC20 deposit amount instead of the amount actually received

**Confidence:** high | **Locations:** `0xfb772316a54dcd439964b561fc2c173697aeeb5b/Contract.sol:1522, 0xfb772316a54dcd439964b561fc2c173697aeeb5b/Contract.sol:1528, 0xfb772316a54dcd439964b561fc2c173697aeeb5b/Contract.sol:1919`

The mint path prices shares from the caller-supplied `depositAmount` before any transfer happens, then only checks whether `transferFrom` returned success. It never measures the contract's actual balance delta, so a fee-on-transfer or otherwise deflationary `loanTokenAddress` can deliver fewer tokens than `depositAmount` while the minter still receives shares as if the full amount arrived.

**Impact:** An attacker can over-mint iTokens, diluting existing lenders and later redeeming more underlying than they contributed. If enough liquidity exists, this can make the pool insolvent.

**Paths:**

- Use a pool whose `loanTokenAddress` burns, taxes, or otherwise transfers less than the requested amount.

- Call `mint(receiver, X)` so `_safeTransferFrom` succeeds but the contract receives less than `X`.

- Receive shares computed from `X`, then burn them later for a disproportionate amount of underlying.

*Round 1 | Agents: codex_1*

---

### F-003: Borrow and margin-trade accounting can overstate user deposits for fee-on-transfer tokens

**Confidence:** medium | **Locations:** `0xfb772316a54dcd439964b561fc2c173697aeeb5b/Contract.sol:1790, 0xfb772316a54dcd439964b561fc2c173697aeeb5b/Contract.sol:1821, 0xfb772316a54dcd439964b561fc2c173697aeeb5b/Contract.sol:1869, 0xfb772316a54dcd439964b561fc2c173697aeeb5b/Contract.sol:1880, 0xfb772316a54dcd439964b561fc2c173697aeeb5b/Contract.sol:1919`

`_verifyTransfers` forwards collateral and optional `loanTokenSent` to `bZxContract` with blind `transferFrom` calls, while `_borrowOrTrade` still passes the original nominal `sentAmounts` into `borrowOrTradeFromPool`. If either token transfers less than requested, downstream accounting can still treat the full nominal amounts as having been deposited.

**Impact:** A trader can open positions with less real collateral or less real lender-side contribution than the protocol believes it has received, creating undercollateralized debt and lender bad debt.

**Paths:**

- Choose a supported collateral token or loan token that charges transfer fees or otherwise delivers less than requested.

- Open a `borrow` or `marginTrade` position with nominal `collateralTokenSent` and/or `loanTokenSent`.

- The protocol receives fewer real tokens than the values encoded in `sentAmounts`, but the loan is opened using the overstated amounts.

*Round 1 | Agents: codex_1*

---

## Medium (1)

### F-004: The first minter can capture assets already present in the pool

**Confidence:** high | **Locations:** `0xfb772316a54dcd439964b561fc2c173697aeeb5b/Contract.sol:1522, 0xfb772316a54dcd439964b561fc2c173697aeeb5b/Contract.sol:1943, 0xfb772316a54dcd439964b561fc2c173697aeeb5b/Contract.sol:2124`

When `totalSupply_ == 0`, `_totalAssetSupply` returns zero and `_tokenPrice` falls back to `initialPrice`, ignoring any underlying tokens already sitting in the pool. If the contract is pre-funded or receives stray underlying before the first mint, the first supplier can buy shares at the default price instead of paying for the pre-existing assets.

**Impact:** Any bootstrap liquidity or accidental direct transfer of underlying into an uninitialized pool can be stolen by the first minter.

**Paths:**

- Transfer underlying tokens into the pool before any iTokens exist.

- Perform the first `mint` with a minimal deposit; shares are still minted at `initialPrice`.

- Burn the received iTokens to redeem a disproportionate share of the pre-seeded underlying, including the assets that were already in the pool.

*Round 1 | Agents: codex_1*

---

## Low (1)

### F-005: The proxy silently accepts low-gas ETH transfers and bypasses logic execution

**Confidence:** high | **Locations:** `0x7f3fe9d492a9a60aebb06d82cba23c6f32cad10b/Contract.sol:624, 0x7f3fe9d492a9a60aebb06d82cba23c6f32cad10b/Contract.sol:628, 0x7f3fe9d492a9a60aebb06d82cba23c6f32cad10b/Contract.sol:635`

The proxy fallback is payable and returns immediately when `gasleft() <= 2300` instead of reverting or delegating. Plain ETH transfers via `transfer` or `send` therefore succeed while executing no application logic.

**Impact:** Users or integrations can accidentally send ETH into the proxy and receive no protocol action in return. Those funds remain in the proxy balance with no user-controlled recovery path shown in this code.

**Paths:**

- Send ETH to the proxy using a 2300-gas transfer.

- The fallback returns early before `delegatecall`ing the implementation.

- The ETH stays on the proxy while the sender receives no tokens, loan action, or revert signal.

*Round 1 | Agents: codex_1*

---
