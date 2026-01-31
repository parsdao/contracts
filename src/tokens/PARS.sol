// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {IPARS} from "../interfaces/IPARS.sol";

/**
 * @title  PARS Token
 * @author Pars Protocol
 * @notice The main governance token of the Pars Protocol.
 * @dev    PARS is the native token of the Pars Network, used for:
 *         - Protocol governance through vePARS
 *         - Staking rewards via xPARS
 *         - Treasury backing and protocol-owned liquidity
 *
 *         Pars (پارس) = Persia/Persian
 *         Token Decimals: 9 (following Olympus convention)
 *
 *         Mint permissions are controlled by the Pars Authority system.
 */
contract PARS is ERC20, ERC20Permit, ERC20Votes, IPARS {
    // =========  ERRORS ========= //

    error PARS_OnlyVault();
    error PARS_OnlyGovernor();
    error PARS_OnlyGuardian();
    error PARS_Unauthorized();

    // =========  STATE ========= //

    /// @notice The Pars Authority contract that manages permissions.
    IParsAuthority public authority;

    // =========  CONSTRUCTOR ========= //

    /**
     * @notice Construct a new PARS token.
     * @param  authority_ The address of the Pars Authority contract.
     */
    constructor(
        address authority_
    ) ERC20("Pars", "PARS") ERC20Permit("Pars") {
        authority = IParsAuthority(authority_);
    }

    // =========  MODIFIERS ========= //

    modifier onlyVault() {
        if (msg.sender != authority.vault()) revert PARS_OnlyVault();
        _;
    }

    modifier onlyGovernor() {
        if (msg.sender != authority.governor()) revert PARS_OnlyGovernor();
        _;
    }

    // =========  ERC20 OVERRIDES ========= //

    /**
     * @notice Returns the number of decimals for the token.
     * @dev    PARS uses 9 decimals (following Olympus convention).
     * @return The number of decimals (9).
     */
    function decimals() public pure override returns (uint8) {
        return 9;
    }

    // =========  MINT / BURN ========= //

    /**
     * @notice Mint PARS tokens to an address.
     * @dev    Only callable by the vault (Treasury/Staking).
     *         Zarb (ضرب) = Mint in Persian
     * @param  account_ The address to mint tokens to.
     * @param  amount_  The amount of tokens to mint.
     */
    function mint(address account_, uint256 amount_) external override onlyVault {
        _mint(account_, amount_);
    }

    /**
     * @notice Burn PARS tokens from the caller's balance.
     * @dev    Suzandan (سوزاندن) = Burn in Persian
     * @param  amount_ The amount of tokens to burn.
     */
    function burn(uint256 amount_) external override {
        _burn(msg.sender, amount_);
    }

    /**
     * @notice Burn PARS tokens from an address with approval.
     * @param  account_ The address to burn tokens from.
     * @param  amount_  The amount of tokens to burn.
     */
    function burnFrom(address account_, uint256 amount_) external override {
        _spendAllowance(account_, msg.sender, amount_);
        _burn(account_, amount_);
    }

    // =========  AUTHORITY ========= //

    /**
     * @notice Update the Pars Authority contract.
     * @dev    Only callable by the current governor.
     * @param  newAuthority_ The new authority contract address.
     */
    function setAuthority(IParsAuthority newAuthority_) external onlyGovernor {
        authority = newAuthority_;
    }

    // =========  REQUIRED OVERRIDES ========= //

    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {
        super._update(from, to, amount);
    }

    function nonces(
        address owner
    ) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}

/**
 * @title  IParsAuthority Interface
 * @notice Interface for the Pars Authority contract that manages protocol permissions.
 * @dev    Ekhtyar (اختیار) = Authority in Persian
 */
interface IParsAuthority {
    // =========  EVENTS ========= //

    event GovernorPushed(address indexed from, address indexed to, bool effectiveImmediately);
    event GuardianPushed(address indexed from, address indexed to, bool effectiveImmediately);
    event PolicyPushed(address indexed from, address indexed to, bool effectiveImmediately);
    event VaultPushed(address indexed from, address indexed to, bool effectiveImmediately);

    event GovernorPulled(address indexed from, address indexed to);
    event GuardianPulled(address indexed from, address indexed to);
    event PolicyPulled(address indexed from, address indexed to);
    event VaultPulled(address indexed from, address indexed to);

    // =========  VIEW ========= //

    /// @notice The governor address (highest authority).
    /// @dev    Farmandar (فرماندار) = Governor in Persian
    function governor() external view returns (address);

    /// @notice The guardian address (emergency powers).
    /// @dev    Negahban (نگهبان) = Guardian in Persian
    function guardian() external view returns (address);

    /// @notice The policy address (day-to-day operations).
    /// @dev    Siasat (سیاست) = Policy in Persian
    function policy() external view returns (address);

    /// @notice The vault address (Treasury/minting authority).
    /// @dev    Khazaneh (خزانه) = Vault/Treasury in Persian
    function vault() external view returns (address);
}
