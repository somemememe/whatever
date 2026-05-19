# Global Audit Memory

## Scope Touched
- `src/swappers/ZeroXStargateLPSwapper.sol`: primary audit focus so far; trust boundary around permissionless `swap()`, caller-chosen recipient / calldata, and whole-balance accounting is the main issue surface
- `src/libraries/SafeApprove.sol`: relevant to approval lifecycle and unlimited-allowance behavior used by the swapper path
- `src/interfaces/IStargateRouter.sol`, `src/interfaces/IStargatePool.sol`: matter for redeem flow assumptions, especially `instantRedeemLocal` approval / allowance expectations
- `src/interfaces/ISwapperV2.sol`: useful for intended swapper role and permission model context
- `lib/BoringSolidity/contracts/libraries/BoringERC20.sol`: supporting token-transfer / approval helper context around the swapper flow

## Issue Directions Seen
- Swap flow lets caller influence external 0x execution while the contract holds protocol-owned assets and approvals
- Permissionless swapper entrypoints interacting with contract-held BentoBox shares or token balances are a recurring risk direction
- Whole-balance redeem / deposit logic can accidentally incorporate pre-existing stray balances into the active caller’s flow
- Approval assumptions around Stargate redeem paths remain a live but unresolved direction

## Useful Context
- Cross-round attention is heavily concentrated on the Stargate LP swapper; most other scoped files have only light coverage
- Durable concern is not one isolated line but the combination of caller control, external swap execution, persistent approvals, and contract-balance reuse in a single path
- Retained findings so far both originate from the same swapper flow: asset redirection via unchecked external swap calldata and sweeping of any assets left parked on the swapper
- Interface and helper files have mainly served as support for understanding the swapper’s accounting and approval model rather than as independent issue hotspots
