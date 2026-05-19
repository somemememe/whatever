[
{
"id": "F-025",
"severity": "High",
"confidence": "medium",
"title": "SwapDataHelperLib decodeCompressedMixSwapParams lacks calldata bounds checks",
"locations": [
"libraries/SwapDataHelperLib.sol:144"
],
"claim": "decodeCompressedMixSwapParams reads multiple length-prefixed variable-length regions from calldata without validating that the total encoded length fits within the provided calldata.",
"impact": "Malformed or truncated calldata causes out-of-bounds library calldata reads, leading to unexpected reverts or extraction of unintended memory region data as parsed parameter values.",
"paths": [
"Caller encodes compressed swap params with incorrect length prefixes → decodeCompressedMixSwapParams attempts to read beyond calldata bounds → reverts or reads stale memory"
]
},
{
"id": "F-026",
"severity": "Medium",
"confidence": "low",
"title": "SwapDataHelperLib decodeCompressedMixSwapParams offset arithmetic can underflow",
"locations": [
"libraries/SwapDataHelperLib.sol:144"
],
"claim": "The offset variable in decodeCompressedMixSwapParams only increments and wraps in assembly; if calldata contains crafted lengths, arithmetic can proceed past valid bounds without explicit check.",
"impact": "Corrupted parsed parameters can flow downstream to external calls (DODORouteProxy.mixSwap), potentially causing unexpected token movement or approval manipulation.",
"paths": [
"Calldata contains length fields pointing backward → offset wraps or becomes misaligned → parsing produces invalid address/amount values passed to mixSwap"
]
},
{
"id": "F-027",
"severity": "Medium",
"confidence": "medium",
"title": "GatewaySend onCall lacks reentrancy protection on token transfers",
"locations": [
"GatewaySend.sol:341"
],
"claim": "onCall performs external token transfers (IERC20.transfer, transferFrom) and ETH .call without a reentrancy guard, allowing a malicious contract receiver to callback into onCall before state updates finalize.",
"impact": "A malicious token callback can trigger onCall again (as the gateway) during the execution window, potentially manipulating state-dependent logic or draining assets in the same transaction.",
"paths": [
"Gateway calls onCall with malicious recipient → recipient is a contract with a hook → hook calls back into onCall as gateway (using onRevert or another path) before onCall completes state updates"
]
},
{
"id": "F-028",
"severity": "High",
"confidence": "medium",
"title": "GatewaySend onCall does not validate outputAmount >= amount for swap paths",
"locations": [
"GatewaySend.sol:362"
],
"claim": "When fromToken != toToken, the code performs \_doMixSwap but does not validate that outputAmount >= amount (or a minimum threshold), trusting the swap output directly.",
"impact": "If the DODO swap path returns less than input (or zero) due to pool exhaustion or manipulation, the contract transfers_less to the recipient while the full amount is accounted as processed. Combined with fee treatment, this can result in losses for users.",
"paths": [
"User initiates cross-chain swap → swap pool is manipulated/drained → outputAmount < amount → onCall transfers reduced amount with no user notification or revert → funds lost"
]
},
{
"id": "F-029",
"severity": "Critical",
"confidence": "medium",
"title": "GatewayCrossChain onCall slippage check uses post-swap amount incorrectly",
"locations": [
"GatewayCrossChain.sol:492"
],
"claim": "The onCall function in GatewayCrossChain performs \_doMixSwap and uses outputAmount directly for withdrawal without comparing against expected output or applying slippage protection.",
"impact": "A manipulated or exhausted Uniswap pool can cause outputAmount to be significantly lower than the input, yet the full amount is approved to the gateway for withdrawal, potentially leading to a DoS of the withdrawal or unexpected token approvals.",
"paths": [
"Gateway calls onCall with cross-chain request → Uniswap pool is manipulated → outputAmount is low → contract approves outputAmount to gateway → gateway withdraws less than expected, breaking user expectations"
]
},
{
"id": "F-030",
"severity": "Medium",
"confidence": "low",
"title": "GatewayTransferNative withdrawToNativeChain uses nominal input amount for swap fee calculation",
"locations": [
"GatewayTransferNative.sol:549"
],
"claim": "withdrawToNativeChain deducts platformFeesForTx from the input amount before swapping, but the swap uses the post-fee amount without confirming swap output satisfies original intent.",
"impact": "If the swap yields minimal output due to poor rates or pool state, the recipient receives less than expected, but the platform has already taken its fee on the input nominal amount.",
"paths": [
"User calls withdrawToNativeChain with amount → platform fee deducted → swap results in minimal output → recipient receives less, platform already took fee"
]
},
{
"id": "F-031",
"severity": "Low",
"confidence": "medium",
"title": "GatewayCrossChain setBot can enable arbitrary external calls",
"locations": [
"GatewayCrossChain.sol:184"
],
"claim": "The setBot function allows the owner to mark any address as a bot, which is then used in claimRefund to bypass the caller check, allowing bots to claim refunds on behalf of any user.",
"impact": "While bot role is intended for automated refund processing, a compromised owner could enable a bot to drain all refund records in a single transaction.",
"paths": [
"Owner calls setBot with attacker address → attacker calls claimRefund for any unclaimed refund → drains refund tokens"
]
},
{
"id": "F-032",
"severity": "Medium",
"confidence": "medium",
"title": "GatewaySend onCall uses .transfer for ETH payouts",
"locations": [
"GatewaySend.sol:370"
],
"claim": "In onCall, ETH payouts to contract recipients use payable(evmWalletAddress).transfer(outputAmount), which forwards 2300 gas and can cause DoS for recipients that require more gas.",
"impact": "Smart contract recipients that require more than 2300 gas will revert, causing the entire onCall to fail and potentially blocking legitimate cross-chain operations.",
"paths": [
"Cross-chain ETH transfer to a contract with receive() that performs operations → .transfer forwards only 2300 gas → contract OOGs → onCall reverts"
]
}
]
