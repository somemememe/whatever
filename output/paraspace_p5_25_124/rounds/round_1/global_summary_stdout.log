# Global Audit Memory

## Scope Touched
- `LiquidationLogic.sol`: central hotspot; ERC721 liquidation path and liquidation math/debt-asset coupling drew repeated scrutiny
- `ValidationLogic.sol`: core gatekeeping surface; borrow-path enforcement gaps and ERC721 supply validation behavior both matter
- `BorrowLogic.sol` / `SupplyLogic.sol`: recurring edge-path review around borrow, repay, and NFT supply flows; tightly coupled to validation assumptions
- `GenericLogic.sol` / `Helpers.sol`: collateral and debt-accounting helpers looked important for downstream correctness, though concerns were not retained
- `UserConfiguration.sol` / `ReserveConfiguration.sol` / `Errors.sol`: supporting config/error machinery shows intended controls, especially around siloed borrowing
- `MarketplaceLogic.sol` / `FlashClaimLogic.sol`: underexplored but previously suspicious for reentrancy-style flow risks
- `ParaProxy.sol` / `ParaProxyLib.sol`: upgradeability/initialization received some attention, but not as a mainline issue direction
- `ERC721.sol` and nToken-linked NFT supply flow: standard `ownerOf` behavior is relevant to protocol assumptions in `supplyERC721FromNToken`

## Issue Directions Seen
- Missing enforcement of intended siloed-borrowing restrictions despite existing state/config plumbing
- Liquidation flow risk from weak binding between the repaid debt asset and collateral seizure path, especially for ERC721 collateral
- NFT supply / transfer paths depend on ownership assumptions that can break against standard ERC721 semantics
- Core math/accounting helpers are a recurring place to look for collateral, debt, and liquidation inconsistencies
- Reentrancy and ordering concerns appeared around marketplace and flash-claim related flows, but remain unconfirmed

## Useful Context
- Cross-round attention concentrated on core protocol logic rather than isolated integrations
- `LiquidationLogic.sol`, `ValidationLogic.sol`, `BorrowLogic.sol`, and `SupplyLogic.sol` form the main cluster and should be read together
- Several suspicious directions came from helper-layer logic (`GenericLogic.sol`, `Helpers.sol`) that influences many user-facing flows even when no finding was retained
- Configuration/error definitions can expose intended invariants that implementation paths fail to enforce
- Underexplored surfaces with some signal remain `MarketplaceLogic.sol`, `FlashClaimLogic.sol`, `Helpers.sol`, and `GenericLogic.sol`
