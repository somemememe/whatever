// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract FlawVerifier {
    address public constant TARGET = 0xCcd04073f4BdC4510927ea9Ba350875C3c65BF81;

    // All findings reference bundle
    function executeOnOpportunity() external {
        revert("POC generation failed for ALL_FINDINGS");
    }

    receive() external payable {}
}
