You are auditing the smart contracts in /Users/lu/Desktop/Red_V1G/2025-05-dodo-cross-chain-dex/omni-chain-contracts/contracts.

## Contracts in Scope

# Scope

- GatewayCrossChain.sol:GatewayCrossChain (634 LOC) — TODO
- GatewayCrossChain.sol:address (634 LOC) — TODO
- GatewaySend.sol:GatewaySend (409 LOC) — TODO
- GatewaySend.sol:address (409 LOC) — TODO
- GatewayTransferNative.sol:GatewayTransferNative (705 LOC) — TODO
- GatewayTransferNative.sol:address (705 LOC) — TODO
- GatewayTransferNative.sol:is (705 LOC) — TODO
- interfaces/IDODORouteProxy.sol:IDODORouteProxy (19 LOC) — TODO
- interfaces/IUniswapV2Factory.sol:IUniswapV2Factory (18 LOC) — TODO
- interfaces/IUniswapV2Router01.sol:IUniswapV2Router01 (96 LOC) — TODO
- interfaces/IWETH9.sol:IWETH9 (30 LOC) — TODO
- interfaces/IZRC20.sol:IZRC20 (11 LOC) — TODO
- libraries/AccountEncoder.sol:AccountEncoder (54 LOC) — TODO
- libraries/BytesHelperLib.sol:BytesHelperLib (41 LOC) — TODO
- libraries/SafeMath.sol:for (17 LOC) — TODO
- libraries/SafeMath.sol:SafeMath (17 LOC) — TODO
- libraries/SwapDataHelperLib.sol:SwapDataHelperLib (273 LOC) — TODO
- libraries/TransferHelper.sol:TransferHelper (28 LOC) — TODO
- libraries/UniswapV2Library.sol:UniswapV2Library (95 LOC) — TODO
- mocks/DODORouteProxyMock.sol:DODORouteProxyMock (103 LOC) — TODO
- mocks/ERC20Mock.sol:ERC20Mock (22 LOC) — TODO
- mocks/GatewayEVMMock.sol:GatewayEVMMock (131 LOC) — TODO
- mocks/GatewayZEVMMock.sol:GatewayZEVMMock (79 LOC) — TODO
- mocks/ZRC20Mock.sol:ZRC20Mock (40 LOC) — TODO

# Notes

- Auto-generated contract-level map.
- Descriptions are placeholders and can be edited later.


## Known Findings (do NOT repeat — find NEW issues)

- C-001: Cross-chain handlers trust unbound token and swap metadata, enabling withdrawals of unrelated contract-held assets (High, high)
- F-002: Refund metadata truncates non-EVM recipients to 20 bytes and misdirects failed native withdrawals (High, high)
- F-005: GatewayTransferNative refund claims are reentrant and can be claimed multiple times before state deletion (Medium, high)
- F-006: Fee-on-transfer tokens are over-credited, letting callers spend prior balances held by the contracts (Medium, medium)

## Task

Find security vulnerabilities in the contracts listed above.

You should look for:
- direct vulnerabilities
- low-confidence but still reportable issues
- issues that only become clear after connecting multiple observations

If you identify a problem that is not fully proven, still report it as a low-confidence finding.

## Output Format

Return ONLY a JSON array.

Each element must have:
- `id`: local finding id such as `F-001`
- `severity`: `Critical` / `High` / `Medium` / `Low` / `Informational`
- `confidence`: `high` / `medium` / `low`
- `title`: one-line summary
- `locations`: array of `file:line`
- `claim`: core mechanism statement
- `impact`: why it matters
- `paths`: array of trigger/exploit paths, may be empty

If there are no findings, return `[]`.
