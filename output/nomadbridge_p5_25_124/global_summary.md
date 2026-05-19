# Global Audit Memory

## Scope Touched
- `Replica.sol` / `NomadBase.sol`: primary audit surface so far; repeated focus on root update, proof validation, message processing, and execution state transitions
- `Message.sol` / `TypeCasts.sol`: message-format and address-casting logic matter for downstream dispatch correctness, including recipient-encoding/truncation risk
- `UpgradeBeaconProxy.sol`: initialization path is a durable concern; proxy setup safety and takeover exposure were a confirmed direction
- `Merkle.sol`: reviewed as supporting proof/root infrastructure tied to `Replica` validation flow
- `Version0.sol` / `IMessageRecipient.sol`: relevant to initialization behavior and recipient dispatch semantics
- Supporting libraries (`ECDSA.sol`, `Address.sol`, `OwnableUpgradeable.sol`): mainly contextual for signature recovery, call behavior, and ownership assumptions around the core flow

## Issue Directions Seen
- Proxy/beacon initialization safety around uninitialized deployments and setup-time control capture
- Updater-signature domain binding and replay scope across deployments with shared configuration
- Message recipient encoding/casting mismatches causing dispatch to an unintended address
- Broad `Replica` verification/execution lifecycle review: proof reuse, message processing states, and root acceptance timing/control remain recurring audit themes
- Governance / updater trust and operational misconfiguration were repeatedly considered, though many variants were not retained

## Useful Context
- Cross-round attention is heavily concentrated on `Replica`-centric execution paths, with `NomadBase` as the main companion contract
- The most durable retained risks so far combine initialization, signature-domain separation, and message-address interpretation rather than deep cryptographic flaws in Merkle verification itself
- `Message.sol` and `TypeCasts.sol` are important because small encoding assumptions propagate directly into cross-chain delivery behavior
- Several hypothesized issues clustered around misconfiguration or edge-state handling; even when not retained, they suggest the audit has repeatedly found sensitivity to setup parameters and lifecycle transitions
