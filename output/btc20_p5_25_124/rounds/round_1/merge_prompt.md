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
    "title": "Upgradeable presale has no initializer, leaving owner and all core config permanently unset",
    "locations": [
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:31",
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:78",
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol:29"
    ],
    "claim": "PresaleV5 inherits upgradeable modules but never exposes an external initializer that calls __Ownable_init / __Pausable_init / any config setup. The constructor only marks the implementation as initialized, so a proxy deployment starts with owner == address(0) and all sale parameters unset.",
    "impact": "All onlyOwner administration paths are unreachable in the live proxy state, so the sale cannot be configured, paused, started for claim, or repaired through this implementation. Any funds or accounting later routed into the proxy can become stuck behind an ownerless contract until the proxy admin deploys and upgrades to a different implementation.",
    "paths": [
      "Deploy PresaleV5 behind TransparentUpgradeableProxy with empty or arbitrary _data",
      "Proxy storage keeps owner, paymentWallet, aggregatorInterface, USDTInterface, saleToken, timings, and prices at zero values",
      "Every onlyOwner function reverts forever because no account can satisfy owner() == msg.sender"
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "high",
    "title": "Claim schedule is never enforced, so users can withdraw before claimStart",
    "locations": [
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:130",
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:151",
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:164",
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:181"
    ],
    "claim": "Although the contract stores claimStart and even exposes changeClaimStart, neither claim() nor claimAndStake() checks block.timestamp against claimStart.",
    "impact": "As soon as startClaim funds the contract and a participant is whitelisted, they can bypass the intended vesting/TGE delay and immediately pull or stake their full allocation. That breaks any promised lockup schedule and can enable early dumping or unfair staking rewards.",
    "paths": [
      "Owner calls startClaim with a future _claimStart and funds the contract",
      "Participant is present in userDeposits and isWhitelisted",
      "Participant calls claim() or claimAndStake() before claimStart and receives the allocation anyway"
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "high",
    "title": "Claim funding check is ineffective because totalTokensSold is never updated",
    "locations": [
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:32",
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:130",
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:273"
    ],
    "claim": "startClaim() tries to require enough sale tokens via noOfTokens >= totalTokensSold * baseDecimals, but totalTokensSold is never incremented anywhere, while updateFromBSC() can increase userDeposits arbitrarily.",
    "impact": "The contract can enter the claim phase with far fewer tokens than users are owed. Early claimers drain the pool and later claimers revert on transfer, creating a permanent shortfall and lockup of purchased allocations.",
    "paths": [
      "Owner imports claim balances through updateFromBSC(), increasing userDeposits while totalTokensSold stays 0",
      "Owner calls startClaim() with too few tokens; the check still passes because totalTokensSold was never updated",
      "Some users claim successfully, then later claimants fail once the contract balance is exhausted"
    ]
  },
  {
    "id": "F-004",
    "severity": "High",
    "confidence": "medium",
    "title": "USDT purchase paths accept non-reverting calls as payment success",
    "locations": [
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:304",
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:310",
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:333",
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:339"
    ],
    "claim": "buyWithUSDT() and buyWithUSDTDynamic() use a raw low-level call to transferFrom and only require the CALL opcode to succeed; they never decode the returned bool and never verify that the target is a token contract.",
    "impact": "If the configured payment token returns false instead of reverting, or is misconfigured to a non-contract address, the functions still continue and allocate stake/tokens without receiving payment. That can let an attacker or bad configuration drain inventory for free.",
    "paths": [
      "USDTInterface points to a token that returns false on failed transferFrom, or to an address with no code",
      "Buyer calls buyWithUSDT() or buyWithUSDTDynamic() without actually transferring funds",
      "require(success) passes and the contract still credits staking or transfers sale tokens"
    ]
  },
  {
    "id": "F-005",
    "severity": "High",
    "confidence": "medium",
    "title": "Staking manager is never validated, so purchases can succeed while recording no stake",
    "locations": [
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:139",
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:191",
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:284",
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:297",
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:312"
    ],
    "claim": "The contract blindly casts any address to StakingManager and treats depositByPresale() as successful without checking code size, return data, or any post-condition.",
    "impact": "If stakingManagerInterface/stakingContract is set to address(0), an EOA, or an incompatible contract, buyWithEth(), buyWithUSDT(), and claimAndStake() can complete without creating any stake position. Users can therefore pay funds or burn their claim balance yet receive nothing on the staking side.",
    "paths": [
      "stakingManagerInterface is configured to an EOA or wrong contract",
      "User calls buyWithEth() or buyWithUSDT(); payment is forwarded and event emitted",
      "The external call trivially succeeds but no stake is recorded anywhere"
    ]
  },
  {
    "id": "F-006",
    "severity": "Medium",
    "confidence": "high",
    "title": "Configured sale window is dead code and does not restrict any purchase path",
    "locations": [
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:118",
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:289",
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:304",
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:317",
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:333"
    ],
    "claim": "The contract defines checkSaleState() to enforce startTime/endTime, but none of the four buy functions use it; purchases are gated only by dynamicSaleState and maxTokensToSell.",
    "impact": "Whenever dynamicSaleState is enabled, users can buy before the intended opening time or after the intended closing time. This breaks sale scheduling, round controls, and any compliance assumptions tied to the configured window.",
    "paths": [
      "Owner/admin enables dynamicSaleState expecting startTime/endTime to limit access",
      "Buyer calls any buy function outside the configured sale period",
      "Purchase succeeds because no function checks the time window"
    ]
  }
]

```

### Agent: opencode_1
```
Let me read the main contract file that likely contains the main logic:
Let me also check the import.sol file and review other key files:
Now I have enough information. Let me compile the security findings:

```json
[
  {
    "id": "F-001",
    "severity": "Critical",
    "confidence": "high",
    "title": "Buy functions missing sale time validation",
    "locations": [
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:289",
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:304",
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:317",
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:333"
    ],
    "claim": "All four buy functions (buyWithEth, buyWithUSDT, buyWithEthDynamic, buyWithUSDTDynamic) do not validate sale end time. They only use whenNotPaused modifier but skip the checkSaleState modifier that validates block.timestamp >= startTime && block.timestamp <= endTime",
    "impact": "Users can purchase tokens after the presale has officially ended, allowing purchases when sale should be closed. This breaks the core sale timing logic and can lead to unauthorized token sales post-endTime",
    "paths": [
      "Wait for sale endTime to pass",
      "Call any buy function (buyWithEth/buyWithUSDT/buyWithEthDynamic/buyWithUSDTDynamic)",
      "Transaction succeeds even though sale ended"
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "high",
    "title": "USDT transfer uses unsafe low-level call without interface",
    "locations": [
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:310",
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:339"
    ],
    "claim": "USDT payment functions use low-level call with abi.encodeWithSignature('transferFrom(address,address,uint256)', ...) instead of the IERC20Upgradeable interface. The return value is checked but the encoding can fail or behave unexpectedly",
    "impact": "If USDT contract returns false or has unexpected behavior, the require(success) will revert but the error message is generic. More critically, using low-level call bypasses the safe token transfer patterns and could be vulnerable if USDT proxy behavior changes",
    "paths": [
      "Call buyWithUSDT or buyWithUSDTDynamic",
      "If USDT transfer fails, generic 'Token payment failed' error shown"
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "high",
    "title": "Missing nonReentrant modifier on USDT buy functions",
    "locations": [
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:304",
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:333"
    ],
    "claim": "buyWithUSDT and buyWithUSDTDynamic functions lack the nonReentrant modifier, while buyWithEth and buyWithEthDynamic include it. Both sets of functions perform similar external calls (token transfers and staking deposits)",
    "impact": "Reentrancy attack possible on USDT purchase functions. A malicious contract could call back into buyWithUSDT/buyWithUSDTDynamic during the execution to manipulate state or drain funds",
    "paths": [
      "Deploy malicious contract with fallback that re-enters buyWithUSDT",
      "Execute purchase, allowing reentrancy during token transfer"
    ]
  },
  {
    "id": "F-004",
    "severity": "High",
    "confidence": "medium",
    "title": "Owner can change staking contract to any address",
    "locations": [
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:284"
    ],
    "claim": "setStakingManager function allows owner to set any address as staking contract without validation. No zero-address check, no timelock, no confirmation",
    "impact": "Owner can redirect all staking deposits to a malicious contract, stealing user funds. Additionally, in startClaim (line 140), an unlimited token approval is granted to the stakingContract - if staking contract is changed to malicious address, they can drain all sale tokens",
    "paths": [
      "Owner calls setStakingManager with attacker's contract address",
      "Users buy tokens which call depositByPresale on attacker contract",
      "Attacker steals deposited funds"
    ]
  },
  {
    "id": "F-005",
    "severity": "High",
    "confidence": "medium",
    "title": "Unlimited token approval in startClaim without revocation",
    "locations": [
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:140"
    ],
    "claim": "startClaim grants infinite approval (type(uint256).max) to the staking contract. If stakingContract is changed via setStakingManager later, the old approval remains and new contract gets unlimited access to sale tokens",
    "impact": "If staking contract is changed after startClaim, the new contract can transfer all sale tokens from the contract. The approval is never revoked from old staking contract either",
    "paths": [
      "startClaim is called, infinite approval granted",
      "setStakingManager changes to new contract",
      "New contract drains all saleToken balance"
    ]
  },
  {
    "id": "F-006",
    "severity": "Medium",
    "confidence": "high",
    "title": "Division before multiplication causes precision loss",
    "locations": [
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:294",
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:309",
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:322",
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:338"
    ],
    "claim": "Price calculations use division before multiplication: (usdPrice * baseDecimals)/getLatestPrice() and usdPrice / (10 ** 12). This causes truncation of significant digits when usdPrice is small",
    "impact": "Users may overpay for tokens due to truncated precision. Small purchases lose value to rounding down. For example, if usdPrice=100 and baseDecimals=1e18, the calculation loses significant precision",
    "paths": [
      "Purchase small amount of tokens",
      "Precision loss in calculation causes overpayment"
    ]
  },
  {
    "id": "F-007",
    "severity": "Medium",
    "confidence": "medium",
    "title": "claimAndStake deletes userDeposits before verifying staking success",
    "locations": [
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:181"
    ],
    "claim": "claimAndStake calls stakingManagerInterface.depositByPresale() then deletes userDeposits without checking if staking succeeded. If staking contract reverts, user loses their deposit record",
    "impact": "Users can lose their purchase record if staking contract fails. The userDeposits is deleted before confirming successful staking, causing permanent fund loss with no recourse",
    "paths": [
      "User calls claimAndStake",
      "Staking contract reverts due to internal error",
      "userDeposits deleted, user loses tokens with no way to recover"
    ]
  },
  {
    "id": "F-008",
    "severity": "Medium",
    "confidence": "low",
    "title": "No slippage protection on token purchases",
    "locations": [
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:289",
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:304",
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:317",
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:333"
    ],
    "claim": "Buy functions have no minimum amount/out slippage parameter. Users must accept whatever output amount is calculated, with no protection against price movement during transaction",
    "impact": "If blockchain congestion or price oracle delay causes price mismatch, users could receive significantly fewer tokens than expected with no ability to specify minimum output",
    "paths": [
      "Price changes between transaction signing and execution",
      "User receives less tokens than expected with no recourse"
    ]
  },
  {
    "id": "F-009",
    "severity": "Low",
    "confidence": "high",
    "title": "Missing events for critical administrative functions",
    "locations": [
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:284",
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:347",
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:351",
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:355",
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:363",
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:366"
    ],
    "claim": "Multiple state-changing owner functions (setStakingManager, setDynamicSaleState, setMaxTokensToSell, setRouter, setPercent, setStaticTokenPrice) do not emit events",
    "impact": "Difficult to track off-chain changes to critical protocol parameters. Lack of transparency makes it harder to detect malicious administrative actions",
    "paths": [
      "Owner calls setStakingManager or other setter functions",
      "No on-chain record of the change beyond storage modification"
    ]
  },
  {
    "id": "F-010",
    "severity": "Low",
    "confidence": "medium",
    "title": "No access control on updateFromBSC function",
    "locations": [
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:273"
    ],
    "claim": "updateFromBSC function allows owner to arbitrarily set userDeposits for any address with no verification or limit. Only checks that array lengths match",
    "impact": "Owner can inflate deposit records for any user, allowing unfair allocation or bypassing purchase limits. Could be used to grant claims to specific addresses without proper payment",
    "paths": [
      "Owner calls updateFromBSC with arbitrary addresses and amounts",
      "Users can claim tokens without actual payment"
    ]
  },
  {
    "id": "F-011",
    "severity": "Low",
    "confidence": "medium",
    "title": "stakeingWhitelistStatus can be disabled after claims start",
    "locations": [
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:249"
    ],
    "claim": "setStakeingWhitelistStatus allows owner to disable staking whitelist requirement at any time, even after claiming has started",
    "impact": "Owner can allow anyone to stake via claimAndStake after launch, bypassing intended whitelist restrictions. Combined with other vulnerabilities, could allow draining of staking contract",
    "paths": [
      "Claim period starts with whitelist enabled",
      "Owner disables whitelist via setStakeingWhitelistStatus(false)",
      "Anyone can now use claimAndStake"
    ]
  },
  {
    "id": "F-012",
    "severity": "Informational",
    "confidence": "high",
    "title": "Unused variable and unreachable code",
    "locations": [
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:32",
      "0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol:118"
    ],
    "claim": "totalTokensSold variable is defined but never updated in buy functions (only directTotalTokensSold is used). The checkSaleState modifier is defined but never used by any function",
    "impact": "Dead code that adds confusion and potential for future bugs. Developers may expect totalTokensSold to track sales but it remains zero",
    "paths": []
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
