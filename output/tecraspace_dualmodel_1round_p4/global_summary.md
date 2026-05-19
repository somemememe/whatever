# Global Audit Memory

## Scope Touched
- `0xe38b72d6595fd3885d1d2f770aa23e94757f91a1/Contract.sol` — sole in-scope file so far; repeated focus on ERC20 state transitions, upgrade/deprecation routing, and admin-controlled operational paths
- `burnFrom` path — recurring high-signal area around allowance indexing and destructive token-state changes
- upgrade / deprecation flow — central cross-round surface; attention on redirected canonical ERC20 behavior versus still-live legacy storage writes
- legacy `_balances` / `_allowances` mutation paths — non-canonical write surfaces that remain relevant when the contract is deprecated
- `acquire`, `permit`, blacklist / pause / role-management paths — secondary but notable areas raised for owner powers, enforcement consistency, and integration behavior

## Issue Directions Seen
- Allowance-handling mistakes in `burnFrom`, especially mismatched spender/owner indexing that can decouple the checked allowance from the victim-approved allowance
- Split-brain token state risk from upgrade/deprecation design: canonical ERC20 reads/writes may redirect while legacy balance/allowance storage can still be mutated through old paths
- Upgrade redirection as a recurring concern, including whether invalid or malicious upgrade targets can distort expected token behavior
- Consistency gaps across blacklist, pause, burn, bulk-transfer, and owner-recovery style flows remained a recurring investigative direction even when not retained
- Admin / privileged operation surfaces (`acquire`, role-management, upgrade control) drew recurring scrutiny as potential sources of non-standard balance movement or observability gaps

## Useful Context
- Audit attention has been entirely concentrated in `Contract.sol`; no broader multi-file context exists yet
- The strongest retained themes are one direct token-burn authorization flaw and one architectural legacy-ledger / upgrade split
- Cross-agent overlap was highest on upgrade/deprecation behavior; deeper single-agent probes additionally flagged `permit`, pause/blacklist coverage, and admin-event visibility as underexplored context
- The contract appears to mix standard ERC20 interfaces with bespoke admin, blacklist, recovery, and upgrade mechanics, making behavior divergence across code paths a durable audit theme
