# Global Audit Memory

## Scope Touched
- `onchain_auto/0xeac2a259f3ebb8fd1097aeccaa62e73b6e43d5bf/contracts/SchnoodleV9.sol` — central surface for bridge mint/burn flows, transfer gating, maintenance powers, and farming-linked liveness
- `onchain_auto/0xeac2a259f3ebb8fd1097aeccaa62e73b6e43d5bf/contracts/imports/SchnoodleV9Base.sol` — recurring attention on fee/tokenomics internals and transfer-side state interactions
- `onchain_auto/0xeac2a259f3ebb8fd1097aeccaa62e73b6e43d5bf/@schnoodle/contracts-upgradeable/access/{OwnableUpgradeable.sol,AccessControlUpgradeable.sol}` — ownership/admin-role split and post-handoff residual authority matter
- `onchain_auto/0xeac2a259f3ebb8fd1097aeccaa62e73b6e43d5bf/@schnoodle/contracts-upgradeable/proxy/utils/Initializable.sol` and nearby upgrade surfaces — reviewed mainly for upgrade/authorization context, with no retained core issue yet
- ERC777/base-token paths, especially `.../token/ERC777/ERC777Upgradeable.sol` — supporting context for transfer-hook and token behavior analysis
- Test/proxy code such as `0xd45740ab9ec920bedbd9bab2e863519e59731941/contracts/test/Proxiable.sol` — seen once as suspicious but not a retained audit direction

## Issue Directions Seen
- Bridge accounting/authentication is the strongest recurring direction: destination-side minting appears insufficiently tied to an originating burn/consume record
- Ownership and access control are materially split: `owner` transitions do not imply cleanup of `DEFAULT_ADMIN_ROLE` powers
- Core token operations are coupled to an external farming contract, creating a recurring liveness/freeze dependency for ordinary transfers and burns
- Administrative maintenance logic includes a hardcoded confiscation/seizure path against specific holder addresses
- Reconfiguration of farming via repeated `configure(true, ...)` suggests privilege residue and stranded reserve state across old/new farming contracts
- Transfer/fee/base-token mechanics in `SchnoodleV9Base.sol` remain a secondary but repeatedly examined area, even where individual claims were not retained

## Useful Context
- Cross-round attention heavily converges on `SchnoodleV9.sol`; most retained risk comes from privileged flows and external dependency wiring rather than isolated arithmetic bugs
- The audit repeatedly distinguishes retained structural issues from many one-off hypotheses around fee precision, validation inversions, reentrancy, and test-only proxy code
- Access-control review should keep tracking both explicit ownership and role-based authority, since prior owner powers can persist after apparent handoff
- Farming integration is not just an auxiliary feature; it sits on the critical path of token usability and privilege management
- Underexplored context remains around unevenly reviewed base-contract internals and adjacent upgrade/test surfaces, but these are currently weaker directions than the retained bridge/admin/farming themes
