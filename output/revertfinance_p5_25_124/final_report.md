# Audit Report

**Total findings:** 3

## Critical (1)

### F-001: Any approved NFT operator can force callback execution and drain a position's withdrawable value

**Confidence:** high | **Locations:** `onchain_auto/0x531110418d8591c92e9cbbfc722db8ffb604fafd/src/V3Utils.sol:137, onchain_auto/0x531110418d8591c92e9cbbfc722db8ffb604fafd/src/V3Utils.sol:144, onchain_auto/0x531110418d8591c92e9cbbfc722db8ffb604fafd/src/V3Utils.sol:150, onchain_auto/0x531110418d8591c92e9cbbfc722db8ffb604fafd/src/V3Utils.sol:152, onchain_auto/0x531110418d8591c92e9cbbfc722db8ffb604fafd/src/V3Utils.sol:219`

`onERC721Received` only checks that the NFT came from the Uniswap position manager, then blindly decodes and executes arbitrary `Instructions` against the transferred position before returning the NFT to `from`. It never verifies that the owner initiated the transfer or that the flow came through `execute()`. Because any address approved for the position NFT can call `nonfungiblePositionManager.safeTransferFrom(owner, address(this), tokenId, abi.encode(instructions))`, an approved operator can force `WITHDRAW_AND_COLLECT_AND_SWAP`, `COMPOUND_FEES`, or `CHANGE_RANGE` with attacker-chosen parameters and attacker-controlled `instructions.recipient`.

**Impact:** Any marketplace, delegated manager, or other approved operator can steal all currently withdrawable liquidity and fees from a victim Uniswap V3 position without retaining custody of the NFT: the victim receives the NFT back after execution, but the tokens have already been redirected.

**Paths:**

- Victim grants `approve(tokenId)` or `setApprovalForAll` on their Uniswap V3 position NFT to an external operator.

- The operator calls `nonfungiblePositionManager.safeTransferFrom(owner, address(V3Utils), tokenId, abi.encode(instructions))` directly, setting `instructions.recipient` to an attacker-controlled address and choosing a draining action.

- `V3Utils` decreases liquidity, collects fees, optionally swaps, and pays the resulting tokens to the attacker before returning the now-depleted NFT to `from`.

*Round 1 | Agents: codex_1, opencode_1*

---

## High (2)

### F-002: User-supplied swap data is an arbitrary-call primitive while V3Utils temporarily owns the user's position

**Confidence:** high | **Locations:** `onchain_auto/0x531110418d8591c92e9cbbfc722db8ffb604fafd/src/V3Utils.sol:159, onchain_auto/0x531110418d8591c92e9cbbfc722db8ffb604fafd/src/V3Utils.sol:164, onchain_auto/0x531110418d8591c92e9cbbfc722db8ffb604fafd/src/V3Utils.sol:175, onchain_auto/0x531110418d8591c92e9cbbfc722db8ffb604fafd/src/V3Utils.sol:180, onchain_auto/0x531110418d8591c92e9cbbfc722db8ffb604fafd/src/V3Utils.sol:190, onchain_auto/0x531110418d8591c92e9cbbfc722db8ffb604fafd/src/V3Utils.sol:199, onchain_auto/0x531110418d8591c92e9cbbfc722db8ffb604fafd/src/V3Utils.sol:537, onchain_auto/0x531110418d8591c92e9cbbfc722db8ffb604fafd/src/V3Utils.sol:543`

`_swap` blindly decodes `swapData` into `(swapRouter, allowanceTarget, data)` and performs a raw `swapRouter.call(data)` as `V3Utils`. In callback-based flows, this call happens while `V3Utils` temporarily owns the user's Uniswap position NFT and has custody of the collected position tokens. A malicious router can therefore use `V3Utils` as `msg.sender` to invoke arbitrary contracts, including the Uniswap position manager, and perform unauthorized side effects such as additional `decreaseLiquidity`/`collect` calls on the active position. The post-call checks only compare `tokenIn`/`tokenOut` balance deltas, so unrelated side effects are not blocked.

**Impact:** A malicious or tampered swap quote can drain the user's active position or steal unrelated assets temporarily/accidentally held by the contract while still satisfying local slippage checks. This turns swap calldata into a powerful arbitrary-execution surface during sensitive custody windows.

**Paths:**

- A user (or an attacker exploiting the callback path) reaches a branch that calls `_swap` while `V3Utils` owns `tokenId`.

- The supplied `swapData` points `swapRouter` to a malicious contract whose payload calls `nonfungiblePositionManager.decreaseLiquidity(...)` and `collect(..., attacker, ...)` using `V3Utils`' current ownership.

- The malicious router returns successfully with `amountOutMin` set to zero or with attacker-supplied output, so `_swap` passes its local balance checks and execution continues while the position has already been drained.

*Round 1 | Agents: codex_1*

---

### F-003: Residual position-manager allowances can permanently brick zero-first ERC20 flows across the deployment

**Confidence:** medium | **Locations:** `onchain_auto/0x531110418d8591c92e9cbbfc722db8ffb604fafd/src/V3Utils.sol:424, onchain_auto/0x531110418d8591c92e9cbbfc722db8ffb604fafd/src/V3Utils.sol:451, onchain_auto/0x531110418d8591c92e9cbbfc722db8ffb604fafd/src/V3Utils.sol:493, onchain_auto/0x531110418d8591c92e9cbbfc722db8ffb604fafd/src/V3Utils.sol:496`

`_swapAndPrepareAmounts` approves the Uniswap position manager for `total0` and `total1`, but after `mint` or `increaseLiquidity` the contract never clears any unused allowance. If Uniswap consumes less than the approved amount, a non-zero allowance remains on this shared `V3Utils` deployment. Tokens that require first resetting allowance to zero before setting a new non-zero allowance will then revert on every later call that reaches these raw `approve` statements.

**Impact:** A single partial mint/add-liquidity operation involving a zero-first token can permissionlessly and permanently DOS `swapAndMint`, `swapAndIncreaseLiquidity`, `COMPOUND_FEES`, and `CHANGE_RANGE` flows for that token on the affected deployment, with no recovery function to reset the stuck approval.

**Paths:**

- A user calls `swapAndMint`, `swapAndIncreaseLiquidity`, `COMPOUND_FEES`, or `CHANGE_RANGE` with a token that enforces zero-first approvals.

- `V3Utils` approves `nonfungiblePositionManager` for `total0`/`total1`, but Uniswap only spends `added0`/`added1`, leaving a non-zero residual allowance.

- Any later attempt to approve a fresh non-zero amount for the same token reverts, permanently bricking those flows on this deployment until users migrate to a new contract.

*Round 1 | Agents: codex_1*

---
