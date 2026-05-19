# Global Audit Memory

## Scope Touched
- `Bybit.sol` — sole file examined across rounds; review remains concentrated on the exploit/takeover path rather than broader surrounding logic
- Wallet signature/transaction helpers in `Bybit.sol` — recurring authorization hotspot, especially where signed execution can package misleading or reusable approvals
- Proxy execution / `DelegateCall` path in `Bybit.sol` — repeatedly treated as the bridge from signed wallet actions into privileged code execution
- `changeMasterCopy()` / implementation-switch surface in `Bybit.sol` — persistent trust-boundary crossing and takeover focus
- Trojan/helper-contract region in `Bybit.sol` — examined as the storage-collision / slot-overwrite leg of the exploit chain
- Backdoor sweep logic in `Bybit.sol` — recurring drain surface once execution or implementation control is redirected

## Issue Directions Seen
- Privileged control repeatedly centers on signature-authorized wallet execution, with concern around deceptive calldata packaging, replayability, or embedded approvals
- Delegatecall-enabled execution remains the clearest takeover direction, especially when it can reach implementation-switch logic
- Storage collision or slot-0 overwrite is a standing exploit direction when paired with delegatecall or helper-contract execution
- Implementation replacement followed by unrestricted ETH/ERC20 sweeping is the recurring end-to-end exploit model
- Hardcoded or precomputed authorization material remains a background suspicion area, though not a durable finding direction so far

## Useful Context
- Audit context is still entirely single-file: only `Bybit.sol` has contributed meaningful review context
- Cross-round work converges on one exploit chain viewed from multiple angles: signed execution, delegatecall transition, implementation overwrite/replacement, then sweeping funds
- Highest review density is around the labeled exploit path, helper contracts, and transaction/signature plumbing; broader contract behavior remains comparatively underexplored
- No retained findings exist yet; the durable value is the repeated convergence on takeover mechanics and privileged execution boundaries rather than broad surface coverage
