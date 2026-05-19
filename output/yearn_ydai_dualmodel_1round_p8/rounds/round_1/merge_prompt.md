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
    "title": "Share inflation attack can force victim deposits to mint zero shares",
    "locations": [
      "0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:326",
      "0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:333",
      "0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:336"
    ],
    "claim": "Deposits mint `shares = _amount * totalSupply / _pool` rounded down, but the vault never enforces a minimum-share or minimum-out check. After minting a tiny initial position, an attacker can donate underlying to inflate `_pool` so a victim deposit mints 0 shares and becomes a pure donation to existing holders.",
    "impact": "A permissionless attacker can steal later user deposits by sandwiching them: the victim transfers real underlying into the vault but receives no vault shares, and the attacker then withdraws the inflated pool.",
    "paths": [
      "Attacker deposits 1 wei when `totalSupply == 0` and receives 1 share",
      "Attacker front-runs a victim by transferring enough underlying directly into the vault so that `victimAmount * totalSupply < _pool`",
      "Victim's `deposit()` mints 0 shares because of floor division",
      "Attacker calls `withdraw(1)` and redeems the victim's assets plus the temporary donation"
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "medium",
    "title": "Changing `controller` can permanently orphan funds in the previous controller",
    "locations": [
      "0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:290",
      "0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:305",
      "0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:362"
    ],
    "claim": "The vault's accounting and withdrawals only reference the current `controller`, but `setController()` blindly swaps the pointer without first recalling assets from the old controller. Any funds still deployed in the old controller instantly disappear from vault accounting and cannot be withdrawn through this vault anymore.",
    "impact": "A bad upgrade, governance mistake, or governance compromise can render part or all of user funds permanently inaccessible, creating immediate insolvency for existing share holders.",
    "paths": [
      "Vault sends funds to controller A via `earn()`",
      "Governance calls `setController(controllerB)` while controller A still holds assets",
      "`balance()` now ignores assets in controller A",
      "Withdrawals only pull from controller B, so assets left in controller A are stranded"
    ]
  },
  {
    "id": "F-003",
    "severity": "Medium",
    "confidence": "high",
    "title": "Controller address is never validated, enabling full vault lockup on bad configuration",
    "locations": [
      "0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:280",
      "0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:287",
      "0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:305",
      "0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:290",
      "0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:362"
    ],
    "claim": "Neither the constructor nor `setController()` checks that `controller` is a non-zero contract implementing the expected interface. If governance sets an EOA, zero address, or incompatible contract, core paths such as `balance()`, `deposit()`, and `withdraw()` will revert on external calls/ABI decoding.",
    "impact": "A single bad controller update can brick deposits and redemptions and lock all idle vault funds until governance can repair the configuration, which is especially dangerous if governance is lost or compromised.",
    "paths": [
      "Governance sets `controller` to `address(0)`, an EOA, or a non-conforming contract",
      "Any later `deposit()` or `withdraw()` hits `Controller(controller).balanceOf(...)` or `Controller(controller).withdraw(...)`",
      "The external call cannot return the expected ABI-encoded data, so the transaction reverts and the vault becomes unusable"
    ]
  },
  {
    "id": "F-004",
    "severity": "Low",
    "confidence": "high",
    "title": "Zero-supply divisions make view and edge-case redemption paths revert",
    "locations": [
      "0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:355",
      "0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:373"
    ],
    "claim": "`withdraw()` and `getPricePerFullShare()` divide by `totalSupply()` without handling the `totalSupply == 0` case. Before the first successful deposit, or after total loss scenarios that leave no shares outstanding, these functions revert.",
    "impact": "This can break integrations, off-chain monitoring, or edge-case user flows that expect price and redemption helpers to work safely on an empty vault.",
    "paths": [
      "Call `getPricePerFullShare()` before any shares are minted",
      "Call `withdraw(0)` while `totalSupply() == 0`"
    ]
  }
]

```

### Agent: opencode_1
```
[{"id":"F-001","severity":"Critical","confidence":"high","title":"First depositor can steal all funds via price manipulation","locations":["0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:326-339","0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:333-334"],"claim":"The first depositor who calls deposit() when totalSupply()==0 receives shares 1:1 with their deposit amount, establishing an extremely favorable exchange rate that allows them to steal nearly all funds from subsequent depositors","impact":"An attacker can deposit a small amount (e.g., 1 wei) as the first depositor, then immediately deposit a large amount. Due to the share price calculation at line 336: shares = (_amount.mul(totalSupply())).div(_pool), the attacker's first small deposit will receive a disproportionately large share of the pool, allowing them to extract nearly all funds from subsequent depositors.","paths":["1. Attacker deploys vault or is first to deposit\n2. Attacker deposits 1 wei, receives 1 share at 1:1 ratio, setting price at 1 share = 1 wei of underlying\n3. Victim deposits 1000e18 tokens\n4. Victim receives ~1 share (1000e18 * 1 / 1000e18 = 1)\n5. Attacker withdraws and steals ~999.999e18 tokens"]},{"id":"F-002","severity":"High","confidence":"high","title":"Division by zero in getPricePerFullShare","locations":["0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:373-375"],"claim":"If totalSupply() returns 0, the getPricePerFullShare function will revert due to division by zero","impact":"Calling getPricePerFullShare on a newly deployed vault with no deposits will cause the transaction to revert, breaking integration with external systems and front-ends that rely on this function","paths":["1. Deploy new vault\n2. Call getPricePerFullShare()\n3. Transaction reverts due to division by zero at line 375"]},{"id":"F-003","severity":"High","confidence":"medium","title":"Division by zero in deposit when balance is zero","locations":["0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:336"],"claim":"If totalSupply() > 0 but balance() returns 0, the deposit function will revert due to division by zero at line 336","impact":"If all funds are withdrawn from the vault and controller, any subsequent deposit will fail. This can happen if the controller's balance is drained but shares still exist.","paths":["1. Vault has shares but balance() returns 0\n2. User calls deposit()\n3. Transaction reverts due to division by zero at line 336"]},{"id":"F-004","severity":"Medium","confidence":"high","title":"No slippage protection in deposit and withdraw","locations":["0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:326-339","0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:354-371"],"claim":"Users have no control over the minimum amount of shares/tokens they will receive, exposing them to sandwich attacks and front-running","impact":"Front-runners can sandwich user transactions by: 1) For deposit: deposit first to manipulate price up, then user's deposit gets fewer shares, then attacker withdraws for profit. 2) For withdraw: user signs transaction, attacker withdraws first to lower price, user gets fewer tokens, attacker deposits to restore price. Users receive less than expected with no recourse.","paths":["1. User submits deposit/withdraw transaction to mempool\n2. Attacker sees transaction, submits sandwich transactions before and after\n3. User receives fewer shares/tokens than expected"]},{"id":"F-005","severity":"Medium","confidence":"low","title":"Governance can set min to 0, breaking deposits","locations":["0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:295-298","0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:312-314"],"claim":"The setMin function allows governance to set min to any value including 0, which would cause available() to always return 0","impact":"If governance sets min=0, the available() function will always return 0, meaning earn() will never move funds to the controller. This would cause the vault to become stuck as all funds remain in the vault and deposits may fail due to balance issues.","paths":["1. Governance calls setMin(0)\n2. available() returns 0 forever\n3. earn() never moves funds to controller\n4. Vault functionality is compromised"]},{"id":"F-006","severity":"Low","confidence":"medium","title":"Controller can be set to address(0), permanently breaking vault","locations":["0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:305-308"],"claim":"The setController function allows governance to set controller to address(0)","impact":"If governance accidentally sets controller to address(0), all deposits and withdrawals will fail because balance() calls Controller(address(0)).balanceOf() which will revert, and withdraw() calls Controller(address(0)).withdraw() which will also revert.","paths":["1. Governance calls setController(address(0))\n2. Any call to balance() reverts\n3. Any call to withdraw() reverts\n4. Vault is permanently broken"]},{"id":"F-007","severity":"Low","confidence":"high","title":"No event emitted on setMin, setGovernance, setController","locations":["0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:295-308"],"claim":"Critical governance functions setMin, setGovernance, and setController do not emit events","impact":"It is difficult to track governance changes on-chain and off-chain. External systems and block explorers cannot easily detect when critical vault parameters change.","paths":["1. Governance changes parameters via setMin/setGovernance/setController\n2. No event is emitted\n3. Off-chain systems cannot index these changes"]}]

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
