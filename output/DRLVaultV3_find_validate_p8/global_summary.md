# Global Audit Memory

## Scope Touched
- `DRLVaultV3.sol` — audit attention centers on the swap execution path and callback-facing surfaces
- `swapToWETH` / router interaction — recurring concern around live-price execution and weak output protection during large swaps
- `onMorphoFlashLoan` — examined as a trust boundary with potentially weak callback/input validation
- `uniswapV3SwapCallback` — examined as an external callback surface with authentication concerns
- `testExploit` — noted as a public trigger into sensitive flow, though not retained as a finding

## Issue Directions Seen
- Price manipulation / sandwich risk on treasury swaps due to reliance on manipulable live pricing and insufficient minimum-output protection
- External callback surfaces remain a recurring review direction, especially authentication and parameter validation
- Flash-loan-driven execution paths are a repeated focus because public reachability and weak validation can widen attack surface
- Persistent approvals to external contracts were flagged as a secondary direction, though not yet retained

## Useful Context
- So far, meaningful audit scope has been concentrated entirely in `DRLVaultV3.sol`
- Cross-round signal is strongest around swap execution under adversarial market conditions rather than a confirmed direct callback-drain path
- Several directions were explored but not retained; the durable pattern is weak protection at integration boundaries rather than a single isolated bug class
