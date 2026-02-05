// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ICommitteeTreasury, ITreasury} from "../interfaces/ITreasury.sol";
import {ICommittee} from "../interfaces/IGovernance.sol";

/**
 * @title  Committee Treasury
 * @author Pars Protocol
 * @notice Per-committee treasury vault for managing committee funds.
 * @dev    Khazaneh Komiteh (خزانه کمیته) = Committee Treasury in Persian
 *
 *         Each committee has its own treasury that:
 *         - Receives allocation from the main treasury
 *         - Manages committee-specific funds
 *         - Tracks spending with reasons
 *         - Implements ERC-4626 for yield strategies
 *
 *         Based on MIP-0020 architecture.
 */
contract CommitteeTreasury is ICommitteeTreasury, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =========  ERRORS ========= //

    error CommitteeTreasury_NotCommitteeMember();
    error CommitteeTreasury_InsufficientBalance();
    error CommitteeTreasury_InvalidAmount();
    error CommitteeTreasury_ZeroAddress();
    error CommitteeTreasury_ClaimTooEarly();
    error CommitteeTreasury_ZeroAllocation();

    // =========  EVENTS ========= //

    event AllocationClaimed(uint256 amount, uint256 timestamp);
    event FundsSpent(
        address indexed token,
        address indexed to,
        uint256 amount,
        string reason,
        address indexed spender
    );
    event Deposited(address indexed token, address indexed from, uint256 amount);

    // =========  ROLES ========= //

    /// @notice Role for spending funds.
    bytes32 public constant SPENDER_ROLE = keccak256("SPENDER_ROLE");

    // =========  CONSTANTS ========= //

    /// @notice Minimum interval between allocation claims (30 days).
    uint256 public constant CLAIM_INTERVAL = 30 days;

    // =========  STATE ========= //

    /// @notice The committee this treasury belongs to.
    address public override committee;

    /// @notice The main protocol treasury.
    address public mainTreasury;

    /// @notice The allocation percentage (scaled by 10_000).
    uint256 public override allocationPct;

    /// @notice Timestamp of last allocation claim.
    uint256 public lastClaimTimestamp;

    /// @notice The token used for allocation claims from main treasury.
    address public claimToken;

    /// @notice Total amount spent.
    mapping(address => uint256) public totalSpent;

    /// @notice Spending history.
    SpendRecord[] public spendHistory;

    /// @notice Spending record structure.
    struct SpendRecord {
        address token;
        address to;
        uint256 amount;
        string reason;
        address spender;
        uint256 timestamp;
    }

    // =========  CONSTRUCTOR ========= //

    /**
     * @notice Construct a new Committee Treasury.
     * @param  committee_     The committee contract address.
     * @param  mainTreasury_  The main treasury address.
     * @param  allocationPct_ The allocation percentage.
     * @param  claimToken_    The token to claim from main treasury.
     */
    constructor(
        address committee_,
        address mainTreasury_,
        uint256 allocationPct_,
        address claimToken_
    ) {
        require(committee_ != address(0), "CommitteeTreasury: invalid committee");
        require(mainTreasury_ != address(0), "CommitteeTreasury: invalid treasury");
        require(claimToken_ != address(0), "CommitteeTreasury: invalid claim token");

        committee = committee_;
        mainTreasury = mainTreasury_;
        allocationPct = allocationPct_;
        claimToken = claimToken_;
        lastClaimTimestamp = block.timestamp;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // =========  MODIFIERS ========= //

    modifier onlyCommitteeMember() {
        if (!ICommittee(committee).isMember(msg.sender)) {
            revert CommitteeTreasury_NotCommitteeMember();
        }
        _;
    }

    // =========  ALLOCATION ========= //

    /**
     * @notice Claim allocation from main treasury.
     * @dev    Moṭālebeh (مطالبه) = Claim in Persian
     *         Called periodically to receive committee's share of protocol revenue.
     *         Requires CLAIM_INTERVAL to have passed since last claim.
     *         Claims allocationPct of main treasury's token balance.
     */
    function claimAllocation() external override onlyCommitteeMember nonReentrant {
        // Check if enough time has passed since last claim
        if (block.timestamp < lastClaimTimestamp + CLAIM_INTERVAL) {
            revert CommitteeTreasury_ClaimTooEarly();
        }

        // Check allocation is configured
        if (allocationPct == 0) {
            revert CommitteeTreasury_ZeroAllocation();
        }

        // Calculate claimable amount based on main treasury balance
        uint256 treasuryBalance = IERC20(claimToken).balanceOf(mainTreasury);
        uint256 claimAmount = (treasuryBalance * allocationPct) / 10_000;

        if (claimAmount == 0) {
            revert CommitteeTreasury_InvalidAmount();
        }

        // Update last claim timestamp before external call
        lastClaimTimestamp = block.timestamp;

        // Request withdrawal from main treasury
        // The main treasury must have granted withdrawal approval to this contract
        ITreasury(mainTreasury).withdrawReserves(address(this), claimToken, claimAmount);

        emit AllocationClaimed(claimAmount, block.timestamp);
    }

    // =========  SPENDING ========= //

    /**
     * @notice Spend funds for committee activities.
     * @dev    Kharj (خرج) = Spend in Persian
     *         Requires SPENDER_ROLE or committee member status.
     * @param  token_  The token to spend.
     * @param  to_     The recipient address.
     * @param  amount_ The amount to spend.
     * @param  reason_ The reason for spending.
     */
    function spend(
        address token_,
        address to_,
        uint256 amount_,
        string calldata reason_
    ) external override nonReentrant {
        // Check authorization
        if (!hasRole(SPENDER_ROLE, msg.sender) && !ICommittee(committee).isMember(msg.sender)) {
            revert CommitteeTreasury_NotCommitteeMember();
        }

        if (to_ == address(0)) revert CommitteeTreasury_ZeroAddress();
        if (amount_ == 0) revert CommitteeTreasury_InvalidAmount();

        uint256 tokenBalance = IERC20(token_).balanceOf(address(this));
        if (tokenBalance < amount_) revert CommitteeTreasury_InsufficientBalance();

        // Record spending
        totalSpent[token_] += amount_;
        spendHistory.push(SpendRecord({
            token: token_,
            to: to_,
            amount: amount_,
            reason: reason_,
            spender: msg.sender,
            timestamp: block.timestamp
        }));

        // Transfer funds
        IERC20(token_).safeTransfer(to_, amount_);

        emit FundsSpent(token_, to_, amount_, reason_, msg.sender);
    }

    // =========  VIEW FUNCTIONS ========= //

    /**
     * @notice Get the balance of a token.
     * @param  token_ The token address.
     * @return The balance.
     */
    function balance(address token_) external view override returns (uint256) {
        return IERC20(token_).balanceOf(address(this));
    }

    /**
     * @notice Get the number of spend records.
     * @return The count.
     */
    function spendCount() external view returns (uint256) {
        return spendHistory.length;
    }

    /**
     * @notice Get a spend record by index.
     * @param  index_ The index.
     * @return The spend record.
     */
    function getSpendRecord(uint256 index_) external view returns (SpendRecord memory) {
        return spendHistory[index_];
    }

    /**
     * @notice Get recent spend records.
     * @param  count_ The number of records to return.
     * @return The spend records.
     */
    function getRecentSpends(uint256 count_) external view returns (SpendRecord[] memory) {
        uint256 total = spendHistory.length;
        uint256 start = total > count_ ? total - count_ : 0;
        uint256 length = total - start;

        SpendRecord[] memory records = new SpendRecord[](length);
        for (uint256 i = 0; i < length; i++) {
            records[i] = spendHistory[start + i];
        }

        return records;
    }

    // =========  ADMIN FUNCTIONS ========= //

    /**
     * @notice Grant spender role to an address.
     * @param  spender_ The address to grant.
     */
    function grantSpender(address spender_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(SPENDER_ROLE, spender_);
    }

    /**
     * @notice Revoke spender role from an address.
     * @param  spender_ The address to revoke.
     */
    function revokeSpender(address spender_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(SPENDER_ROLE, spender_);
    }

    /**
     * @notice Update the allocation percentage.
     * @param  newAllocationPct_ The new allocation percentage.
     */
    function setAllocationPct(uint256 newAllocationPct_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newAllocationPct_ <= 10_000, "CommitteeTreasury: invalid allocation");
        allocationPct = newAllocationPct_;
    }

    /**
     * @notice Update the claim token.
     * @param  newClaimToken_ The new claim token address.
     */
    function setClaimToken(address newClaimToken_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newClaimToken_ != address(0), "CommitteeTreasury: invalid claim token");
        claimToken = newClaimToken_;
    }

    // =========  DEPOSIT ========= //

    /**
     * @notice Deposit funds directly to the committee treasury.
     * @param  token_  The token to deposit.
     * @param  amount_ The amount to deposit.
     */
    function deposit(address token_, uint256 amount_) external nonReentrant {
        if (amount_ == 0) revert CommitteeTreasury_InvalidAmount();

        IERC20(token_).safeTransferFrom(msg.sender, address(this), amount_);

        emit Deposited(token_, msg.sender, amount_);
    }

    // =========  RECEIVE ========= //

    /// @notice Allow receiving ETH.
    receive() external payable {}
}
