# Global Audit Memory

## Scope Touched
- `FlawVerifier.sol` — primary review target so far; attention centered on route execution, native-call forwarding, asset-lock behavior, and liquidation output handling
- `interface.sol` — despite the name, it includes executable/library code (`TransferHelper`, `FixedPointMathLib`, `SafeTransferLib`, `Nonces`) plus router/provider-related logic that may influence downstream call safety and token handling
- Router / liquidation flow surfaces — cross-cutting focus on externally directed execution paths, zero-input assumptions, and minimum-output handling

## Issue Directions Seen
- Attacker-controlled external call surfaces, especially `routerCallNative` target and calldata paths
- Route execution assumptions around zero-input or weakly validated execution parameters
- Potential asset-lock or stuck-funds behavior in `FlawVerifier`
- Liquidation paths using zero `amountOutMin`, with slippage / MEV exposure as a recurring economic-risk direction
- Hidden complexity risk from executable code living inside `interface.sol`, making it a likely source of overlooked behavior

## Useful Context
- No retained findings yet; current memory is about concentration areas and recurring suspicion, not confirmed issues
- Review depth has been highest in `FlawVerifier.sol`, while `interface.sol` has only been selectively inspected
- `interface.sol` should be treated as a substantive code container rather than a pure interface file
- Early automated sanity checking did not add durable signal, so value is likely in continued manual flow analysis
