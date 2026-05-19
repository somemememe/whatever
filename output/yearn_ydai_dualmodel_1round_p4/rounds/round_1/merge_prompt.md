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
    "title": "Empty-vault inflation attack can steal later deposits via zero-share minting",
    "locations": [
      "onchain_auto/0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:290",
      "onchain_auto/0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:327",
      "onchain_auto/0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:333",
      "onchain_auto/0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:336"
    ],
    "claim": "Share issuance uses `shares = _amount * totalSupply / _pool` with no minimum-share check, while `balance()` counts unsolicited token donations. An attacker can become the initial shareholder with a dust deposit, donate underlying directly to the vault or controller to inflate `_pool`, and force subsequent deposits to mint zero or negligible shares.",
    "impact": "Victim deposits are accepted but they receive no meaningful yShares, so their underlying becomes owned by the attacker as the dominant/only shareholder. The attacker can then withdraw nearly all assets from the vault.",
    "paths": [
      "Attacker deposits 1 wei when `totalSupply() == 0`, receiving 1 share.",
      "Attacker transfers a large amount of underlying directly to the vault (or controller so `balance()` rises) without minting new shares.",
      "A victim calls `deposit()`; because `_pool` is now huge, `shares = _amount * totalSupply / _pool` rounds to 0 or dust.",
      "Attacker calls `withdraw()` and redeems almost the entire vault balance, including the victim's deposit."
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "high",
    "title": "Permissionless repeated `earn()` calls can drain the vault's cash buffer to near zero",
    "locations": [
      "onchain_auto/0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:312",
      "onchain_auto/0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:316",
      "onchain_auto/0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:318"
    ],
    "claim": "`available()` returns `token.balanceOf(this) * min / max`, and `earn()` is permissionless. With `min = 9500`, each call sends 95% of the current on-hand balance to the controller, so repeated calls exponentially reduce the intended withdrawal reserve from 5% to 0.25%, 0.0125%, and so on.",
    "impact": "Any user can strip almost all idle liquidity from the vault, forcing nearly every withdrawal to depend on controller liquidity. If the controller/strategy is illiquid, paused, or charges exit losses, this creates realistic permissionless withdrawal DoS and loss amplification for users.",
    "paths": [
      "Vault holds idle underlying intended to satisfy small withdrawals.",
      "An arbitrary caller invokes `earn()` multiple times in succession.",
      "Each call transfers 95% of the remaining cash buffer to the controller, leaving almost no tokens locally.",
      "Subsequent `withdraw()` calls must pull funds from the controller and can revert, stall, or realize extra losses if controller liquidity is unavailable."
    ]
  },
  {
    "id": "F-003",
    "severity": "Low",
    "confidence": "high",
    "title": "`getPricePerFullShare()` reverts while the vault is empty",
    "locations": [
      "onchain_auto/0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:373",
      "onchain_auto/0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:374"
    ],
    "claim": "`getPricePerFullShare()` divides by `totalSupply()` without handling the zero-supply case.",
    "impact": "Integrations, UIs, or off-chain monitors that query price-per-share before the first deposit will revert unexpectedly, which can break initialization flows and health checks.",
    "paths": [
      "Vault is freshly deployed and `totalSupply() == 0`.",
      "A caller invokes `getPricePerFullShare()`.",
      "The division by zero reverts."
    ]
  }
]

```

### Agent: opencode_1
```
I need to read the contract file first, then analyze it for security vulnerabilities.
[{"id":"F-001","severity":"Critical","confidence":"high","title":"Controller set to address(0) permanently locks all funds","locations":["Contract.sol:305-308"],"claim":"The setController function allows setting the controller to address(0) without any validation. When controller is set to address(0), all vault operations that depend on the controller (balance(), earn(), withdraw(), harvest()) will fail because they attempt to call functions on a non-contract address.","impact":"If the controller is accidentally or maliciously set to address(0), all funds in the vault become permanently locked. Users cannot withdraw their funds because withdraw() calls Controller(controller).withdraw() which will revert.","paths":["1. Owner calls setController(address(0)) either accidentally or maliciously\n2. Any user attempting to withdraw fails because controller.call() reverts\n3. All vault funds are permanently locked"]},{"id":"F-002","severity":"Critical","confidence":"high","title":"Controller can drain any ERC20 tokens from vault via harvest()","locations":["Contract.sol:347-351"],"claim":"The harvest() function allows the controller to transfer ANY reserve token (except the vault's main token) to itself. A malicious or compromised controller can call this function to drain any other ERC20 tokens held in the vault.","impact":"If the controller is malicious or compromised, it can call harvest() to transfer any ERC20 tokens (e.g., airdrops, accidental transfers) from the vault to itself. While it cannot directly drain the main vault token, it can steal any other valuable tokens.","paths":["1. Any ERC20 token is accidentally sent to the vault (airdrop, user error)\n2. Controller calls harvest(tokenAddress, amount) to transfer the tokens to itself\n3. Tokens are stolen by the controller"]},{"id":"F-003","severity":"High","confidence":"high","title":"Division by zero in getPricePerFullShare when totalSupply is zero","locations":["Contract.sol:373-375"],"claim":"The getPricePerFullShare() function performs balance().mul(1e18).div(totalSupply()). If totalSupply is zero (before any deposits), this causes a division by zero error.","impact":"Calling getPricePerFullShare() when the vault is empty will revert, causing a denial of service. Frontends or integrators relying on this function for price calculations will fail.","paths":["1. Call getPricePerFullShare() on a fresh vault with zero total supply\n2. Division by zero reverts the transaction"]},{"id":"F-004","severity":"High","confidence":"high","title":"Division by zero in withdraw when totalSupply is zero","locations":["Contract.sol:354-356"],"claim":"The withdraw() function calculates r = (balance().mul(_shares)).div(totalSupply()). If totalSupply is zero, this causes a division by zero.","impact":"If the vault has zero total supply and someone tries to withdraw, the transaction will revert, causing a denial of service. While unlikely (deposit creates shares first), it's a potential edge case.","paths":["1. Vault has zero total supply (edge case)\n2. User attempts to withdraw\n3. Transaction reverts due to division by zero"]},{"id":"F-005","severity":"High","confidence":"medium","title":"Division by zero in deposit when _pool is zero","locations":["Contract.sol:326-338"],"claim":"The deposit() function calculates shares as (_amount.mul(totalSupply())).div(_pool) where _pool is the balance before deposit. If _pool is zero but totalSupply > 0 (e.g., after a complete withdrawal), division by zero occurs.","impact":"If all users withdraw and totalSupply becomes 0, then someone deposits, totalSupply becomes > 0 but _pool (balance) is 0. The next deposit will cause division by zero and revert, making the vault unusable for subsequent deposits.","paths":["1. All users withdraw (totalSupply > 0 but vault balance = 0)\n2. New user attempts to deposit\n3. _pool = 0, division by zero reverts"]},{"id":"F-006","severity":"Medium","confidence":"high","title":"setMin can be set to 0, disabling yield generation","locations":["Contract.sol:295-298,312-314"],"claim":"The setMin() function allows setting min to any value including 0. When min=0, available() returns 0, meaning no funds are ever transferred to the controller for yield generation.","impact":"If min is set to 0, the vault will never deposit funds into the controller to earn yield. Users will receive no returns on their deposits, effectively losing opportunity cost.","paths":["1. Governance calls setMin(0)\n2. earn() is called but available() returns 0\n3. No yield is generated, users lose returns"]},{"id":"F-007","severity":"Medium","confidence":"high","title":"No slippage protection allows sandwich attacks on deposit/withdraw","locations":["Contract.sol:322-339,354-371"],"claim":"The deposit() and withdraw() functions have no minimum output parameter. Users receive shares or tokens based on the current exchange rate which can be manipulated by front-running.","impact":"Users can be sandwiched by malicious actors who front-run their transactions with large deposits/withdrawals to manipulate the price, resulting in the user receiving fewer shares (deposit) or tokens (withdraw) than expected.","paths":["1. User submits deposit/withdraw transaction\n2. Attacker front-runs with large trade to manipulate price\n3. User's transaction executes at worse rate\n4. Attacker back-runs to capture profit"]},{"id":"F-008","severity":"Medium","confidence":"medium","title":"No deadline parameter allows unfavorable transaction execution","locations":["Contract.sol:322-339,354-371"],"claim":"The deposit() and withdraw() functions have no deadline parameter. Transactions may remain pending in the mempool and execute at an unfavorable time when market conditions change.","impact":"Users have no guarantee that their transaction will execute within a specific time frame. If the transaction executes after significant price changes, users may receive less than expected.","paths":["1. User submits deposit/withdraw transaction\n2. Network congestion delays transaction\n3. Price changes during delay\n4. Transaction executes at unfavorable rate"]},{"id":"F-009","severity":"Medium","confidence":"medium","title":"setController has no validation allowing malicious controller","locations":["Contract.sol:305-308"],"claim":"The setController function allows setting the controller to any address without checking if it's a valid contract or if it implements the expected interface.","impact":"Governance can set the controller to a malicious contract that implements the Controller interface but performs unauthorized actions. While the harvest() function already gives controller significant power, a malicious controller could also grief operations.","paths":["1. Governance calls setController(maliciousAddress)\n2. Malicious controller can block withdrawals or steal funds via harvest()"]},{"id":"F-010","severity":"Low","confidence":"high","title":"earn() can be called by anyone triggering unnecessary operations","locations":["Contract.sol:316-320"],"claim":"The earn() function has no access control - anyone can call it. While this doesn't directly cause fund loss, it could be used to trigger operations at unexpected times or grief the governance.","impact":"Any user can trigger the earn() function, potentially at unfavorable times or more frequently than intended. While not directly harmful, this allows unauthorized manipulation of when yield is harvested.","paths":["1. Anyone calls earn()\n2. Available funds are transferred to controller\n3. Can be used to front-run or grief governance strategies"]},{"id":"F-011","severity":"Low","confidence":"medium","title":"Missing ERC20 transfer return value check in deposit (indirect)","locations":["Contract.sol:329"],"claim":"While deposit uses safeTransferFrom which properly checks return values, this is a defensive coding note. The vault relies on SafeERC20 which does perform return value checks.","impact":"Low - SafeERC20 already handles this correctly. The comment is just noting the vault properly delegates to SafeERC20 for safety."}]

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
