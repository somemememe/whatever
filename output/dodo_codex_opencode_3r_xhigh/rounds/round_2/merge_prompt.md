Below are findings from 2 agents auditing the same codebase,
plus accumulated findings from previous rounds.

You are the merge layer for a audit loop. You can inspect the source code when needed.

Your task is to read all findings from this round, merge them into the 
summary of distinct issues, compare that round summary against accumulated findings,
and keep new or materially improved findings in the updated list. And you are encouraged to find more based on these findings and source code.

If an issue already exists in accumulated findings, do not add a duplicate. 
Remove findings that are not defensible after checking the code.
Downgrade severity or confidence when the issue depends on unusual configuration or weak
assumptions. 
Treat each finding carefully.

## Accumulated Findings
[
  {
    "id": "F-001",
    "severity": "High",
    "confidence": "high",
    "title": "Bridged input, swap output, and settlement asset are never bound, enabling theft of resident balances",
    "locations": [
      "GatewayCrossChain.sol:369",
      "GatewayCrossChain.sol:373",
      "GatewayCrossChain.sol:397",
      "GatewayCrossChain.sol:416",
      "GatewayCrossChain.sol:492",
      "GatewayTransferNative.sol:414",
      "GatewayTransferNative.sol:449",
      "GatewayTransferNative.sol:453",
      "GatewayTransferNative.sol:477",
      "GatewayTransferNative.sol:554",
      "GatewayTransferNative.sol:574",
      "GatewaySend.sol:184",
      "GatewaySend.sol:195",
      "GatewaySend.sol:245",
      "GatewaySend.sol:257",
      "GatewaySend.sol:266"
    ],
    "claim": "Across these gateway flows, swaps produce only a numeric outputAmount, and later logic transfers, withdraws, or deposits whatever token the caller selected without proving that the current execution actually received that token. Empty swapData on the ZEVM contracts simply returns the bridged amount even when targetZRC20 differs from the bridged zrc20; non-empty swaps never validate params.fromToken or params.toToken against the actual bridged asset or settlement asset; and GatewaySend deposits the caller-chosen asset independently of the token returned by _doMixSwap. In GatewayTransferNative.withdrawToNativeChain, callers can also pass zrc20 == _ETH_ADDRESS_ and skip funding entirely because no msg.value check is performed before the function starts withdrawing target ZRC20 balances.",
    "impact": "Any token or ETH balance already sitting in these contracts, including dust, failed refunds, accidental transfers, or swap leftovers, can be bridged out or paid to the attacker. GatewayTransferNative additionally exposes a zero-input path that can drain resident ZRC20 balances directly.",
    "paths": [
      "GatewayTransferNative.onCall -> decodeNativeMessage(targetZRC20 = victimToken, swapData = empty) -> _doMixSwap returns the bridged amount -> safeTransfer(victimToken, attacker, outputAmount) spends resident victimToken.",
      "GatewayCrossChain.onCall -> decodeMessage(targetZRC20 = victimToken, swapDataZ = empty) -> _handleBitcoinWithdraw or _handleEvmOrSolanaWithdraw approves and withdraws resident victimToken instead of the bridged zrc20.",
      "GatewaySend.depositAndCall(fromToken = cheapToken, swapData swaps to some other token, asset = victimToken) -> _handleERC20Deposit approves victimToken and the gateway pulls resident victimToken.",
      "GatewayTransferNative.withdrawToNativeChain(zrc20 = _ETH_ADDRESS_, amount = N, message targets victimToken with empty swapDataZ) -> no input is collected, but resident victimToken is withdrawn."
    ],
    "round": 1,
    "source_agents": [
      "codex_1",
      "merge_layer"
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "high",
    "title": "GatewaySend traps native-ETH refunds by treating asset == address(0) as an ERC20",
    "locations": [
      "GatewaySend.sol:393",
      "GatewaySend.sol:396",
      "libraries/TransferHelper.sol:12",
      "libraries/TransferHelper.sol:14"
    ],
    "claim": "GatewayEVM reports gas-token refunds with context.asset == address(0), but GatewaySend.onRevert forwards that value into TransferHelper.safeTransfer. Because safeTransfer performs a low-level ERC20 transfer call, calling it on address(0) succeeds with empty returndata and transfers nothing. The callback therefore emits a refund event while leaving the refunded ETH inside GatewaySend.",
    "impact": "Every reverted native-ETH bridge or call leaves the refund stuck in GatewaySend instead of returning it to the user. GatewaySend has no rescue path, so those funds are effectively lost unless they are later extracted through another bug.",
    "paths": [
      "GatewaySend.depositAndCall with ETH (or any native gateway call) -> downstream failure -> GatewayEVM.executeRevert sends msg.value to GatewaySend and sets asset = address(0) -> GatewaySend.onRevert executes safeTransfer(address(0), sender, amount), which no-ops and strands the ETH."
    ],
    "round": 1,
    "source_agents": [
      "codex_1",
      "merge_layer"
    ]
  },
  {
    "id": "F-003",
    "severity": "Medium",
    "confidence": "high",
    "title": "Dusting the deterministic pair address can force a nonexistent Uniswap route",
    "locations": [
      "GatewayCrossChain.sol:234",
      "GatewayCrossChain.sol:253",
      "GatewayTransferNative.sol:235",
      "GatewayTransferNative.sol:254",
      "libraries/UniswapV2Library.sol:42"
    ],
    "claim": "Pair existence is inferred only from token balances at the deterministic CREATE2 pair address. An attacker can transfer dust of both tokens to that address before the pair is deployed, making getPathForTokens choose a direct route even though no pair contract exists there. The later getAmountsIn/getReserves call then reverts when it tries to query reserves from an undeployed pair.",
    "impact": "Withdrawals that should have fallen back through WZETA can be permissionlessly DoSed for chosen token pairs until the real pair is deployed or the contracts are upgraded.",
    "paths": [
      "Attacker transfers dust of tokenA and tokenB to uniswapv2PairFor(factory, tokenA, tokenB) while no pair is deployed -> _existsPairPool returns true -> getPathForTokens chooses the direct pair -> UniswapV2Library.getAmountsIn calls getReserves on a nonexistent pair and reverts."
    ],
    "round": 1,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-004",
    "severity": "Medium",
    "confidence": "high",
    "title": "Solana account decompression builds an invalid Account[] and corrupts outbound payloads",
    "locations": [
      "libraries/AccountEncoder.sol:19",
      "libraries/AccountEncoder.sol:44",
      "libraries/AccountEncoder.sol:48",
      "GatewayCrossChain.sol:425",
      "GatewayCrossChain.sol:455",
      "GatewayTransferNative.sol:505",
      "GatewayTransferNative.sol:535"
    ],
    "claim": "AccountEncoder.decompressAccounts allocates an Account[] of static structs but writes 32-byte pointers into the array body instead of laying out each Account inline. It also derives isWritable from a full mload(ptr) word rather than the single compressed flag byte. When encodeInput later ABI-encodes the array, it serializes heap addresses as public keys and corrupts writability flags.",
    "impact": "Solana withdrawAndCall payloads are malformed. Solana routes can fail outright, revert into refund handling, or target unintended accounts.",
    "paths": [
      "decoded.dstChainId == SOLANA_EDDY -> AccountEncoder.decompressAccounts(decoded.accounts) -> AccountEncoder.encodeInput(...) -> malformed payload is passed to withdrawAndCall."
    ],
    "round": 1,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-005",
    "severity": "Low",
    "confidence": "medium",
    "title": "GatewayTransferNative refund claims stay reentrant until after the external token transfer",
    "locations": [
      "GatewayTransferNative.sol:685",
      "GatewayTransferNative.sol:691",
      "GatewayTransferNative.sol:692"
    ],
    "claim": "GatewayTransferNative.claimRefund transfers refundInfo.token before deleting refundInfos[externalId]. A malicious refundable token can reenter claimRefund from its transfer implementation while the same refund record is still live, and the attacker can choose walletAddress so the reentrant call still satisfies msg.sender == receiver.",
    "impact": "If a malicious or non-standard token ever reaches the refund path, the same refund can be claimed multiple times and other balances of that token held by the contract can be drained.",
    "paths": [
      "Attacker creates a refund entry for a malicious token with walletAddress set to the token contract -> claimRefund(externalId) -> token.transfer reenters claimRefund(externalId) before delete refundInfos[externalId]."
    ],
    "round": 1,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-006",
    "severity": "High",
    "confidence": "high",
    "title": "GatewaySend.onCall pays out resident balances based on untrusted payload fields",
    "locations": [
      "GatewaySend.sol:106",
      "GatewaySend.sol:143",
      "GatewaySend.sol:341",
      "GatewaySend.sol:358",
      "GatewaySend.sol:363",
      "GatewaySend.sol:366",
      "GatewaySend.sol:369",
      "GatewaySend.sol:372"
    ],
    "claim": "GatewaySend.onCall decodes amount, fromToken, and toToken directly from the cross-chain message and never binds them to the asset or value that the gateway actually delivered. If fromToken is set to _ETH_ADDRESS_, the function skips transferFrom entirely, so even a zero-asset cross-chain call can make the contract transfer out ETH it already holds. More generally, _doMixSwap returns only a number and onCall never proves that the token it later transfers matches the swap output, so resident ERC20 balances can also be paid out.",
    "impact": "Any ETH or token balance sitting in a destination GatewaySend instance can be stolen with a crafted cross-chain payload, potentially without bridging any asset at all.",
    "paths": [
      "Attacker uses GatewayEVM.call or any zero-asset cross-chain call to GatewaySend with payload {amount = contractETHBalance, fromToken = _ETH_ADDRESS_, toToken = _ETH_ADDRESS_, recipient = attacker} -> onCall skips transferFrom and transfers resident ETH.",
      "Attacker sends any small cross-chain call or transfer to GatewaySend with payload that sets an arbitrary toToken and swap data -> _doMixSwap produces an outputAmount number, but onCall transfers resident toToken instead of the actual swap output."
    ],
    "round": 1,
    "source_agents": [
      "merge_layer"
    ]
  },
  {
    "id": "F-007",
    "severity": "High",
    "confidence": "high",
    "title": "Failed Bitcoin withdrawals refund to an EVM address derived from the BTC recipient bytes",
    "locations": [
      "GatewayCrossChain.sol:397",
      "GatewayCrossChain.sol:402",
      "GatewayCrossChain.sol:318",
      "GatewayCrossChain.sol:550",
      "GatewayTransferNative.sol:477",
      "GatewayTransferNative.sol:482",
      "GatewayTransferNative.sol:319",
      "GatewayTransferNative.sol:631"
    ],
    "claim": "The Bitcoin path passes decoded.receiver, which is the target Bitcoin recipient bytes, into withdraw. withdraw truncates that bytes value to bytes20 inside the revert message, and onRevert always interprets a 52-byte revert message as an EVM address and transfers the refund there. A failed BTC withdrawal therefore refunds to address(uint160(bytes20(decoded.receiver))) instead of the original user or a claimable refund record.",
    "impact": "Any failed Bitcoin withdrawal can misdeliver the entire refund to an unintended EVM address, causing permanent loss for those transactions.",
    "paths": [
      "GatewayCrossChain.onCall -> _handleBitcoinWithdraw -> withdraw(externalId, decoded.receiver, ...) -> revert -> onRevert transfers to address(uint160(bytes20(decoded.receiver))).",
      "GatewayTransferNative.withdrawToNativeChain(... dstChainId = BITCOIN_EDDY ...) -> _handleBitcoinWithdraw -> same truncated refund path."
    ],
    "round": 1,
    "source_agents": [
      "merge_layer"
    ]
  },
  {
    "id": "F-008",
    "severity": "Low",
    "confidence": "high",
    "title": "GatewayTransferNative rejects valid gas swaps by comparing against amountInMax instead of actual spend",
    "locations": [
      "GatewayTransferNative.sol:338",
      "GatewayTransferNative.sol:352",
      "GatewayTransferNative.sol:355"
    ],
    "claim": "After swapTokensForExactTokens returns the actual target-token input consumed in amounts[0], GatewayTransferNative still checks targetAmount - amountInMax > 0. Because amountInMax includes the slippage buffer rather than the amount really spent, the function can revert even when the swap succeeded and amounts[0] leaves a positive residual balance to withdraw.",
    "impact": "Outgoing withdrawals that need a gas-token conversion can fail unnecessarily, especially for small transfers or higher owner-configured slippage, creating avoidable DoS for otherwise valid routes.",
    "paths": [
      "GatewayTransferNative.onCall or withdrawToNativeChain -> _handleEvmOrSolanaWithdraw -> _swapAndSendERC20Tokens -> actual swap spends amounts[0] < targetAmount, but amountInMax >= targetAmount so the function reverts anyway."
    ],
    "round": 1,
    "source_agents": [
      "opencode_1",
      "merge_layer"
    ]
  }
]

## This Round's Agent Outputs
### Agent: codex_1
```
[
  {
    "id": "F-009",
    "severity": "High",
    "confidence": "high",
    "title": "Any caller can steal pending Bitcoin/Solana refunds",
    "locations": [
      "GatewayCrossChain.sol:607",
      "GatewayCrossChain.sol:612",
      "GatewayTransferNative.sol:685",
      "GatewayTransferNative.sol:689"
    ],
    "claim": "Both `claimRefund()` implementations default `receiver` to `msg.sender` and only overwrite it for 20-byte wallet addresses, so for non-EVM refunds the authorization check collapses to `msg.sender == receiver` and always passes for the caller.",
    "impact": "Any pending refund whose `walletAddress` is not 20 bytes can be front-run and paid to an arbitrary attacker instead of the intended non-EVM recipient.",
    "paths": [
      "A BTC/Solana withdrawal fails and `onRevert`/`onAbort` stores `refundInfos[externalId]` with a non-20-byte `walletAddress`.",
      "An attacker calls `claimRefund(externalId)` before any trusted bot/user action and receives the full refund."
    ]
  },
  {
    "id": "F-010",
    "severity": "High",
    "confidence": "high",
    "title": "GatewaySend callback ABI is incompatible with Zeta's authenticated-call interface",
    "locations": [
      "GatewaySend.sol:341",
      "GatewaySend.sol:385"
    ],
    "claim": "`GatewaySend.onCall()` returns `bytes4`, but Zeta's authenticated-call path invokes receivers as `Callable.onCall(... ) returns (bytes memory)`, so the gateway ABI-decodes the fixed-size returndata as dynamic bytes and reverts.",
    "impact": "Authenticated destination-side deliveries into `GatewaySend` fail at the gateway boundary, breaking cross-chain receives that rely on `withdrawAndCall` into this contract.",
    "paths": [
      "GatewayCrossChain/GatewayTransferNative performs `withdrawAndCall` to the EVM leg.",
      "GatewayEVM calls `GatewaySend.onCall(...)` and then reverts while decoding the `bytes4` return value as `bytes memory`."
    ]
  },
  {
    "id": "F-011",
    "severity": "Medium",
    "confidence": "high",
    "title": "GatewayTransferNative swaps the pre-fee amount after already transferring out the fee",
    "locations": [
      "GatewayTransferNative.sol:389",
      "GatewayTransferNative.sol:414"
    ],
    "claim": "In `onCall()`, the contract transfers `platformFeesForTx` to the treasury but does not reduce `amount` before entering the swap branch, so `_doMixSwap(decoded.swapData, amount, params)` still tries to spend the pre-fee balance.",
    "impact": "Inbound native-to-Zeta swap executions can revert once fees are enabled unless users manually understate the swap input, causing valid cross-chain receives to fail.",
    "paths": [
      "Gateway invokes `onCall(zrc20, amount, message)` with `decoded.targetZRC20 != zrc20`.",
      "Treasury fee is transferred out, then DODO is asked to pull `amount` even though the contract only holds `amount - fee`."
    ]
  },
  {
    "id": "F-012",
    "severity": "Medium",
    "confidence": "high",
    "title": "GatewaySend can consume or bridge excess ETH beyond the declared amount",
    "locations": [
      "GatewaySend.sol:202",
      "GatewaySend.sol:233",
      "GatewaySend.sol:307",
      "GatewaySend.sol:311"
    ],
    "claim": "ETH-source flows only enforce `msg.value >= amount` and then forward the full `msg.value` downstream: `_doMixSwap()` uses all attached ETH, while direct ETH bridging deposits `msg.value` instead of the user-declared `amount`.",
    "impact": "Any accidental ETH overpayment is irrecoverably consumed by the swap or bridged away rather than refunded to the caller.",
    "paths": [
      "User calls the swap-enabled `depositAndCall` with `fromToken == _ETH_ADDRESS_` and `msg.value > amount`; `_doMixSwap{value: msg.value}` uses the full overpayment.",
      "User calls the direct ETH `depositAndCall` overload with `msg.value > amount`; `_handleETHDeposit` bridges `msg.value` instead of `amount`."
    ]
  },
  {
    "id": "F-013",
    "severity": "Medium",
    "confidence": "high",
    "title": "Destination ETH payouts are broken for smart-wallet recipients",
    "locations": [
      "GatewaySend.sol:369"
    ],
    "claim": "`GatewaySend.onCall()` pays ETH with Solidity `transfer`, which forwards only 2300 gas to the receiver.",
    "impact": "Bridged ETH deliveries to multisigs, proxies, AA wallets, or any contract with non-trivial receive logic can fail systematically.",
    "paths": [
      "A cross-chain receive resolves to `toToken == _ETH_ADDRESS_` and `recipient` is a contract wallet.",
      "`payable(evmWalletAddress).transfer(outputAmount)` reverts because the recipient needs more than 2300 gas."
    ]
  },
  {
    "id": "F-014",
    "severity": "Low",
    "confidence": "medium",
    "title": "GatewaySend treats false-returning ERC20 transfers as success",
    "locations": [
      "GatewaySend.sol:359",
      "GatewaySend.sol:372"
    ],
    "claim": "`onCall()` uses raw `IERC20.transferFrom` and `IERC20.transfer` without checking the returned boolean, so tokens that return `false` instead of reverting are silently treated as successfully moved.",
    "impact": "Destination deliveries can emit success while no tokens moved, or fall back to resident balances if later logic assumes the transfer succeeded.",
    "paths": [
      "Gateway invokes `GatewaySend.onCall()` with a false-returning ERC20 as `fromToken` or `toToken`.",
      "The token operation returns `false`, but the function keeps executing and emits `EddyCrossChainReceive`."
    ]
  },
  {
    "id": "F-015",
    "severity": "Low",
    "confidence": "high",
    "title": "ERC20 native-chain withdrawals can silently forward accidental ETH",
    "locations": [
      "GatewayTransferNative.sol:454",
      "GatewayTransferNative.sol:553",
      "GatewayTransferNative.sol:554"
    ],
    "claim": "`withdrawToNativeChain()` is payable for every asset type and never rejects `msg.value` when `zrc20 != _ETH_ADDRESS_`, while `_doMixSwap()` always forwards `msg.value` to DODO.",
    "impact": "Users initiating ERC20 withdrawals can accidentally lose attached native ETH/ZETA because the extra value is consumed or stranded instead of refunded.",
    "paths": [
      "User calls `withdrawToNativeChain(zrc20 != _ETH_ADDRESS_, ...)` with non-zero `msg.value`.",
      "The contract pulls ERC20 from the user and then forwards the unrelated ETH to `mixSwap`."
    ]
  },
  {
    "id": "F-016",
    "severity": "Low",
    "confidence": "medium",
    "title": "GatewayTransferNative refund records are overwriteable by repeated callbacks",
    "locations": [
      "GatewayTransferNative.sol:642",
      "GatewayTransferNative.sol:648",
      "GatewayTransferNative.sol:664",
      "GatewayTransferNative.sol:670"
    ],
    "claim": "Unlike `GatewayCrossChain`, `GatewayTransferNative.onRevert()` and `onAbort()` never check whether `refundInfos[externalId]` is already populated before writing a new record.",
    "impact": "If the gateway/protocol emits duplicate callbacks for the same `externalId`, the original refund token, amount, or claimant metadata can be replaced before anyone claims it.",
    "paths": [
      "A failed withdrawal stores `refundInfos[externalId]` once.",
      "A later revert/abort callback for the same `externalId` overwrites the stored refund entry."
    ]
  }
]

```

### Agent: opencode_1
```
[{"id": "F-009", "severity": "High", "confidence": "medium", "title": "No slippage protection for DODO Router swaps", "locations": ["GatewayCrossChain.sol:374-387", "GatewayTransferNative.sol:444-468"], "claim": "The DODO Router swap calls pass minReturnAmount directly from user-provided params without enforcing the contract's slippage parameter, leaving users vulnerable to sandwich attacks and price impact losses.", "impact": "Users may receive significantly less than expected from swaps due to price manipulation or unfavorable market conditions without any protection.", "paths": ["User calls withdrawToNativeChain or onCall -> _doMixSwap executes with user-supplied minReturnAmount -> attacker sandwiches the swap -> user receives less than expected with no recourse"]}, {"id": "F-010", "severity": "High", "confidence": "medium", "title": "GatewaySend.onCall has no slippage protection", "locations": ["GatewaySend.sol:366-367"], "claim": "When onCall performs a swap via _doMixSwap, it ignores the returned outputAmount and makes no validation against expected amounts or slippage limits.", "impact": "Users receiving cross-chain tokens through onCall could receive far less than intended due to unfavorable swap execution.", "paths": ["Cross-chain message triggers onCall -> _doMixSwap executes -> outputAmount not validated -> recipient receives less than expected"]}, {"id": "F-011", "severity": "High", "confidence": "high", "title": "Owner can drain all contract funds via superWithdraw", "locations": ["GatewayCrossChain.sol:188-196", "GatewayTransferNative.sol:185-193"], "claim": "The superWithdraw function allows the owner to withdraw any amount of any token (including ETH) from the contract without any restrictions.", "impact": "A malicious or compromised owner can steal all funds from the contract, including user deposits and protocol fees.", "paths": ["Compromised owner calls superWithdraw -> all tokens transferred to owner"]}, {"id": "F-012", "severity": "High", "confidence": "high", "title": "DODOApprove can be set to arbitrary address enabling token theft", "locations": ["GatewayCrossChain.sol:148-152", "GatewayTransferNative.sol:149-152"], "claim": "The setDODOApprove function allows setting any address as the approval target for DODO swaps without any restrictions or timelock.", "impact": "A malicious owner can set DODOApprove to a attacker-controlled address, then all swap approvals will transfer tokens to the attacker.", "paths": ["Malicious owner calls setDODOApprove(attackerAddress) -> subsequent swaps approve tokens to attacker -> attacker drains approved tokens"]}, {"id": "F-013", "severity": "Medium", "confidence": "medium", "title": "DODO Router calls lack deadline parameter", "locations": ["GatewayCrossChain.sol:374-387", "GatewayTransferNative.sol:444-468", "GatewaySend.sol:195-216"], "claim": "The mixSwap calls to DODO Router do not pass a deadline parameter, allowing swaps to potentially execute at unfavorable prices if delayed.", "impact": "Swaps may execute at worse rates if transaction is delayed, with no way to cancel.", "paths": ["User submits swap -> network congestion delays execution -> swap executes at worse price with no cancellation option"]}, {"id": "F-014", "severity": "Medium", "confidence": "high", "title": "Reentrancy vulnerability in GatewayTransferNative.claimRefund", "locations": ["GatewayTransferNative.sol:680-700"], "claim": "The claimRefund function transfers tokens BEFORE deleting the refundInfo, allowing reentrancy attacks. Compare to GatewayCrossChain.sol which correctly deletes before transfer.", "impact": "Attacker can reenter claimRefund multiple times to drain refund contract balances.", "paths": ["Attacker calls claimRefund -> TransferHelper.safeTransfer executes -> callback triggers reentrancy -> attacker calls claimRefund again before delete -> repeats until drained"]}, {"id": "F-015", "severity": "Medium", "confidence": "high", "title": "On-chain slippage validation bug in GatewayTransferNative", "locations": ["GatewayTransferNative.sol:352"], "claim": "The validation checks targetAmount - amountInMax > 0 but amountInMax is the maximum allowed input, not the actual spent amount (amounts[0]). The actual spent amount is not validated.", "impact": "Incorrect validation logic could allow invalid swaps to proceed or reject valid ones inconsistently.", "paths": ["Swap executes -> validation uses wrong variable (amountInMax instead of amounts[0]) -> inconsistent results"]}, {"id": "F-016", "severity": "Medium", "confidence": "low", "title": "ExternalId can be predicted enabling front-running", "locations": ["GatewaySend.sol:160-162", "GatewaySend.sol:227-228"], "claim": "The externalId is computed using globalNonce, msg.sender, and block.timestamp. Since globalNonce is incremented after the externalId is computed, the sequence is predictable.", "impact": "Users may be vulnerable to front-running on their cross-chain transactions if attackers can predict externalIds.", "paths": ["User submits depositAndCall -> attacker observes predictable externalId -> front-runs with higher gas"]}, {"id": "F-017", "severity": "Low", "confidence": "medium", "title": "No deadline check for Uniswap V2 gas swaps", "locations": ["GatewayCrossChain.sol:346-353", "GatewayTransferNative.sol:342-349"], "claim": "The swapTokensForExactTokens calls use block.timestamp + MAX_DEADLINE but MAX_DEADLINE is only 200 seconds, which may be too short for congested network conditions.", "impact": "Swaps may fail in network congestion, causing entire cross-chain transaction to fail.", "paths": ["Network congestion causes delay -> deadline expires -> entire cross-chain transaction reverts and may require refund"]}, {"id": "F-018", "severity": "Low", "confidence": "medium", "title": "Missing event for ownership transfer", "locations": ["GatewayCrossChain.sol:138-140", "GatewayTransferNative.sol:140-142"], "claim": "The setOwner function calls transferOwnership but does not emit any event, making ownership changes non-transparent.", "impact": "Users cannot track ownership changes through events, reducing transparency and auditability.", "paths": ["Owner calls setOwner -> no event emitted -> users cannot detect ownership change"]}, {"id": "F-019", "severity": "Low", "confidence": "low", "title": "No access control on withdrawToNativeChain", "locations": ["GatewayTransferNative.sol:549-619"], "claim": "The withdrawToNativeChain function has no access control beyond msg.value >= 0, allowing anyone to trigger cross-chain withdrawals.", "impact": "Anyone can initiate outbound transfers from the contract, though they must provide the source tokens.", "paths": ["Anyone calls withdrawToNativeChain with tokens -> cross-chain withdrawal initiated"]}, {"id": "F-020", "severity": "Low", "confidence": "low", "title": "Uniswap path fallback may use stale pools", "locations": ["GatewayCrossChain.sol:249-269", "GatewayTransferNative.sol:250-270"], "claim": "The _existsPairPool check only verifies balances > 0 in the pool, which could be a dust balance from a dead pool, not actual liquidity.", "impact": "Swaps might route through unusable pools if they're dusted with small balances.", "paths": ["Attacker dusts a dead pair with minimal tokens -> _existsPairPool returns true -> swaps route through non-functional pool -> fails"]}]

```

## Output
Return the COMPLETE updated findings list as a JSON array.

Each element must have:
- `id`
- `severity`
- `confidence`
- `title`
- `locations`
- `claim`
- `impact`
- `paths`
- `round`
- `source_agents`

Preserve existing IDs for surviving findings whenever possible.
`source_agents` must include every agent that materially supports the final finding.

Output ONLY valid JSON. No markdown. No prose.
