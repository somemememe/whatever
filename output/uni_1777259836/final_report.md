# Audit Report

**Total findings:** 5

## High (1)

### F-001: All ETH, extracted profits, and arbitrary ERC20s are permanently locked in the contract

**Confidence:** high | **Locations:** `FlawVerifier.sol:29, FlawVerifier.sol:61, FlawVerifier.sol:69, FlawVerifier.sol:74`

`executeOnOpportunity` relies on the contract already holding ETH so it can wrap `1 wei` into WETH, later unwraps all harvested WETH back into raw ETH, and `FlawVerifier` exposes no withdrawal, sweep, or beneficiary-controlled transfer for either ETH or arbitrary ERC20 balances.

**Impact:** Any ETH used to seed the strategy, any accidental ETH sent to `receive`/`fallback`, any successful exploit proceeds, and any ERC20 transferred or stranded in the contract become permanently unrecoverable. This can trap operator capital, fully strand profits, and permanently burn any non-WETH tokens that end up on the contract.

**Paths:**

- An operator or third party sends ETH to the contract so `IWETH.deposit{value: 1 wei}()` can succeed

- A successful run leaves value on the contract after `IWETH.withdraw(wethBal)` converts WETH into ETH

- A user or external interaction transfers a non-WETH ERC20 to `FlawVerifier`

- No external function exists to move ETH or ERC20 balances out of the contract

*Round 1 | Agents: codex*

---

## Medium (3)

### F-002: Forced ETH donations can permanently brick `executeOnOpportunity`

**Confidence:** high | **Locations:** `FlawVerifier.sol:30, FlawVerifier.sol:66, FlawVerifier.sol:74`

Profitability is measured against `address(this).balance` at the start of each run, so anyone can raise the required profit threshold by sending or force-sending ETH to the contract. Because the contract has no withdrawal path, the inflated baseline cannot be reset.

**Impact:** A griefing attacker can permanently make `executeOnOpportunity` fail once the trapped balance is high enough that the strategy cannot end with `initialBalance + 0.1 ether`. This creates a permissionless denial of service against the contract's only execution path.

**Paths:**

- An attacker transfers ETH to the contract or force-sends ETH via `SELFDESTRUCT`

- `executeOnOpportunity` snapshots the donated balance in `initialBalance`

- The final check `address(this).balance >= initialBalance + 0.1 ether` becomes unattainable, causing every call to revert

*Round 1 | Agents: codex*

---

### F-003: Anyone can permissionlessly trigger the hardcoded exploit once the contract is funded

**Confidence:** high | **Locations:** `FlawVerifier.sol:29, FlawVerifier.sol:44, FlawVerifier.sol:51`

`executeOnOpportunity()` is fully permissionless even though it spends the contract's prefunded ETH/WETH and irreversibly mutates the fixed target pair by syncing corrupted balances and swapping out nearly all WETH reserves. There is no owner check or designated executor.

**Impact:** A bot or griefing third party can front-run the intended operator, fire the exploit at an arbitrary time, and consume the one-shot opportunity through this contract. That strips the operator of execution control and can permanently leave the target pair drained while all resulting value remains trapped in the contract.

**Paths:**

- The operator funds the contract so `IWETH.deposit{value: 1 wei}()` can succeed

- A third party observes the funded balance and calls `executeOnOpportunity()` first

- The function syncs the manipulated reserves and drains the pair's WETH side, so later calls no longer face the same profitable state

*Round 2 | Agents: codex*

---

### F-004: A successful run can self-brick all future executions by ratcheting the profit baseline with trapped proceeds

**Confidence:** high | **Locations:** `FlawVerifier.sol:30, FlawVerifier.sol:61, FlawVerifier.sol:66`

`executeOnOpportunity()` snapshots the contract's entire ETH balance as `initialBalance` and later requires `address(this).balance >= initialBalance + 0.1 ether`; because the function also unwraps all WETH into ETH and leaves the proceeds in-contract, each successful run raises the minimum balance future runs must exceed by another `0.1 ether` even though the old profit is unrecoverable.

**Impact:** The contract can become unusable after its own first success: later opportunities that are still profitable in isolation revert unless they clear the ever-increasing historical balance hurdle. This creates a permanent liveness failure even without any external donation attack.

**Paths:**

- Fund the contract with the ETH seed needed for `IWETH.deposit{value: 1 wei}()`

- Call `executeOnOpportunity()` successfully once

- The harvested WETH is unwrapped to ETH and remains trapped in the contract

- A later call snapshots the larger trapped ETH balance as `initialBalance`

- Future runs revert unless they generate another `0.1 ether` on top of all previously trapped profits

*Round 5 | Agents: codex*

---

## Low (1)

### F-005: Prefunded WETH can spoof the profitability check

**Confidence:** medium | **Locations:** `FlawVerifier.sol:30, FlawVerifier.sol:61, FlawVerifier.sol:63, FlawVerifier.sol:66`

`executeOnOpportunity` snapshots only the contract's native ETH balance at entry, but later unwraps and counts the entire WETH balance held by the contract before enforcing the `+0.1 ether` profit threshold. Any WETH prefunded or donated before the call is therefore misclassified as profit from the current execution.

**Impact:** The contract's only economic safety check can be bypassed with stale or donated WETH, allowing an actually unprofitable or marginal execution to return success. This can produce false-positive exploit verification and lead operators or integrations to consume a one-shot opportunity or burn their own capital under the mistaken belief that the required profit was achieved.

**Paths:**

- An attacker or operator transfers at least `0.1 WETH` to `FlawVerifier` before calling `executeOnOpportunity`

- The function unwraps all WETH held by the contract via `IWETH(WETH).withdraw(wethBal)`

- The final balance check treats the donated WETH-as-ETH as fresh profit and the call succeeds even if the exploit itself did not generate `0.1 ether` of profit

*Round 4 | Agents: codex*

---
