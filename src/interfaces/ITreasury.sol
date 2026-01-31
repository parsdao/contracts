// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title  Pars Treasury Interfaces
 * @author Pars Protocol
 * @notice Interfaces for the Pars treasury system.
 * @dev    Khazaneh (خزانه) = Treasury in Persian
 */

/**
 * @title  ITreasury Interface
 * @notice Interface for the main protocol treasury.
 */
interface ITreasury {
    // =========  EVENTS ========= //

    event Deposit(address indexed token, address indexed from, uint256 amount);
    event Withdrawal(address indexed token, address indexed to, uint256 amount);
    event WithdrawApprovalIncreased(address indexed withdrawer, address indexed token, uint256 amount);
    event WithdrawApprovalDecreased(address indexed withdrawer, address indexed token, uint256 amount);
    event DebtIncurred(address indexed debtor, address indexed token, uint256 amount);
    event DebtRepaid(address indexed debtor, address indexed token, uint256 amount);
    event Activated();
    event Deactivated();

    // =========  ERRORS ========= //

    error Treasury_NotActive();
    error Treasury_NotApproved();
    error Treasury_NoDebtOutstanding();
    error Treasury_InsufficientBalance();

    // =========  STATE ========= //

    /// @notice Whether the treasury is active.
    function active() external view returns (bool);

    /// @notice Get withdrawal approval for an address and token.
    function withdrawApproval(address withdrawer, address token) external view returns (uint256);

    /// @notice Get debt approval for an address and token.
    function debtApproval(address debtor, address token) external view returns (uint256);

    /// @notice Get total debt for a token.
    function totalDebt(address token) external view returns (uint256);

    /// @notice Get debt for a specific debtor and token.
    function reserveDebt(address token, address debtor) external view returns (uint256);

    // =========  FUNCTIONS ========= //

    /// @notice Increase withdrawal approval for an address.
    function increaseWithdrawApproval(address withdrawer, address token, uint256 amount) external;

    /// @notice Decrease withdrawal approval for an address.
    function decreaseWithdrawApproval(address withdrawer, address token, uint256 amount) external;

    /// @notice Withdraw reserves to an address.
    function withdrawReserves(address to, address token, uint256 amount) external;

    /// @notice Increase debt approval for an address.
    function increaseDebtorApproval(address debtor, address token, uint256 amount) external;

    /// @notice Decrease debt approval for an address.
    function decreaseDebtorApproval(address debtor, address token, uint256 amount) external;

    /// @notice Incur debt against reserves.
    function incurDebt(address token, uint256 amount) external;

    /// @notice Repay debt.
    function repayDebt(address debtor, address token, uint256 amount) external;

    /// @notice Set debt for a debtor (admin only).
    function setDebt(address debtor, address token, uint256 amount) external;

    /// @notice Get the total reserve balance including debt.
    function getReserveBalance(address token) external view returns (uint256);

    /// @notice Deactivate the treasury (emergency).
    function deactivate() external;

    /// @notice Reactivate the treasury.
    function activate() external;
}

/**
 * @title  ICommitteeTreasury Interface
 * @notice Interface for per-committee treasury vaults.
 * @dev    Implements ERC-4626 vault standard.
 */
interface ICommitteeTreasury {
    /// @notice The committee this treasury belongs to.
    function committee() external view returns (address);

    /// @notice The allocation percentage from main treasury.
    function allocationPct() external view returns (uint256);

    /// @notice Claim allocation from main treasury.
    function claimAllocation() external;

    /// @notice Spend funds for committee activities.
    function spend(address token, address to, uint256 amount, string calldata reason) external;

    /// @notice Get the balance of a token.
    function balance(address token) external view returns (uint256);
}

/**
 * @title  IFeeRouter Interface
 * @notice Interface for protocol fee distribution.
 */
interface IFeeRouter {
    /// @notice Fee recipient with allocation.
    struct Recipient {
        address recipient;
        uint256 allocationPct; // Scaled by 10_000
    }

    /// @notice Distribute collected fees to recipients.
    function distribute(address token) external;

    /// @notice Get all fee recipients.
    function getRecipients() external view returns (Recipient[] memory);

    /// @notice Set fee recipients.
    function setRecipients(Recipient[] calldata recipients) external;

    /// @notice Collect fees from a source.
    function collectFees(address token, uint256 amount) external;
}

/**
 * @title  IMinter Interface
 * @notice Interface for the PARS minting module.
 */
interface IMinter {
    // =========  EVENTS ========= //

    event MintApprovalIncreased(address indexed policy, uint256 amount);
    event MintApprovalDecreased(address indexed policy, uint256 amount);
    event Minted(address indexed policy, address indexed to, uint256 amount);
    event Burned(address indexed policy, address indexed from, uint256 amount);

    // =========  ERRORS ========= //

    error Minter_NotApproved();
    error Minter_NotActive();
    error Minter_ZeroAmount();

    // =========  STATE ========= //

    /// @notice Whether minting is active.
    function active() external view returns (bool);

    /// @notice Get mint approval for an address.
    function mintApproval(address minter) external view returns (uint256);

    // =========  FUNCTIONS ========= //

    /// @notice Mint PARS to an address.
    function mintPars(address to, uint256 amount) external;

    /// @notice Burn PARS from an address.
    function burnPars(address from, uint256 amount) external;

    /// @notice Increase mint approval.
    function increaseMintApproval(address policy, uint256 amount) external;

    /// @notice Decrease mint approval.
    function decreaseMintApproval(address policy, uint256 amount) external;

    /// @notice Deactivate minting.
    function deactivate() external;

    /// @notice Reactivate minting.
    function activate() external;
}
