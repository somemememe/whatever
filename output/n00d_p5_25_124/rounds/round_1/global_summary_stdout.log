# Global Audit Memory

## Scope Touched
- `onchain_auto/0x2321537fd8ef4644bacdceec54e5f35bf44311fa/Contract.sol`: primary audit focus; ERC777 token logic with repeated attention on constructor-set `defaultOperators`, `transfer`/`transferFrom`, `_send`, `_burn`, and operator/hook execution order
- `onchain_auto/src/FlawVerifier.sol`: referenced as related to retained reentrancy evidence, but appears underexplored in direct audit coverage
- Deployment inputs / live config: constructor-provided `defaultOperators` remain a key unresolved scope item because risk depends on whether the live deployment used a non-empty list

## Issue Directions Seen
- ERC777 default-operator authority as a likely high-impact direction, especially deployment-time operator configuration creating broad transfer/burn power
- ERC20-shaped entrypoints masking ERC777 behavior, with `transfer`/`transferFrom` still invoking ERC777 hooks and preserving callback/reentrancy exposure for ERC20-style integrators
- Pre-state hook execution order in `_send` and `_burn`, especially sender-side hooks running before balance updates and enabling reentrancy against pull/burn integrations
- Recurring but currently unretained direction around hook-driven transfer blocking or token stranding when recipient expectations and ERC777 acknowledgement paths diverge
- Lower-confidence side directions explored but not retained: approval race patterns, inheritance-based mint expansion, and ERC1820 registry dependence / chain-compatibility risk

## Useful Context
- Cross-round attention is concentrated almost entirely on a single token contract; the main stable pattern is ERC777 semantics hidden behind ERC20-like surfaces
- The audit repeatedly distinguishes deployment-configuration risk from pure code-path risk: some highest-impact outcomes depend on live constructor values rather than source alone
- Reentrancy concern is not limited to recipient callbacks; sender hooks before debits are a separate recurring theme
- Underexplored areas are the verifier/demo contract and any source of truth for actual deployed `defaultOperators` values
