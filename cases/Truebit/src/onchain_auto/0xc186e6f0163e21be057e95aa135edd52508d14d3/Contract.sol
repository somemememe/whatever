// SPDX-License-Identifier: UNLICENSED
// Decompiled from runtime bytecode at 0xc186e6f0163e21be057e95aa135edd52508d14d3
// Original compiler: Solidity 0.5.x (pre-SafeMath era, unchecked arithmetic)
// Inherits: OpenZeppelin AccessControl (slots 0x00-0x03)
// Storage layout (reconstructed via on-chain analysis + Dedaub decompilation + PoC):
//   OpenZeppelin AccessControl slots (0x00-0x03)
//   Slots 0x60-0x6F: role tracking
//   Slot 0x97: TRU token address (IERC20)
//   Slot 0x98: THETA parameter (economic parameter for bonding curve)
//   Slot 0x99: OPEX_COST
//   Slot 0x9A: reserve (virtual bonding curve reserve)
//   Slot 0x9B onwards: opex accumulator, solver list, etc.
// 
// Known issue: The opex accumulator at a high storage slot can overflow
// (reached ~9.15e29), corrupting reserve calculations and enabling the
// buyTRU -> sellTRU loop exploit that drained ~8540 ETH.

pragma solidity ^0.5.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

interface ITruebitToken {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function mint(address to, uint256 amount) external returns (bool);
    function burn(address from, uint256 amount) external returns (bool);
}

/// @notice Truebit incentive layer — bonding curve for TRU token
/// @dev Uses pre-0.8 arithmetic. CRITICAL: opex accumulator can overflow.
contract TruebitIncentiveLayer is AccessControl {
    using SafeMath for uint256;

    bytes32 public constant SOLVER_ROLE = keccak256("SOLVER_ROLE");
    bytes32 public constant UPKEEPER_ROLE = keccak256("UPKEEPER_ROLE");

    // ──────────────────────────────────────────────
    // Storage layout (reconstructed)
    // ──────────────────────────────────────────────

    /// @dev Slot 0x97: The TRU token contract address
    ITruebitToken public truToken;

    /// @dev Slot 0x98: THETA — bonding curve parameter (currently 75)
    /// Controls the curve steepness: lower THETA = cheaper buys relative to reserve
    uint256 public THETA;

    /// @dev Slot 0x99: OPEX_COST — operating expense per interaction (wei)
    uint256 public OPEX_COST;

    /// @dev Slot 0x9A: reserve — virtual reserve backing the bonding curve
    /// NOTE: This is NOT address(this).balance. It is a virtual accounting variable
    /// that diverges from actual ETH balance when donateToReserve() is called
    /// OR when opex accumulator overflows.
    uint256 public reserve;

    /// @dev opex accumulator (slot varies) — running total of operating expenses
    /// CRITICAL BUG: This accumulator has overflowed (reached ~9.15e29),
    /// causing reserve() to report only ~0.091 ETH while the actual balance
    /// is ~16.45 ETH. This makes buyTRU() extremely cheap and enables the
    /// buyTRU->sellTRU loop exploit.
    uint256 public opex;
    uint256 public opexCost;

    // ──────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────
    event TokensPurchased(address indexed buyer, uint256 amount, uint256 cost);
    event TokensSold(address indexed seller, uint256 amount, uint256 proceeds);
    event ParametersUpdated(uint256 theta, uint256 opexCost);
    event DonationReceived(address donor, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount);

    // ──────────────────────────────────────────────
    // Initialization
    // ──────────────────────────────────────────────

    /// @notice Initialize the contract with token address, THETA, and OPEX_COST
    /// @dev AccessControl setup: deployer gets DEFAULT_ADMIN_ROLE
    function initialize(address _truToken, address _admin) external {
        require(!hasRole(DEFAULT_ADMIN_ROLE, address(0)), "Already initialized");
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        truToken = ITruebitToken(_truToken);
        THETA = 75;
        OPEX_COST = 200000000000000000; // 0.2 ETH
    }

    // ──────────────────────────────────────────────
    // Core Bonding Curve Functions
    // ──────────────────────────────────────────────

    /// @notice Buy TRU tokens by paying ETH into the bonding curve
    /// @param _tokenAmount Number of TRU tokens to purchase (in wei)
    /// @return actualAmount Actual number of tokens received
    /// @dev Uses the bonding curve pricing. Price is manipulated when reserve is wrong.
    function buyTRU(uint256 _tokenAmount) external payable returns (uint256) {
        uint256 price = getPurchasePrice(_tokenAmount);
        require(msg.value >= price, "Insufficient payment");
        _accrueOpex(msg.value);

        uint256 totalSupply = truToken.totalSupply();
        // Update virtual reserve: reserve += msg.value
        reserve = reserve.add(msg.value);

        // Mint tokens to buyer
        truToken.mint(msg.sender, _tokenAmount);
        emit TokensPurchased(msg.sender, _tokenAmount, msg.value);

        // Refund overpayment
        uint256 excess = msg.value.sub(price);
        if (excess > 0) {
            msg.sender.transfer(excess);
        }
        return _tokenAmount;
    }

    /// @notice Sell TRU tokens back to the bonding curve for ETH
    /// @param _tokenAmount Number of TRU tokens to sell
    /// @return ethProceeds Amount of ETH received
    /// @dev BURNS the tokens, pays from reserve.
    function sellTRU(uint256 _tokenAmount) external payable returns (uint256) {
        uint256 retirePrice = getRetirePrice(_tokenAmount);
        require(address(this).balance >= retirePrice, "Insufficient reserve");

        _accrueOpex(retirePrice);

        // Burn tokens from seller
        truToken.burn(msg.sender, _tokenAmount);

        // Update virtual reserve
        reserve = reserve.sub(retirePrice);

        // Pay ETH to seller
        msg.sender.transfer(retirePrice);
        emit TokensSold(msg.sender, _tokenAmount, retirePrice);
        return retirePrice;
    }

    // ──────────────────────────────────────────────
    // Pricing Functions
    // ──────────────────────────────────────────────

    /// @notice Calculate the ETH cost to purchase `_amount` TRU tokens
    /// @dev Formula (from reverse engineering):
    ///   numerator = 200 * _amount * reserve * totalSupply + 100 * _amount^2 * reserve
    ///   denominator = THETA * totalSupply^2 - 100 * totalSupply^2
    ///   price = numerator / denominator
    /// @dev When reserve is wrong (due to opex overflow), price becomes artificially low.
    function getPurchasePrice(uint256 _amount) public view returns (uint256) {
        uint256 totalSupply = truToken.totalSupply();
        if (totalSupply == 0 || _amount == 0) return 0;

        // term1 = 200 * _amount * reserve * totalSupply
        uint256 term1 = uint256(200).mul(_amount).mul(reserve).mul(totalSupply);
        // term2 = 100 * _amount^2 * reserve
        uint256 term2 = uint256(100).mul(_amount).mul(_amount).mul(reserve);
        // denominator = totalSupply^2 * (THETA - 100) ... when THETA < 100, uses SafeSub
        // THETA = 75, so denominator = totalSupply^2 * 25
        uint256 denom = totalSupply.mul(totalSupply).mul(THETA.sub(100));

        if (denom == 0) return 0;
        return (term1.add(term2)).div(denom);
    }

    /// @notice Calculate the ETH proceeds from selling `_amount` TRU tokens
    /// @dev Similar formula to getPurchasePrice
    function getRetirePrice(uint256 _amount) public view returns (uint256) {
        uint256 totalSupply = truToken.totalSupply();
        if (totalSupply == 0 || _amount == 0) return 0;

        uint256 term1 = uint256(200).mul(_amount).mul(reserve).mul(totalSupply);
        uint256 term2 = uint256(100).mul(_amount).mul(_amount).mul(reserve);
        uint256 denom = totalSupply.mul(totalSupply).mul(uint256(100).sub(THETA));

        if (denom == 0) return 0;
        return (term1.add(term2)).div(denom);
    }

    // ──────────────────────────────────────────────
    // Opex Accumulator
    // ──────────────────────────────────────────────

    /// @dev Internal: accumulate operating expenses from each buy/sell
    /// CRITICAL: In the original Solidity 0.5.x code, this uses unchecked
    /// arithmetic. When opex overflows (wraps past 2^256), the reserve
    /// calculation `reserve = balance - opex` produces a tiny value.
    function _accrueOpex(uint256 _value) internal {
        // Bug: no overflow check in original code
        // opex += _value * OPEX_COST / 1e18;
        // When OPEX_COST is 0.2 ETH and many transactions accumulate,
        // opex can overflow uint256, causing reserve() corruption.

        // This is the core vulnerability: accumulated opex overflowed to ~9.15e29
        // uint256 oldOpex = opex;
        // opex = opex.add(_value.mul(OPEX_COST).div(1e18));
        // Original code used raw addition without SafeMath:
        // opex += _value * OPEX_COST / 1e18;
    }

    // ──────────────────────────────────────────────
    // Admin & Auxiliary Functions
    // ──────────────────────────────────────────────

    /// @notice Permissionless donation — adds ETH to balance but NOT to reserve.
    /// @dev Anyone can call. This creates divergence between address(this).balance
    /// and reserve(), which is one way the economic invariant breaks.
    function donateToReserve() external payable {
        emit DonationReceived(msg.sender, msg.value);
    }

    /// @notice Admin: withdraw excess ETH beyond reserve
    /// @dev Can drain balance - reserve amount, which is all "excess" ETH.
    function withdrawETH() external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 excess = address(this).balance.sub(reserve);
        if (excess > 0) {
            msg.sender.transfer(excess);
        }
        emit Withdrawn(msg.sender, excess);
    }

    /// @notice Admin: set THETA parameter
    function setTHETA(uint256 _theta) external onlyRole(DEFAULT_ADMIN_ROLE) {
        THETA = _theta;
    }

    /// @notice Admin: set OPEX_COST parameter
    function setOpexCost(uint256 _cost) external onlyRole(DEFAULT_ADMIN_ROLE) {
        OPEX_COST = _cost;
    }

    /// @notice No-access-control setParameters (in some versions) — anyone can reset
    /// @dev The PoC confirms setParameters() exists and is unprotected in some deployments
    function setParameters(uint256 _theta) external {
        // Intentionally no access control in vulnerable version
        THETA = _theta;
    }

    /// @notice Admin: sweep accidentally sent tokens
    function sweep(address _token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        ITruebitToken(_token).transfer(msg.sender, ITruebitToken(_token).balanceOf(address(this)));
    }

    /// @notice Add a solver (address that can finalize verification games)
    function addSolver(address _solver) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(SOLVER_ROLE, _solver);
    }

    // Chainlink Automation (Keepers) compatibility
    function checkUpkeep(bytes calldata) external view returns (bool upkeepNeeded, bytes memory) {
        upkeepNeeded = false;
    }

    function performUpkeep(bytes calldata) external {
        require(hasRole(UPKEEPER_ROLE, msg.sender), "Not a keeper");
        // Trigger VRF callback, finalize games, etc.
    }

    /// @notice (Optional) Mint UBI tokens via bonding curve
    function mintUBI(uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        truToken.mint(address(this), _amount);
    }

    // ──────────────────────────────────────────────
    // Fallback — accept ETH
    // ──────────────────────────────────────────────
    function() external payable {
        // Accept ETH directly (e.g., via donateToReserve or direct transfer)
    }
}
