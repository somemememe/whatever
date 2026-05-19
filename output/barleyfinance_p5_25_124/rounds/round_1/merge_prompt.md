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
    "title": "First caller can seize the referral hook and freeze or siphon all staking rewards",
    "locations": [
      "0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/TokenRewards.sol:64",
      "0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/TokenRewards.sol:65",
      "0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/TokenRewards.sol:68",
      "0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/TokenRewards.sol:223",
      "0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/StakingPoolToken.sol:92",
      "0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/StakingPoolToken.sol:96"
    ],
    "claim": "TokenRewards has no trusted initializer: while `referral` is unset, any address can call `updateReferral()` and install an arbitrary referral contract, and all later reward claims and share updates blindly trust that contract for `owner()` and `getRelationsREF()`.",
    "impact": "An attacker who initializes `referral` first can permanently control reward routing. A malicious referral contract can return attacker-controlled referrers to skim every reward distribution, or simply revert in `getRelationsREF()` and brick `claimReward()`, staking-token transfers, and `unstake()` for users with accrued rewards, effectively locking staked LP positions until the attacker-controlled referral is replaced.",
    "paths": [
      "Call `TokenRewards.updateReferral(maliciousReferral)` before the legitimate referral contract is set.",
      "Have `maliciousReferral.getRelationsREF()` revert so `_distributeReward()` fails during `claimReward()` or `StakingPoolToken._afterTokenTransfer()`.",
      "Alternatively, have `maliciousReferral.getRelationsREF()` return attacker addresses so referral rewards are redirected on every payout."
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "high",
    "title": "Anyone can front-run a user's first claim and permanently assign attacker-controlled referrers",
    "locations": [
      "0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/TokenRewards.sol:279",
      "0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/TokenRewards.sol:280",
      "0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/TokenRewards.sol:281",
      "0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/TokenRewards.sol:283"
    ],
    "claim": "`claimReward(address _wallet, address _referrer)` does not require `_wallet == msg.sender`, yet it can call `referral.setReferral(_referrer, _wallet)` whenever the wallet has not been initialized.",
    "impact": "Any attacker can front-run a victim's first reward claim and bind the victim to attacker-controlled referral addresses. That permanently diverts the protocol's referral share from all future reward distributions for that victim without ever needing control of the victim wallet.",
    "paths": [
      "Watch for a staker whose referral has not been set yet.",
      "Front-run with `claimReward(victim, attackerReferrer)`.",
      "All later `_distributeReward(victim)` calls pay the referral cut to the attacker-controlled referral tree."
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "medium",
    "title": "Bond mints redeemable index tokens before collecting the full basket, enabling malicious-asset reentrancy",
    "locations": [
      "0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/WeightedIndex.sol:121",
      "0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/WeightedIndex.sol:124",
      "0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/WeightedIndex.sol:128",
      "0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/WeightedIndex.sol:136",
      "0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/DecentralizedIndex.sol:133",
      "0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/DecentralizedIndex.sol:134"
    ],
    "claim": "`WeightedIndex.bond()` mints index tokens to the caller before the contract has finished pulling all component assets, and the subsequent `_transferAndValidate()` calls invoke untrusted ERC20 `transferFrom()` logic without any reentrancy guard.",
    "impact": "If any listed index asset is malicious or hook-enabled, its `transferFrom()` can reenter after the attacker has already received freshly minted index tokens but before the full basket has been paid in. The attacker can then redeem against the index's existing honest reserves, leaving the fund undercollateralized and extracting value from other holders.",
    "paths": [
      "Create or interact with an index that includes a malicious/reentrant asset.",
      "Call `bond()` so `_mint()` credits the attacker before the asset-transfer loop completes.",
      "Reenter from the malicious asset's `transferFrom()` into `debond()` using the newly minted index tokens."
    ]
  },
  {
    "id": "F-004",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Dust total supply makes the auto-fee path call a zero-amount swap and can freeze transfers",
    "locations": [
      "0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/DecentralizedIndex.sol:94",
      "0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/DecentralizedIndex.sol:96",
      "0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/DecentralizedIndex.sol:100",
      "0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/DecentralizedIndex.sol:108",
      "0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/DecentralizedIndex.sol:145"
    ],
    "claim": "The transfer hook computes `_min = totalSupply() / 10000`; once supply falls below 10,000 base units, `_min` becomes zero and every eligible transfer executes `_feeSwap(0)`.",
    "impact": "After supply is debonded down to dust while LP still exists, remaining holders can be unable to transfer or sell their index tokens because each transfer enters the zero-input fee-swap path and the downstream swap reverts instead of no-oping.",
    "paths": [
      "Reduce the circulating supply to below 10,000 wei of the index token while `V2_POOL` still has liquidity.",
      "Trigger any transfer or sell from a non-pool address.",
      "The transfer hook calls `_feeSwap(0)`, causing the transfer to revert."
    ]
  },
  {
    "id": "F-005",
    "severity": "Medium",
    "confidence": "low",
    "title": "Repeated failed reward swaps can underflow slippage math and strand DAI fees",
    "locations": [
      "0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/TokenRewards.sol:40",
      "0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/TokenRewards.sol:154",
      "0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/TokenRewards.sol:163",
      "0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/TokenRewards.sol:175"
    ],
    "claim": "On every failed `exactInputSingle()` call, `_rewardsSwapSlippage` is incremented by 10 and later used inside `(1000 - _rewardsSwapSlippage)` under Solidity 0.7 unchecked arithmetic.",
    "impact": "If an attacker can force enough consecutive swap failures while the rewards contract holds DAI, `_rewardsSwapSlippage` eventually exceeds 1000 and the min-out calculation wraps. From that point, DAI-to-reward conversions can keep failing indefinitely, causing auto-collected DAI fees and flash-loan fees to accumulate in `TokenRewards` instead of reaching stakers.",
    "paths": [
      "Ensure `TokenRewards` holds DAI and repeatedly make `exactInputSingle()` fail.",
      "Call `depositFromDAI(0)` enough times for `_rewardsSwapSlippage` to exceed 1000.",
      "Future conversions use wrapped `amountOutMinimum` values and continue failing, leaving DAI stuck."
    ]
  }
]

```

### Agent: opencode_1
```
Let me read the main contracts to identify vulnerabilities.
Let me also read the interfaces to better understand the contract interactions.
Based on my audit, I've identified several security vulnerabilities in these contracts. Let me compile the findings:

```json
[
  {
    "id": "F-001",
    "severity": "Critical",
    "confidence": "high",
    "title": "Unrestricted Rescue Functions Allow Draining of Protocol Assets",
    "locations": ["DecentralizedIndex.sol:254-261", "DecentralizedIndex.sol:263-276"],
    "claim": "The rescueERC20() and rescueETH() functions have no access control and can drain any tokens not marked as index assets, including LP tokens held in the contract.",
    "impact": "The LP tokens (V2_POOL) and any other non-index tokens can be stolen by anyone calling these functions. An attacker could drain the LP tokens that were supposed to be locked in the protocol.",
    "paths": ["1. Call rescueERC20() with V2_POOL address to drain LP tokens", "2. Call rescueETH() to drain any ETH in the contract"]
  },
  {
    "id": "F-002",
    "severity": "Critical",
    "confidence": "high",
    "title": "Unrestricted Staking Pool Token Transfers Bypass Stake Restrictions",
    "locations": ["StakingPoolToken.sol:68-98"],
    "claim": "The _transfer() function has no restriction checks - tokens can be transferred to any address, bypassing the stakeUserRestriction that was intended to only allow staking by specific users.",
    "impact": "Anyone can transfer staking pool tokens to addresses other than the restricted user, potentially allowing the restricted user to bypass their stake limitation by having others hold tokens on their behalf.",
    "paths": ["1. Restricted user stake is limited by stakeUserRestriction", "2. Others can transfer tokens to restricted user after stake"]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "high",
    "title": "Division by Zero in WeightedIndex Constructor",
    "locations": ["WeightedIndex.sol:68"],
    "claim": "If the first token's weight (_weights[0]) is 0, the calculation (FixedPoint96.Q96 * _totalWeights) / _weights[0] will cause division by zero.",
    "impact": "Deployment will fail if any token weight is 0, potentially causing funds locked in constructor to be permanently stuck.",
    "paths": ["1. Deploy WeightedIndex with _weights[0] = 0"]
  },
  {
    "id": "F-004",
    "severity": "High",
    "confidence": "high",
    "title": "Uniswap V2 Price Manipulation via Flash Loans",
    "locations": ["WeightedIndex.sol:76-115"],
    "claim": "Token prices are fetched from Uniswap V2 pairs using on-chain reserves which can be manipulated with flash loans. Bond/debond operations use these prices without any TWAP oracle protection.",
    "impact": "An attacker can manipulate the price in one block, perform bond/debond at favorable rates, then reverse the manipulation in the same transaction, extracting value from the protocol.",
    "paths": ["1. Flash loan to manipulate Uniswap V2 reserves", "2. Call bond() or debond() with manipulated prices", "3. Flash loan repayment"]
  },
  {
    "id": "F-005",
    "severity": "High",
    "confidence": "medium",
    "title": "Flash Loan Callback Without Reentrancy Protection",
    "locations": ["DecentralizedIndex.sol:235-252"],
    "claim": "The flash() function calls the callback (IFlashLoanRecipient(_recipient).callback(_data)) without a reentrancy guard, allowing the recipient to call back into the contract during execution.",
    "impact": "A malicious flash loan recipient could reenter the contract during the callback, potentially manipulating state or executing operations that should not be allowed during a flash loan.",
    "paths": ["1. Call flash() with malicious _recipient", "2. In callback, call back into bond() or other functions", "3. Exploit state inconsistencies"]
  },
  {
    "id": "F-006",
    "severity": "High",
    "confidence": "high",
    "title": "Referral Contract Ownership Not Verified - Anyone Can Change Referral",
    "locations": ["TokenRewards.sol:64-71"],
    "claim": "The updateReferral() function checks _msgSender() == referral.owner() only AFTER the first referral is set. However, the initial referral assignment has no access control check - anyone can set any referral contract on first call.",
    "impact": "The first caller of updateReferral() can set any arbitrary referral contract, gaining control over all future referral updates and potentially redirecting referral rewards.",
    "paths": ["1. Call updateReferral() as first caller with malicious referral contract", "2. All future referral distributions can be manipulated"]
  },
  {
    "id": "F-007",
    "severity": "High",
    "confidence": "medium",
    "title": "Insufficient Slippage Protection on Token Swap",
    "locations": ["TokenRewards.sol:141-164"],
    "claim": "The swap uses TWAP oracle prices to calculate expected output but the slippage tolerance (1%) is applied to TWAP price, not the actual market price. This provides insufficient protection against MEV/sandwich attacks.",
    "impact": "Users swapping DAI for rewards tokens can be sandwiched, resulting in significantly worse execution than expected. The 1% slippage tolerance is applied to a potentially stale TWAP price.",
    "paths": ["1. User calls depositFromDAI()", "2. MEV bot sandwiches the transaction", "3. User receives less tokens than expected"]
  },
  {
    "id": "F-008",
    "severity": "Medium",
    "confidence": "high",
    "title": "No Validation of Token Decimals in WeightedIndex",
    "locations": ["WeightedIndex.sol:70-72"],
    "claim": "The q1 calculation uses 10 ** IERC20Metadata(_tokens[_i]).decimals() without checking that decimals() returns a reasonable value. If a token returns 0 or an extreme value, calculations will be incorrect.",
    "impact": "Malicious or buggy token returning extreme decimals could cause bond() calculations to fail or produce incorrect token mint amounts.",
    "paths": ["1. Use token with 0 decimals in index", "2. Bond operations produce incorrect results"]
  },
  {
    "id": "F-009",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Unchecked Return Value in ETH Transfer",
    "locations": ["DecentralizedIndex.sol:272-275"],
    "claim": "The low-level call (bool _sent, ) = owner().call{value: _amount}('') does not verify the return value properly - if call fails, _sent will be false but function continues.",
    "impact": "If ETH transfer fails, the function still returns without reverting, potentially causing inconsistent state where ETH is not rescued but function reports success.",
    "paths": ["1. Call rescueETH() when recipient cannot receive ETH", "2. ETH remains in contract but no error thrown"]
  },
  {
    "id": "F-010",
    "severity": "High",
    "confidence": "medium",
    "title": "Potential Integer Overflow in Price Calculations",
    "locations": ["WeightedIndex.sol:86-93", "WeightedIndex.sol:108-115"],
    "claim": "Price calculations multiply large numbers (Q96 * reserves * 10^decimals) without SafeMath, potentially causing overflow on Solidity 0.7.x which does not have built-in overflow checks.",
    "impact": "On integer overflow, price calculations will produce incorrect values, potentially allowing attackers to bond at manipulated/incorrect rates.",
    "paths": ["1. Certain reserve sizes and decimal combinations cause overflow", "2. Incorrect prices used in bond/debond"]
  },
  {
    "id": "F-011",
    "severity": "High",
    "confidence": "medium",
    "title": "Missing Zero-Address Validation in Constructor",
    "locations": ["DecentralizedIndex.sol:53-87", "TokenRewards.sol:51-62"],
    "claim": "Constructors do not validate critical input parameters like _dai, _v2Router, _lpRewardsToken, and _v3TwapUtilities. Zero addresses could cause irreversible issues.",
    "impact": "Deploying with zero addresses will cause all subsequent operations to fail, potentially locking user funds in LP pairs that cannot be recovered.",
    "paths": ["1. Deploy with zero address for DAI or router", "2. All subsequent operations fail permanently"]
  },
  {
    "id": "F-012",
    "severity": "Medium",
    "confidence": "high",
    "title": "Missing Access Control on StakingPoolToken Admin Functions",
    "locations": ["StakingPoolToken.sol:60-66"],
    "claim": "The removeStakeUserRestriction() and setStakeUserRestriction() functions use onlyRestricted modifier but the restricted user could be address(0) making these functions inaccessible forever after deployment.",
    "impact": "If stakeUserRestriction is set to address(0) (when _stakeRestriction=false), these functions can never be called, locking the restriction management permanently.",
    "paths": ["1. Deploy with _stakeRestriction=false", "2. Cannot ever change stake restrictions"]
  }
]
```

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
