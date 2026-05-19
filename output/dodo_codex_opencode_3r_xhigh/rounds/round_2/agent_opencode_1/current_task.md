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

- F-001: Bridged input, swap output, and settlement asset are never bound, enabling theft of resident balances (High, high)
- F-002: GatewaySend traps native-ETH refunds by treating asset == address(0) as an ERC20 (High, high)
- F-003: Dusting the deterministic pair address can force a nonexistent Uniswap route (Medium, high)
- F-004: Solana account decompression builds an invalid Account[] and corrupts outbound payloads (Medium, high)
- F-005: GatewayTransferNative refund claims stay reentrant until after the external token transfer (Low, medium)
- F-006: GatewaySend.onCall pays out resident balances based on untrusted payload fields (High, high)
- F-007: Failed Bitcoin withdrawals refund to an EVM address derived from the BTC recipient bytes (High, high)
- F-008: GatewayTransferNative rejects valid gas swaps by comparing against amountInMax instead of actual spend (Low, high)

## Task

Find security vulnerabilities in the contracts listed above as more as you can.

You should look for:
- vulnerabilities
- reportable issues

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
