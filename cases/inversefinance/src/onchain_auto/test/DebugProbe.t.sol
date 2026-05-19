// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/DebugProbe.sol";

interface Vm {
    function createSelectFork(string calldata urlOrAlias, uint256 blockNumber) external returns (uint256);
}

contract DebugProbeTest {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function testDebug() external {
        vm.createSelectFork("https://eth-mainnet.g.alchemy.com/v2/ugA3TDW3tlXhwhc3SHfuk", 14_972_418);
        DebugProbe probe = new DebugProbe();
        probe.probeMeta();
        probe.probeMarket();
        probe.probePairs();
    }
}
