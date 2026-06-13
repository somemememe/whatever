pragma solidity 0.6.2;

import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/Address.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./interfaces/IPriceEstimator.sol";

contract PriceEstimator is IPriceEstimator, Initializable, OwnableUpgradeSafe {
    using Address for address;

    IUniswapV2Router02 internal uniswapRouter;
    AggregatorV3Interface internal dataFeed;

    bool public useOracle;

    event SettingsUpdated(address priceAggregatorAddress, bool useOracle);

    modifier onlyContract(address account) {
        require(
            account.isContract(),
            "[Validation] The address does not contain a contract"
        );
        _;
    }

    function initialize(
        address uniswapOrOracleAddress,
        bool _useOracle
    ) external onlyContract(uniswapOrOracleAddress) {
        __PriceEstimator_init(uniswapOrOracleAddress, _useOracle);
    }

    function __PriceEstimator_init(
        address uniswapOrOracleAddress,
        bool _useOracle
    ) internal initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        if (_useOracle) {
            dataFeed = AggregatorV3Interface(uniswapOrOracleAddress);
        } else {
            uniswapRouter = IUniswapV2Router02(uniswapOrOracleAddress);
        }
        useOracle = _useOracle;
    }

    /// @notice Set Price estimator to use dex router.
    /// @param uniswapRouterAddress The dex router to use.
    /// @param _useOracle flag for using oracle, set false for dex router.
    function setUniswapRouter(
        address uniswapRouterAddress,
        bool _useOracle
    ) external onlyOwner onlyContract(uniswapRouterAddress) {
        require(
            uniswapRouterAddress != address(0),
            "[Validation]: Invalid uniswap router address"
        );
        uniswapRouter = IUniswapV2Router02(uniswapRouterAddress);
        useOracle = _useOracle;
        emit SettingsUpdated(uniswapRouterAddress, _useOracle);
    }

    function getEstimatedETHforERC20(
        uint256 erc20Amount,
        address tokenAddress
    ) external view override returns (uint256[] memory) {
        return
            uniswapRouter.getAmountsIn(
                erc20Amount,
                getPathForETHtoERC20(tokenAddress)
            );
    }

    function getPathForETHtoERC20(
        address tokenAddress
    ) internal view returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = uniswapRouter.WETH();
        path[1] = tokenAddress;
        return path;
    }

    function getUseOracle() external view override returns (bool) {
        return useOracle;
    }

    function getEstimatedERC20forETH(
        uint256 etherAmount,
        address tokenAddress
    ) external view override returns (uint256[] memory) {
        return
            uniswapRouter.getAmountsIn(
                etherAmount,
                getPathForERC20toETH(tokenAddress)
            );
    }

    function getPathForERC20toETH(
        address tokenAddress
    ) internal view returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = tokenAddress;
        path[1] = uniswapRouter.WETH();
        return path;
    }

    /// @notice Set Price estimator to use oracle feed.
    /// @param _dataFeed The chainlink feed to use.
    /// @param _useOracle flag for using _dataFeed, set true to use data feed.
    function setOracleParams(
        address _dataFeed,
        bool _useOracle
    ) external override onlyOwner onlyContract(_dataFeed) {
        require(address(_dataFeed) != address(0), "dataFeed is zero address");
        useOracle = _useOracle;
        dataFeed = AggregatorV3Interface(_dataFeed);
        emit SettingsUpdated(_dataFeed, _useOracle);
    }

    /// @notice Retrieves the current fee amount in ETH for a given token.
    /// @param _feesInUSD The Fees in USD.
    /// @return The calculated fee amount in ETH.
    /// @dev Uses the Chainlink data feed to get the latest ETH price for fee calculation.
    function getFeeInETHWithOracle(
        uint256 _feesInUSD
    ) external view override returns (uint256) {
        (
            ,
            /* uint80 roundID */ int answer /*uint startedAt*/ /*uint timeStamp*/ /*uint80 answeredInRound*/,
            ,
            ,

        ) = dataFeed.latestRoundData();

        // multiply by 100 to keep decimals same with uniswap router response
        return ((_feesInUSD * 10 ** 18) / uint256(answer)) * 100;
    }
}
