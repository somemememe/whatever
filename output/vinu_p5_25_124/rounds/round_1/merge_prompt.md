Below are findings and vulnerability signals from 2 agents auditing the same codebase,
plus accumulated findings from previous rounds. You need to inspect the source code when needed.

You are the merge and review layer for a audit.

Your task:
- merge new or materially improved reportable issues into the accumulated findings
- reconstruct plausible but poorly written findings or signals into low-confidence findings when the code supports them
- reject clearly non-reportable candidates with your reasons
- try to use this round's signals and the source code to look for additional findings yourself

Prefer downgrading severity or confidence over discarding a plausible issue.
Keep findings that can cause realistic protocol-level harm, including fund loss,
theft, insolvency, permanent lockup, economic manipulation, or permissionless DoS and some other realistic issues.

## Accumulated Findings
None yet.

## This Round's Agent Outputs
### Agent: codex_1
```
[
  {
    "id": "F-001",
    "severity": "High",
    "confidence": "high",
    "title": "A hidden external controller can selectively block transfers and sells",
    "locations": [
      "0xf7ef0d57277ad6c2babf87ab64ba61abdd2590d2/Contract.sol:259",
      "0xf7ef0d57277ad6c2babf87ab64ba61abdd2590d2/Contract.sol:468",
      "0xf7ef0d57277ad6c2babf87ab64ba61abdd2590d2/Contract.sol:609"
    ],
    "claim": "The constructor stores an arbitrary `_router` address, and every token transfer delegates authorization to that address through a non-standard `swapExactTokensForETHSupportingFeeOnTransferTokens(address,address,uint256)` call. Because `_transfer` requires the returned `allow` flag to be true, the external controller can revert or return false for chosen senders/recipients and thereby deny transfers.",
    "impact": "A deployer-controlled controller can turn the token into a honeypot by letting buyers receive tokens but preventing them from selling or transferring out later, trapping user funds.",
    "paths": [
      "Deploy the token with an attacker-controlled `_router` contract.",
      "Users buy or receive tokens normally.",
      "When a victim transfers to the pair or another address, the controller returns `false` or reverts, causing the transfer to fail."
    ]
  },
  {
    "id": "F-002",
    "severity": "Critical",
    "confidence": "high",
    "title": "Transfer balance changes are fully attacker-controlled, enabling confiscation and hidden minting",
    "locations": [
      "0xf7ef0d57277ad6c2babf87ab64ba61abdd2590d2/Contract.sol:467",
      "0xf7ef0d57277ad6c2babf87ab64ba61abdd2590d2/Contract.sol:471",
      "0xf7ef0d57277ad6c2babf87ab64ba61abdd2590d2/Contract.sol:472",
      "0xf7ef0d57277ad6c2babf87ab64ba61abdd2590d2/Contract.sol:609"
    ],
    "claim": "The token never enforces ERC-20 transfer invariants inside `_transfer`. Instead, it blindly trusts the external controller to return `subBal` and `addBal`, then subtracts `subBal` from the sender and adds `addBal` to the recipient without requiring either value to equal `amount` or even each other.",
    "impact": "The controller can secretly over-debit victims, under-credit recipients, or mint arbitrary balances to privileged accounts without changing `totalSupply`, enabling direct holder theft, stealth taxes, and unlimited token fabrication for price manipulation and rug pulls.",
    "paths": [
      "On a victim transfer, the controller returns `(true, senderBalance, 0)` to wipe the holder while the event still shows a normal transfer.",
      "On an attacker transfer, the controller returns `(true, 0, veryLargeAmount)` to credit unbacked tokens that can then be dumped into liquidity."
    ]
  },
  {
    "id": "F-003",
    "severity": "Critical",
    "confidence": "high",
    "title": "Public liquidity bootstrap can seize 80% of any address balance and mint LP to an arbitrary recipient",
    "locations": [
      "0xf7ef0d57277ad6c2babf87ab64ba61abdd2590d2/Contract.sol:552",
      "0xf7ef0d57277ad6c2babf87ab64ba61abdd2590d2/Contract.sol:553",
      "0xf7ef0d57277ad6c2babf87ab64ba61abdd2590d2/Contract.sol:554",
      "0xf7ef0d57277ad6c2babf87ab64ba61abdd2590d2/Contract.sol:560"
    ],
    "claim": "`addLiquidityETH` is externally callable by anyone and directly debits `devaddr` by 80% of its balance with no ownership, approval, or consent checks. It then adds those tokens as liquidity and sends the LP tokens to caller-chosen `lpraddr`.",
    "impact": "Any attacker can front-run launch or target a holder address, forcibly move most of that address's tokens into a pool, and assign the resulting LP ownership anywhere they want. This enables theft of launch control and repeated draining of balances.",
    "paths": [
      "Call `addLiquidityETH(router, attackerLPRecipient, victim)` with some ETH.",
      "The function removes 80% of `victim`'s token balance and places it in the contract.",
      "Liquidity is added and the LP tokens are minted to `attackerLPRecipient`, not the victim."
    ]
  },
  {
    "id": "F-004",
    "severity": "Medium",
    "confidence": "high",
    "title": "Transfer events can be falsified to hide the real balance changes",
    "locations": [
      "0xf7ef0d57277ad6c2babf87ab64ba61abdd2590d2/Contract.sol:468",
      "0xf7ef0d57277ad6c2babf87ab64ba61abdd2590d2/Contract.sol:474"
    ],
    "claim": "After applying arbitrary `subBal` and `addBal` values from the external controller, the contract still emits `Transfer(sender, recipient, amount)` instead of the actual debited or credited amounts.",
    "impact": "Off-chain monitors, explorers, and integrations can be shown fake transfer activity while hidden confiscation or minting occurs in storage, making the backdoor harder to detect and breaking downstream accounting assumptions.",
    "paths": [
      "The controller returns `subBal` and `addBal` that differ from the requested `amount`.",
      "Storage is updated with those hidden values, but the emitted `Transfer` event still reports the original `amount`."
    ]
  }
]

```

### Agent: opencode_1
```
[{"id":"F-001","severity":"Critical","confidence":"high","title":"Malicious Router Can Steal All Tokens","locations":["Contract.sol:260","Contract.sol:318","Contract.sol:468"],"claim":"The contract stores an arbitrary router address in constructor that can be set to a malicious contract. Anyone can call the public `decode` function to extract this address, and the `_transfer` function calls this router to execute swaps.","impact":"An attacker deploying a malicious router can implement a fake `swapExactTokensForETHSupportingFeeOnTransferTokens` that returns false or manipulates the return values to drain all user tokens during transfers.","paths":["1. Deploy contract with malicious router address\n2. Wait for victim to call transfer()\n3. Malicious router returns manipulated subBal/addBal values\n4. Attacker drains victim tokens"]},{"id":"F-002","severity":"Critical","confidence":"high","title":"Unrestricted addLiquidityETH Allows Theft of Dev Tokens","locations":["Contract.sol:552-562"],"claim":"The addLiquidityETH function has no access control (missing onlyOwner), allowing anyone to trigger it.","impact":"Any user can call addLiquidityETH to trigger the function that transfers 80% of dev's tokens to the contract and adds them to liquidity, effectively stealing the dev's tokens.","paths":["1. Any user calls addLiquidityETH()\n2. 80% of dev's balance transferred to contract\n3. Tokens added to LP, permanently locked"]},{"id":"F-003","severity":"Critical","confidence":"high","title":"Incorrect UniswapV2Router Interface Causes Transfer Failure","locations":["Contract.sol:468-470","Contract.sol:609-613"],"claim":"The custom interface for swapExactTokensForETHSupportingFeeOnTransferTokens does not match the actual UniswapV2Router02 function signature.","impact":"The _transfer function will always fail or behave incorrectly because it calls the router with wrong parameters (sender, recipient, amount) instead of (amountIn, amountOutMin, path, to, deadline). Transfers will revert.","paths":["Any transfer() call will fail due to incorrect function signature"]},{"id":"F-004","severity":"High","confidence":"medium","title":"Unlimited Token Approval to Router","locations":["Contract.sol:558"],"claim":"addLiquidityETH approves the entire _totalSupply to the router instead of just the tokens being added.","impact":"If the router is compromised or malicious, it can drain the entire token supply from the contract.","paths":["1. addLiquidityETH is called\n2. Router gets approval for all tokens\n3. Router drains all tokens"]},{"id":"F-005","severity":"High","confidence":"high","title":"External Call Before State Update Enables Manipulation","locations":["Contract.sol:468-472"],"claim":"The external swap call executes before balances are updated, and the returned subBal/addBal values are used for balance adjustments without validation.","impact":"A malicious or manipulated router can return arbitrary values, allowing the attacker to inflate their balance or drain the contract.","paths":["1. Deploy malicious router\n2. Call transfer()\n3. Router returns exaggerated addBal\n4. Attacker balance inflated"]},{"id":"F-006","severity":"High","confidence":"medium","title":"Missing Zero Address Check in addLiquidityETH","locations":["Contract.sol:552"],"claim":"The addLiquidityETH function does not validate that routeraddr, lpraddr, and devaddr are non-zero addresses.","impact":"Passing zero addresses can cause permanent loss of funds when liquidity is added or tokens get stuck.","paths":["Call addLiquidityETH with zero address parameters"]},{"id":"F-007","severity":"Medium","confidence":"medium","title":"Block Timestamp Dependency for Deadline","locations":["Contract.sol:560"],"claim":"Uses block.timestamp directly as deadline.","impact":"Miner can manipulate block timestamp within reasonable bounds to extend deadline, though impact is limited in this context.","paths":["Miner manipulates block.timestamp"]},{"id":"F-008","severity":"Medium","confidence":"medium","title":"Missing Return Value Check for ERC20 approve","locations":["Contract.sol:354-360"],"claim":"The approve function does not check the return value of the internal _approve call.","impact":"Some tokens (like USDT) do not return true on approval and may cause the call to appear to succeed while actually not setting the allowance.","paths":["Approve certain tokens may not work correctly"]},{"id":"F-009","severity":"Low","confidence":"medium","title":"Public decode Function Exposes Router Address","locations":["Contract.sol:318-320"],"claim":"The public decode function can be called by anyone to retrieve the stored router address.","impact":"Information disclosure - router address becomes publicly known, potentially enabling targeted attacks if router is vulnerable.","paths":["Call decode(routerbyt) to extract router address"]}]

```



## Output
Return a JSON object with:
- `findings`: the COMPLETE updated findings list
- `rejected_candidates`: candidates rejected from this round, with concise reasons

Each `findings` element must have:
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

Each `rejected_candidates` element must have:
- `title`
- `source_agents`
- `reason`

Output ONLY valid JSON. No markdown. No prose.
