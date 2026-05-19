# Global Audit Memory

## Scope Touched
- `0xae60ac8e69414c2dc362d0e6a03af643d1d85b92/Contract.sol`: router execution path centered on `route`, `_balanceBefore`, `_ensureTransferIn`, `_execute`, `_ensureBalance`, and `withdraw`; recurring concern is fund/accounting correctness around inputs, outputs, and router-held balances
- `0xe04b08dfc6caa0f4ec523a3ae283ece7efe00019/Contract.sol`: Uniswap plugin swap paths for ERC20/ETH movement; attention has mainly been on how plugin execution interacts with router custody and balance assumptions

## Issue Directions Seen
- Output-delivery/custody mismatch: routes may satisfy internal success checks while `tokenOut` remains stranded in router custody rather than reaching the intended recipient
- Input-accounting mismatch: ERC20 routing logic appears sensitive to nominal vs actual received amounts, letting pre-existing router balances mask shortfalls
- ETH overpayment retention: excess native value sent into routes can remain trapped in the router and later become owner-withdrawable
- Balance-check narrowness after plugin execution: repeated attention on the risk of validating only expected output balances while other asset movements or router state changes go unchecked
- Generic plugin-execution themes were explored repeatedly, but durable traction so far is strongest on concrete fund-flow/accounting behavior rather than broad delegatecall/approval/reentrancy claims

## Useful Context
- Cross-round attention is concentrated on late-stage routing and plugin swap execution, especially token/ETH movement between router and plugin
- The most durable audit signal so far is not abstract plugin trust risk, but concrete cases where router-held inventory, accounting assumptions, or missing transfers change who actually bears losses
- `withdraw` matters mainly as the terminal sink for assets unintentionally left in router custody
