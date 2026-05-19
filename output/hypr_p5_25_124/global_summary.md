# Global Audit Memory

## Scope Touched
- `src/universal/StandardBridge.sol`: primary audit surface across rounds; bridge auth, ERC20 custody/accounting, and finalize/deposit paths keep surfacing
- `src/L1/L1StandardBridge.sol`: tightly coupled with `StandardBridge`; initialization state and messenger trust assumptions are central
- `proxy/utils/Initializable.sol` and legacy proxy/initializer interactions: relevant where historical storage-slot handling can reopen initialization
- `src/universal/CrossDomainMessenger.sol` and `src/libraries/SafeCall.sol`: secondary attention area around relay/gas behavior and call-safety assumptions
- bridge token interfaces/implementations such as `src/universal/OptimismMintableERC20.sol`: reviewed mainly to separate mintable-token assumptions from escrowed-token risk

## Issue Directions Seen
- Reinitialization or trust-reset paths in bridge setup can cascade into cross-domain authentication failure
- Escrow accounting is sensitive to ERC20s whose actual received amount differs from the credited amount
- Bridge safety depends on stronger token-behavior assumptions than simple ERC20 compliance; post-deposit balance or transfer control changes can strand user funds
- Finalization and relay paths remain a recurring angle, especially around messenger-mediated execution and gas edge cases, though not yet producing retained cross-round findings

## Useful Context
- Audit attention has consistently converged on the L1 bridge stack, especially the `L1StandardBridge`/`StandardBridge` pair
- The strongest recurring themes are messenger trust, token collateralization, and redeemability under non-standard asset behavior
- Secondary exploration has covered messenger, proxy, and utility-library edges, but durable signal so far is concentrated in bridge initialization and asset custody semantics
