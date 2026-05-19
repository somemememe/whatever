# Global Audit Memory

## Scope Touched
- `onchain_auto/0xeda47e13fd1192e32226753dc2261c4a14908fb7/Contract.sol`: primary focus so far; constructor/pair setup, `_transfer`, swapback path, reflection math (`_getValues`, `_getRValues`, `_reflectFee`, `_takeTeam`), and fee-wallet forwarding are the recurring high-signal areas
- Reflection supply helpers (`_getCurrentSupply()`, `_getRate()`, `_excluded` handling): received some scrutiny for possible gas/supply-accounting edge cases, but not yet sustained as a merged issue direction

## Issue Directions Seen
- Reflection-accounting invariants are a central risk area, especially fee handling mismatches between reflected and token-denominated amounts
- Uniswap pair participation in reflections is a recurring direction, with LP balance drift / skim-style extraction risk
- Publicly triggerable swapback mechanics remain a strong economic-risk direction, especially threshold-triggered sells with no output floor
- Fee-distribution payout design is a recurring operational-risk area, particularly swapback liveness dependence on wallet compatibility
- Gas-bricking or accounting distortion through exclusion-list / supply-rate logic was explored but remains lower-confidence than the confirmed reflection-path issues

## Useful Context
- Audit attention is heavily concentrated in a single token contract with intertwined reflection, AMM-pair, and swapback behavior
- The durable cross-round pattern is that reflection bugs do not stay isolated: they couple into LP state, swapback extraction, and treasury-value leakage
- Swapback is both an economic and availability surface in this codebase: trigger conditions, execution pricing, and downstream ETH forwarding all matter together
- Pair setup and exclusion configuration are important because small initialization choices materially affect downstream reflection and liquidity behavior
