# Round 1 Summary

## Agent: codex
- files touched: `hex-otc.sol`, `erc20.sol`, `math.sol`, `Contract.sol`
- files revisited / highest-attention files: `hex-otc.sol` was read in full and revisited for function/transfer searches; `erc20.sol` was checked for token interface behavior; `Contract.sol` was briefly inspected as a placeholder/blob
- main issue directions investigated: offer creation / ID propagation around `newOffer`, `offerETH`, `offerHEX`, and `make`; ETH settlement and refund paths using `transfer` in `buyHEX`, `buyETH`, and `cancel`; token interaction assumptions around the hardcoded HEX address and transfer semantics
- promising but not retained directions: wrong-network / hardcoded token address trust at `hexAddress`; lack of balance-delta checks for non-exact ERC20 behavior; `Contract.sol` was examined but did not produce a retained issue

## Cross-Agent Status
- main overlap in file/area attention: only one agent logged this round; attention centered overwhelmingly on `hex-otc.sol`, especially order creation, settlement, and cancellation paths
- notable differences in attention: no cross-agent differences available this round
- underexplored but suspicious files/functions if clearly supported by the logs: `math.sol` and `erc20.sol` were only lightly reviewed; within `hex-otc.sol`, the hardcoded token-address trust assumption and non-exact token transfer behavior were investigated but not retained

## Retained Findings
- retained issue 1: order creation stores offers under a real internal ID while public returns/events expose `0`, breaking normal order discovery, fill, and cancel workflows
- retained issue 2: ETH payouts rely on Solidity `transfer`, allowing contract-wallet participants to make ETH-backed orders unfillable or unwithdrawable through revert-on-receive behavior
