# Global Audit Memory

## Scope Touched
- `0xe5c6f5fef89b64f36bfccb063962820136bac42f/Contract.sol` (`_transfer()`): central hotspot for blacklist enforcement, hidden transfer-tax behavior, and sell-throttling logic
- `Contract.sol` admin/launch path (`openTrading()`, `addBots()`, `removeTransferTax()`, `removeLimits()`, `reduceFee()`): owner-controlled switches repeatedly tied to trading control and post-launch behavior changes
- `Contract.sol` fee/liquidity handling (`manualSwap()`, LP custody during `openTrading()`): attention centered on tax extraction mechanics and owner custody over liquidity-related assets

## Issue Directions Seen
- Owner/admin privilege concentration affecting market access, fees, and launch-state transitions
- Blacklist-style controls that can freeze specific holders or broadly disrupt trading
- Hidden or mutable post-launch taxation, especially transfer-specific tax behavior not obvious from launch expectations
- Liquidity/LP custody remaining with privileged actors, preserving rug-style exit paths
- Global sell throttling or fee-swap coupling creating denial-of-sell conditions
- Secondary but less-retained directions: manual fee extraction, limit/fee toggle misuse, router approval exposure, and launch-timing control

## Useful Context
- Audit attention has been almost entirely concentrated in a single `Contract.sol`; no broader multi-contract surface emerged
- Cross-round overlap is strongest around `_transfer()` and owner-control surfaces, suggesting the main risk profile is behavioral control rather than complex integration bugs
- Retained findings converged on four durable themes: LP custody, blacklist freeze power, hidden high transfer tax, and sell-per-block throttling
- Functions like `manualSwap()`, `removeLimits()`, and `reduceFee()` were flagged as suspicious but had weaker cross-agent confirmation than the retained core issues
