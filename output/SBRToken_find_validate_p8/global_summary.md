# Global Audit Memory

## Scope Touched
- `SBRToken.sol` — sole audited contract so far; attention centers on token balance accounting when the Uniswap pair is involved
- Uniswap pair interaction flow in `SBRToken.sol` — `skim(pair)`-driven pair self-transfer, then small `transfer(..., 1)` / `sync()` reserve update, followed by selling into WETH/ETH liquidity

## Issue Directions Seen
- Pair self-transfer can desynchronize or corrupt SBR balance accounting, potentially creating duplicate or fabricated sellable balance
- AMM-facing accounting paths are the main risk area, especially where pair balances and internal token bookkeeping can diverge
- Reserve manipulation via `sync()` appears relevant mainly as a follow-on amplifier of the same balance-inflation root cause rather than a separate issue class

## Useful Context
- Audit attention has been highly concentrated on a single exploit chain in `SBRToken.sol`; no other Solidity files or flows have yet developed durable cross-round signal
- The strongest retained pattern is balance inflation around the Uniswap pair from dust-capital setup, later realized against pool liquidity
- Drafted concerns about the dump / reserve-poisoning phase collapsed back into the same underlying accounting-break issue, so the root cause is the durable memory item
