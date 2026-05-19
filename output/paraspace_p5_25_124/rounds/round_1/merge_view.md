# Merge View - Round 1

## Summary
- total findings: 3
- new findings: 3
- updated existing findings: 0
- rejected candidates: 10

## Finding Actions
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | High | high | codex_1 | Siloed-borrowing risk controls are defined but never enforced on borrow | codex_1:0.625 Siloed-borrowing risk controls are dead code and can be bypassed entirely |
| F-002 | rewritten_agent_signal | High | high | codex_1 | ERC721 liquidation can seize NFT collateral using any listed ERC20 without repaying or even bounding against actual debt | codex_1:0.511 ERC721 liquidation lets the caller choose any reserve asset as payment instead of repaying an actual debt asset |
| F-003 | rewritten_agent_signal | Medium | high | codex_1 | supplyERC721FromNToken is bricked by `ownerOf` on nonexistent nToken ids | codex_1:0.752 supplyERC721FromNToken is bricked because validation calls ownerOf() on an unminted NToken id |

## Rejection Reasons
- factually_incorrect: 2
- other: 3
- trust_or_owner_model: 1
- unsupported_or_speculative: 4

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| unsupported_or_speculative | opencode_1 | Incorrect debt calculation uses balanceOf instead of scaledBalanceOf | Not supported. `IVariableDebtToken` explicitly exposes `balanceOf(user)` as the current debt view, and this helper is used where current debt is needed. The separate `scaledBalanceOf` path in `GenericLogic` is an optimization, not evidence that `balanceOf` is wrong here. |
| other | opencode_1 | Integer overflow in GenericLogic liquidity threshold calculation | Not reportable. The cited multiplications are executed under Solidity 0.8 checked arithmetic, so overflow reverts instead of silently corrupting health factor calculations. |
| other | opencode_1 | Division by zero when liquidation bonus is zero | Only arises from administrator misconfiguration of reserve parameters. The code does not show an attacker-triggerable path, so this is not a protocol vulnerability. |
| unsupported_or_speculative | opencode_1 | Reentrancy vulnerability in FlashClaimLogic | Insufficiently supported. The report does not identify a concrete state-corruption path, and the repository snapshot does not expose a vulnerable public `flashClaim` entrypoint that would make the callback reentrancy claim reportable on its own. |
| unsupported_or_speculative | opencode_1 | Reentrancy in marketplace flash loan pattern | Not supported. The public marketplace entrypoints in `PoolMarketplace` are protected by `nonReentrant`, so a generic callback/reentrancy claim against `_buyWithCredit` is not enough. |
| other | opencode_1 | NFT transferred before state update in supply | Not reportable. If `executeSupplyERC721Base` reverts, the prior `safeTransferFrom` is reverted as part of the same transaction, so the NFT is not permanently stranded by this ordering alone. |
| factually_incorrect | opencode_1 | Unchecked return value in MarketplaceLogic | Incorrect. `Address.functionDelegateCall` reverts on failure; the delegatecall result is not silently ignored. |
| factually_incorrect | opencode_1 | Repay with pTokens allows repaying more than debt | Incorrect. `paybackAmount` is initialized to actual debt and only reduced when `params.amount` is smaller, so repayment is capped at `min(requestedAmount, variableDebt)`. |
| trust_or_owner_model | opencode_1 | Missing initialization check in ParaProxy constructor | Deployment self-misconfiguration only. Passing `address(0)` as owner does not create an attacker-triggerable protocol issue. |
| unsupported_or_speculative | opencode_1 | Potential division by zero in GenericLogic | Not supported. The cited divisions are guarded by explicit nonzero checks on the relevant collateral totals, and the ERC721 health-factor denominator is separately guarded by `payableDebtByERC20Assets >= totalDebtInBaseCurrency`. |
