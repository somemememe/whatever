# Global Audit Memory

## Scope Touched
- `onchain_auto/0xe7597f774fd0a15a617894dc39d45a28b97afa4f/Contract.sol`: core attention on `ACOWriter`, especially `write()`, `_sellACOTokens()`, `receive()`, and token/ETH helper paths; issue direction centers on trust boundaries, balance accounting, and ETH/WETH handling
- `onchain_auto/src/FlawVerifier.sol`: used to validate exploitability and anchor retained paths rather than as an issue source
- `ACOWriter` helper flows (`_approveERC20`, `_transferFromERC20`, `_balanceOfERC20`): relevant to untrusted-token interaction and accounting behavior, though not yet treated as standalone findings
- `onchain_auto/0xe7597f774fd0a15a617894dc39d45a28b97afa4f/_etherscan_meta.json`: metadata only, low analytical weight

## Issue Directions Seen
- Caller-controlled `acoToken` is the dominant trust-boundary concern: fake collateral/mint semantics and untrusted asset metadata can redirect or drain writer-held assets
- Caller-controlled exchange routing is a recurring loss direction: external sale targets can receive protocol ETH under weak validation
- Balance accounting is a major theme: flows appear to use whole-contract balances rather than per-operation deltas, creating cross-user/cross-trade leakage
- ETH-collateral paths remain sensitive to underfunding assumptions, allowing protocol-held ETH to subsidize writes
- ETH/WETH interoperability is fragile: `WETH.withdraw()` can be bricked by the restrictive `receive()` gate during ETH-strike flows

## Useful Context
- Cross-round focus converged heavily on `ACOWriter` entry and settlement paths rather than broad repository coverage
- The strongest retained patterns are economic/accounting and trust-boundary failures, not classic access-control issues
- Generic “public `write()`” and broad validation concerns were explored, but durable signal came from concrete asset-flow abuse paths
- Residual balances inside the writer contract are repeatedly implicated as an attack surface, both for direct forwarding and for later mis-settlement
