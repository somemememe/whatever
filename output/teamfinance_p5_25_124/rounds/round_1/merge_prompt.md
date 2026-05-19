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
    "confidence": "medium",
    "title": "Uninitialized deployment can be seized by the first caller",
    "locations": [
      "onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:119",
      "onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:125",
      "onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/node_modules/@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol:31"
    ],
    "claim": "The contract exposes an unrestricted external `initialize()` that reaches `__Ownable_init_unchained()` and sets `_owner = _msgSender()`. If the proxy is ever deployed without initialization data, or initialization is otherwise left pending, any attacker can become owner.",
    "impact": "A successful initializer frontrun gives the attacker full admin control: they can pause the system, change fee/NFT settings, whitelist accounts, and use `recoverAssets()` to take over all user locks.",
    "paths": [
      "Deploy proxy without atomic initialization",
      "Attacker calls `initialize()` first",
      "Attacker becomes owner and invokes privileged functions such as `recoverAssets(victim, attacker)`"
    ]
  },
  {
    "id": "F-002",
    "severity": "Critical",
    "confidence": "high",
    "title": "Owner backdoor can reassign any user's locked assets to an arbitrary recipient",
    "locations": [
      "onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:963",
      "onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:983",
      "onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:990",
      "onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:994"
    ],
    "claim": "`recoverAssets()` lets the owner iterate over every deposit of any `user`, rewrite the stored `withdrawalAddress` to `newRecipient`, move the accounting balance, and burn any lock NFTs, all without proving user consent.",
    "impact": "This is a direct administrative theft primitive. The owner can seize ownership of every user's timelocked ERC20s/NFTs and withdraw them once unlock time is reached; already-unlocked assets can be stolen immediately.",
    "paths": [
      "Owner calls `recoverAssets(victim, attacker)`",
      "All of victim's deposit ownership is rewritten to the attacker",
      "Attacker calls `withdrawTokens()` immediately for matured locks or after unlock time"
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "high",
    "title": "Anyone can grief a victim with arbitrary dust locks and make withdrawals gas-prohibitive",
    "locations": [
      "onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:147",
      "onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:186",
      "onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:312",
      "onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:340",
      "onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:751",
      "onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:767",
      "onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:770"
    ],
    "claim": "Both `lockToken()` and `lockNFT()` allow the caller to choose any `_withdrawalAddress`, while withdrawals/transfers remove deposit IDs by linearly scanning `depositsByWithdrawalAddress[_withdrawalAddress]`. An attacker can therefore bloat a victim's deposit list with many tiny locks and force later victim operations into O(n) gas costs.",
    "impact": "Victims can be prevented from withdrawing or transferring their legitimate positions once their deposit array becomes too large to scan within block gas limits, creating a permissionless lockup/DoS on funds.",
    "paths": [
      "Attacker repeatedly calls `lockToken()` or `lockNFT()` with the victim as `_withdrawalAddress`",
      "Victim's `depositsByWithdrawalAddress` grows without bound",
      "Victim's `withdrawTokens()` / `transferLocks()` hits `_removeDepositsForWithdrawalAddress()` and eventually runs out of gas"
    ]
  },
  {
    "id": "F-004",
    "severity": "Medium",
    "confidence": "high",
    "title": "The contract accepts arbitrary ERC721 transfers and permanently blackholes untracked NFTs",
    "locations": [
      "onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:135"
    ],
    "claim": "`onERC721Received()` unconditionally returns the selector for every incoming NFT, but only `lockNFT()` populates `lockedNFTs`. Any NFT sent directly with `safeTransferFrom` is accepted yet never registered as a withdrawable lock.",
    "impact": "NFTs sent directly to the contract, whether by user mistake, airdrop, or third-party integration error, become permanently stuck because there is no matching deposit record to authorize recovery.",
    "paths": [
      "User or third party calls `safeTransferFrom(..., LockToken, tokenId)` directly",
      "The receiver hook accepts the NFT",
      "No `lockedNFTs` entry exists, so `withdrawTokens()` cannot recover it"
    ]
  },
  {
    "id": "F-005",
    "severity": "Medium",
    "confidence": "high",
    "title": "Referral fee math undercharges by using the discount as the final fee percentage",
    "locations": [
      "onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:522",
      "onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:885"
    ],
    "claim": "`setReferralParams()` stores `referralDiscount`, but `_chargeFeesReferral()` computes `feeInEth = feeInEth * referralDiscount / MAX_PERCENTAGE`. This means a configured 5% discount (`500`) charges only 5% of the normal fee instead of 95%.",
    "impact": "Whenever referrals are enabled, users can permissionlessly pay far less than the intended protocol fee, materially bypassing the fee model and draining protocol revenue.",
    "paths": [
      "Owner configures `referralDiscount = 500` expecting a 5% discount",
      "User supplies any nonzero `referrer`",
      "Contract accepts roughly 5% of the normal fee instead of 95%"
    ]
  }
]

```

### Agent: opencode_1
```
I need to audit the smart contracts in the specified directory. Let me first explore the contracts to identify security vulnerabilities.
Now let me read the other contract:
Let me also check the interfaces to understand the full context:
Now I have a comprehensive understanding of the contracts. Let me compile the security vulnerabilities I've found:

[{"id":"F-001","severity":"Critical","confidence":"high","title":"Owner Can Steal All User Funds via recoverAssets Function","locations":["0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:963-1001"],"claim":"The owner-only recoverAssets function allows changing the withdrawal address of ANY user's deposits to an arbitrary recipient, enabling complete theft of all locked funds.","impact":"The contract owner can steal all tokens and NFTs locked by users by calling recoverAssets with any user's address and setting newRecipient to themselves. This completely undermines the trustless nature of the locking contract and defeats its fundamental purpose.","paths":["1. Owner calls recoverAssets(userAddress, ownerAddress) where userAddress has locked tokens\n2. Contract changes all user's deposit withdrawalAddress to owner\n3. Owner withdraws all tokens via withdrawTokens function"]},{"id":"F-002","severity":"Critical","confidence":"high","title":"Proxy Admin Can Hijack Implementation to Malicious Contract","locations":["0xe2fe530c047f2d85298b07d9333c05737f1435fb/Contract.sol:267-269"],"claim":"The upgradeTo function allows the proxy admin to set any address as the implementation without validation, enabling redirection to a malicious contract.","impact":"A malicious or compromised proxy admin can upgrade the proxy to point to a malicious contract that steals all funds or performs other unauthorized actions. All user funds stored in the proxy can be stolen.","paths":["1. Admin calls upgradeTo(maliciousContractAddress)\n2. All future calls to the proxy execute malicious code\n3. Attacker can drain funds or steal sensitive data"]},{"id":"F-003","severity":"High","confidence":"high","title":"NFT Burned Before Token Transfer - Potential Loss of NFT","locations":["0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:377-384"],"claim":"In withdrawTokens, the NFT is burned before the underlying ERC721 token is transferred to the user. If the token transfer fails, the NFT is permanently lost.","impact":"If the ERC721.safeTransferFrom fails after the NFT has been burned, the user loses both their NFT representation AND their underlying token with no recourse. This creates a potential permanent loss scenario.","paths":["1. User calls withdrawTokens for an NFT lock\n2. NFT is burned (nftMinted[_id] = false; IERC721Extended(NFT).burn(_id))\n3. ERC721 safeTransferFrom fails (e.g., token not in contract, contract paused)\n4. User loses NFT and may not receive underlying token"]},{"id":"F-004","severity":"High","confidence":"medium","title":"NFT Burned Before ERC20 Transfer in Partial Withdrawal","locations":["0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:396-410"],"claim":"When performing a full withdrawal of ERC20 tokens, the NFT is burned before the token transfer completes. If transfer fails, NFT is lost.","impact":"User loses their NFT representation permanently while not receiving their underlying tokens. The burn happens before the transfer is confirmed successful.","paths":["1. User calls withdrawTokens with full amount for an ERC20 lock that has NFT minted\n2. _removeERC20Deposit is called which processes the withdrawal\n3. NFT is burned before IERC20.safeTransfer completes\n4. If transfer reverts, user loses NFT without receiving tokens"]},{"id":"F-005","severity":"High","confidence":"medium","title":"Missing Validation Prevents Recovery of Stuck NFTs","locations":["0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:384"],"claim":"The withdrawTokens function transfers NFT via safeTransferFrom but does not verify the transfer success, potentially leaving NFT stuck in contract if transfer fails.","impact":"If the ERC721 token contract rejects the transfer (e.g., hook reverts, contract paused), the NFT remains in the contract but the lockedNFT.withdrawn is already marked true, permanently locking the user's NFT.","paths":["1. User calls withdrawTokens for an NFT lock\n2. IERC721.safeTransferFrom is called but fails silently or reverts\n3. Event is emitted but NFT remains in contract\n4. User cannot retry - withdrawn is already true"]},{"id":"F-006","severity":"Medium","confidence":"high","title":"Inconsistent Unlock Time Enforcement in splitLock","locations":["0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:463-464"],"claim":"The splitLock function only requires _splitUnlockTime >= original unlockTime, but doesn't prevent the original lock from being extended later to a later time while the split lock keeps the original unlockTime.","impact":"If a user extends the original lock's duration after splitting, the split lock can have an earlier unlock time than the original lock. This creates inconsistent unlock times and potentially allows earlier withdrawal of split tokens while original tokens remain locked.","paths":["1. User splits a lock with unlockTime T\n2. User later extends original lock to T+30 days via extendLockDuration\n3. Split lock still unlocks at T, original at T+30 days\n4. User can withdraw split portion before original"]},{"id":"F-007","severity":"Medium","confidence":"high","title":"No Zero Address Validation for priceEstimator in setFeeParams","locations":["0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:498-511"],"claim":"The setFeeParams function validates _priceEstimator and _usdTokenAddress with onlyContract but doesn't check for address(0). Setting priceEstimator to address(0) breaks getFeesInETH.","impact":"If owner sets priceEstimator to address(0), all fee calculations in getFeesInETH will return 0 (due to address(0) check on line 681), effectively making all locks free. This enables free locking without paying fees.","paths":["1. Owner calls setFeeParams with priceEstimator=address(0)\n2. getFeesInETH returns 0 due to line 681 check\n3. All users can lock tokens without paying fees"]},{"id":"F-008","severity":"Medium","confidence":"medium","title":"No Validation of referrer Address in _chargeFeesReferral","locations":["0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:865-909"],"claim":"The _chargeFeesReferral function doesn't validate if referrer is a valid contract or EOA, and doesn't check if referrer can receive ETH.","impact":"If referrer is a contract that cannot receive ETH, the referrer transfer will fail and the entire transaction reverts, preventing the user from locking tokens. If referrer is address(0), the referrerFee calculation would be incorrect.","paths":["1. User calls lockToken with a referrer that cannot receive ETH\n2. Transaction reverts at referrer transfer\n3. User cannot lock tokens"]},{"id":"F-009","severity":"Medium","confidence":"medium","title":"Unchecked Return Value in Fee Collection","locations":["0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:814-815"],"claim":"The company wallet ETH transfer uses low-level call without checking return value properly - it uses require(success) which could allow address(0) as company wallet.","impact":"If companyWallet is set to address(0), the call will succeed but ETH will be lost. The require(success) will pass even if the call fails due to how low-level calls work with address(0).","paths":["1. Owner sets companyWallet to address(0)\n2. User pays fees\n3. ETH sent to address(0) is lost permanently"]},{"id":"F-010","severity":"Medium","confidence":"low","title":"Potential Integer Overflow in getFeesInETH Calculation","locations":["0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:698-700"],"claim":"The fee calculation in getFeesInETH uses deprecated SafeMath but could still have overflow issues with extremely large feesInUSD values.","impact":"With extremely large fee values, the calculation could overflow, causing incorrect fee calculations. However, this is low risk as feesInUSD is owner-controlled and would require intentional malicious configuration.","paths":["1. Owner sets extremely large feesInUSD\n2. Calculation overflows\n3. Users pay incorrect fees"]},{"id":"F-011","severity":"Low","confidence":"high","title":"Missing Event Emission in recoverAssets","locations":["0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:963-1001"],"claim":"The recoverAssets function doesn't emit any event when changing ownership of user deposits, making it impossible to track on-chain.","impact":"Users cannot detect when their deposits have been transferred to another address. This lack of transparency hides the critical owner backdoor action from on-chain monitoring and users.","paths":["1. Owner calls recoverAssets to steal funds\n2. No event emitted\n3. Users have no on-chain way to detect the theft"]},{"id":"F-012","severity":"Low","confidence":"medium","title":"No Validation of tokenAddress in lockToken Function","locations":["0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:147-181"],"claim":"The lockToken function doesn't validate that _tokenAddress is a valid ERC20 contract before attempting to transfer.","impact":"If a user provides a non-ERC20 address as _tokenAddress, the safeTransferFrom will likely fail, but could potentially cause unexpected behavior with certain proxy implementations.","paths":["1. User calls lockToken with invalid tokenAddress\n2. Transaction fails with unclear error message\n3. Wasted gas for user"]},{"id":"F-013","severity":"Low","confidence":"high","title":"Inconsistent Access Control for whitelistAdmins","locations":["0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:590-599"],"claim":"The updateWhitelist function can be called by any whitelistAdmin or owner, but there's no maximum limit on how many admins can be added or any rate limiting.","impact":"A malicious owner could add many addresses as whitelistAdmins, and any of those admins could exempt addresses from fees. This creates potential for collusion and fee evasion.","paths":["1. Owner adds multiple addresses as whitelistAdmins\n2. Any admin can whitelist addresses to avoid fees\n3. Protocol loses fee revenue"]},{"id":"F-014","severity":"Low","confidence":"medium","title":"Potential Array Length Mismatch in depositsByWithdrawalAddress","locations":["0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:998"],"claim":"The recoverAssets function pushes deposit IDs to newRecipient's array without checking for potential duplicate entries or array overflow.","impact":"If newRecipient already has the same deposit IDs in their array (edge case), this could lead to duplicate entries causing incorrect balance calculations later.","paths":["1. Owner calls recoverAssets(user, newRecipient)\n2. newRecipient already has some of these deposit IDs\n3. Duplicate entries created in depositsByWithdrawalAddress"]},{"id":"F-015","severity":"Informational","confidence":"high","title":"Missing Initialization Check in Contract Constructor","locations":["0xe2fe530c047f2d85298b07d9333c05737f1435fb/Contract.sol:185-192"],"claim":"The UpgradeabilityProxy constructor performs delegatecall to init data but doesn't verify if initialization succeeded.","impact":"Proxy may be left in an uninitialized state if initialization fails silently, leading to potential security issues if users assume the contract is properly initialized.","paths":["1. Deploy proxy with faulty init data\n2. Initialization fails but proxy is deployed\n3. Users interact with uninitialized proxy"]}]

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
