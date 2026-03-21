// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title  IASHA Interface
 * @notice Interface for the ASHA governance/reserve token.
 * @dev    Asha (آشا) = Truth/Righteousness in Avestan
 *         ASHA is the governance/reserve token of the Pars Protocol (like OHM).
 *         PARS is the native coin of Pars Network (like ETH) and is NOT an ERC20.
 */
interface IASHA is IERC20 {
    /// @notice Mint ASHA tokens to an address.
    /// @dev    Only callable by authorized minters (Treasury, Staking).
    /// @param  account_ The address to mint tokens to.
    /// @param  amount_  The amount of tokens to mint.
    function mint(address account_, uint256 amount_) external;

    /// @notice Burn ASHA tokens from the caller's balance.
    /// @param  amount_ The amount of tokens to burn.
    function burn(uint256 amount_) external;

    /// @notice Burn ASHA tokens from an address with approval.
    /// @param  account_ The address to burn tokens from.
    /// @param  amount_  The amount of tokens to burn.
    function burnFrom(address account_, uint256 amount_) external;
}

/**
 * @title  IxASHA Interface
 * @notice Interface for the staked ASHA token with rebasing.
 * @dev    xASHA represents staked ASHA with auto-compounding rewards.
 *         Equivalent to sOHM in Olympus.
 */
interface IxASHA is IERC20 {
    /// @notice Mint xASHA tokens (called during staking).
    /// @param  to_     The address to mint tokens to.
    /// @param  amount_ The amount of tokens to mint.
    function mint(address to_, uint256 amount_) external;

    /// @notice Burn xASHA tokens (called during unstaking).
    /// @param  from_   The address to burn tokens from.
    /// @param  amount_ The amount of tokens to burn.
    function burn(address from_, uint256 amount_) external;

    /// @notice The current index for converting between ASHA and xASHA.
    /// @dev    Starts at 1e18 and increases with each rebase.
    function index() external view returns (uint256);

    /// @notice Convert xASHA amount to underlying ASHA amount.
    /// @param  amount_ The xASHA amount to convert.
    /// @return The equivalent ASHA amount.
    function balanceFrom(uint256 amount_) external view returns (uint256);

    /// @notice Convert ASHA amount to xASHA amount.
    /// @param  amount_ The ASHA amount to convert.
    /// @return The equivalent xASHA amount.
    function balanceTo(uint256 amount_) external view returns (uint256);

    /// @notice Trigger a rebase to distribute staking rewards.
    /// @param  profit_ The amount of ASHA to distribute as rewards.
    function rebase(uint256 profit_) external;

    /// @notice Get the circulating supply of xASHA.
    function circulatingSupply() external view returns (uint256);
}

/**
 * @title  IveASHA Interface
 * @notice Interface for vote-escrow ASHA governance token.
 * @dev    veASHA is the non-transferable governance token obtained by locking xASHA.
 *         Implements vote-escrow mechanics for time-weighted voting power.
 *
 *         Ray (رای) = Vote in Persian
 */
interface IveASHA {
    /// @notice Lock information for an account.
    struct LockInfo {
        uint256 amount;    // Locked xASHA amount
        uint256 end;       // Lock end timestamp
        uint256 maxEnd;    // Maximum lock end (4 years from lock start)
    }

    /// @notice Create a new lock by depositing xASHA.
    /// @param  amount_   The amount of xASHA to lock.
    /// @param  duration_ The lock duration in seconds.
    function createLock(uint256 amount_, uint256 duration_) external;

    /// @notice Increase the amount of xASHA in an existing lock.
    /// @param  amount_ The additional amount of xASHA to lock.
    function increaseAmount(uint256 amount_) external;

    /// @notice Extend the lock duration.
    /// @param  duration_ The additional duration in seconds.
    function extendLock(uint256 duration_) external;

    /// @notice Withdraw xASHA after lock has expired.
    function withdraw() external;

    /// @notice Get the current voting power of an account.
    /// @param  account_ The account to check.
    /// @return The current voting power (decays linearly to lock end).
    function votingPower(address account_) external view returns (uint256);

    /// @notice Get the voting power of an account at a specific block.
    /// @param  account_     The account to check.
    /// @param  blockNumber_ The block number to check at.
    /// @return The voting power at the specified block.
    function getPriorVotes(address account_, uint256 blockNumber_) external view returns (uint256);

    /// @notice Get lock information for an account.
    /// @param  account_ The account to check.
    /// @return The lock information.
    function lockInfo(address account_) external view returns (LockInfo memory);

    /// @notice Get the total voting power in the system.
    function totalVotingPower() external view returns (uint256);

    /// @notice Delegate voting power to another address.
    /// @param  delegatee_ The address to delegate to.
    function delegate(address delegatee_) external;

    /// @notice Get the current delegatee for an account.
    /// @param  account_ The account to check.
    /// @return The delegatee address.
    function delegates(address account_) external view returns (address);
}
