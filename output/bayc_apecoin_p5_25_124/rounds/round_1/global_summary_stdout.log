# Global Audit Memory

## Scope Touched
- `onchain_auto/0x025c6da5bd0e6a5dd1350fda9e3b6a614b205a1f/contracts/AirdropGrapesToken.sol` — central focus across rounds; claim-path logic, eligibility accounting, pause/admin flows, and unclaimed-token handling all concentrate here
- `claimTokens()` / `getClaimableTokenAmountAndGammaToClaim()` — repeated full-owner NFT enumeration is the main risk surface; dusting with transferable eligible NFTs points toward gas-driven claim denial
- `startClaimablePeriod()` / `pauseClaimablePeriod()` / `claimUnclaimedTokens()` — reviewed as adjacent admin lifecycle functions, but no durable issue direction retained yet
- OpenZeppelin dependencies (`ERC721.sol`, `ERC721Enumerable.sol`, `Ownable.sol`, `Pausable.sol`, `SafeERC20.sol`, `Address.sol`) — mainly relevant as semantic context for transferability, enumerable owner scans, and admin/token-transfer behavior rather than as primary issue sources

## Issue Directions Seen
- Claim-path gas/DoS from repeated `tokenOfOwnerByIndex`-style enumeration over live NFT balances is the strongest recurring direction and currently the retained high-severity pattern
- Transferable-NFT dusting as a griefing amplifier matters because eligibility is derived from current holdings, letting attackers bloat victim claim computation
- Economic edge cases were explored around temporary-holder eligibility capture, underfunded first-come-first-served distribution, and fee-on-transfer / non-standard token payout mismatch, but these did not remain durable findings
- Admin-control and observability themes (`pause` behavior, event coverage) surfaced briefly but have not shown strong exploit traction compared with the claim-scaling issue

## Useful Context
- Cross-agent attention heavily converges on `AirdropGrapesToken.sol`; most meaningful risk appears to come from how business logic composes with enumerable ERC721 ownership scans
- The core pattern is scalability failure in user claims, not an isolated micro-optimization concern: repeated balance-wide iteration appears in both claim execution and claimable-amount calculation paths
- Imported OZ contracts were mainly inspected to confirm transfer semantics and enumeration behavior supporting the dusting/griefing model
- Round-1 durable outcome is a single merged root cause: live-balance-based, repeatedly enumerated claim eligibility can make claims unscalable or effectively unclaimable within the claim window
