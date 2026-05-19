# Global Audit Memory

## Scope Touched
- `LeverageSIR.sol` — core attention stays on the exploit chain spanning `initialize`, `mint`, CREATE2 market deployment, and `uniswapV3SwapCallback`
- Vault/bootstrap flow — initialization appears permissionless enough to let an attacker bind funded vault state to attacker-chosen market parameters
- Mint/callback bridge — untrusted token-return data may be reused as privileged transient state and then consumed by the swap callback path

## Issue Directions Seen
- Attacker-controlled initialization of a funded vault via fabricated or attacker-shaped Uniswap market setup
- Privileged transient-state poisoning during `mint`, especially where external token behavior influences later trusted callback context
- Crafted or forged `uniswapV3SwapCallback` execution paths that can redirect settlement logic and drain arbitrary vault-held assets
- These directions are linked and should be viewed as one exploit family rather than isolated bugs

## Useful Context
- Audit attention so far has been concentrated almost entirely in `LeverageSIR.sol`; no separate high-signal auxiliary file has emerged yet
- The strongest retained pattern is a chained exploit: permissive setup -> poisoned transient state -> callback-driven asset drain
- A narrower callback-settlement-token concern was explored but effectively folds into the broader callback-drain direction rather than standing alone
