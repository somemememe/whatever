# Global Audit Memory

## Scope Touched
- `src/strategies/LidoLevV3.sol`: dominant focus across rounds; leveraged exit/unwind path, Curve swap constraints, Balancer flash-loan settlement, debt creation trust boundaries, and stressed-position accounting all matter here
- `src/vaults/AffineVault.sol`: important for vault-side handling of strategy divest/TVL signals, especially when leveraged positions are distressed or strategy exits degrade
- `src/interfaces/balancer/IFlashLoanRecipient.sol`: relevant for flash-loan repayment semantics and fee assumptions in unwind flows
- `src/interfaces/curve/ICurvePool.sol`: relevant for Curve slippage / near-par exit behavior in deleveraging
- `src/strategies/BaseStrategy.sol`: secondary attention on generic strategy controls such as asset sweeping and shared trust surfaces
- `src/strategies/AccessStrategy.sol`, `src/utils/AffineGovernable.sol`: secondary attention on operational/admin control surfaces around strategy behavior
- `src/strategies/deployed/LidoLevEthStrategy.sol`, `src/interfaces/lido/IWSTETH.sol`, `src/libs/SlippageUtils.sol`: supporting context for wrapper/slippage assumptions around the Lido leveraged flow

## Issue Directions Seen
- Leveraged unwind/exit fragility in `LidoLevV3` is the clearest recurring direction, especially Curve-dependent deleveraging under tight pricing or stressed conditions
- Vault/strategy accounting mismatches are a recurring theme, particularly where TVL, divest outputs, or distressed positions are valued too optimistically
- Flash-loan repayment semantics and fee handling are a meaningful economic-risk direction in the unwind path
- Cross-strategy trust boundaries deserve attention, especially `createAaveDebt()` enabling one active strategy to affect another strategy’s debt posture
- Broader operational/griefing surfaces were explored around allocation updates, setters, harvest timing, callbacks, and sweep functionality, but remain secondary to the core unwind/accounting themes

## Useful Context
- Audit attention has concentrated heavily on the interaction between `LidoLevV3` and `AffineVault`, not on isolated library bugs
- Durable risk pattern: assumptions that hold near par or in healthy positions become unsafe during deleveraging or underwater states
- Repeated concern is less classic reentrancy and more economic/accounting correctness under adverse market conditions
- Single-agent-only areas that still looked suspicious included `_divest()` output accounting, `createAaveDebt()`, `updateStrategyAllocations()`, and `BaseStrategy.sweep()`
