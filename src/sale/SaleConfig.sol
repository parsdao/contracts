// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ISaleConfig} from "../interfaces/ISale.sol";

/**
 * @title  SaleConfig
 * @author Pars Protocol
 * @notice Configuration contract for CYRUS and MIGA token sales.
 * @dev    Stores sale parameters including token addresses, deposit limits,
 *         sale window, and running totals for BTC-equivalent raised and tokens minted.
 *
 *         Only the deposit verifier contract can update running totals via recordSale().
 */
contract SaleConfig is AccessControl, ISaleConfig {
    // =========  ROLES ========= //

    /// @notice Role for admin operations.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // =========  ERRORS ========= //

    error SaleConfig_InvalidAddress();
    error SaleConfig_InvalidTimestamp();
    error SaleConfig_OnlyVerifier();
    error SaleConfig_InvalidChain(uint8 chain);

    // =========  STATE ========= //

    /// @notice The token being sold (CYRUS or MIGA address).
    address public override saleToken;

    /// @notice The deposit verifier contract address.
    address public override depositVerifier;

    /// @notice Minimum deposit amount per chain (in native decimals).
    mapping(uint8 => uint256) public override minDeposit;

    /// @notice Maximum deposit amount per chain (in native decimals).
    mapping(uint8 => uint256) public override maxDeposit;

    /// @notice Sale start timestamp.
    uint256 public override saleStart;

    /// @notice Sale end timestamp.
    uint256 public override saleEnd;

    /// @notice Total BTC-equivalent raised in satoshis.
    uint256 public override totalRaised;

    /// @notice Total tokens minted during the sale.
    uint256 public override totalMinted;

    // =========  EVENTS ========= //

    event SaleTokenSet(address indexed token);
    event DepositVerifierSet(address indexed verifier);
    event MinDepositSet(uint8 indexed chain, uint256 amount);
    event MaxDepositSet(uint8 indexed chain, uint256 amount);
    event SaleStartSet(uint256 timestamp);
    event SaleEndSet(uint256 timestamp);

    // =========  CONSTRUCTOR ========= //

    /**
     * @notice Construct a new SaleConfig.
     * @param  admin_ The initial admin address.
     */
    constructor(address admin_) {
        require(admin_ != address(0), "SaleConfig: invalid admin");

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(ADMIN_ROLE, admin_);
    }

    // =========  MODIFIERS ========= //

    modifier onlyVerifier() {
        if (msg.sender != depositVerifier) revert SaleConfig_OnlyVerifier();
        _;
    }

    modifier validChain(uint8 chain) {
        if (chain > 6) revert SaleConfig_InvalidChain(chain);
        _;
    }

    // =========  ADMIN FUNCTIONS ========= //

    /**
     * @notice Set the sale token address (CYRUS or MIGA).
     * @param  token The token contract address.
     */
    function setSaleToken(address token) external onlyRole(ADMIN_ROLE) {
        if (token == address(0)) revert SaleConfig_InvalidAddress();
        saleToken = token;
        emit SaleTokenSet(token);
    }

    /**
     * @notice Set the deposit verifier contract address.
     * @param  verifier The verifier contract address.
     */
    function setDepositVerifier(address verifier) external onlyRole(ADMIN_ROLE) {
        if (verifier == address(0)) revert SaleConfig_InvalidAddress();
        depositVerifier = verifier;
        emit DepositVerifierSet(verifier);
    }

    /**
     * @notice Set the minimum deposit amount for a chain.
     * @param  chain     The source chain enum value (0-6).
     * @param  minAmount The minimum deposit in native decimals.
     */
    function setMinDeposit(
        uint8 chain,
        uint256 minAmount
    ) external onlyRole(ADMIN_ROLE) validChain(chain) {
        minDeposit[chain] = minAmount;
        emit MinDepositSet(chain, minAmount);
    }

    /**
     * @notice Set the maximum deposit amount for a chain.
     * @param  chain     The source chain enum value (0-6).
     * @param  maxAmount The maximum deposit in native decimals.
     */
    function setMaxDeposit(
        uint8 chain,
        uint256 maxAmount
    ) external onlyRole(ADMIN_ROLE) validChain(chain) {
        maxDeposit[chain] = maxAmount;
        emit MaxDepositSet(chain, maxAmount);
    }

    /**
     * @notice Set the sale start timestamp.
     * @param  timestamp The start timestamp.
     */
    function setSaleStart(uint256 timestamp) external onlyRole(ADMIN_ROLE) {
        saleStart = timestamp;
        emit SaleStartSet(timestamp);
    }

    /**
     * @notice Set the sale end timestamp.
     * @param  timestamp The end timestamp.
     */
    function setSaleEnd(uint256 timestamp) external onlyRole(ADMIN_ROLE) {
        if (timestamp != 0 && timestamp <= saleStart) revert SaleConfig_InvalidTimestamp();
        saleEnd = timestamp;
        emit SaleEndSet(timestamp);
    }

    // =========  VERIFIER FUNCTIONS ========= //

    /**
     * @notice Record a sale (called by the deposit verifier after minting).
     * @param  satsRaised    BTC-equivalent satoshis raised in this claim.
     * @param  tokensMinted_ Number of tokens minted in this claim.
     */
    function recordSale(
        uint256 satsRaised,
        uint256 tokensMinted_
    ) external override onlyVerifier {
        totalRaised += satsRaised;
        totalMinted += tokensMinted_;
    }
}
