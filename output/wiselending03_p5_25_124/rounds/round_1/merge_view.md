# Merge View - Round 1

## Summary
- total findings: 5
- new findings: 5
- updated existing findings: 0
- rejected candidates: 14

## Finding Actions
- exact_agent_candidate: 2
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | High | high | codex_1 | Transfer-in accounting trusts nominal amounts and ignores unsuccessful ERC20 return values | codex_1:0.522 Transfer-in accounting trusts the requested amount instead of the tokens actually received |
| F-002 | exact_agent_candidate | High | high | codex_1 | depositExactAmountETHMint skips WETH pool synchronization and can mint shares at a stale price | codex_1:0.947 depositExactAmountETHMint skips pool synchronization and can mint WETH shares at a stale price |
| F-004 | rewritten_agent_signal | High | low | codex_1 | Verified isolation pools can bypass liquidation repayment invariants | opencode_1:0.459 Pure collateral can be liquidated without health check |
| F-003 | exact_agent_candidate | Medium | high | codex_1 | Illiquid liquidation credits residual shares to the liquidator but records the token under the victim NFT | codex_1:0.955 Illiquid liquidation credits shares to the liquidator but records the token under the victim NFT |
| F-005 | rewritten_agent_signal | Medium | medium | codex_1 | Arbitrary NFT dusting combines with a uint8 loop to freeze position cleanup once enough markets are listed | codex_1:0.396 Anyone can dust arbitrary NFTs, and token-removal logic breaks once a position tracks more than 255 tokens |

## Rejection Reasons
- other: 9
- trust_or_owner_model: 1
- unsupported_or_speculative: 4

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| unsupported_or_speculative | codex_1 | The per-pool allowBorrow flag is stored but never enforced in the audited borrow path | Borrowing routes through `WISE_SECURITY.checksBorrow()`, and the security-module implementation is not present in scope. The available code is insufficient to prove that `allowBorrow` is unenforced. |
| other | opencode_1 | Reentrancy vulnerability in liquidation due to unsafe external calls | The report does not show a concrete reentrant profit path. ERC20 calls are external, but the claim relies on a malicious listed token and does not demonstrate an exploitable invariant break in the audited code. |
| unsupported_or_speculative | opencode_1 | Flash loan price manipulation vulnerability in liquidation | The source only exposes an oracle interface and gives no evidence that liquidation uses flash-loan-manipulable spot pricing. The Chainlink manipulation claim is unsupported by the audited code. |
| other | opencode_1 | Division by zero in share calculation functions | Pools initialize `pseudoTotalPool`, `pseudoTotalBorrowAmount`, `totalDepositShares`, and `totalBorrowShares` to 1, so the cited denominators are not zero in normal empty-pool states. |
| other | opencode_1 | Fee calculation can result in zero shares causing fee loss | This is a protocol-fee rounding edge case, not a realistic user-loss, solvency, or theft issue. |
| other | opencode_1 | Lack of Oracle dead switch - price manipulation via dead oracle | Borrow and withdraw checks are delegated to external `WISE_SECURITY` hooks that are not included in scope, so the code shown does not prove a dead-oracle bypass. |
| other | opencode_1 | Missing access control allows unauthorized position operations | `approve()` only updates `allowance[msg.sender][poolToken][spender]`; it cannot set allowances for another user's NFT or position. |
| other | opencode_1 | Inconsistent position lock checks across functions | Potentially plausible, but `unCollateralizeDeposit()` immediately calls `WISE_SECURITY.checkUncollateralizedDeposit()`, and the security-module implementation is missing, so a real bypass is not established. |
| other | opencode_1 | Race condition in _reduceAllowance allows double spending of allowance | Allowance checks and decrements occur atomically within each call, and no concurrent or reentrant double-spend path is demonstrated. |
| other | opencode_1 | No slippage protection in liquidation | This is generic MEV/front-running exposure for liquidators, not a protocol-level vulnerability affecting pool safety. |
| unsupported_or_speculative | opencode_1 | LASA algorithm can be manipulated via deposit/withdraw timing | The claim is speculative and does not show a concrete path to extract value, steal funds, or break solvency. |
| trust_or_owner_model | opencode_1 | Immutable WISE_SECURITY after initial setup - no upgrade path | A one-time security-module configuration is a governance/design choice, not a standalone vulnerability. |
| unsupported_or_speculative | opencode_1 | Timestamp dependence in LASA algorithm | Minor timestamp influence on a three-hour control loop is too weak and speculative to be reportable. |
| other | opencode_1 | Pure collateral can be liquidated without health check | The code intentionally includes pure collateral in liquidation recovery, and the report does not show a separate health-check bypass beyond that designed behavior. |
