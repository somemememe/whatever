# Global Audit Memory

## Scope Touched
- `0xe7597f774fd0a15a617894dc39d45a28b97afa4f/Contract.sol` — audit attention centers on the `write` → `_sellACOTokens` flow, `receive()`, and internal ERC20 helper interactions
- `write` / `_sellACOTokens` path — repeated concerns around option minting vs sale source, premium accounting, and payout/refund handling
- `receive()` + WETH/ETH handling — ETH acceptance rules interact dangerously with unwrap and final payout behavior
- caller-supplied `acoToken` boundary — token metadata and asset-selection trust assumptions are a primary attack surface

## Issue Directions Seen
- ETH-strike settlement is fragile: WETH unwrap delivery conflicts with the contract’s restricted `receive()` path
- Asset accounting repeatedly depends on whole-contract balances, creating leftover-balance leakage/drain risk across calls
- Caller-controlled `acoToken` parameters appear able to influence which existing assets get moved or sold
- The intended write-and-sell lifecycle looks internally inconsistent: minted options are delivered to the user while sale logic sources from the writer/contract side
- ETH payout/refund mechanics are brittle, including `transfer`-based recipient assumptions and broader ERC20/ETH edge-case handling
- Generic directions like reentrancy, SafeMath, and plain `msg.value` validation were explored, but the durable signal is concentrated in flow/accounting and trust-boundary issues

## Useful Context
- Audit activity so far is concentrated almost entirely in this single contract rather than spread across multiple files
- Cross-agent overlap is strongest on concrete accounting and payout paths, especially around premium delivery and sale mechanics
- Low-level ERC20 helper behavior matters mainly through the `acoToken` trust boundary and asset-movement side effects, not as a standalone library concern
- The most durable pattern is mismatch between intended economic flow and actual token/ETH movement under edge conditions or residual balances
