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
    "title": "Anyone can steal another user's whitelist mint by supplying an arbitrary `_user`",
    "locations": [
      "onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1395",
      "onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1398",
      "onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1400",
      "onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1401"
    ],
    "claim": "`freeMint` authorizes against the caller-controlled `_user` parameter, but mints to `msg.sender`, so any caller can consume any whitelisted address's slot and receive the NFT themselves.",
    "impact": "Whitelist allocations are not bound to their intended recipients. Attackers can front-run or monitor known allowlisted addresses, mint for themselves at zero cost, and permanently invalidate the victim's whitelist privilege. If the resulting mint is lucky, the attacker also siphons ETH from the prize pool.",
    "paths": [
      "Victim address is whitelisted via `setWhiteLists`",
      "Attacker calls `freeMint(victimAddress)` from their own account or contract",
      "Whitelist check passes on `victimAddress`, but `_safeMint` sends the NFT to `msg.sender`",
      "Contract clears `whiteLists[victimAddress]`, locking out the victim"
    ]
  },
  {
    "id": "F-002",
    "severity": "Critical",
    "confidence": "high",
    "title": "A wrapper contract can revert every losing mint and keep only winning outcomes",
    "locations": [
      "onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1400",
      "onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1402",
      "onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1405",
      "onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1407",
      "onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1418",
      "onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1419",
      "onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1422",
      "onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1424",
      "onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1436"
    ],
    "claim": "Both mint functions fully resolve the prize and pay the caller before control returns to the caller's contract, so an attacker can wrap the call, inspect whether they won, and revert the outer transaction whenever the result is unfavorable.",
    "impact": "This turns the lottery into a one-sided option. For `publicMint`, the attacker only finalizes profitable mints and can earn roughly `0.9 * price` per successful attempt while losing only gas on failed attempts. For `freeMint`, the attacker can repeatedly retry until they get a lucky free mint, receiving the NFT plus ~95% of `price` from the contract. This can drain the bonus pool and make the game economically non-viable.",
    "paths": [
      "Attacker deploys an ERC721Receiver wrapper contract",
      "Wrapper calls `publicMint()` or `freeMint()`",
      "After the call returns, wrapper checks whether it received the prize payout or whether the minted token is marked lucky",
      "If the outcome is losing, wrapper reverts, rolling back the mint/payment/whitelist consumption",
      "If the outcome is winning, wrapper does not revert and keeps the payout"
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "high",
    "title": "Prize randomness is derived from block fields that are predictable, proposer-influenceable, and constant for the whole block",
    "locations": [
      "onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1402",
      "onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1419",
      "onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1436",
      "onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1437",
      "onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1438"
    ],
    "claim": "`_getRandom()` uses only `block.difficulty` and `block.timestamp`, which are block-level values rather than user-specific entropy, making the result predictable for block builders and identical across all mints in the same block.",
    "impact": "A proposer/builder or any user with private-orderflow access can simulate the block outcome and include mint transactions only in winning blocks. Because every mint in the same block shares the same random bit, once a block is known to be lucky an attacker can batch many mints and drain the prize pool much faster than intended.",
    "paths": [
      "Attacker sends mint transactions through a builder/relay that can simulate the block outcome",
      "Builder includes the transaction only when `keccak256(block.difficulty, block.timestamp) % 2 == 1`",
      "All mints included in that block inherit the same lucky result",
      "Attacker batches repeated `publicMint()` calls to extract repeated payouts from the pool"
    ]
  },
  {
    "id": "F-004",
    "severity": "Medium",
    "confidence": "low",
    "title": "Immutable `send`-based payout target can permanently brick withdrawals and winning mints",
    "locations": [
      "onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1344",
      "onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1408",
      "onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1425",
      "onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1430",
      "onchain_auto/0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1431"
    ],
    "claim": "Critical ETH flows rely on `send()` to a hardcoded `withdrawAddress`, but `send()` forwards only 2300 gas and the address cannot be updated, so any revert or non-payable recipient permanently breaks those code paths.",
    "impact": "If `withdrawAddress` is, or later becomes, a contract that rejects plain ETH transfers, every winning mint reverts at the 5%/10% fee transfer and `withdraw()` can never empty the contract. Because there is no setter or escape hatch, ETH can become permanently trapped and prize mints become unavailable.",
    "paths": [
      "`withdrawAddress` is a contract with a reverting or non-trivial receive/fallback function",
      "A user hits the lucky branch in `freeMint()` or `publicMint()`",
      "The fee transfer to `withdrawAddress` fails, causing the entire mint to revert",
      "Owner also cannot recover ETH because `withdraw()` uses the same `send()` pattern"
    ]
  }
]

```

### Agent: opencode_1
```
[{"id":"F-001","severity":"High","confidence":"high","title":"Access Control Bypass in freeMint Function","locations":["0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1395-1409"],"claim":"The freeMint function accepts a _user parameter to check whitelist but mints to msg.sender. An attacker can bypass the whitelist requirement by using any whitelisted address as _user while calling from a non-whitelisted address.","impact":"Non-whitelisted users can mint for free by using any whitelisted address as parameter, bypassing the whitelist restriction and consuming whitelist slots intended for legitimate users.","paths":["1. Attacker calls freeMint(_whitelistedUser) where attacker is not in whitelist but _whitelistedUser is\n2. Check whiteLists[_user] passes because _whitelistedUser is in whitelist\n3. NFT is minted to msg.sender (attacker)\n4. Whitelist spot of _whitelistedUser is consumed"]},{"id":"F-002","severity":"High","confidence":"high","title":"Predictable Random Number Generation","locations":["0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1436-1441"],"claim":"The _getRandom function uses block.difficulty and block.timestamp which are predictable and controllable by miners/validators.","impact":"The 'lucky' outcome determining prize status can be manipulated by miners, allowing them to influence which tokens receive prize status and potentially profit from prize refunds.","paths":["1. Miner/validator can influence block.difficulty and block.timestamp\n2. Can potentially predict and manipulate random outcome\n3. May mint repeatedly to find favorable blocks"]},{"id":"F-003","severity":"High","confidence":"high","title":"Reentrancy and Silent Failure in ETH Transfers","locations":["0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1407-1408","0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1424-1425","0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1431"],"claim":"The contract uses .send() which has limited gas (2300) and fails silently without reverting. Additionally, external calls precede state modifications, violating checks-effects-interactions pattern.","impact":"ETH transfers can fail silently, leaving contract state inconsistent. Refunds may not be sent, prize commissions may not be paid, and funds may become locked in contract.","paths":["1. If recipient is a contract requiring >2300 gas in fallback, .send() fails\n2. require() after .send() catches failure but state already modified (token minted)\n3. In withdraw, if withdrawAddress is a contract, transfer may fail silently"]},{"id":"F-004","severity":"Medium","confidence":"high","title":"Incorrect Price Calculation in freeMint","locations":["0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1407-1408"],"claim":"The freeMint function is supposed to be free but processes a 95% price refund to the user and 5% commission to withdrawAddress when the token is 'lucky'.","impact":"Users calling freeMint expect to get tokens for free but are unexpectedly refunded (95% of price) only if lucky, creating misleading user experience and potential financial loss for users who don't understand the mechanism.","paths":["1. User calls freeMint expecting free NFT\n2. If token is lucky, user receives 95% price refund (0.0095 ETH)\n3. User may lose money on transaction fees expecting free mint"]},{"id":"F-005","severity":"Medium","confidence":"medium","title":"Missing Access Control on addBonusPool Function","locations":["0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1386-1387"],"claim":"The addBonusPool function is public and payable but has no access control, allowing anyone to send ETH to the contract.","impact":"Any user can send ETH to the contract. While not directly harmful, this could lead to unintended accumulation of funds or be used to send dust amounts to clutter the contract.","paths":["1. Any user calls addBonusPool() with value\n2. ETH is added to contract balance\n3. Only owner can withdraw these funds"]},{"id":"F-006","severity":"Low","confidence":"high","title":"Unused withdrawAddress Update Functionality","locations":["0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1344"],"claim":"The withdrawAddress is set as a public immutable-like variable but there is no function to update it by the owner.","impact":"If the withdrawAddress private key is compromised or the address becomes unusable, funds cannot be redirected to a new safe address, potentially leading to permanent fund loss.","paths":["1. withdrawAddress private key compromised\n2. No way to change withdrawAddress\n3. Funds stuck forever"]},{"id":"F-007","severity":"Low","confidence":"medium","title":"Missing Event Emission in Critical Functions","locations":["0x9c87a5726e98f2f404cdd8ac8968e9b2c80c0967/Contract.sol:1363-1382"],"claim":"The setWhiteLists, removeWhitelistUser, setMintPrice, and setPauseMint functions do not emit events.","impact":"Off-chain monitoring and indexing is difficult as there are no events to track important state changes like whitelist modifications, price changes, or mint pause status changes.","paths":["1. External systems cannot easily track important state changes\n2. Difficult to build proper indexers for the contract"]}]

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
