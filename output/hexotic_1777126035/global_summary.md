# Global Audit Memory

## Scope Touched
- `hex-otc.sol` — persistent audit center; offer creation/discovery, escrow, fill, settlement, cancellation, and overall state bookkeeping remain the dominant risk surface
- `hex-otc.sol:newOffer` / `offerETH` / `offerHEX` / `make` / `take` — recurring workflow entrypoints for order identity, lifecycle coupling, and bookkeeping integrity
- `hex-otc.sol:getOffer` / `offers` / `last_offer_id` / `_next_id` / `locked` — repeatedly reviewed as the order-indexing and execution-state backbone
- `hex-otc.sol:buyHEX` / `buyETH` / `cancel` — settlement/refund paths continue to matter for payout liveness, token-transfer trust, and state transitions
- `hex-otc.sol` asset-handling surface — repeated attention on escrowed vs directly received ETH/HEX and general custody edge cases
- `hex-otc.sol` token interaction surface — escrow/accounting depends on a hardcoded HEX token and standard ERC20 behavior assumptions
- `erc20.sol` — supporting interface context for transfer semantics and return-value assumptions, not a primary standalone source
- `math.sol` — peripheral supporting check only; no durable arithmetic issue direction established
- `Contract.sol` — inspected as context and appears effectively empty / low relevance as a live Solidity target

## Issue Directions Seen
- Order identity / bookkeeping mismatches between stored offers, visible IDs, and lookup paths remain a recurring lifecycle direction
- ETH settlement liveness risk from fixed-gas `transfer` persists across maker/taker/cancel payout paths, especially for contract-wallet participants
- Hardcoded HEX token / chain-context trust remains a durable integration direction, including wrong-chain or wrong-code deployment assumptions
- ERC20 interaction trust is a recurring direction: settlement/cancel logic relies on nominal `transfer` / `transferFrom` success and standard token behavior
- Escrow exactness and asset-handling edges remain active directions, especially where recorded ETH/HEX may diverge from actual balances or direct transfers bypass intended flow
- Trade lifecycle and state-change integrity remain the broadest cross-round lens, spanning offer mechanics, buy/cancel behavior, and coupled order-state transitions
- Public fillability, self-fill behavior, and event/order-state integrity were repeatedly probed around execution, though not retained as findings
- Stranded or unsolicited asset handling remains recurring custody context, secondary to lifecycle and settlement paths
- Order-id progression and overflow/wraparound were examined as bookkeeping edge cases, but without durable confirmation so far

## Useful Context
- Audit signal remains concentrated in `hex-otc.sol`; other files mostly provide interface, arithmetic, or deployment-context support
- The strongest cross-round pattern is that risk clusters around workflow integrity, settlement liveness, token trust assumptions, and custody/asset-movement edges rather than arithmetic complexity
- Creation, fill, escrow, settlement, cancel, and related state changes are tightly coupled, so identifier, payout, or token-accounting weaknesses can propagate across the full order lifecycle
- Repeated attention on order handling, fund flows, and state transitions reinforces state-model consistency as the key audit lens
- The contract’s external dependency model is simple but rigid: it assumes a specific HEX token and broadly standard ERC20 behavior without stronger code-identity or balance-delta assurances
- `math.sol` has stayed peripheral and `Contract.sol` has remained low relevance / effectively empty compared with the core trading and payment paths
