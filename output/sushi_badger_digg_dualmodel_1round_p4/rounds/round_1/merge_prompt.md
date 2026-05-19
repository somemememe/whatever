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
    "severity": "Critical",
    "confidence": "high",
    "title": "MasterChef migrator can replace real LP collateral with worthless tokens and steal all staked funds",
    "locations": [
      "0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/MasterChef.sol:132",
      "0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/MasterChef.sol:137",
      "0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/MasterChef.sol:142",
      "0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/Migrator.sol:28"
    ],
    "claim": "The owner can set an arbitrary migrator, and `migrate()` grants that migrator approval over the pool's entire LP balance before only checking that the returned replacement token reports the same `balanceOf`. A malicious migrator can transfer out the real LP tokens, mint or spoof an equal balance of a fake token to MasterChef, and permanently switch the pool to that worthless token.",
    "impact": "All LP tokens staked in the migrated pool can be stolen, while users are left holding claim receipts for a fake replacement asset when they withdraw.",
    "paths": [
      "Owner calls `setMigrator(maliciousMigrator)`",
      "Anyone calls `migrate(pid)`",
      "Malicious migrator uses the approval to pull all real LP tokens from MasterChef",
      "Migrator returns a fake token that gives MasterChef a matching `balanceOf`",
      "Pool token is replaced and user withdrawals return worthless tokens"
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "high",
    "title": "SUSHI governance votes are not updated on transfers, enabling double-counted voting power",
    "locations": [
      "0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/SushiToken.sol:12",
      "0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/SushiToken.sol:184",
      "0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/@openzeppelin/contracts/token/ERC20/ERC20.sol:115",
      "0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/@openzeppelin/contracts/token/ERC20/ERC20.sol:152",
      "0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/@openzeppelin/contracts/token/ERC20/ERC20.sol:208"
    ],
    "claim": "Vote checkpoints are updated on mint and explicit delegation, but token transfers use the inherited OZ ERC20 logic and never call `_moveDelegates`. A holder can delegate, transfer tokens away, and retain the old votes while the recipient can also delegate the received tokens, inflating total governance power above total supply.",
    "impact": "Governance can be captured or proposals can pass with phantom votes that are no longer backed by token ownership.",
    "paths": [
      "Alice delegates 100 SUSHI to herself",
      "Alice transfers the 100 SUSHI to Bob",
      "Alice keeps 100 recorded votes because no transfer hook moves delegates",
      "Bob delegates the received 100 SUSHI and obtains another 100 votes"
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "high",
    "title": "First xSUSHI minter can steal all SUSHI sent to SushiBar before staking starts",
    "locations": [
      "0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/SushiBar.sol:23",
      "0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/SushiBar.sol:29",
      "0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/SushiBar.sol:43",
      "0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/SushiMaker.sol:195"
    ],
    "claim": "When `totalShares == 0`, `enter()` mints xSUSHI 1:1 with the caller's deposit and ignores any SUSHI that is already sitting in the bar. If SushiBar receives SUSHI before the first staker arrives, the first depositor can mint a tiny number of shares and then redeem them for the entire prefunded balance.",
    "impact": "Any bootstrap fees, direct donations, or early SushiMaker conversions sent to SushiBar before the first real staker can be completely stolen by a dust-sized first deposit.",
    "paths": [
      "SushiBar receives SUSHI before any xSUSHI exists",
      "Attacker calls `enter(1)` and receives 1 xSUSHI",
      "Attacker immediately calls `leave(1)`",
      "Attacker withdraws the entire SushiBar SUSHI balance, not just the 1 deposited token"
    ]
  },
  {
    "id": "F-004",
    "severity": "Medium",
    "confidence": "high",
    "title": "Transient xSUSHI holders can capture SushiMaker fee conversions meant for long-term stakers",
    "locations": [
      "0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/SushiMaker.sol:85",
      "0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/SushiMaker.sol:195",
      "0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/SushiBar.sol:23",
      "0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/SushiBar.sol:43"
    ],
    "claim": "SushiMaker sends converted SUSHI directly to SushiBar at the moment `convert()` is called, and SushiBar share ownership is purely snapshot-less. An attacker can temporarily acquire most xSUSHI shares just before conversion, trigger `convert()`, and then exit to reclaim most of the newly added SUSHI even though they only held the shares momentarily.",
    "impact": "Fee revenue intended for long-term xSUSHI stakers can be siphoned by short-term capital, especially around large pending conversions.",
    "paths": [
      "Attacker deposits a large amount of SUSHI into SushiBar to dominate xSUSHI supply",
      "Attacker calls `SushiMaker.convert(...)` while holding most shares",
      "Converted SUSHI is transferred to SushiBar",
      "Attacker exits SushiBar and withdraws a disproportionate share of that conversion"
    ]
  },
  {
    "id": "F-005",
    "severity": "Medium",
    "confidence": "high",
    "title": "Stale `pendingOwner` survives direct ownership transfer and can later seize SushiMaker",
    "locations": [
      "0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/BoringOwnable.sol:30",
      "0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/BoringOwnable.sol:36",
      "0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/BoringOwnable.sol:46",
      "0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/SushiMaker.sol:17"
    ],
    "claim": "`transferOwnership(..., direct=true, ...)` updates `owner` but never clears an existing `pendingOwner`. If ownership was previously offered to address A and later directly transferred to address B, A can still call `claimOwnership()` and take the contract away from B.",
    "impact": "A stale pending owner can unexpectedly regain ownership of SushiMaker and then alter bridge routes or otherwise sabotage or redirect fee conversions.",
    "paths": [
      "Current owner calls `transferOwnership(alice, false, false)`",
      "Before Alice claims, owner calls `transferOwnership(bob, true, false)`",
      "Alice later calls `claimOwnership()` and becomes owner, overriding Bob"
    ]
  },
  {
    "id": "F-006",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Reentrant pool tokens can double-claim rewards because MasterChef updates debt after external calls",
    "locations": [
      "0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/MasterChef.sol:203",
      "0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/MasterChef.sol:214",
      "0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/MasterChef.sol:217",
      "0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/MasterChef.sol:222",
      "0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/MasterChef.sol:233",
      "0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/MasterChef.sol:235"
    ],
    "claim": "In both `deposit()` and `withdraw()`, MasterChef performs external token transfers before updating `user.rewardDebt`. If a listed pool token is hook-enabled or malicious, it can reenter `deposit(0)` or `withdraw(0)` during `safeTransferFrom`/`safeTransfer` and observe the old `rewardDebt`, allowing the same pending reward to be paid multiple times.",
    "impact": "A malicious or callback-enabled pool token can drain SUSHI rewards from its pool and potentially from the MasterChef balance as a whole.",
    "paths": [
      "Attacker stakes in a pool whose LP token can reenter on transfer",
      "Attacker calls `deposit(pid, amount)` with pending rewards accrued",
      "MasterChef pays pending SUSHI, then calls `lpToken.safeTransferFrom(...)` before updating `rewardDebt`",
      "Token reenters `deposit(pid, 0)` or `withdraw(pid, 0)` and claims the same pending reward again"
    ]
  },
  {
    "id": "F-007",
    "severity": "Medium",
    "confidence": "medium",
    "title": "MasterChef over-credits fee-on-transfer tokens, creating withdrawal insolvency and cross-user loss",
    "locations": [
      "0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/MasterChef.sol:214",
      "0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/MasterChef.sol:215",
      "0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/MasterChef.sol:232",
      "0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/MasterChef.sol:233"
    ],
    "claim": "Deposits credit `user.amount += _amount` based on the requested amount rather than the amount actually received by the contract. If a listed pool token charges transfer fees or burns on transfer, users are credited for more shares than the pool holds, so later withdrawals either drain other users' funds or revert due to insufficient token balance.",
    "impact": "Pools using deflationary or taxed tokens can become insolvent, causing user fund loss or permanent inability to withdraw the full recorded balance.",
    "paths": [
      "A fee-on-transfer token is added as a pool token",
      "User deposits 100 tokens but MasterChef receives only 90",
      "MasterChef still records `user.amount = 100`",
      "When users withdraw, the contract owes more tokens than it holds"
    ]
  }
]

```

### Agent: opencode_1
```
Let me read the main contracts to identify security vulnerabilities.
Now I have a good understanding of the contracts. Let me compile the security vulnerabilities I've found:
Now I have reviewed the contracts and identified several security vulnerabilities. Let me compile the findings:

[{"id":"F-001","severity":"Critical","confidence":"high","title":"Missing Parentheses in SushiMaker._swap Causes Incorrect Amount Calculation","locations":["0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/SushiMaker.sol:181","0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/SushiMaker.sol:186"],"claim":"The _swap function in SushiMaker has missing parentheses in the amountOut calculation formula. At line 181: `amountIn.mul(997).mul(reserve1) / reserve0.mul(1000).add(amountInWithFee)` is computed as `amountIn * 997 * reserve1 / reserve0 * 1000 + amountIn * 997` instead of the correct `amountIn * 997 * reserve1 / (reserve0 * 1000 + amountIn * 997)`","impact":"Users receive significantly less output tokens than expected during swaps, causing permanent loss of funds. The protocol will lose tokens in every conversion operation.","paths":["Call SushiMaker.convert() or convertMultiple() with any token pair - the incorrect formula will cause the protocol to lose value on each swap"]},{"id":"F-002","severity":"High","confidence":"high","title":"Migrator Can Drain All LP Tokens from MasterChef","locations":["0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/MasterChef.sol:137-146"],"claim":"The migrate() function can be called by anyone (not just owner) and gives the migrator full control over LP tokens. Once a migrator is set by the owner, anyone can trigger `migrator.migrate(lpToken)` which approves all LP tokens to the migrator contract.","impact":"A malicious or compromised migrator contract can drain all LP tokens from MasterChef, causing permanent loss of all staked funds.","paths":["1. Owner sets a malicious migrator via setMigrator()\n2. Anyone calls migrate() with any pool ID\n3. Migrator receives approval for all LP tokens and transfers them out"]},{"id":"F-003","severity":"High","confidence":"high","title":"Timelock Allows Arbitrary Contract Execution Without Validation","locations":["0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/Timelock.sol:103-128"],"claim":"The executeTransaction() function executes arbitrary calls to any target address without validating that the target is a known safe contract. It also uses low-level .call() without specifying gas limits.","impact":"If the admin account is compromised, the attacker can execute arbitrary calls to any contract, potentially stealing funds from any contract the admin has access to. No protection against reentrancy or malicious targets.","paths":["1. Compromise admin account\n2. Queue and execute transaction to malicious target\n3. Target can call back into Timelock or other vulnerable contracts"]},{"id":"F-004","severity":"Medium","confidence":"medium","title":"SushiRoll Migration Lacks Slippage Protection for New Pools","locations":["0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/SushiRoll.sol:42-72"],"claim":"The migrate() function uses amountAMin and amountBMin only for the removeLiquidity call on the old router, but doesn't verify that the amount of new LP tokens received provides adequate value.","impact":"If the new SushiSwap pool has worse rates or if price moves significantly during the migration, users could receive significantly fewer tokens than expected with no protection.","paths":["1. User calls migrate() with small slippage parameters\n2. Price moves significantly between removeLiquidity and addLiquidity\n3. User receives less than expected tokens"]},{"id":"F-005","severity":"Medium","confidence":"high","title":"MasterChef Dev Fee Not Transparent","locations":["0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/MasterChef.sol:196"],"claim":"The updatePool() function mints 10% of rewards to the dev address without any user disclosure or opt-out mechanism. The dev address can be changed by the current dev.","impact":"Users stake in the protocol without knowing that 10% of rewards are diverted to a developer address. The dev can also change the dev address to redirect fees.","paths":["1. User deposits into MasterChef\n2. Rewards are distributed with 10% going to devaddr\n3. Dev can change dev address to redirect fees"]},{"id":"F-006","severity":"Medium","confidence":"medium","title":"MasterChef SafeSushiTransfer May Distribute Incorrect Amounts","locations":["0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/MasterChef.sol:251-258"],"claim":"The safeSushiTransfer function transfers the full balance if pending reward exceeds balance, rather than reverting. This can cause users to receive more than their pending reward when the pool is depleted.","impact":"When the contract doesn't have enough SUSHI to pay all pending rewards, early withdrawers may receive more than their fair share, leaving later withdrawers with nothing.","paths":["1. Large reward distribution occurs\n2. Multiple users withdraw simultaneously\n3. Early users get full balance, later users get nothing"]},{"id":"F-007","severity":"Low","confidence":"high","title":"MasterChef Pool Allocation Points Have No Upper Bound","locations":["0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/MasterChef.sol:108-120"],"claim":"The add() function allows setting any allocPoint value without upper bound check. Total allocPoint can become extremely large.","impact":"Very large allocation points could cause precision issues in reward calculations due to integer division limitations.","paths":["Owner calls add() with extremely large allocation points"]},{"id":"F-008","severity":"Low","confidence":"medium","title":"SushiToken Uses Deprecated `now` Keyword","locations":["0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/SushiToken.sol:121"],"claim":"The delegateBySig function uses `now` for signature expiry check which is deprecated in favor of `block.timestamp`.","impact":"Code maintainability and future compatibility issues. `now` may be removed in future Solidity versions.","paths":["None - this is a code quality issue"]},{"id":"F-009","severity":"Informational","confidence":"high","title":"SushiBar Enter/Leave Functions Subject to Rounding Loss","locations":["0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/SushiBar.sol:23-50"],"claim":"The enter() and leave() functions use integer division which can result in users losing small amounts of tokens due to rounding.","impact":"Users may lose up to a few wei of tokens per transaction due to division truncation.","paths":["User repeatedly enters and leaves SushiBar - small amounts lost per transaction"]},{"id":"F-010","severity":"High","confidence":"medium","title":"SushiMaker onlyEOA Modifier Can Be Bypassed Via Smart Contract","locations":["0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/SushiMaker.sol:73-77"],"claim":"The onlyEOA modifier checks msg.sender == tx.origin but can be bypassed by calling from a separately deployed contract that isn't a proxy. The SushiMakerExploitMock demonstrates this vulnerability.","impact":"Flash loan attacks could potentially be executed if the onlyEOA check can be bypassed, allowing manipulation of xSushi balances.","paths":["1. Deploy a contract that calls SushiMaker.convert()\n2. This contract has msg.sender != tx.origin (contract vs EOA)\n3. However, the check still passes since tx.origin is the original caller"]},{"id":"F-011","severity":"Medium","confidence":"medium","title":"Timelock Receive Function Allows Direct ETH Transfers","locations":["0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/Timelock.sol:51"],"claim":"The receive() function accepts direct ETH transfers without any control or logging.","impact":"ETH can be sent directly to Timelock but can only be recovered via executeTransaction, creating potential for locked funds if admin is unavailable.","paths":["Any EOA sends ETH directly to Timelock contract"]}]

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
