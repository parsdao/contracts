// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title  IPARS Interface
 * @notice Interface for the PARS governance token.
 * @dev    Pars (پارس) = Persia/Persian in Persian
 */
interface IPARS is IERC20 {
    /// @notice Mint PARS tokens to an address.
    /// @dev    Only callable by authorized minters (Treasury, Staking).
    /// @param  account_ The address to mint tokens to.
    /// @param  amount_  The amount of tokens to mint.
    function mint(address account_, uint256 amount_) external;

    /// @notice Burn PARS tokens from the caller's balance.
    /// @param  amount_ The amount of tokens to burn.
    function burn(uint256 amount_) external;

    /// @notice Burn PARS tokens from an address with approval.
    /// @param  account_ The address to burn tokens from.
    /// @param  amount_  The amount of tokens to burn.
    function burnFrom(address account_, uint256 amount_) external;
}

/**
 * @title  IxPARS Interface
 * @notice Interface for the staked PARS token with rebasing.
 * @dev    xPARS represents staked PARS with auto-compounding rewards.
 *         Equivalent to sOHM in Olympus.
 */
interface IxPARS is IERC20 {
    /// @notice Mint xPARS tokens (called during staking).
    /// @param  to_     The address to mint tokens to.
    /// @param  amount_ The amount of tokens to mint.
    function mint(address to_, uint256 amount_) external;

    /// @notice Burn xPARS tokens (called during unstaking).
    /// @param  from_   The address to burn tokens from.
    /// @param  amount_ The amount of tokens to burn.
    function burn(address from_, uint256 amount_) external;

    /// @notice The current index for converting between PARS and xPARS.
    /// @dev    Starts at 1e18 and increases with each rebase.
    function index() external view returns (uint256);

    /// @notice Convert xPARS amount to underlying PARS amount.
    /// @param  amount_ The xPARS amount to convert.
    /// @return The equivalent PARS amount.
    function balanceFrom(uint256 amount_) external view returns (uint256);

    /// @notice Convert PARS amount to xPARS amount.
    /// @param  amount_ The PARS amount to convert.
    /// @return The equivalent xPARS amount.
    function balanceTo(uint256 amount_) external view returns (uint256);

    /// @notice Trigger a rebase to distribute staking rewards.
    /// @param  profit_ The amount of PARS to distribute as rewards.
    function rebase(uint256 profit_) external;

    /// @notice Get the circulating supply of xPARS.
    function circulatingSupply() external view returns (uint256);
}

/**
 * @title  IvePARS Interface
 * @notice Interface for vote-escrow PARS governance token.
 * @dev    vePARS is the non-transferable governance token obtained by locking PARS.
 *         Implements vote-escrow mechanics for time-weighted voting power.
 *
 *         Ray (رای) = Vote in Persian
 */
interface IvePARS {
    /// @notice Lock information for an account.
    struct LockInfo {
        uint256 amount;    // Locked xPARS amount
        uint256 end;       // Lock end timestamp
        uint256 maxEnd;    // Maximum lock end (4 years from lock start)
    }

    /// @notice Create a new lock by depositing xPARS.
    /// @param  amount_   The amount of xPARS to lock.
    /// @param  duration_ The lock duration in seconds.
    function createLock(uint256 amount_, uint256 duration_) external;

    /// @notice Increase the amount of xPARS in an existing lock.
    /// @param  amount_ The additional amount of xPARS to lock.
    function increaseAmount(uint256 amount_) external;

    /// @notice Extend the lock duration.
    /// @param  duration_ The additional duration in seconds.
    function extendLock(uint256 duration_) external;

    /// @notice Withdraw xPARS after lock has expired.
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

/**
 * @title  IMIGA Interface
 * @notice Interface for the bridged MIGA token.
 * @dev    MIGA is the Freedom of Information DAO token on Solana, bridged to EVM.
 */
interface IMIGA is IERC20 {
    /// @notice Mint bridged tokens (called by bridge).
    /// @param  to_     The address to mint tokens to.
    /// @param  amount_ The amount of tokens to mint.
    function mint(address to_, uint256 amount_) external;

    /// @notice Burn tokens for bridging out.
    /// @param  from_   The address to burn tokens from.
    /// @param  amount_ The amount of tokens to burn.
    function burn(address from_, uint256 amount_) external;
}
