# Global Audit Memory

## Scope Touched
- `0x364f17a23ae4350319b7491224d10df5796190bc/contracts/LiquidXv2Zap.sol`: dominant audit surface so far; attention concentrated on `deposit()`, `withdraw()`, `_depositSwap()`, `withdrawToken()`, with secondary scrutiny on `_calculateSwapAmount()`, `receive()`, and operator-setting paths
- Deposit/withdraw zap flow: repeated concern around user-supplied routing/output parameters, approval/account binding, and asset custody assumptions
- Operator/admin-controlled recovery paths: recurring suspicion that privileged token withdrawal functions can reach custodial basket or residual assets unexpectedly

## Issue Directions Seen
- Withdrawal output control looks high risk: user- or caller-chosen `tokenOut` and related routing choices may let value be redirected or withdrawals break for certain asset types
- Caller/account authorization is a recurring theme: flows appear sensitive to third-party approvals and may not bind actions tightly enough to the intended beneficiary/account
- Swap protection is weak in the zap path: zero or weak minimum-out handling on deposit-side swaps creates a repeated MEV/sandwich direction
- Custody boundaries remain a core concern: basket-held assets, leftovers, or contract balances may be drainable through operator-oriented withdrawal/recovery logic
- Native ETH handling is a notable edge area: ETH/WETH assumptions and `receive()`-adjacent accounting were repeatedly treated as suspicious, especially on withdrawal paths

## Useful Context
- The audit has been almost entirely concentrated in a single file, so cross-round memory should stay centered on flow interactions inside `LiquidXv2Zap.sol` rather than broader protocol structure
- Both agents converged on the same core surfaces: deposit/withdraw execution, half-swap logic, and operator-controlled token movement
- Broader checks on arithmetic, timestamp/deadline use, identical-token validation, and reward/callback edge cases were explored but not retained; the more durable pattern is unsafe parameter trust plus weak custody/authorization boundaries
- Underexplored but repeatedly mentioned support areas inside the same file are `_calculateSwapAmount()`, `receive()`, and operator-setter configuration paths
