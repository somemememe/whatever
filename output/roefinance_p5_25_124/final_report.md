# Audit Report

**Total findings:** 4

## Critical (1)

### F-003: Zero oracle prices make listed reserves borrowable for free

**Confidence:** high | **Locations:** `onchain_auto/0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/misc/AaveOracle.sol:88, onchain_auto/0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/misc/AaveOracle.sol:93, onchain_auto/0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/misc/AaveOracle.sol:100, onchain_auto/0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/lendingpool/LendingPool.sol:963, onchain_auto/0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/libraries/logic/ValidationLogic.sol:176, onchain_auto/0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/libraries/logic/ValidationLogic.sol:180`

`AaveOracle.getAssetPrice` can return `0` when an asset has no configured source and the fallback oracle returns `0`, or when a configured source is non-positive and the fallback also returns `0`. `_executeBorrow` forwards that price directly into borrow validation, making `amountInETH` and the incremental collateral requirement for that borrowed asset equal to zero.

**Impact:** If any borrowable reserve resolves to a zero price, an attacker can post minimal valid collateral elsewhere and drain that reserve because the protocol records no additional debt value for the borrowed asset. The result is immediate reserve loss and protocol insolvency for that market.

**Paths:**

- A listed reserve's primary source is unset or unusable, and the fallback oracle also returns `0`.

- An attacker supplies enough collateral in another asset to satisfy general borrow preconditions.

- The attacker borrows the zero-priced reserve asset.

- Borrow validation treats the additional debt as worth zero and allows the reserve to be drained.

*Round 1 | Agents: codex_1*

---

## High (3)

### F-001: User-initiated `PMTransfer` lets a whitelisted position manager seize arbitrary collateral from healthy accounts

**Confidence:** medium | **Locations:** `onchain_auto/0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/lendingpool/LendingPool.sol:482, onchain_auto/0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/lendingpool/LendingPool.sol:487, onchain_auto/0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/lendingpool/LendingPool.sol:488, onchain_auto/0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/lendingpool/LendingPool.sol:499, onchain_auto/0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/tokenization/AToken.sol:191, onchain_auto/0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/tokenization/AToken.sol:198`

`PMTransfer` skips its health-factor gate whenever `tx.origin == user`, so a whitelisted PM contract can make any user-originated call double as authorization to pull arbitrary aTokens from that user. The transfer is executed through `transferOnLiquidation`, which bypasses the normal post-transfer health checks enforced on standard aToken transfers.

**Impact:** A compromised or malicious whitelisted PM can steal collateral from otherwise healthy users after getting them to call the PM contract once, then withdraw the underlying assets. This creates direct user fund loss without requiring approval or a hard-liquidation condition.

**Paths:**

- Pool admin whitelists a PM contract via `PMSet`.

- Victim sends a transaction to that PM contract, making `tx.origin == victim`.

- The PM contract calls `LendingPool.PMTransfer(aToken, victim, amount)` for any amount.

- The PM receives the victim's aTokens and can withdraw the underlying collateral.

*Round 1 | Agents: codex_1*

---

### F-002: Soft-liquidation `PMTransfer` can strip collateral without repaying debt

**Confidence:** medium | **Locations:** `onchain_auto/0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/lendingpool/LendingPool.sol:488, onchain_auto/0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/lendingpool/LendingPool.sol:497, onchain_auto/0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/lendingpool/LendingPool.sol:499, onchain_auto/0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/tokenization/AToken.sol:191, onchain_auto/0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/tokenization/AToken.sol:198, onchain_auto/0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/libraries/logic/ValidationLogic.sol:447`

When `tx.origin != user`, `PMTransfer` only requires the user's health factor to be at or below `softLiquidationThreshold`, but it does not cap `amount`, require any debt repayment, or re-check solvency after the transfer. Because it routes through `transferOnLiquidation`, the PM can remove collateral from an account near liquidation without performing an actual liquidation unwind.

**Impact:** A whitelisted PM can worsen or create undercollateralization by taking large amounts of collateral from users whose health factor is merely near the soft-liquidation threshold, leaving debt untouched and externalizing the loss to the protocol as bad debt.

**Paths:**

- A user's health factor falls to `softLiquidationThreshold` or below.

- A whitelisted PM calls `PMTransfer` for a large portion of the user's collateral.

- The PM receives the user's aTokens without repaying any debt.

- The PM withdraws the collateral, pushing the account underwater and leaving the protocol exposed.

*Round 1 | Agents: codex_1*

---

### F-004: Oracle freshness is never checked, allowing stale prices to drive collateral and liquidation logic

**Confidence:** medium | **Locations:** `onchain_auto/0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/interfaces/IChainlinkAggregator.sol:5, onchain_auto/0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/interfaces/IChainlinkAggregator.sol:7, onchain_auto/0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/misc/AaveOracle.sol:96, onchain_auto/0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/lendingpool/LendingPool.sol:961, onchain_auto/0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/libraries/logic/GenericLogic.sol:186, onchain_auto/0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/libraries/logic/GenericLogic.sol:200`

The oracle adapter only reads `latestAnswer()` and never validates freshness, round completeness, or `latestTimestamp()` before prices are used in borrow-power, health-factor, and liquidation calculations.

**Impact:** If a feed freezes on a favorable price, users can keep borrowing or avoid liquidation against stale valuations until governance or operators intervene. That can lead to overborrowing, delayed liquidations, and bad debt during market moves.

**Paths:**

- A price feed stops updating but continues returning its last value.

- `AaveOracle.getAssetPrice` accepts that stale `latestAnswer()` without checking timestamps or round status.

- Borrow and health-factor calculations continue using the stale valuation.

- Attackers borrow against overstated collateral or avoid liquidation against understated debt.

*Round 1 | Agents: codex_1*

---
