# Audit Report

**Total findings:** 6

## Critical (1)

### F-003: All swaps use zero minimum output, enabling price-manipulation extraction

**Confidence:** high | **Locations:** `FlawVerifier.sol:241, FlawVerifier.sol:266, FlawVerifier.sol:384`

Every live Uniswap V2 and V3 swap path sets `amountOutMin`/`amountOutMinimum` to zero and performs no independent price or slippage validation before trading the contract's full token balance.

**Impact:** An MEV searcher can manipulate the relevant pool immediately before execution, let the verifier trade at an arbitrarily bad rate, then back-run to restore price and capture most of the treasury value as profit.

**Paths:**

- Observe a pending `executeOnOpportunity()` transaction or call it directly after funding.

- Manipulate one of the pools used by `_swapV3All()` or `_swapV2Path()`.

- Let the verifier execute swaps with zero slippage protection.

- Back-run the pool to unwind the manipulation and keep the extracted value.

*Round 1 | Agents: codex*

---

## High (2)

### F-001: ETH and residual token balances can be permanently trapped in FlawVerifier

**Confidence:** high | **Locations:** `FlawVerifier.sol:96, FlawVerifier.sol:102, FlawVerifier.sol:418, FlawVerifier.sol:419`

The contract can receive native tokens through `receive`/`fallback` and can accumulate ERC20 balances during probing and liquidation, but `executeOnOpportunity()` only unwraps WETH back into ETH held by the same contract. There is no code path anywhere in the contract that transfers ETH or ERC20 balances out to an operator or recovery address.

**Impact:** Any ETH used to fund the verifier, together with any profits or residual ERC20 balances it acquires, can become permanently unrecoverable. In the documented deployment model, the pre-funded treasury can be locked forever inside the contract.

**Paths:**

- Fund `FlawVerifier` with native tokens.

- Call `executeOnOpportunity()` so the contract probes, swaps, and may end with ETH/WETH or other ERC20 balances.

- Observe that no withdrawal or sweep function exists to move those assets out of the contract.

*Round 1 | Agents: codex*

---

### F-005: Hard-coded Ethereum mainnet endpoints can burn the treasury on the wrong chain

**Confidence:** high | **Locations:** `FlawVerifier.sol:74, FlawVerifier.sol:80, FlawVerifier.sol:96, FlawVerifier.sol:134, FlawVerifier.sol:241`

The contract hard-codes Ethereum mainnet token and router addresses but never verifies `block.chainid` or that those endpoints are the intended contracts before sending value and interacting with them. In particular, `_tryCycle()` sends native currency to the hard-coded `WETH` address through `deposit()` with no code or chain check.

**Impact:** If `FlawVerifier` is deployed or replayed on a different EVM network, its funded native-token treasury can be irreversibly transferred to an unrelated EOA or noncanonical contract at the same address, or otherwise routed through arbitrary endpoints instead of real WETH/Uniswap infrastructure.

**Paths:**

- Deploy `FlawVerifier` on any non-Ethereum-mainnet EVM chain.

- Fund it with native currency and call `executeOnOpportunity()`.

- `_tryCycle()` executes `IWETH(WETH).deposit{value: ethIn}()` against the hard-coded address, sending treasury funds to whatever exists there on that chain.

*Round 2 | Agents: codex*

---

## Medium (3)

### F-002: Anyone can execute the full treasury strategy without authorization

**Confidence:** high | **Locations:** `FlawVerifier.sol:96, FlawVerifier.sol:97, FlawVerifier.sol:101`

`executeOnOpportunity()` is `external` and has no access control, caller validation, cooldown, or one-shot guard, so any account can trigger the entire probing, mint-arbitrage, and liquidation routine against whatever assets the contract currently holds.

**Impact:** A third party can force the verifier to deploy its treasury at attacker-chosen times, reopen the strategy whenever the contract is re-funded, and generally grief the operator or pre-position MEV around the contract's full balance.

**Paths:**

- Wait until the contract is funded.

- Call `executeOnOpportunity()` from any EOA or contract.

- Repeat the call whenever the contract is funded again or still holds tradable balances.

*Round 1 | Agents: codex*

---

### F-004: Blind low-level probing with persistent approvals can self-inflict irreversible token loss

**Confidence:** low | **Locations:** `FlawVerifier.sol:141, FlawVerifier.sol:156, FlawVerifier.sol:282, FlawVerifier.sol:299, FlawVerifier.sol:300, FlawVerifier.sol:347, FlawVerifier.sol:392, FlawVerifier.sol:406`

The verifier grants large allowances to external contracts, leaves those allowances in place, and then issues many guessed low-level calls against `TARGET`, `USD0`, and `USUAL` while discarding success flags and enforcing no post-call safety invariant. If any probed selector or later token-pull path resolves to live state-changing logic, approved balances can be silently transferred, burned, or locked without the verifier detecting the loss.

**Impact:** A matching selector on one of the fixed external contracts can permanently burn, transfer away, or lock the verifier's assets during execution, and any surviving `USD0`/`USUAL` balances remain exposed afterward because the `TARGET` approvals are never revoked.

**Paths:**

- Call `executeOnOpportunity()` so `_probeEcosystem()` and `_probeSelectors()` run.

- The verifier first sets broad approvals for `TARGET`.

- One probed selector or later `TARGET` code path uses those approvals against the verifier's balances.

- The external call succeeds and the verifier continues without reverting or checking for unexpected balance loss.

*Round 1 | Agents: codex*

---

### F-006: No end-to-end profit check lets losing executions complete successfully

**Confidence:** medium | **Locations:** `FlawVerifier.sol:89, FlawVerifier.sol:96, FlawVerifier.sol:97, FlawVerifier.sol:101, FlawVerifier.sol:201, FlawVerifier.sol:282`

Although the contract comment states the final balance must exceed the initial balance, `executeOnOpportunity()` never snapshots starting balances or reverts on an overall net loss. Only `_tryCycle()` enforces a local WETH-profit condition; the surrounding probe and liquidation stages can still make state-changing calls, incur adverse conversions, and return successfully even when the contract finishes poorer than it started.

**Impact:** A caller can finalize treasury-burning runs that leave the verifier with less native-token value than it began with, so unsuccessful or partially harmful probe/liquidation sequences become permanent instead of reverting atomically.

**Paths:**

- Fund the contract and call `executeOnOpportunity()` when no genuine profitable opportunity exists.

- `_probeEcosystem()` and `_probeSelectors()` perform speculative external calls anyway.

- `_liquidateAll()` converts any resulting balances under the available execution paths.

- The function returns successfully even if the contract's final native-token-equivalent balance is below its starting balance.

*Round 2 | Agents: codex*

---
