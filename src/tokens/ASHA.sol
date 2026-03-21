// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {IASHA} from "../interfaces/IASHA.sol";

/**
 * @title  ASHA Token
 * @author Pars Protocol
 * @notice The governance/reserve token of the Pars Protocol.
 * @dev    ASHA is the governance/reserve token (like OHM on Olympus), used for:
 *         - Protocol governance through veASHA
 *         - Staking rewards via xASHA
 *         - Treasury backing and protocol-owned liquidity
 *
 *         PARS is the native coin of Pars Network (like ETH) and is NOT an ERC20.
 *
 *         Asha (آشا) = Truth/Righteousness in Avestan
 *         Token Decimals: 9 (following Olympus convention)
 *
 *         Mint permissions are controlled by the Pars Authority system.
 */
contract ASHA is ERC20, ERC20Permit, ERC20Votes, IASHA {
    // =========  ERRORS ========= //

    error ASHA_OnlyVault();
    error ASHA_OnlyGovernor();
    error ASHA_OnlyGuardian();
    error ASHA_Unauthorized();

    // =========  STATE ========= //

    /// @notice The Pars Authority contract that manages permissions.
    IParsAuthority public authority;

    // =========  CONSTRUCTOR ========= //

    /**
     * @notice Construct a new ASHA token.
     * @param  authority_ The address of the Pars Authority contract.
     */
    constructor(
        address authority_
    ) ERC20("Asha", "ASHA") ERC20Permit("Asha") {
        authority = IParsAuthority(authority_);
    }

    // =========  MODIFIERS ========= //

    modifier onlyVault() {
        if (msg.sender != authority.vault()) revert ASHA_OnlyVault();
        _;
    }

    modifier onlyGovernor() {
        if (msg.sender != authority.governor()) revert ASHA_OnlyGovernor();
        _;
    }

    // =========  ERC20 OVERRIDES ========= //

    /**
     * @notice Returns the number of decimals for the token.
     * @dev    ASHA uses 9 decimals (following Olympus convention).
     * @return The number of decimals (9).
     */
    function decimals() public pure override returns (uint8) {
        return 9;
    }

    // =========  MINT / BURN ========= //

    /**
     * @notice Mint ASHA tokens to an address.
     * @dev    Only callable by the vault (Treasury/Staking).
     *         Zarb (ضرب) = Mint in Persian
     * @param  account_ The address to mint tokens to.
     * @param  amount_  The amount of tokens to mint.
     */
    function mint(address account_, uint256 amount_) external override onlyVault {
        _mint(account_, amount_);
    }

    /**
     * @notice Burn ASHA tokens from the caller's balance.
     * @dev    Suzandan (سوزاندن) = Burn in Persian
     * @param  amount_ The amount of tokens to burn.
     */
    function burn(uint256 amount_) external override {
        _burn(msg.sender, amount_);
    }

    /**
     * @notice Burn ASHA tokens from an address with approval.
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
