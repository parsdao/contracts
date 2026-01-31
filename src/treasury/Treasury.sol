// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ITreasury} from "../interfaces/ITreasury.sol";
import {Kernel, Module, Keycode, toKeycode} from "../Kernel.sol";

/**
 * @title  Pars Treasury
 * @author Pars Protocol
 * @notice Main treasury module for the Pars Protocol.
 * @dev    Khazaneh (خزانه) = Treasury in Persian
 *
 *         The Treasury holds all protocol reserves and manages:
 *         - Reserve deposits and withdrawals
 *         - Debt issuance for yield strategies
 *         - Asset management and allocation
 *
 *         Based on the Olympus TRSRY module pattern.
 *
 *         Key features:
 *         - Approval-based withdrawals for policies
 *         - Debt tracking for yield strategies
 *         - Emergency shutdown capability
 *         - Integration with Pars Kernel system
 */
contract Treasury is Module, ITreasury, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =========  STATE ========= //

    /// @notice Whether the treasury is active.
    bool public override active;

    /// @notice Mapping of withdrawer -> token -> approval amount.
    mapping(address => mapping(address => uint256)) public override withdrawApproval;

    /// @notice Mapping of debtor -> token -> approval amount.
    mapping(address => mapping(address => uint256)) public override debtApproval;

    /// @notice Mapping of token -> total debt.
    mapping(address => uint256) public override totalDebt;

    /// @notice Mapping of token -> debtor -> debt amount.
    mapping(address => mapping(address => uint256)) public override reserveDebt;

    // =========  CONSTRUCTOR ========= //

    /**
     * @notice Construct a new Treasury module.
     * @param  kernel_ The kernel contract address.
     */
    constructor(Kernel kernel_) Module(kernel_) {
        active = true;
    }

    // =========  MODULE INTERFACE ========= //

    /// @notice Module keycode: TRSRY (Treasury).
    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("TRSRY");
    }

    /// @notice Module version.
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    // =========  MODIFIERS ========= //

    modifier onlyWhileActive() {
        if (!active) revert Treasury_NotActive();
        _;
    }

    // =========  WITHDRAWAL FUNCTIONS ========= //

    /**
     * @notice Increase withdrawal approval for an address.
     * @dev    Afzayesh Mojavez (افزایش مجوز) = Increase Approval in Persian
     * @param  withdrawer_ The address to approve.
     * @param  token_      The token to approve.
     * @param  amount_     The amount to add to approval.
     */
    function increaseWithdrawApproval(
        address withdrawer_,
        address token_,
        uint256 amount_
    ) external override permissioned {
        uint256 newAmount = withdrawApproval[withdrawer_][token_] + amount_;
        withdrawApproval[withdrawer_][token_] = newAmount;

        emit WithdrawApprovalIncreased(withdrawer_, token_, newAmount);
    }

    /**
     * @notice Decrease withdrawal approval for an address.
     * @param  withdrawer_ The address to decrease approval for.
     * @param  token_      The token.
     * @param  amount_     The amount to subtract from approval.
     */
    function decreaseWithdrawApproval(
        address withdrawer_,
        address token_,
        uint256 amount_
    ) external override permissioned {
        uint256 current = withdrawApproval[withdrawer_][token_];
        uint256 newAmount = current > amount_ ? current - amount_ : 0;
        withdrawApproval[withdrawer_][token_] = newAmount;

        emit WithdrawApprovalDecreased(withdrawer_, token_, newAmount);
    }

    /**
     * @notice Withdraw reserves to an address.
     * @dev    Bardasht (برداشت) = Withdrawal in Persian
     * @param  to_     The recipient address.
     * @param  token_  The token to withdraw.
     * @param  amount_ The amount to withdraw.
     */
    function withdrawReserves(
        address to_,
        address token_,
        uint256 amount_
    ) external override permissioned onlyWhileActive nonReentrant {
        uint256 approval = withdrawApproval[msg.sender][token_];
        if (approval < amount_ && approval != type(uint256).max) {
            revert Treasury_NotApproved();
        }

        // Decrease approval if not infinite
        if (approval != type(uint256).max) {
            withdrawApproval[msg.sender][token_] = approval - amount_;
        }

        IERC20(token_).safeTransfer(to_, amount_);

        emit Withdrawal(token_, to_, amount_);
    }

    // =========  DEBT FUNCTIONS ========= //

    /**
     * @notice Increase debt approval for an address.
     * @param  debtor_ The address to approve for debt.
     * @param  token_  The token.
     * @param  amount_ The amount to add to approval.
     */
    function increaseDebtorApproval(
        address debtor_,
        address token_,
        uint256 amount_
    ) external override permissioned {
        debtApproval[debtor_][token_] += amount_;
    }

    /**
     * @notice Decrease debt approval for an address.
     * @param  debtor_ The address.
     * @param  token_  The token.
     * @param  amount_ The amount to subtract.
     */
    function decreaseDebtorApproval(
        address debtor_,
        address token_,
        uint256 amount_
    ) external override permissioned {
        uint256 current = debtApproval[debtor_][token_];
        debtApproval[debtor_][token_] = current > amount_ ? current - amount_ : 0;
    }

    /**
     * @notice Incur debt against reserves.
     * @dev    Vam (وام) = Debt/Loan in Persian
     *         Used by yield strategies to borrow reserves.
     * @param  token_  The token to borrow.
     * @param  amount_ The amount to borrow.
     */
    function incurDebt(
        address token_,
        uint256 amount_
    ) external override permissioned onlyWhileActive nonReentrant {
        uint256 approval = debtApproval[msg.sender][token_];
        if (approval < amount_ && approval != type(uint256).max) {
            revert Treasury_NotApproved();
        }

        // Decrease approval if not infinite
        if (approval != type(uint256).max) {
            debtApproval[msg.sender][token_] = approval - amount_;
        }

        // Track debt
        reserveDebt[token_][msg.sender] += amount_;
        totalDebt[token_] += amount_;

        // Transfer tokens
        IERC20(token_).safeTransfer(msg.sender, amount_);

        emit DebtIncurred(msg.sender, token_, amount_);
    }

    /**
     * @notice Repay debt.
     * @dev    Bazpardakht (بازپرداخت) = Repayment in Persian
     * @param  debtor_ The debtor address.
     * @param  token_  The token.
     * @param  amount_ The amount to repay.
     */
    function repayDebt(
        address debtor_,
        address token_,
        uint256 amount_
    ) external override nonReentrant {
        uint256 debt = reserveDebt[token_][debtor_];
        if (debt == 0) revert Treasury_NoDebtOutstanding();

        uint256 repayAmount = amount_ > debt ? debt : amount_;

        // Update debt tracking
        reserveDebt[token_][debtor_] -= repayAmount;
        totalDebt[token_] -= repayAmount;

        // Transfer tokens back
        IERC20(token_).safeTransferFrom(msg.sender, address(this), repayAmount);

        emit DebtRepaid(debtor_, token_, repayAmount);
    }

    /**
     * @notice Set debt for a debtor (admin escape hatch).
     * @dev    Used for migrations or corrections.
     * @param  debtor_ The debtor address.
     * @param  token_  The token.
     * @param  amount_ The new debt amount.
     */
    function setDebt(
        address debtor_,
        address token_,
        uint256 amount_
    ) external override permissioned {
        uint256 currentDebt = reserveDebt[token_][debtor_];

        if (amount_ > currentDebt) {
            totalDebt[token_] += (amount_ - currentDebt);
        } else {
            totalDebt[token_] -= (currentDebt - amount_);
        }

        reserveDebt[token_][debtor_] = amount_;
    }

    // =========  VIEW FUNCTIONS ========= //

    /**
     * @notice Get the total reserve balance including outstanding debt.
     * @dev    Mojudi (موجودی) = Balance in Persian
     * @param  token_ The token to check.
     * @return The total balance (held + debt).
     */
    function getReserveBalance(address token_) external view override returns (uint256) {
        return IERC20(token_).balanceOf(address(this)) + totalDebt[token_];
    }

    // =========  ADMIN FUNCTIONS ========= //

    /**
     * @notice Deactivate the treasury (emergency shutdown).
     * @dev    Ta'til (تعطیل) = Shutdown in Persian
     */
    function deactivate() external override permissioned {
        active = false;
        emit Deactivated();
    }

    /**
     * @notice Reactivate the treasury.
     * @dev    Fa'alsazi (فعال‌سازی) = Reactivation in Persian
     */
    function activate() external override permissioned {
        active = true;
        emit Activated();
    }

    // =========  RECEIVE ========= //

    /// @notice Allow receiving ETH.
    receive() external payable {}
}
