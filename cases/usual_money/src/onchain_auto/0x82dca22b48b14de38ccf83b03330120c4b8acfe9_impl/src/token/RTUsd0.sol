// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import {
    ERC20Upgradeable
} from "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {
    ERC20PausableUpgradeable
} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {
    ERC20PermitUpgradeable
} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

import {IRegistryAccess} from "src/interfaces/registry/IRegistryAccess.sol";
import {IRegistryContract} from "src/interfaces/registry/IRegistryContract.sol";
import {IRTUsd0} from "src/interfaces/token/IRTUsd0.sol";
import {IUsd0} from "src/interfaces/token/IUsd0.sol";
import {CheckAccessControl} from "src/utils/CheckAccessControl.sol";

import {
    PAUSING_CONTRACTS_ROLE,
    UNPAUSING_CONTRACTS_ROLE,
    RTUSD0Symbol,
    RTUSD0Name,
    CONTRACT_USD0,
    CONTRACT_REGISTRY_ACCESS,
    RTUSD0_MINT_ROLE,
    RTUSD0_BURN_ROLE
} from "src/constants.sol";

import {AmountIsZero, Blacklisted, NullContract} from "src/errors.sol";

/// @title   RTUsd0 Contract
/// @notice  Manages redemption tokens for the UsualDAO USD ecosystem, providing functionality for transferring redemption tokens.
/// @dev     Inherits from ERC20, ERC20PermitUpgradeable  to provide a range of functionalities including pausing and permit-based approvals.
/// @dev     This contract is upgradeable, allowing for future improvements and enhancements.
/// @author  Usual Tech team

contract RTUsd0 is ERC20PausableUpgradeable, ERC20PermitUpgradeable, IRTUsd0 {
    using CheckAccessControl for IRegistryAccess;

    /// @custom:storage-location erc7201:RTUsd0.storage.v0
    struct RTUsd0StorageV0 {
        /// The address of the registry access contract.
        IRegistryAccess registryAccess;
        /// The address of the USD0 token.
        IUsd0 usd0;
    }

    // keccak256(abi.encode(uint256(keccak256("RTUsd0.storage.v0")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable-next-line
    bytes32 public constant RTUsd0StorageV0Location =
        0x54320cf6e50305ceaa39d95fcadb712e6fe8877a8425b1400ccc9a9598f09700;

    /// @notice Returns the storage struct of the contract.
    /// @return $ .
    function _rtusd0StorageV0() internal pure returns (RTUsd0StorageV0 storage $) {
        bytes32 position = RTUsd0StorageV0Location;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := position
        }
    }

    /*//////////////////////////////////////////////////////////////
                             Constructor
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////
                             Initializer
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the RTUsd0 contract with the given parameters
    /// @param registryContract The address of the registry contract
    function initialize(address registryContract) public initializer {
        // Validate input parameters
        if (registryContract == address(0)) {
            revert NullContract();
        }

        // Initialize parent contracts
        __ERC20_init(RTUSD0Name, RTUSD0Symbol);
        __ERC20Pausable_init();
        __ERC20Permit_init(RTUSD0Name);

        // Set up storage
        RTUsd0StorageV0 storage $ = _rtusd0StorageV0();

        // Get registry access from registry contract
        IRegistryContract registry = IRegistryContract(registryContract);
        $.registryAccess = IRegistryAccess(registry.getContract(CONTRACT_REGISTRY_ACCESS));

        // Get USD0 token from registry contract
        $.usd0 = IUsd0(registry.getContract(CONTRACT_USD0));
    }

    /*//////////////////////////////////////////////////////////////
                             External Functions
    //////////////////////////////////////////////////////////////*/

    // @inheritdoc IRTUsd0
    function pause() external {
        RTUsd0StorageV0 storage $ = _rtusd0StorageV0();
        $.registryAccess.onlyMatchingRole(PAUSING_CONTRACTS_ROLE);
        _pause();
    }

    // @inheritdoc IRTUsd0
    function unpause() external {
        RTUsd0StorageV0 storage $ = _rtusd0StorageV0();
        $.registryAccess.onlyMatchingRole(UNPAUSING_CONTRACTS_ROLE);
        _unpause();
    }

    // @inheritdoc IRTUsd0
    function mint(address to, uint256 amount) external {
        RTUsd0StorageV0 storage $ = _rtusd0StorageV0();
        $.registryAccess.onlyMatchingRole(RTUSD0_MINT_ROLE);
        _mint(to, amount);
    }

    // @inheritdoc IRTUsd0
    function burnFrom(address account, uint256 amount) external {
        RTUsd0StorageV0 storage $ = _rtusd0StorageV0();
        $.registryAccess.onlyMatchingRole(RTUSD0_BURN_ROLE);
        _burn(account, amount);
    }

    /*//////////////////////////////////////////////////////////////
                             Internal Functions
    //////////////////////////////////////////////////////////////*/

    function _update(address sender, address recipient, uint256 amount)
        internal
        override(ERC20PausableUpgradeable, ERC20Upgradeable)
    {
        if (amount == 0) {
            revert AmountIsZero();
        }
        RTUsd0StorageV0 storage $ = _rtusd0StorageV0();
        IUsd0 usd0 = $.usd0;
        if (usd0.isBlacklisted(sender) || usd0.isBlacklisted(recipient)) {
            revert Blacklisted();
        }
        // we update the balance of the sender and the recipient
        super._update(sender, recipient, amount);
    }
}
