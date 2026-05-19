# Global Audit Memory

## Scope Touched
- `0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol` — persistent center of audit attention; issues cluster around initialization, commitment paths, settlement/finalization, and proceeds routing
- `0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Access/MISOAdminAccess.sol` — relevant for admin authority assumptions and takeover/control surfaces tied to auction setup
- `0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Utils/BoringBatchable.sol` — important because batching/delegatecall semantics interact with ETH accounting in auction entrypoints
- `0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Utils/SafeTransfer.sol` — reviewed as supporting transfer primitive, but so far secondary to core auction logic
- `0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/interfaces/IERC20.sol` — relevant mainly for token-behavior assumptions behind accounting and transfer edge cases

## Issue Directions Seen
- Initialization of uninitialized auction instances is a recurring high-value control-risk direction, especially where first caller can seize admin or proceeds influence
- ETH commitment logic remains a key surface, particularly where batching/delegatecall can reuse call value across multiple subcalls
- Token accounting vs actual received balances is a durable concern for funding and bidding flows, especially with fee-on-transfer or otherwise non-standard ERC20 behavior
- Admin-controlled proceeds routing is a repeated trust/control theme, including the ability to redirect auction wallet after user commitments
- Secondary but not yet retained directions included reentrancy coverage gaps, price/math edge cases, transfer-mechanic assumptions, and helper/interface mismatch risks

## Useful Context
- Cross-round attention is heavily concentrated in `DutchAuction.sol`; helper contracts matter mainly insofar as they change assumptions of that auction flow
- The strongest patterns so far are not isolated arithmetic bugs but mismatches between intended auction invariants and actual call/value/token movement semantics
- Admin power boundaries and initialization state are central context for interpreting several otherwise separate issues
- Multiple agents reviewed all in-scope Solidity files, but durable signal remains much stronger in auction lifecycle and proceeds/accounting paths than in peripheral helpers
