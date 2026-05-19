# Audit Report

**Total findings:** 5

## Critical (1)

### F-004: Swap accounting trusts untrusted token `balanceOf`, enabling free withdrawal of the honest-side asset

**Confidence:** high | **Locations:** `onchain_auto/0x76ea342bc038d665e8a116392c82552d2605eda1/Contract.sol:454, onchain_auto/0x76ea342bc038d665e8a116392c82552d2605eda1/Contract.sol:468, onchain_auto/0x76ea342bc038d665e8a116392c82552d2605eda1/Contract.sol:469, onchain_auto/0x76ea342bc038d665e8a116392c82552d2605eda1/Contract.sol:471, onchain_auto/0x76ea342bc038d665e8a116392c82552d2605eda1/Contract.sol:475, onchain_auto/0x76ea342bc038d665e8a116392c82552d2605eda1/Contract.sol:480`

`swap` derives `amount0In` and `amount1In`, checks the invariant, and updates reserves from external `balanceOf(address(this))` reads on the listed tokens. If one pool token is malicious and lies about the pair's balance during these reads, the pair can be made to believe input arrived even when no real tokens were paid.

**Impact:** If one side of the pair is malicious and the other side is valuable, an attacker can withdraw the honest token for free and drain LP value. Because `_update` also writes the forged balance into reserves, the attacker can keep the pool in a poisoned state and repeat the extraction.

**Paths:**

- A pair exists where `token0` is malicious and `token1` is honest.

- The attacker calls `swap(0, amount1Out, attacker, data)` to receive real `token1`.

- During the post-transfer balance check, `token0.balanceOf(pair)` returns an inflated value even though no real `token0` was supplied.

- The pair computes a fake `amount0In`, passes the K-check, stores forged reserves, and finalizes the real `token1` payout.

*Round 1 | Agents: codex*

---

## High (1)

### F-005: Oracle reserves and TWAP can be forged by malicious tokens that spoof `balanceOf` during `sync` and reserve updates

**Confidence:** high | **Locations:** `onchain_auto/0x76ea342bc038d665e8a116392c82552d2605eda1/Contract.sol:368, onchain_auto/0x76ea342bc038d665e8a116392c82552d2605eda1/Contract.sol:374, onchain_auto/0x76ea342bc038d665e8a116392c82552d2605eda1/Contract.sol:375, onchain_auto/0x76ea342bc038d665e8a116392c82552d2605eda1/Contract.sol:377, onchain_auto/0x76ea342bc038d665e8a116392c82552d2605eda1/Contract.sol:378, onchain_auto/0x76ea342bc038d665e8a116392c82552d2605eda1/Contract.sol:493, onchain_auto/0x76ea342bc038d665e8a116392c82552d2605eda1/Contract.sol:494`

`sync()` and other state-changing entrypoints ultimately treat token-reported `balanceOf` values as authoritative and write them into `reserve0` and `reserve1`. The cumulative price oracle is then accrued from those stored reserves over time. A malicious token can therefore publish arbitrary reserve ratios and oracle prices without contributing matching capital.

**Impact:** Any integration that consumes this pair's spot reserves or TWAP as a price source can be manipulated into bad liquidations, under-collateralized borrowing, or mispriced settlement. The attack can require little or no capital when one listed token fabricates balances.

**Paths:**

- A pair lists a malicious token that returns forged values from `balanceOf(pair)`.

- The attacker calls `sync()` or another state-changing entrypoint so the pair stores attacker-chosen reserves.

- Time passes while the manipulated reserve ratio remains recorded.

- A later `_update` accrues `price0CumulativeLast` and `price1CumulativeLast` using the forged reserve ratio, poisoning TWAP consumers.

*Round 1 | Agents: codex*

---

## Medium (2)

### F-002: Positive-balance token mechanics let anyone skim unaccounted surplus from the pair

**Confidence:** medium | **Locations:** `onchain_auto/0x76ea342bc038d665e8a116392c82552d2605eda1/Contract.sol:485, onchain_auto/0x76ea342bc038d665e8a116392c82552d2605eda1/Contract.sol:488, onchain_auto/0x76ea342bc038d665e8a116392c82552d2605eda1/Contract.sol:489`

`skim(to)` is permissionless and transfers `balanceOf(pair) - reserve` for each pool asset. If either listed token can increase the pair's balance without going through `mint`/`swap`/`sync` (for example via positive rebases, yield accrual, reflections, or accidental direct transfers), any caller can immediately withdraw that surplus.

**Impact:** Pools that list balance-increasing or yield-bearing tokens can leak rebased or accrued value to arbitrary callers instead of LPs. Integrations or users that transfer pool assets directly to the pair can also lose those excess tokens to the first account that calls `skim`.

**Paths:**

- A listed token increases the pair's balance outside normal AMM flows -> reserves stay stale -> attacker calls `skim(attacker)` -> attacker receives the entire surplus amount

*Round 1 | Agents: codex*

---

### F-003: Balance-decreasing tokens can desynchronize reserves, DoS swaps, and force LP losses on sync

**Confidence:** medium | **Locations:** `onchain_auto/0x76ea342bc038d665e8a116392c82552d2605eda1/Contract.sol:454, onchain_auto/0x76ea342bc038d665e8a116392c82552d2605eda1/Contract.sol:468, onchain_auto/0x76ea342bc038d665e8a116392c82552d2605eda1/Contract.sol:471, onchain_auto/0x76ea342bc038d665e8a116392c82552d2605eda1/Contract.sol:493, onchain_auto/0x76ea342bc038d665e8a116392c82552d2605eda1/Contract.sol:494`

The pair assumes token balances only change through standard ERC20 transfers. If a listed asset can reduce the pair's balance asynchronously or charge fees when the pair sends or holds tokens, the actual token balance can fall below stored reserves. Subsequent `swap` calls can revert on the input or invariant checks until someone calls `sync()`, which writes the lower balances into reserves and realizes the loss.

**Impact:** Pools that include negative-rebasing, deflationary, or sender-taxed tokens can become partially or fully unusable, and LPs can be forced to socialize the token-side loss once reserves are synced down. This creates a realistic permissionless DoS and insolvency risk for such markets.

**Paths:**

- Pool is created with a balance-decreasing token -> token mechanics reduce the pair's actual balance below `reserve0` or `reserve1` -> swaps begin reverting because balances no longer satisfy the expected invariant -> any user calls `sync()` -> reserves are permanently marked down and LP value is reduced

*Round 1 | Agents: codex*

---

## Low (1)

### F-008: Cached EIP-712 domain separator allows permit replay after a chain split or chain-id change

**Confidence:** medium | **Locations:** `onchain_auto/0x76ea342bc038d665e8a116392c82552d2605eda1/Contract.sol:126, onchain_auto/0x76ea342bc038d665e8a116392c82552d2605eda1/Contract.sol:131, onchain_auto/0x76ea342bc038d665e8a116392c82552d2605eda1/Contract.sol:183, onchain_auto/0x76ea342bc038d665e8a116392c82552d2605eda1/Contract.sol:188`

The LP token computes `DOMAIN_SEPARATOR` once in the constructor using the then-current `chainid` and never recomputes it. If contract state is carried across a fork or the chain id changes after deployment, signatures remain tied to the old domain rather than the current chain context.

**Impact:** A permit signed for LP tokens on one branch can remain valid on another branch that inherited the same contract state, enabling unintended approvals and downstream LP-token theft on the sibling chain.

**Paths:**

- A user signs a `permit` for LP tokens after deployment.

- The chain later splits or changes chain id while preserving the contract state on another branch.

- Because the contract still uses the cached pre-change `DOMAIN_SEPARATOR`, the same signature can be accepted on the sibling branch and used to set an approval there.

*Round 1 | Agents: codex*

---
