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
    "title": "Anyone can reinitialize the NFT contracts and seize deposit/funding token ownership",
    "locations": [
      "onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/NFT.sol:39",
      "onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/NFT.sol:44",
      "onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/NFT.sol:79",
      "onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/NFT.sol:83",
      "onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/DInterest.sol:770",
      "onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/DInterest.sol:903"
    ],
    "claim": "`NFT.init()` is external and has no one-time guard or access control, so any account can call it after deployment to transfer ownership of the live deposit/funding NFT contract to itself, then use the owner-only `mint`/`burn` powers against users.",
    "impact": "A hostile caller can take over the pool's `depositNFT` or `fundingNFT`, burn users' positions, stop future minting, or otherwise break ownership accounting. Because withdrawals and funder payouts depend on `ownerOf()` succeeding for these NFTs, this can permanently lock deposits/fundings and DoS the entire pool.",
    "paths": [
      "Call `NFT.init(attacker, ...)` on the deployed deposit NFT or funding NFT contract.",
      "As the new owner, call `burn(tokenId)` on victim deposit/funding NFTs or interfere with future minting.",
      "Victim `withdraw()` / funder payout paths revert when `ownerOf()` no longer matches an existing valid token."
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "high",
    "title": "Vested MPH rewards can make depositor withdrawals impossible unless the user buys extra MPH",
    "locations": [
      "onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/rewards/MPHMinter.sol:105",
      "onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/rewards/MPHMinter.sol:113",
      "onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/rewards/MPHMinter.sol:154",
      "onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/DInterest.sol:777",
      "onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/DInterestWithDepositFee.sol:808"
    ],
    "claim": "When depositor rewards are vested, `mintDepositorReward()` transfers MPH into `Vesting`, but every withdrawal still calls `takeBackDepositorReward()` which unconditionally `transferFrom`s MPH from the withdrawing user's wallet instead of cancelling/slashing the vest.",
    "impact": "If vesting is enabled, depositors may be unable to withdraw their principal early, and possibly even at maturity if the take-back multiplier is nonzero, unless they separately acquire enough liquid MPH and approve the minter. This creates a realistic principal lockup / forced-buy scenario for ordinary users.",
    "paths": [
      "Configure a pool with a nonzero depositor reward vesting period.",
      "User deposits; MPH reward is escrowed in `Vesting` instead of staying in the user's wallet.",
      "User later withdraws; `DInterest` calls `takeBackDepositorReward(user, ...)`.",
      "`MPHMinter` tries `mph.transferFrom(user, ...)` and reverts because the vested MPH is not in the user's wallet."
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "high",
    "title": "`fundMultiple()` can charge new funders for stale deficits from already-withdrawn deposits that carry no recoverable claim",
    "locations": [
      "onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/DInterest.sol:317",
      "onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/DInterest.sol:320",
      "onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/DInterest.sol:335",
      "onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/DInterest.sol:488",
      "onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/DInterest.sol:817",
      "onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/DInterest.sol:856",
      "onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/DInterestWithDepositFee.sol:320",
      "onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/DInterestWithDepositFee.sol:338",
      "onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/DInterestWithDepositFee.sol:887"
    ],
    "claim": "`fundMultiple()` sums `finalSurplusAmount` from inactive deposits into `totalDeficit`, but only active deposits are added to `recordedFundedDepositAmount`; after an unfunded deposit is withdrawn, its stored negative surplus can therefore make later funders overpay for liabilities that no longer have any deposit attached to repay them.",
    "impact": "A later funder can inject capital that is not tied to any recoverable funded position, so that portion of the funding NFT is economically worthless. This lets stale losses or phantom early-withdraw deficits be socialized onto later funders and can directly destroy funder principal.",
    "paths": [
      "Create an unfunded deposit and withdraw it before it is funded.",
      "The pool records `finalSurplusAmount` for that now-inactive deposit.",
      "A later caller uses `fundMultiple()` over a range that includes the inactive deposit.",
      "`totalDeficit` includes the inactive deposit's stored deficit, but `recordedFundedDepositAmount` excludes it because the deposit is inactive.",
      "The funder pays the larger `totalDeficit` but only receives a claim on the smaller active-deposit amount."
    ]
  },
  {
    "id": "F-004",
    "severity": "Medium",
    "confidence": "high",
    "title": "Zero-coupon bond redemption is first-come-first-served instead of pro-rata when collateral is short",
    "locations": [
      "onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/fractionals/ZeroCouponBond.sol:169",
      "onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/fractionals/ZeroCouponBond.sol:170",
      "onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/fractionals/ZeroCouponBond.sol:175",
      "onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/fractionals/ZeroCouponBond.sol:178"
    ],
    "claim": "`redeemStablecoin()` pays `min(amount, stablecoinBalance)` and burns exactly that many bonds, without scaling by `stablecoinBalance / totalSupply`, so undercollateralized bond series redeem at par for whoever gets there first.",
    "impact": "If the bond contract ever has less stablecoin than total outstanding ZCB supply, early redeemers can drain the available collateral 1:1 and leave later holders with a disproportionate loss. This creates a bank-run dynamic and unfairly reallocates insolvency losses to slower bondholders.",
    "paths": [
      "Wait until bond maturity when `stablecoin.balanceOf(this) < totalSupply()`.",
      "Redeem a large amount early via `redeemStablecoin(amount)`.",
      "The function transfers up to the full current stablecoin balance at 1 bond : 1 stablecoin until the contract is emptied.",
      "Remaining bondholders are left with little or no collateral backing."
    ]
  }
]

```

### Agent: opencode_1
```
Let me continue reading more key contracts to identify vulnerabilities.
Let me read more key contracts to identify additional vulnerabilities.
Let me check a few more important contracts.
Let me continue reading more contracts to identify additional vulnerabilities.
Let me check a couple more contracts.
Now I have reviewed enough contracts to identify the vulnerabilities. Let me compile my findings into the required JSON format.
[{"id":"F-001","severity":"Critical","confidence":"high","title":"MPHMinter allows ownership transfer of MPH token to any address","locations":["contracts/rewards/MPHMinter.sol:241-245"],"claim":"The setMPHTokenOwner function allows the contract owner to transfer ownership of the MPH token to an arbitrary address, giving the new owner full control over the token's minting capability.","impact":"A malicious or compromised owner can transfer MPH token ownership to a wallet they control and mint unlimited tokens, draining all value from the protocol.","paths":["Owner calls setMPHTokenOwner with address they control -> New owner calls ownerMint to mint unlimited MPH tokens"]},{"id":"F-002","severity":"High","confidence":"medium","title":"DInterest early withdraw allows same-block attack via flash loan","locations":["contracts/DInterest.sol:755-759","contracts/DInterestWithDepositFee.sol:786-790"],"claim":"The earlyWithdraw function checks 'now > depositEntry.depositTimestamp' to prevent same-block early withdrawals, but this can be bypassed using flash loans within the same block.","impact":"Users can perform flash loan attacks to deposit and immediately early withdraw in the same block, potentially extracting value before the deposit is properly recorded in the funding pool.","paths":["Attacker takes flash loan -> Deposits and immediately calls earlyWithdraw in same block -> Returns flash loan"]},{"id":"F-003","severity":"High","confidence":"high","title":"ZeroCouponBond grants unlimited ERC20 approval to factory","locations":["contracts/fractionals/ZeroCouponBond.sol:85-90"],"claim":"During initialization, the contract grants unlimited approval (uint256(-1)) to the FractionalDepositFactory for the MPH token.","impact":"If the FractionalDepositFactory is compromised, an attacker can drain all MPH tokens held by ZeroCouponBond contracts.","paths":["Compromise FractionalDepositFactory -> Drain MPH tokens from all ZCB contracts with active approvals"]},{"id":"F-004","severity":"High","confidence":"high","title":"YVaultMarket withdraw returns entire balance instead of actual amount","locations":["contracts/moneymarkets/yvault/YVaultMarket.sol:62-66"],"claim":"The withdraw function transfers the entire stablecoin balance of the contract instead of the actual amount withdrawn from the vault.","impact":"When multiple withdrawals occur, subsequent callers receive less than they should. The contract may also lose track of funds when the vault returns more than expected.","paths":["Multiple users call withdraw -> Later callers receive less than entitled -> Funds incorrectly distributed"]},{"id":"F-005","severity":"Medium","confidence":"high","title":"DInterest owner can change critical contract addresses without timelock","locations":["contracts/DInterest.sol:535-567","contracts/DInterestWithDepositFee.sol:538-570"],"claim":"Critical parameter setters (setFeeModel, setInterestModel, setInterestOracle, setMPHMinter) allow the owner to change to arbitrary contract addresses without any timelock or multi-sig requirement.","impact":"A malicious or compromised owner can change critical contract addresses (like feeModel, interestModel) to point to malicious contracts, stealing user funds or breaking protocol functionality.","paths":["Owner calls setFeeModel with malicious contract -> All future fees go to attacker -> User funds stolen"]},{"id":"F-006","severity":"Medium","confidence":"medium","title":"ZapCurve has hardcoded zapper address that cannot be updated","locations":["contracts/zaps/ZapCurve.sol:19-20"],"claim":"The CurveZapIn zapper contract address is hardcoded as a constant and cannot be updated.","impact":"If the zapper contract is compromised, deprecated, or needs to be upgraded, all ZapCurve functionality becomes permanently unusable.","paths":["Zapper contract is compromised -> No way to update address -> ZapCurve becomes unusable"]},{"id":"F-007","severity":"Medium","confidence":"high","title":"DInterestWithDepositFee sends full deposit amount to money market despite fee deduction","locations":["contracts/DInterestWithDepositFee.sol:706-753"],"claim":"The deposit fee is deducted from the user's deposit amount (amountAfterFee), but the full original amount is transferred to the money market deposit.","impact":"The protocol loses (DepositFee * amount) stablecoins on each deposit. The accounting shows less totalDeposit than actual funds in the money market.","paths":["User deposits 100 with 5% fee -> amountAfterFee = 95 -> Full 100 sent to market -> Protocol loses 5 stablecoins per deposit"]},{"id":"F-008","severity":"Low","confidence":"high","title":"Vesting contract has no access control on vest function","locations":["contracts/rewards/Vesting.sol:25-45"],"claim":"The vest function can be called by any address to create vesting schedules for any recipient, using tokens transferred from the caller.","impact":"While not directly exploitable for theft, anyone can create arbitrary vesting schedules. The main risk is confusion and potential griefing.","paths":["Any user calls vest() with their own tokens -> Creates vesting schedule for any address"]},{"id":"F-009","severity":"Low","confidence":"medium","title":"Rewards contract lacks pause mechanism for emergency","locations":["contracts/rewards/Rewards.sol"],"claim":"The Rewards contract has no pause or emergency stop functionality.","impact":"If a critical vulnerability is discovered in the rewards contract, there is no way to halt distribution to prevent further damage.","paths":["Vulnerability discovered -> No way to stop reward distribution -> Exploit continues"]},{"id":"F-010","severity":"Medium","confidence":"high","title":"NFTFactory lacks access control allowing anyone to mint NFTs","locations":["contracts/NFTFactory.sol","contracts/NFT.sol:39-44"],"claim":"The NFT contract's mint function can be called by any address that has been granted minting rights, which may include the factory but without proper access controls.","impact":"Unauthorized parties may be able to mint NFTs representing fake deposits, potentially used in phishing or social engineering attacks.","paths":["Attacker mints fake deposit NFT -> Uses NFT in social engineering attack -> Victims deceived"]}]

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
