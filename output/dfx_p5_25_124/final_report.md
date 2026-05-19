# Audit Report

**Total findings:** 4

## Critical (1)

### F-001: Flash-loan callback can reenter deposits and mint LP against temporarily drained balances

**Confidence:** high | **Locations:** `0x17af88bcc6590bbad6ec29e4ba63e132cb572326/contracts/Curve.sol:634, 0x17af88bcc6590bbad6ec29e4ba63e132cb572326/contracts/Curve.sol:653, 0x17af88bcc6590bbad6ec29e4ba63e132cb572326/contracts/ProportionalLiquidity.sol:24, 0x17af88bcc6590bbad6ec29e4ba63e132cb572326/contracts/ProportionalLiquidity.sol:34, 0x17af88bcc6590bbad6ec29e4ba63e132cb572326/contracts/ProportionalLiquidity.sol:68, 0x17af88bcc6590bbad6ec29e4ba63e132cb572326/contracts/ProportionalLiquidity.sol:70, 0x17af88bcc6590bbad6ec29e4ba63e132cb572326/contracts/ProportionalLiquidity.sol:73, 0x46161158b1947d9149e066d6d31af1283b2d377c/contracts/Curve.sol:634, 0x46161158b1947d9149e066d6d31af1283b2d377c/contracts/Curve.sol:653, 0x46161158b1947d9149e066d6d31af1283b2d377c/contracts/ProportionalLiquidity.sol:24, 0x46161158b1947d9149e066d6d31af1283b2d377c/contracts/ProportionalLiquidity.sol:34, 0x46161158b1947d9149e066d6d31af1283b2d377c/contracts/ProportionalLiquidity.sol:68, 0x46161158b1947d9149e066d6d31af1283b2d377c/contracts/ProportionalLiquidity.sol:70, 0x46161158b1947d9149e066d6d31af1283b2d377c/contracts/ProportionalLiquidity.sol:73`

`flash()` is not protected by `nonReentrant`, yet it transfers out pool assets and invokes a borrower-controlled callback before checking repayment. The callback can call `deposit()` (or `depositWithWhitelist()` when permitted) while balances are artificially low. LP minting uses `deposit * totalSupply / currentGrossLiquidity`, so temporarily draining reserves shrinks `currentGrossLiquidity` and mints outsized shares for a small real contribution.

**Impact:** A borrower can flash-borrow most liquidity, reenter a deposit while the pool appears nearly empty, repay the loan, and keep disproportionately large LP tokens that can later be redeemed for a large share of the restored pool. This is a direct pool-drain vector.

**Paths:**

- Call `flash()` from a contract borrower and receive most reserves

- Inside `flashCallback`, call `deposit()` while the borrowed assets are still out of the pool

- Repay the flash loan so the end-of-function balance checks pass

- Redeem the inflated LP position via `withdraw()`/`emergencyWithdraw()` to extract more assets than were honestly deposited

*Round 1 | Agents: codex_1, opencode_1*

---

## High (2)

### F-002: Factory-created curves hardwire swaps to a factory that lacks the required fee getter interface

**Confidence:** high | **Locations:** `0x17af88bcc6590bbad6ec29e4ba63e132cb572326/contracts/CurveFactory.sol:71, 0x17af88bcc6590bbad6ec29e4ba63e132cb572326/contracts/Swaps.sol:74, 0x17af88bcc6590bbad6ec29e4ba63e132cb572326/contracts/Swaps.sol:77, 0x17af88bcc6590bbad6ec29e4ba63e132cb572326/contracts/Swaps.sol:78, 0x17af88bcc6590bbad6ec29e4ba63e132cb572326/contracts/Swaps.sol:151, 0x17af88bcc6590bbad6ec29e4ba63e132cb572326/contracts/Swaps.sol:154, 0x17af88bcc6590bbad6ec29e4ba63e132cb572326/contracts/Swaps.sol:155, 0x17af88bcc6590bbad6ec29e4ba63e132cb572326/contracts/interfaces/ICurveFactory.sol:5, 0x17af88bcc6590bbad6ec29e4ba63e132cb572326/contracts/interfaces/ICurveFactory.sol:7, 0x46161158b1947d9149e066d6d31af1283b2d377c/contracts/CurveFactory.sol:71, 0x46161158b1947d9149e066d6d31af1283b2d377c/contracts/Swaps.sol:74, 0x46161158b1947d9149e066d6d31af1283b2d377c/contracts/Swaps.sol:77, 0x46161158b1947d9149e066d6d31af1283b2d377c/contracts/Swaps.sol:78, 0x46161158b1947d9149e066d6d31af1283b2d377c/contracts/Swaps.sol:151, 0x46161158b1947d9149e066d6d31af1283b2d377c/contracts/Swaps.sol:154, 0x46161158b1947d9149e066d6d31af1283b2d377c/contracts/Swaps.sol:155, 0x46161158b1947d9149e066d6d31af1283b2d377c/contracts/interfaces/ICurveFactory.sol:5, 0x46161158b1947d9149e066d6d31af1283b2d377c/contracts/interfaces/ICurveFactory.sol:7`

`CurveFactory.newCurve()` passes `address(this)` into the `Curve` constructor as `curveFactory`, but the concrete `CurveFactory` contract does not implement `getProtocolFee()` or `getProtocolTreasury()`. Both swap paths later cast that stored address to `ICurveFactory` and call those missing functions.

**Impact:** Any pool deployed through this factory can accept deposits and withdrawals but actual swap execution reverts when fee metadata is fetched, causing a permanent trading denial of service for factory-created markets.

**Paths:**

- Deploy a pool via `CurveFactory.newCurve()`

- Call `originSwap()` or `targetSwap()` on the deployed curve

- Swap execution reaches `ICurveFactory(curveFactory).getProtocolFee()` / `getProtocolTreasury()`

- The external call hits a factory with no such functions and the swap reverts

*Round 1 | Agents: codex_1*

---

### F-003: Externally supplied assimilators execute via delegatecall and can seize pool state if malicious or upgradeable

**Confidence:** medium | **Locations:** `0x17af88bcc6590bbad6ec29e4ba63e132cb572326/contracts/Assimilators.sol:28, 0x17af88bcc6590bbad6ec29e4ba63e132cb572326/contracts/Assimilators.sol:32, 0x17af88bcc6590bbad6ec29e4ba63e132cb572326/contracts/CurveFactory.sol:43, 0x17af88bcc6590bbad6ec29e4ba63e132cb572326/contracts/Orchestrator.sol:154, 0x17af88bcc6590bbad6ec29e4ba63e132cb572326/contracts/Orchestrator.sol:160, 0x46161158b1947d9149e066d6d31af1283b2d377c/contracts/Assimilators.sol:28, 0x46161158b1947d9149e066d6d31af1283b2d377c/contracts/Assimilators.sol:32, 0x46161158b1947d9149e066d6d31af1283b2d377c/contracts/CurveFactory.sol:43, 0x46161158b1947d9149e066d6d31af1283b2d377c/contracts/Orchestrator.sol:154, 0x46161158b1947d9149e066d6d31af1283b2d377c/contracts/Orchestrator.sol:160`

The pool records assimilator addresses supplied from outside the curve and later executes their state-changing logic with `delegatecall`. Because delegatecall runs in the pool's storage context, any malicious, compromised, or upgradeable assimilator can overwrite pool state, bypass accounting, or move pool-held tokens during normal deposit, withdrawal, or swap flows.

**Impact:** If an unsafe assimilator is configured for a pool, the next user interaction can be turned into arbitrary code execution inside the curve, leading to full fund theft, broken accounting, or permanent lockup.

**Paths:**

- Deploy a curve with a malicious assimilator address

- A user calls `deposit()`, `withdraw()`, or a swap that routes through that assimilator

- The assimilator code executes via `delegatecall` with full access to curve storage and token approvals/balances

- The assimilator rewrites critical state or transfers out reserves

*Round 1 | Agents: codex_1, opencode_1*

---

## Medium (1)

### F-004: Transferred LP tokens become non-withdrawable during the whitelist stage

**Confidence:** high | **Locations:** `0x17af88bcc6590bbad6ec29e4ba63e132cb572326/contracts/Curve.sol:516, 0x17af88bcc6590bbad6ec29e4ba63e132cb572326/contracts/Curve.sol:583, 0x17af88bcc6590bbad6ec29e4ba63e132cb572326/contracts/Curve.sol:584, 0x17af88bcc6590bbad6ec29e4ba63e132cb572326/contracts/Curve.sol:609, 0x17af88bcc6590bbad6ec29e4ba63e132cb572326/contracts/Curve.sol:618, 0x46161158b1947d9149e066d6d31af1283b2d377c/contracts/Curve.sol:516, 0x46161158b1947d9149e066d6d31af1283b2d377c/contracts/Curve.sol:583, 0x46161158b1947d9149e066d6d31af1283b2d377c/contracts/Curve.sol:584, 0x46161158b1947d9149e066d6d31af1283b2d377c/contracts/Curve.sol:609, 0x46161158b1947d9149e066d6d31af1283b2d377c/contracts/Curve.sol:618`

Whitelist accounting is attached to the original depositor in `whitelistedDeposited[msg.sender]`, but LP tokens remain freely transferable through `transfer()` and `transferFrom()`. During the whitelist stage, `withdraw()` always subtracts `_curvesToBurn` from the caller's own whitelist bucket before burning, so a recipient who only acquired LP by transfer underflows and reverts.

**Impact:** LP positions can be temporarily locked if they change hands during the whitelist period, breaking secondary transfers, custodial integrations, and OTC settlement until whitelisting is turned off.

**Paths:**

- A whitelisted address deposits through `depositWithWhitelist()` and receives LP tokens

- That address transfers some or all LP tokens to another account

- The recipient calls `withdraw()` while `whitelistingStage` is still true

- `whitelistedDeposited[recipient]` underflows at the whitelist decrement and the withdrawal reverts

*Round 1 | Agents: codex_1*

---
