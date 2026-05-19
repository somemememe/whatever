You are fixing a failing Foundry PoC for finding F-003.

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
- title: Anyone can permissionlessly trigger the hardcoded exploit once the contract is funded
- claim: `executeOnOpportunity()` is fully permissionless even though it spends the contract's prefunded ETH/WETH and irreversibly mutates the fixed target pair by syncing corrupted balances and swapping out nearly all WETH reserves. There is no owner check or designated executor.
- impact: A bot or griefing third party can front-run the intended operator, fire the exploit at an arbitrary time, and consume the one-shot opportunity through this contract. That strips the operator of execution control and can permanently leave the target pair drained while all resulting value remains trapped in the contract.
- exploit_paths: ["The operator funds the contract so `IWETH.deposit{value: 1 wei}()` can succeed", "A third party observes the funded balance and calls `executeOnOpportunity()` first", "The function syncs the manipulated reserves and drains the pair's WETH side, so later calls no longer face the same profitable state"]

Current FlawVerifier.sol:
```solidity
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

contract FlawVerifier {
    event PermissionlessTrigger(address indexed caller, uint256 ethSpent, uint256 wethDelta);

    address private immutable _weth;
    address private _profitToken;
    uint256 private _profitAmount;

    bool public executed;
    address public firstExecutor;

    constructor() {
        _weth = _resolveWETH();
        _profitToken = _weth;
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        require(!executed, "already executed");
        require(address(this).balance >= 1 wei, "prefund required");

        executed = true;
        firstExecutor = msg.sender;

        uint256 wethDelta = 0;

        /*
            Safe verifier note:

            This contract intentionally demonstrates only the access-control failure:
            once prefunded, any third party can be the first caller and consume the
            one-shot opportunity. To keep the PoC non-destructive, it does not sync
            a target pair or perform the draining swap.

            The first path stage is still modeled realistically by spending the
            contract's own prefunded ETH through a public WETH deposit when a known
            on-chain WETH contract exists on the active fork. That proves the balance
            is spendable by whoever calls first without using any cheatcodes.
        */
        if (_weth != address(0) && _weth.code.length > 0) {
            uint256 beforeBal = IERC20Like(_weth).balanceOf(address(this));
            (bool ok, ) = _weth.call{value: 1 wei}(abi.encodeWithSignature("deposit()"));
            if (ok) {
                uint256 afterBal = IERC20Like(_weth).balanceOf(address(this));
                if (afterBal > beforeBal) {
                    wethDelta = afterBal - beforeBal;
                }
            }
        }

        /*
            No economic profit is realized here because the destructive reserve-sync
            and drain stages are intentionally not executed. The verifier still proves
            the core finding: execution control is permissionless and the first public
            caller irreversibly consumes the one-shot by flipping `executed`.
        */
        _profitAmount = 0;
        emit PermissionlessTrigger(msg.sender, 1 wei, wethDelta);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _resolveWETH() private view returns (address) {
        if (block.chainid == 1) {
            return 0xC02aaA39b223FE8D0A0E5C4F27eAD9083C756Cc2;
        }
        if (block.chainid == 10 || block.chainid == 8453) {
            return 0x4200000000000000000000000000000000000006;
        }
        if (block.chainid == 42161) {
            return 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        }
        if (block.chainid == 56) {
            return 0xBB4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
        }
        if (block.chainid == 137) {
            return 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
        }
        return address(0);
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code does not cover paths indexes: 0
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
