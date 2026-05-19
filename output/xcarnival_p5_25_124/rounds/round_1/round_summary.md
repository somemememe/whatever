# Round 1 Summary

## Agent: codex_1
- files touched: scoped Solidity inventory via glob/listing; deep read of `0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol`
- files revisited / highest-attention files: `0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol`
- main issue directions investigated: pledge/deposit type handling for CryptoPunks wrapping; liquidation/auction settlement flows; ETH payout/refund mechanics; airdrop routing during active auctions; admin withdrawal/claim powers over escrowed assets
- promising but not retained directions: no distinct discarded hypothesis is clearly visible in the log beyond broader tracing of liquidation, airdrop, and admin-control paths inside `XNFT.sol`

## Agent: opencode_1
- files touched: `0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol`, `0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/interface/IXToken.sol`, `0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/interface/IP2Controller.sol`, `0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/interface/IInterestRateModel.sol`, `0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/interface/IERC20.sol`, `0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/interface/IPunks.sol`, `0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/interface/IWrappedPunks.sol`, `0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/interface/IXAirDrop.sol`
- files revisited / highest-attention files: `0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol`
- main issue directions investigated: airdrop and admin-controlled external-call surfaces; liquidation/repay callbacks; admin mutation of dependency addresses; auction mechanics and payout behavior; token transfer/accounting assumptions
- promising but not retained directions: malicious `xAirDrop` / `setXAirDrop` theft framing, reentrancy claims on `notifyOrderLiquidated()` and `notifyRepayBorrow()`, `setPunks()` abuse, auction pricing/fairness concerns, `batchAirDrop()` openness, and smaller precision/gas/configuration concerns

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated heavily on `0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol`, especially auction/liquidation settlement, airdrop handling, and admin escape hatches
- notable differences in attention: `codex_1` stayed focused on concrete asset-flow breakage and escrow-drain paths; `opencode_1` spent more attention on admin-configurable airdrop dependencies, reentrancy hypotheses, and economic/configuration issues
- underexplored but suspicious files/functions if clearly supported by the logs: `notifyRepayBorrow()` and its controller/xToken integration remain comparatively lightly evidenced in the logs despite a retained lower-confidence concern; most non-`XNFT.sol` files were only touched as interfaces

## Retained Findings
- CryptoPunks wrapping can preserve a caller-controlled wrong `nftType`, causing wrapped ERC721 collateral to be treated as ERC1155 and become permanently stuck
- ETH settlement/refund paths rely on `transfer`, so hostile contract recipients can block outbids, redemption, or final withdrawal flows
- During active liquidation auctions, airdrop proceeds can still be routed to the defaulted borrower instead of the economically exposed party
- Admin `withdraw()` can sweep balances that include user escrow, not just tracked protocol income
- Admin `claim()` is an unrestricted arbitrary-call surface that can move escrowed NFTs or tokens out of the protocol
- A lower-confidence repayment-path concern remains around `notifyRepayBorrow()` using `tx.origin`, which may interfere with contract-wallet or third-party repayment flows
