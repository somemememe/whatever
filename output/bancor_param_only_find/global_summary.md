# Global Audit Memory

## Scope Touched
- `onchain/0x5f58058c0ec971492166763c8c22632b583f667f/Contract.sol` — core attention remains on `TokenHandler`, `convertByPath`, `completeXConversion`, source-token pull mechanics, and conversion-step / beneficiary routing
- Conversion path + converter resolution flow — repeated scrutiny on trust in user-supplied paths and converter derivation through `anchor.owner()`
- BancorX completion path — repeated focus on where source funds are actually sourced during cross-chain completion
- ERC20 / ETH handling helpers — attention on low-level `transfer` / `transferFrom` / `approve` behavior and ETH-sentinel / ether-token entry handling

## Issue Directions Seen
- Trust boundaries around user-controlled conversion paths and converter lookup are a primary recurring direction
- Source-of-funds accounting in `completeXConversion` / BancorX-style completion flow is a persistent investigation area
- Token helper correctness remains a standing direction, especially around nonstandard ERC20 behavior and low-level call assumptions
- Beneficiary assignment and converter-version branching have been reviewed as secondary directions, but with less sustained signal so far

## Useful Context
- Audit attention is concentrated in a single large `Contract.sol` entrypoint-style contract rather than spread across multiple files
- Cross-round durable hotspots are path validation, conversion execution routing, and token-movement semantics rather than isolated arithmetic or storage issues
- Legacy-vs-new converter branching exists and has drawn some review, mainly where it affects beneficiary handling and conversion flow behavior
- No retained findings yet; current memory is mainly about high-friction trust and asset-flow surfaces within the conversion pipeline
