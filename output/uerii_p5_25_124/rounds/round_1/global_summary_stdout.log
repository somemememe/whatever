# Global Audit Memory

## Scope Touched
- `onchain_auto/0x418c24191ae947a78c99fdc0e45a1f96afb254be/Contract.sol` - audit attention has centered on the custom ERC20 tail, especially `constructor`, `mint()`, `decimals()`, and related `_mint` supply behavior
- `onchain_auto/src/FlawVerifier.sol` - surfaced during path discovery but has not been meaningfully audited yet

## Issue Directions Seen
- Unrestricted public `mint()` enabling arbitrary self-minting and supply inflation is the clearest issue direction seen so far
- Supply-scaling and denomination consistency around the 6-decimal override versus hard-coded mint amounts was investigated as a secondary direction, but has not held up as a retained issue
- Broader checks of inherited ERC20 logic did not surface a distinct separate root cause beyond the custom mint/supply configuration

## Useful Context
- Cross-round attention has been heavily concentrated in a single hotspot: the custom token logic in `Contract.sol`
- The accepted issue is economic/inflationary rather than a deeper flaw in standard ERC20 internals
- Audit coverage so far has been narrow, with no clearly supported second file hotspot emerging from the logs
