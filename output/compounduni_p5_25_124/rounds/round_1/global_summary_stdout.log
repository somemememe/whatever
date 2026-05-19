# Global Audit Memory

## Scope Touched
- `UniswapAnchoredView.sol`: dominant audit surface; oracle-selection/failover logic, anchor math, reporter freshness, and initialization behavior keep recurring
- `UniswapConfig.sol`: configuration integrity remains relevant, especially market/pool lookup correctness and duplicate-key shadowing risk
- `UniswapLib.sol`: supporting oracle/TWAP math library touched but still less explored than the main oracle flow
- `AggregatorValidatorInterface.sol`: validator path was inspected lightly around `validate()` behavior, without sustained follow-through yet
- `Ownable.sol`: read during scope review, but no durable issue direction beyond general control-surface awareness

## Issue Directions Seen
- Failover paths can effectively make Uniswap TWAP the active price source, so oracle fallback behavior is a recurring manipulation/correctness direction
- Anchor/TWAP math is a repeated pressure point, including extreme-value overflow/DoS and boundary/precision edge cases
- Reporter-side correctness remains a theme: initialization defaults and missing freshness tracking can allow invalid or stale prices to persist
- Configuration trust assumptions are a standing concern, especially whether anchor pools/market mappings are authentic, unique, and non-shadowed
- Most retained attention clusters around the Uniswap/Chainlink bridge rather than peripheral access-control or interface code

## Useful Context
- Cross-agent attention strongly converged on `UniswapAnchoredView.sol`; other files were mostly secondary and underexplored
- The durable audit shape so far is oracle correctness plus config safety, not isolated implementation bugs in helper contracts
- Several lower-confidence edge cases were explored, but the stable cross-round signal is concentrated in failover behavior, stale/initial price handling, anchor math robustness, and config integrity
