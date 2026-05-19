# Global Audit Memory

## Scope Touched
- `0x9dcb6bc351ab416f35aeab1351776e2ad295abc4/Contract.sol` - primary audit focus; core market accounting, exchange-rate behavior, mint/redeem edge cases, liquidation branching, transfer plumbing, and token sweeping
- `0x5fdbcd61bc9bd4b6d3fd1f49a5d253165ea11750/contracts/OErc20Delegator.sol` - proxy/delegator exposure and implementation-surface review, especially externally reachable market functions and `_setImplementation`
- `ComptrollerInterface.sol`, `EIP20NonStandardInterface.sol`, `InterestRateModel.sol`, `OTokenInterfaces.sol` - supporting interface/model context; mainly used to reason about liquidation, transfer handling, and config assumptions

## Issue Directions Seen
- Exchange-rate/accounting manipulation from direct underlying transfers or residual underlying not reflected in share supply
- Zero-supply reset paths where stranded assets remain and later minting reclaims value at the initial exchange rate
- Liquidation branching assumptions around zero-decimal collateral, with fungible-vs-NFT style misclassification risk
- Externally triggerable `sweepToken` behavior for non-underlying assets
- Secondary but less-confirmed directions: proxy implementation validation, reserve/init parameter bounds, and nonstandard ERC20 transfer behavior

## Useful Context
- Cross-round attention is concentrated much more on `Contract.sol` than the peripheral files
- The strongest recurring theme is broken value accounting at market edges: minting, redemption, liquidation, and token custody/sweeping
- `OErc20Delegator` has mattered mainly as an exposure layer for market functionality rather than for a clearly established delegatecall/storage-collision issue
- Transfer-plumbing and admin/configuration surfaces were explored, but the durable audit signal so far is stronger around accounting and liquidation behavior than around upgrade mechanics
