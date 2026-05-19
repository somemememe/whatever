# Round 1 Summary

## Agent: codex_1
- files touched: `0x9dcb6bc351ab416f35aeab1351776e2ad295abc4/Contract.sol`, `0x5fdbcd61bc9bd4b6d3fd1f49a5d253165ea11750/contracts/OErc20Delegator.sol`; scope inventory also covered the remaining in-scope Solidity files
- files revisited / highest-attention files: `Contract.sol` received the main attention, especially exchange-rate, mint/redeem, liquidation, and token-sweep logic; `OErc20Delegator.sol` was checked for externally exposed implementation functions
- main issue directions investigated: exchange-rate manipulation from direct underlying transfers, zero-supply/reset accounting, zero-decimal collateral liquidation branching, and unrestricted `sweepToken` exposure through the delegator
- promising but not retained directions: no additional non-retained line of inquiry is clearly visible in the log beyond the retained findings

## Agent: opencode_1
- files touched: all six in-scope Solidity files, with explicit reads of `Contract.sol`, `ComptrollerInterface.sol`, `EIP20NonStandardInterface.sol`, `InterestRateModel.sol`, `OErc20Delegator.sol`, and `OTokenInterfaces.sol`
- files revisited / highest-attention files: `0x9dcb6bc351ab416f35aeab1351776e2ad295abc4/Contract.sol` was revisited multiple times and was the clear focus
- main issue directions investigated: liquidation behavior for zero-decimal / ERC721-style collateral, proxy implementation safety in `OErc20Delegator`, initialization and reserve-factor parameter bounds, token sweep behavior, transfer handling, and delegatecall/storage risks
- promising but not retained directions: implementation validation in `_setImplementation`, initial exchange-rate upper-bound concerns, 100% reserve-factor configuration, `doTransferOut`/nonstandard ERC20 handling, borrow-rate-model griefing, and generic delegatecall/storage-collision concerns

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `Contract.sol`; the clearest overlap was around liquidation branching and `sweepToken`, with shared attention also on the delegator exposure of market functions
- notable differences in attention: `codex_1` focused on core market accounting and share-price invariants; `opencode_1` spent more attention on proxy upgrade surfaces, admin/configuration bounds, and transfer plumbing
- underexplored but suspicious files/functions if clearly supported by the logs: `OErc20Delegator._setImplementation` and the transfer plumbing in `Contract.sol` were touched, but the round’s retained conclusions were much stronger around accounting and liquidation than around those surfaces

## Retained Findings
- direct underlying donations can distort the market exchange rate enough for later minters to receive zero shares while still transferring assets in
- if `totalSupply` returns to zero while underlying remains stranded, the next minter can acquire that residual value at the initial exchange rate
- liquidation logic treats any zero-decimal collateral market as NFT-style collateral, creating a misclassification risk for fungible zero-decimal markets
- `sweepToken` is externally triggerable for non-underlying tokens, so any account can force those balances to be sent to the market admin
