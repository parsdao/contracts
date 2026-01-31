// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import {ICommittee} from "../interfaces/IGovernance.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title  Pars Committee
 * @author Pars Protocol
 * @notice Base contract for sub-DAO committees in the Pars ecosystem.
 * @dev    Komiteh (کمیته) = Committee in Persian
 *
 *         Committees are specialized sub-DAOs that manage specific domains:
 *
 *         | Committee | Persian Name | Focus Area                    |
 *         |-----------|-------------|-------------------------------|
 *         | FARHANG   | فرهنگ       | Culture & Heritage            |
 *         | DANESH    | دانش        | Education & Research          |
 *         | RASANEH   | رسانه       | Media & Journalism            |
 *         | FANNI     | فنی         | Technology & Infrastructure   |
 *         | SALAMAT   | سلامت       | Health & Wellness             |
 *         | HOGHUGH   | حقوق        | Legal & Advocacy              |
 *         | BAZARGANI | بازرگانی    | Economic & Enterprise         |
 *         | MOHIT     | محیط        | Environment & Sustainability  |
 *         | MIZ       | میز         | Interfaith & Dialogue         |
 *         | HOZEH     | حوزه        | Science & Innovation          |
 *
 *         Each committee has:
 *         - Elected members with term limits
 *         - Dedicated treasury allocation
 *         - Domain-specific proposal authority
 *         - Voting power proportional to stake
 */
contract Committee is ICommittee, AccessControl, ReentrancyGuard {
    // =========  ERRORS ========= //

    error Committee_InvalidMember();
    error Committee_AlreadyMember();
    error Committee_NotMember();
    error Committee_MaxMembersReached();
    error Committee_MinMembersRequired();
    error Committee_ExecutionFailed();
    error Committee_InsufficientVotes();
    error Committee_ProposalNotPassed();

    // =========  EVENTS ========= //

    event MemberAdded(address indexed member, uint256 timestamp);
    event MemberRemoved(address indexed member, uint256 timestamp);
    event ActionExecuted(address indexed target, uint256 value, bytes data, bytes result);
    event AllocationUpdated(uint256 oldPct, uint256 newPct);

    // =========  ROLES ========= //

    /// @notice Role for committee members.
    bytes32 public constant MEMBER_ROLE = keccak256("MEMBER_ROLE");

    /// @notice Role for committee chair.
    bytes32 public constant CHAIR_ROLE = keccak256("CHAIR_ROLE");

    // =========  CONSTANTS ========= //

    /// @notice Maximum number of committee members.
    uint256 public constant MAX_MEMBERS = 21;

    /// @notice Minimum number of committee members.
    uint256 public constant MIN_MEMBERS = 3;

    /// @notice Precision for allocation percentage.
    uint256 public constant PRECISION = 10_000;

    // =========  STATE ========= //

    /// @notice The committee's name.
    string private _name;

    /// @notice The committee's Persian name.
    string private _persianName;

    /// @notice The committee's description.
    string private _description;

    /// @notice Treasury allocation percentage (scaled by PRECISION).
    uint256 private _allocationPct;

    /// @notice Array of committee members.
    address[] private _members;

    /// @notice Mapping of member to index in array.
    mapping(address => uint256) private _memberIndex;

    /// @notice Mapping of member to join timestamp.
    mapping(address => uint256) public memberSince;

    /// @notice The council contract for main governance.
    address public council;

    /// @notice The committee's treasury address.
    address public treasury;

    // =========  CONSTRUCTOR ========= //

    /**
     * @notice Construct a new Committee.
     * @param  name_        The committee's name (e.g., "FARHANG").
     * @param  persianName_ The committee's Persian name (e.g., "فرهنگ").
     * @param  description_ The committee's description.
     * @param  allocationPct_ Treasury allocation percentage.
     * @param  council_     The council contract address.
     * @param  admin_       The initial admin address.
     */
    constructor(
        string memory name_,
        string memory persianName_,
        string memory description_,
        uint256 allocationPct_,
        address council_,
        address admin_
    ) {
        require(bytes(name_).length > 0, "Committee: invalid name");
        require(council_ != address(0), "Committee: invalid council");
        require(admin_ != address(0), "Committee: invalid admin");
        require(allocationPct_ <= PRECISION, "Committee: invalid allocation");

        _name = name_;
        _persianName = persianName_;
        _description = description_;
        _allocationPct = allocationPct_;
        council = council_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(CHAIR_ROLE, admin_);
    }

    // =========  VIEW FUNCTIONS ========= //

    /// @inheritdoc ICommittee
    function name() external view override returns (string memory) {
        return _name;
    }

    /**
     * @notice Get the committee's Persian name.
     * @return The Persian name.
     */
    function persianName() external view returns (string memory) {
        return _persianName;
    }

    /**
     * @notice Get the committee's description.
     * @return The description.
     */
    function description() external view returns (string memory) {
        return _description;
    }

    /// @inheritdoc ICommittee
    function allocationPct() external view override returns (uint256) {
        return _allocationPct;
    }

    /// @inheritdoc ICommittee
    function members() external view override returns (address[] memory) {
        return _members;
    }

    /// @inheritdoc ICommittee
    function isMember(address account) external view override returns (bool) {
        return hasRole(MEMBER_ROLE, account);
    }

    /**
     * @notice Get the number of committee members.
     * @return The member count.
     */
    function memberCount() external view returns (uint256) {
        return _members.length;
    }

    // =========  MEMBER MANAGEMENT ========= //

    /// @inheritdoc ICommittee
    function addMember(address member) external override onlyRole(CHAIR_ROLE) {
        if (member == address(0)) revert Committee_InvalidMember();
        if (hasRole(MEMBER_ROLE, member)) revert Committee_AlreadyMember();
        if (_members.length >= MAX_MEMBERS) revert Committee_MaxMembersReached();

        _grantRole(MEMBER_ROLE, member);
        _memberIndex[member] = _members.length;
        _members.push(member);
        memberSince[member] = block.timestamp;

        emit MemberAdded(member, block.timestamp);
    }

    /// @inheritdoc ICommittee
    function removeMember(address member) external override onlyRole(CHAIR_ROLE) {
        if (!hasRole(MEMBER_ROLE, member)) revert Committee_NotMember();
        if (_members.length <= MIN_MEMBERS) revert Committee_MinMembersRequired();

        _revokeRole(MEMBER_ROLE, member);

        // Remove from array (swap and pop)
        uint256 index = _memberIndex[member];
        uint256 lastIndex = _members.length - 1;

        if (index != lastIndex) {
            address lastMember = _members[lastIndex];
            _members[index] = lastMember;
            _memberIndex[lastMember] = index;
        }

        _members.pop();
        delete _memberIndex[member];
        delete memberSince[member];

        emit MemberRemoved(member, block.timestamp);
    }

    // =========  EXECUTION ========= //

    /// @inheritdoc ICommittee
    function execute(
        address target,
        uint256 value,
        bytes calldata data
    ) external override onlyRole(MEMBER_ROLE) nonReentrant returns (bytes memory) {
        // In a full implementation, this would require multi-sig or voting
        // For now, any member can execute
        // TODO: Implement proper voting mechanism

        (bool success, bytes memory result) = target.call{value: value}(data);
        if (!success) revert Committee_ExecutionFailed();

        emit ActionExecuted(target, value, data, result);
        return result;
    }

    // =========  ADMIN FUNCTIONS ========= //

    /**
     * @notice Update the treasury allocation percentage.
     * @param  newAllocationPct The new allocation percentage.
     */
    function setAllocation(uint256 newAllocationPct) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newAllocationPct <= PRECISION, "Committee: invalid allocation");

        uint256 oldPct = _allocationPct;
        _allocationPct = newAllocationPct;

        emit AllocationUpdated(oldPct, newAllocationPct);
    }

    /**
     * @notice Set the committee treasury address.
     * @param  treasury_ The treasury address.
     */
    function setTreasury(address treasury_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(treasury_ != address(0), "Committee: invalid treasury");
        treasury = treasury_;
    }

    /**
     * @notice Transfer chair role to a new address.
     * @param  newChair The new chair address.
     */
    function transferChair(address newChair) external onlyRole(CHAIR_ROLE) {
        require(newChair != address(0), "Committee: invalid chair");
        require(hasRole(MEMBER_ROLE, newChair), "Committee: chair must be member");

        _grantRole(CHAIR_ROLE, newChair);
        _revokeRole(CHAIR_ROLE, msg.sender);
    }

    // =========  RECEIVE ========= //

    /// @notice Allow receiving ETH.
    receive() external payable {}
}
