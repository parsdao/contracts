// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IFeeRouter} from "../interfaces/ITreasury.sol";

/**
 * @title  Fee Router
 * @author Pars Protocol
 * @notice Routes protocol fees to designated recipients.
 * @dev    Masir Karmazd (مسیر کارمزد) = Fee Router in Persian
 *
 *         The Fee Router:
 *         - Collects fees from various protocol sources
 *         - Distributes fees according to configured allocations
 *         - Supports multiple tokens
 *         - Allows flexible recipient configuration
 *
 *         Default distribution:
 *         - 70% to Treasury
 *         - 20% to Stakers (via Distributor)
 *         - 10% to Committees
 */
contract FeeRouter is IFeeRouter, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =========  ERRORS ========= //

    error FeeRouter_InvalidAllocation();
    error FeeRouter_NoRecipients();
    error FeeRouter_ZeroBalance();
    error FeeRouter_InvalidRecipient();

    // =========  EVENTS ========= //

    event FeesCollected(address indexed token, uint256 amount, address indexed source);
    event FeesDistributed(address indexed token, uint256 totalAmount);
    event RecipientPaid(address indexed token, address indexed recipient, uint256 amount);
    event RecipientsUpdated(uint256 count);

    // =========  ROLES ========= //

    /// @notice Role for collecting fees.
    bytes32 public constant COLLECTOR_ROLE = keccak256("COLLECTOR_ROLE");

    /// @notice Role for updating recipients.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // =========  CONSTANTS ========= //

    /// @notice Precision for allocation percentages.
    uint256 public constant PRECISION = 10_000;

    // =========  STATE ========= //

    /// @notice Array of fee recipients.
    Recipient[] private _recipients;

    /// @notice Mapping of token -> total collected.
    mapping(address => uint256) public totalCollected;

    /// @notice Mapping of token -> total distributed.
    mapping(address => uint256) public totalDistributed;

    // =========  CONSTRUCTOR ========= //

    /**
     * @notice Construct a new Fee Router.
     * @param  admin_ The initial admin address.
     */
    constructor(address admin_) {
        require(admin_ != address(0), "FeeRouter: invalid admin");

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(ADMIN_ROLE, admin_);
        _grantRole(COLLECTOR_ROLE, admin_);
    }

    // =========  FEE COLLECTION ========= //

    /**
     * @notice Collect fees from a source.
     * @dev    Jam'avari (جمع‌آوری) = Collection in Persian
     * @param  token_  The token to collect.
     * @param  amount_ The amount to collect.
     */
    function collectFees(
        address token_,
        uint256 amount_
    ) external override onlyRole(COLLECTOR_ROLE) nonReentrant {
        IERC20(token_).safeTransferFrom(msg.sender, address(this), amount_);
        totalCollected[token_] += amount_;

        emit FeesCollected(token_, amount_, msg.sender);
    }

    /**
     * @notice Collect fees with permit (gasless approval).
     * @param  token_    The token to collect.
     * @param  amount_   The amount to collect.
     * @param  deadline_ Permit deadline.
     * @param  v_        Signature v.
     * @param  r_        Signature r.
     * @param  s_        Signature s.
     */
    function collectFeesWithPermit(
        address token_,
        uint256 amount_,
        uint256 deadline_,
        uint8 v_,
        bytes32 r_,
        bytes32 s_
    ) external onlyRole(COLLECTOR_ROLE) nonReentrant {
        // Try to use permit
        try IERC20Permit(token_).permit(
            msg.sender,
            address(this),
            amount_,
            deadline_,
            v_,
            r_,
            s_
        ) {} catch {}

        IERC20(token_).safeTransferFrom(msg.sender, address(this), amount_);
        totalCollected[token_] += amount_;

        emit FeesCollected(token_, amount_, msg.sender);
    }

    // =========  FEE DISTRIBUTION ========= //

    /**
     * @notice Distribute collected fees to recipients.
     * @dev    Towzi' (توزیع) = Distribution in Persian
     * @param  token_ The token to distribute.
     */
    function distribute(address token_) external override nonReentrant {
        if (_recipients.length == 0) revert FeeRouter_NoRecipients();

        uint256 balance = IERC20(token_).balanceOf(address(this));
        if (balance == 0) revert FeeRouter_ZeroBalance();

        uint256 totalPaid = 0;

        for (uint256 i = 0; i < _recipients.length; i++) {
            Recipient memory recipient = _recipients[i];
            uint256 amount = (balance * recipient.allocationPct) / PRECISION;

            if (amount > 0 && recipient.recipient != address(0)) {
                IERC20(token_).safeTransfer(recipient.recipient, amount);
                totalPaid += amount;

                emit RecipientPaid(token_, recipient.recipient, amount);
            }
        }

        totalDistributed[token_] += totalPaid;

        emit FeesDistributed(token_, totalPaid);
    }

    /**
     * @notice Distribute a specific amount to recipients.
     * @param  token_  The token to distribute.
     * @param  amount_ The amount to distribute.
     */
    function distributeAmount(address token_, uint256 amount_) external nonReentrant {
        if (_recipients.length == 0) revert FeeRouter_NoRecipients();

        uint256 balance = IERC20(token_).balanceOf(address(this));
        require(balance >= amount_, "FeeRouter: insufficient balance");

        uint256 totalPaid = 0;

        for (uint256 i = 0; i < _recipients.length; i++) {
            Recipient memory recipient = _recipients[i];
            uint256 recipientAmount = (amount_ * recipient.allocationPct) / PRECISION;

            if (recipientAmount > 0 && recipient.recipient != address(0)) {
                IERC20(token_).safeTransfer(recipient.recipient, recipientAmount);
                totalPaid += recipientAmount;

                emit RecipientPaid(token_, recipient.recipient, recipientAmount);
            }
        }

        totalDistributed[token_] += totalPaid;

        emit FeesDistributed(token_, totalPaid);
    }

    // =========  RECIPIENT MANAGEMENT ========= //

    /**
     * @notice Set fee recipients.
     * @dev    Girande (گیرنده) = Recipient in Persian
     * @param  recipients_ The new recipients.
     */
    function setRecipients(
        Recipient[] calldata recipients_
    ) external override onlyRole(ADMIN_ROLE) {
        // Validate allocations sum to 100%
        uint256 totalAllocation = 0;
        for (uint256 i = 0; i < recipients_.length; i++) {
            if (recipients_[i].recipient == address(0)) revert FeeRouter_InvalidRecipient();
            totalAllocation += recipients_[i].allocationPct;
        }
        if (totalAllocation != PRECISION) revert FeeRouter_InvalidAllocation();

        // Clear existing recipients
        delete _recipients;

        // Add new recipients
        for (uint256 i = 0; i < recipients_.length; i++) {
            _recipients.push(recipients_[i]);
        }

        emit RecipientsUpdated(recipients_.length);
    }

    /**
     * @notice Get all fee recipients.
     * @return The recipients array.
     */
    function getRecipients() external view override returns (Recipient[] memory) {
        return _recipients;
    }

    /**
     * @notice Get the number of recipients.
     * @return The count.
     */
    function recipientCount() external view returns (uint256) {
        return _recipients.length;
    }

    /**
     * @notice Get a specific recipient.
     * @param  index_ The index.
     * @return The recipient.
     */
    function getRecipient(uint256 index_) external view returns (Recipient memory) {
        return _recipients[index_];
    }

    // =========  VIEW FUNCTIONS ========= //

    /**
     * @notice Get the pending distribution for a token.
     * @param  token_ The token address.
     * @return The pending amount.
     */
    function pendingDistribution(address token_) external view returns (uint256) {
        return IERC20(token_).balanceOf(address(this));
    }

    /**
     * @notice Preview distribution amounts for recipients.
     * @param  token_ The token address.
     * @return recipients The recipient addresses.
     * @return amounts The distribution amounts.
     */
    function previewDistribution(
        address token_
    ) external view returns (address[] memory recipients, uint256[] memory amounts) {
        uint256 balance = IERC20(token_).balanceOf(address(this));
        recipients = new address[](_recipients.length);
        amounts = new uint256[](_recipients.length);

        for (uint256 i = 0; i < _recipients.length; i++) {
            recipients[i] = _recipients[i].recipient;
            amounts[i] = (balance * _recipients[i].allocationPct) / PRECISION;
        }
    }

    // =========  EMERGENCY ========= //

    /**
     * @notice Emergency withdraw tokens.
     * @param  token_ The token to withdraw.
     * @param  to_    The recipient.
     * @param  amount_ The amount.
     */
    function emergencyWithdraw(
        address token_,
        address to_,
        uint256 amount_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(token_).safeTransfer(to_, amount_);
    }

    // =========  RECEIVE ========= //

    /// @notice Allow receiving ETH.
    receive() external payable {}
}

/**
 * @notice Interface for ERC20 Permit.
 */
interface IERC20Permit {
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}
