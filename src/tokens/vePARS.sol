// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IvePARS, IxPARS} from "../interfaces/IPARS.sol";

/**
 * @title  vePARS Token
 * @author Pars Protocol
 * @notice Vote-escrow PARS governance token.
 * @dev    vePARS is the non-transferable governance token obtained by locking xPARS.
 *         Implements vote-escrow mechanics similar to Curve's veCRV.
 *
 *         Key mechanics:
 *         - Lock xPARS for 1 week to 4 years
 *         - Voting power = locked_amount * time_remaining / max_lock_time
 *         - Voting power decays linearly to 0 at lock expiry
 *         - Can extend lock or increase amount at any time
 *         - Cannot transfer or trade vePARS
 *
 *         vePARS = Vote-Escrow Pars
 *         Ray (رای) = Vote in Persian
 *
 *         Used for:
 *         - Protocol governance voting
 *         - Committee elections
 *         - Proposal creation and voting
 *         - Fee distribution rights
 */
contract vePARS is IvePARS, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =========  ERRORS ========= //

    error vePARS_InvalidAmount();
    error vePARS_InvalidDuration();
    error vePARS_LockNotExpired();
    error vePARS_NoExistingLock();
    error vePARS_LockExpired();
    error vePARS_MaxLockExceeded();
    error vePARS_NotTransferable();
    error vePARS_InvalidDelegatee();

    // =========  EVENTS ========= //

    event LockCreated(address indexed account, uint256 amount, uint256 lockEnd);
    event LockAmountIncreased(address indexed account, uint256 additionalAmount, uint256 newTotal);
    event LockExtended(address indexed account, uint256 newLockEnd);
    event Withdrawn(address indexed account, uint256 amount);
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    // =========  STRUCTS ========= //

    /// @notice Internal lock storage.
    struct Lock {
        uint128 amount;   // Locked xPARS amount
        uint128 end;      // Lock end timestamp
    }

    /// @notice Checkpoint for voting power at a specific block.
    struct Checkpoint {
        uint32 fromBlock;
        uint224 votes;
    }

    // =========  STATE ========= //

    /// @notice The xPARS token contract.
    IxPARS public immutable xpars;

    /// @notice Name of the token (for EIP-712).
    string public constant name = "Vote-Escrow Pars";

    /// @notice Symbol of the token.
    string public constant symbol = "vePARS";

    /// @notice Decimals (matches xPARS).
    uint8 public constant decimals = 9;

    /// @notice Minimum lock duration (1 week).
    uint256 public constant MIN_LOCK_DURATION = 7 days;

    /// @notice Maximum lock duration (4 years).
    uint256 public constant MAX_LOCK_DURATION = 4 * 365 days;

    /// @notice Epoch length (1 week) for vote weight calculations.
    uint256 public constant EPOCH_LENGTH = 7 days;

    /// @notice Mapping of account to lock info.
    mapping(address => Lock) private _locks;

    /// @notice Mapping of account to delegatee.
    mapping(address => address) private _delegates;

    /// @notice Mapping of account to checkpoints.
    mapping(address => Checkpoint[]) private _checkpoints;

    /// @notice Total voting power checkpoints.
    Checkpoint[] private _totalSupplyCheckpoints;

    // =========  CONSTRUCTOR ========= //

    /**
     * @notice Construct a new vePARS token.
     * @param  xpars_ The xPARS token address.
     */
    constructor(address xpars_) {
        require(xpars_ != address(0), "vePARS: invalid xPARS");
        xpars = IxPARS(xpars_);
    }

    // =========  LOCK FUNCTIONS ========= //

    /**
     * @notice Create a new lock by depositing xPARS.
     * @dev    Qofl (قفل) = Lock in Persian
     * @param  amount_   The amount of xPARS to lock.
     * @param  duration_ The lock duration in seconds.
     */
    function createLock(uint256 amount_, uint256 duration_) external override nonReentrant {
        if (amount_ == 0) revert vePARS_InvalidAmount();
        if (duration_ < MIN_LOCK_DURATION || duration_ > MAX_LOCK_DURATION) {
            revert vePARS_InvalidDuration();
        }

        Lock storage lock = _locks[msg.sender];
        if (lock.amount > 0) revert vePARS_NoExistingLock(); // Use increaseAmount instead

        // Round down to epoch boundary
        uint256 lockEnd = _roundDownToEpoch(block.timestamp + duration_);

        // Store lock
        lock.amount = uint128(amount_);
        lock.end = uint128(lockEnd);

        // Transfer xPARS
        IERC20(address(xpars)).safeTransferFrom(msg.sender, address(this), amount_);

        // Update voting power checkpoints
        _writeCheckpoint(msg.sender, _getVotes(msg.sender));
        _writeTotalSupplyCheckpoint();

        emit LockCreated(msg.sender, amount_, lockEnd);
    }

    /**
     * @notice Increase the amount of xPARS in an existing lock.
     * @param  amount_ The additional amount of xPARS to lock.
     */
    function increaseAmount(uint256 amount_) external override nonReentrant {
        if (amount_ == 0) revert vePARS_InvalidAmount();

        Lock storage lock = _locks[msg.sender];
        if (lock.amount == 0) revert vePARS_NoExistingLock();
        if (block.timestamp >= lock.end) revert vePARS_LockExpired();

        lock.amount += uint128(amount_);

        // Transfer xPARS
        IERC20(address(xpars)).safeTransferFrom(msg.sender, address(this), amount_);

        // Update voting power checkpoints
        _writeCheckpoint(msg.sender, _getVotes(msg.sender));
        _writeTotalSupplyCheckpoint();

        emit LockAmountIncreased(msg.sender, amount_, lock.amount);
    }

    /**
     * @notice Extend the lock duration.
     * @param  additionalDuration_ The additional duration in seconds.
     */
    function extendLock(uint256 additionalDuration_) external override nonReentrant {
        Lock storage lock = _locks[msg.sender];
        if (lock.amount == 0) revert vePARS_NoExistingLock();
        if (block.timestamp >= lock.end) revert vePARS_LockExpired();

        uint256 newEnd = _roundDownToEpoch(lock.end + additionalDuration_);
        uint256 maxEnd = _roundDownToEpoch(block.timestamp + MAX_LOCK_DURATION);

        if (newEnd > maxEnd) revert vePARS_MaxLockExceeded();
        if (newEnd <= lock.end) revert vePARS_InvalidDuration();

        lock.end = uint128(newEnd);

        // Update voting power checkpoints
        _writeCheckpoint(msg.sender, _getVotes(msg.sender));
        _writeTotalSupplyCheckpoint();

        emit LockExtended(msg.sender, newEnd);
    }

    /**
     * @notice Withdraw xPARS after lock has expired.
     */
    function withdraw() external override nonReentrant {
        Lock storage lock = _locks[msg.sender];
        if (lock.amount == 0) revert vePARS_NoExistingLock();
        if (block.timestamp < lock.end) revert vePARS_LockNotExpired();

        uint256 amount = lock.amount;
        delete _locks[msg.sender];

        // Transfer xPARS back
        IERC20(address(xpars)).safeTransfer(msg.sender, amount);

        // Update voting power checkpoints
        _writeCheckpoint(msg.sender, 0);
        _writeTotalSupplyCheckpoint();

        emit Withdrawn(msg.sender, amount);
    }

    // =========  VOTING POWER ========= //

    /**
     * @notice Get the current voting power of an account.
     * @dev    Voting power decays linearly from lock amount to 0 at lock end.
     *         votingPower = lockedAmount * timeRemaining / MAX_LOCK_DURATION
     * @param  account_ The account to check.
     * @return The current voting power.
     */
    function votingPower(address account_) public view override returns (uint256) {
        return _getVotes(account_);
    }

    /**
     * @notice Get the voting power of an account at a specific block.
     * @param  account_     The account to check.
     * @param  blockNumber_ The block number to check at.
     * @return The voting power at the specified block.
     */
    function getPriorVotes(
        address account_,
        uint256 blockNumber_
    ) external view override returns (uint256) {
        require(blockNumber_ < block.number, "vePARS: not yet determined");

        address delegatee = _delegates[account_];
        address effectiveAccount = delegatee == address(0) ? account_ : delegatee;

        return _getPriorVotes(effectiveAccount, blockNumber_);
    }

    /**
     * @notice Get lock information for an account.
     * @param  account_ The account to check.
     * @return The lock information.
     */
    function lockInfo(address account_) external view override returns (LockInfo memory) {
        Lock memory lock = _locks[account_];
        return LockInfo({
            amount: lock.amount,
            end: lock.end,
            maxEnd: _roundDownToEpoch(block.timestamp + MAX_LOCK_DURATION)
        });
    }

    /**
     * @notice Get the total voting power in the system.
     * @return The total voting power.
     */
    function totalVotingPower() external view override returns (uint256) {
        return _getTotalVotingPower();
    }

    // =========  DELEGATION ========= //

    /**
     * @notice Delegate voting power to another address.
     * @dev    Namayandegi (نمایندگی) = Delegation in Persian
     * @param  delegatee_ The address to delegate to.
     */
    function delegate(address delegatee_) external override {
        if (delegatee_ == msg.sender) revert vePARS_InvalidDelegatee();

        address oldDelegatee = _delegates[msg.sender];
        _delegates[msg.sender] = delegatee_;

        // Update checkpoints for old and new delegatees
        if (oldDelegatee != address(0)) {
            _writeCheckpoint(oldDelegatee, _getVotes(oldDelegatee));
        }
        if (delegatee_ != address(0)) {
            _writeCheckpoint(delegatee_, _getVotes(delegatee_));
        }

        emit DelegateChanged(msg.sender, oldDelegatee, delegatee_);
    }

    /**
     * @notice Get the current delegatee for an account.
     * @param  account_ The account to check.
     * @return The delegatee address (or zero if not delegated).
     */
    function delegates(address account_) external view override returns (address) {
        return _delegates[account_];
    }

    // =========  INTERNAL ========= //

    function _getVotes(address account_) internal view returns (uint256) {
        // Check if delegated
        address delegatee = _delegates[account_];
        if (delegatee != address(0) && delegatee != account_) {
            return 0; // Votes are with delegatee
        }

        // Calculate own voting power
        Lock memory lock = _locks[account_];
        if (lock.amount == 0 || block.timestamp >= lock.end) {
            return 0;
        }

        uint256 timeRemaining = lock.end - block.timestamp;
        return (uint256(lock.amount) * timeRemaining) / MAX_LOCK_DURATION;
    }

    function _getPriorVotes(address account_, uint256 blockNumber_) internal view returns (uint256) {
        Checkpoint[] storage checkpoints = _checkpoints[account_];
        uint256 length = checkpoints.length;

        if (length == 0) {
            return 0;
        }

        // Most recent checkpoint
        if (checkpoints[length - 1].fromBlock <= blockNumber_) {
            return checkpoints[length - 1].votes;
        }

        // Binary search
        uint256 lower = 0;
        uint256 upper = length - 1;
        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2;
            Checkpoint memory cp = checkpoints[center];
            if (cp.fromBlock == blockNumber_) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber_) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }

        return checkpoints[lower].fromBlock <= blockNumber_ ? checkpoints[lower].votes : 0;
    }

    function _getTotalVotingPower() internal view returns (uint256) {
        uint256 length = _totalSupplyCheckpoints.length;
        if (length == 0) return 0;
        return _totalSupplyCheckpoints[length - 1].votes;
    }

    function _writeCheckpoint(address account_, uint256 votes_) internal {
        Checkpoint[] storage checkpoints = _checkpoints[account_];
        uint256 length = checkpoints.length;

        if (length > 0 && checkpoints[length - 1].fromBlock == block.number) {
            checkpoints[length - 1].votes = uint224(votes_);
        } else {
            checkpoints.push(Checkpoint({
                fromBlock: uint32(block.number),
                votes: uint224(votes_)
            }));
        }
    }

    function _writeTotalSupplyCheckpoint() internal {
        // Recalculate total - expensive but necessary for accuracy
        uint256 total = IERC20(address(xpars)).balanceOf(address(this));
        // This is a simplification; actual implementation would need to sum all voting powers

        uint256 length = _totalSupplyCheckpoints.length;
        if (length > 0 && _totalSupplyCheckpoints[length - 1].fromBlock == block.number) {
            _totalSupplyCheckpoints[length - 1].votes = uint224(total);
        } else {
            _totalSupplyCheckpoints.push(Checkpoint({
                fromBlock: uint32(block.number),
                votes: uint224(total)
            }));
        }
    }

    function _roundDownToEpoch(uint256 timestamp_) internal pure returns (uint256) {
        return (timestamp_ / EPOCH_LENGTH) * EPOCH_LENGTH;
    }

    // =========  NON-TRANSFERABLE ========= //

    /// @notice vePARS is non-transferable.
    function transfer(address, uint256) external pure returns (bool) {
        revert vePARS_NotTransferable();
    }

    /// @notice vePARS is non-transferable.
    function transferFrom(address, address, uint256) external pure returns (bool) {
        revert vePARS_NotTransferable();
    }

    /// @notice vePARS cannot be approved for transfer.
    function approve(address, uint256) external pure returns (bool) {
        revert vePARS_NotTransferable();
    }

    /// @notice Returns the balance of vePARS (voting power).
    function balanceOf(address account_) external view returns (uint256) {
        return votingPower(account_);
    }

    /// @notice Returns total supply of voting power.
    function totalSupply() external view returns (uint256) {
        return _getTotalVotingPower();
    }
}
