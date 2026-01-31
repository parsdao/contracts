// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IMIGA} from "../interfaces/IPARS.sol";

/**
 * @title  MIGA Token
 * @author MIGA Protocol / Pars Network
 * @notice Bridged MIGA token on EVM chains.
 * @dev    MIGA is the Freedom of Information DAO token, native on Solana.
 *         This contract represents the bridged version on Pars Network and other EVM chains.
 *
 *         MIGA is used for:
 *         - DAO governance voting (1 MIGA = 1 Vote)
 *         - Funding freedom of information projects
 *         - Anti-censorship technology development
 *
 *         Bridge mechanics:
 *         - Wormhole bridge mints tokens on EVM when locked on Solana
 *         - Tokens burned on EVM when bridging back to Solana
 *         - Only authorized bridge contracts can mint/burn
 *
 *         Total Supply: 1,000,000,000 MIGA (native on Solana)
 *         Decimals: 9 (matches Solana SPL token standard)
 */
contract MIGA is ERC20, ERC20Permit, ERC20Burnable, AccessControl, IMIGA {
    // =========  ROLES ========= //

    /// @notice Role for bridge contracts that can mint tokens.
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");

    /// @notice Role for emergency admin functions.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // =========  ERRORS ========= //

    error MIGA_OnlyBridge();
    error MIGA_BridgePaused();
    error MIGA_InvalidAmount();

    // =========  STATE ========= //

    /// @notice Whether bridge operations are paused.
    bool public bridgePaused;

    /// @notice Total amount minted through bridge (for tracking).
    uint256 public totalBridgedIn;

    /// @notice Total amount burned through bridge (for tracking).
    uint256 public totalBridgedOut;

    // =========  EVENTS ========= //

    event BridgedIn(address indexed to, uint256 amount, bytes32 indexed sourceChain);
    event BridgedOut(address indexed from, uint256 amount, bytes32 indexed targetChain);
    event BridgePausedChanged(bool paused);

    // =========  CONSTRUCTOR ========= //

    /**
     * @notice Construct a new MIGA token.
     * @param  admin_ The initial admin address.
     */
    constructor(
        address admin_
    ) ERC20("MIGA", "MIGA") ERC20Permit("MIGA") {
        require(admin_ != address(0), "MIGA: invalid admin");

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(ADMIN_ROLE, admin_);
    }

    // =========  ERC20 OVERRIDES ========= //

    /**
     * @notice Returns the number of decimals for the token.
     * @dev    MIGA uses 9 decimals to match Solana SPL token standard.
     */
    function decimals() public pure override returns (uint8) {
        return 9;
    }

    // =========  BRIDGE FUNCTIONS ========= //

    /**
     * @notice Mint bridged tokens.
     * @dev    Called by bridge contract when tokens are locked on source chain.
     *         Only callable by addresses with BRIDGE_ROLE.
     * @param  to_     The address to mint tokens to.
     * @param  amount_ The amount of tokens to mint.
     */
    function mint(address to_, uint256 amount_) external override onlyRole(BRIDGE_ROLE) {
        if (bridgePaused) revert MIGA_BridgePaused();
        if (amount_ == 0) revert MIGA_InvalidAmount();

        totalBridgedIn += amount_;
        _mint(to_, amount_);

        emit BridgedIn(to_, amount_, bytes32(0)); // Source chain can be passed via another param
    }

    /**
     * @notice Burn tokens for bridging out.
     * @dev    Called by bridge contract when user wants to bridge back to Solana.
     *         Only callable by addresses with BRIDGE_ROLE.
     * @param  from_   The address to burn tokens from.
     * @param  amount_ The amount of tokens to burn.
     */
    function burn(address from_, uint256 amount_) external override onlyRole(BRIDGE_ROLE) {
        if (bridgePaused) revert MIGA_BridgePaused();
        if (amount_ == 0) revert MIGA_InvalidAmount();

        totalBridgedOut += amount_;
        _burn(from_, amount_);

        emit BridgedOut(from_, amount_, bytes32(0)); // Target chain can be passed via another param
    }

    /**
     * @notice Mint bridged tokens with source chain tracking.
     * @param  to_          The address to mint tokens to.
     * @param  amount_      The amount of tokens to mint.
     * @param  sourceChain_ The source chain identifier.
     */
    function mintWithSource(
        address to_,
        uint256 amount_,
        bytes32 sourceChain_
    ) external onlyRole(BRIDGE_ROLE) {
        if (bridgePaused) revert MIGA_BridgePaused();
        if (amount_ == 0) revert MIGA_InvalidAmount();

        totalBridgedIn += amount_;
        _mint(to_, amount_);

        emit BridgedIn(to_, amount_, sourceChain_);
    }

    /**
     * @notice Burn tokens for bridging out with target chain tracking.
     * @param  from_        The address to burn tokens from.
     * @param  amount_      The amount of tokens to burn.
     * @param  targetChain_ The target chain identifier.
     */
    function burnWithTarget(
        address from_,
        uint256 amount_,
        bytes32 targetChain_
    ) external onlyRole(BRIDGE_ROLE) {
        if (bridgePaused) revert MIGA_BridgePaused();
        if (amount_ == 0) revert MIGA_InvalidAmount();

        totalBridgedOut += amount_;
        _burn(from_, amount_);

        emit BridgedOut(from_, amount_, targetChain_);
    }

    // =========  ADMIN FUNCTIONS ========= //

    /**
     * @notice Pause or unpause bridge operations.
     * @dev    Only callable by ADMIN_ROLE.
     * @param  paused_ Whether to pause or unpause.
     */
    function setBridgePaused(bool paused_) external onlyRole(ADMIN_ROLE) {
        bridgePaused = paused_;
        emit BridgePausedChanged(paused_);
    }

    /**
     * @notice Add a bridge contract.
     * @dev    Only callable by DEFAULT_ADMIN_ROLE.
     * @param  bridge_ The bridge contract address.
     */
    function addBridge(address bridge_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(bridge_ != address(0), "MIGA: invalid bridge");
        _grantRole(BRIDGE_ROLE, bridge_);
    }

    /**
     * @notice Remove a bridge contract.
     * @dev    Only callable by DEFAULT_ADMIN_ROLE.
     * @param  bridge_ The bridge contract address.
     */
    function removeBridge(address bridge_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(BRIDGE_ROLE, bridge_);
    }

    // =========  VIEW FUNCTIONS ========= //

    /**
     * @notice Get the net bridged amount (in - out).
     * @return The net amount of tokens bridged onto this chain.
     */
    function netBridged() external view returns (uint256) {
        return totalBridgedIn - totalBridgedOut;
    }

    /**
     * @notice Check if an address is an authorized bridge.
     * @param  bridge_ The address to check.
     * @return Whether the address has BRIDGE_ROLE.
     */
    function isBridge(address bridge_) external view returns (bool) {
        return hasRole(BRIDGE_ROLE, bridge_);
    }
}
