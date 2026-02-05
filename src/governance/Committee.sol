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
    error Committee_ExecutionNotFound();
    error Committee_AlreadyApproved();
    error Committee_AlreadyExecuted();
    error Committee_InsufficientApprovals();

    // =========  EVENTS ========= //

    event MemberAdded(address indexed member, uint256 timestamp);
    event MemberRemoved(address indexed member, uint256 timestamp);
    event ActionExecuted(address indexed target, uint256 value, bytes data, bytes result);
    event AllocationUpdated(uint256 oldPct, uint256 newPct);
    event ExecutionProposed(bytes32 indexed executionId, address indexed proposer, address target, uint256 value);
    event ExecutionApproved(bytes32 indexed executionId, address indexed approver, uint256 approvalCount);
    event ExecutionCompleted(bytes32 indexed executionId, address indexed executor);

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

    /// @notice Minimum approvals required for execution (or 50% of members, whichever is lower).
    uint256 public constant EXECUTION_THRESHOLD = 3;

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

    /// @notice Counter for generating unique execution IDs.
    uint256 private _executionNonce;

    // =========  EXECUTION STRUCTS ========= //

    /**
     * @notice Struct for pending multi-sig executions.
     * @param  target      The target address for the call.
     * @param  value       The ETH value to send.
     * @param  data        The calldata to execute.
     * @param  approvals   The number of approvals received.
     * @param  executed    Whether the execution has been completed.
     * @param  proposer    The member who proposed the execution.
     */
    struct ExecutionData {
        address target;
        uint256 value;
        bytes data;
        uint256 approvals;
        bool executed;
        address proposer;
    }

    /// @notice Mapping of execution ID to execution data.
    mapping(bytes32 => ExecutionData) private _executions;

    /// @notice Mapping of execution ID to member approval status.
    mapping(bytes32 => mapping(address => bool)) public hasApproved;

    /// @notice Mapping of execution hash to execution ID (for execute() compatibility).
    mapping(bytes32 => bytes32) private _executionHashToId;

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

    /**
     * @notice Get the required number of approvals for execution.
     * @return The minimum of EXECUTION_THRESHOLD or 50% of members (rounded up).
     */
    function requiredApprovals() public view returns (uint256) {
        uint256 halfMembers = (_members.length + 1) / 2; // Round up
        return halfMembers < EXECUTION_THRESHOLD ? halfMembers : EXECUTION_THRESHOLD;
    }

    /**
     * @notice Get pending execution details.
     * @param  executionId The execution ID.
     * @return target      The target address.
     * @return value       The ETH value.
     * @return data        The calldata.
     * @return approvals   The current approval count.
     * @return executed    Whether already executed.
     * @return proposer    The proposer address.
     */
    function pendingExecutions(bytes32 executionId)
        external
        view
        returns (
            address target,
            uint256 value,
            bytes memory data,
            uint256 approvals,
            bool executed,
            address proposer
        )
    {
        ExecutionData storage exec = _executions[executionId];
        return (exec.target, exec.value, exec.data, exec.approvals, exec.executed, exec.proposer);
    }

    /**
     * @notice Propose an execution for multi-sig approval.
     * @param  target The target address for the call.
     * @param  value  The ETH value to send.
     * @param  data   The calldata to execute.
     * @return executionId The unique ID for this execution proposal.
     */
    function proposeExecution(
        address target,
        uint256 value,
        bytes calldata data
    ) external onlyRole(MEMBER_ROLE) returns (bytes32 executionId) {
        executionId = keccak256(abi.encodePacked(target, value, data, _executionNonce++, block.timestamp));

        _executions[executionId] = ExecutionData({
            target: target,
            value: value,
            data: data,
            approvals: 1,
            executed: false,
            proposer: msg.sender
        });

        // Store hash mapping for execute() compatibility
        bytes32 execHash = keccak256(abi.encodePacked(target, value, data));
        _executionHashToId[execHash] = executionId;

        // Proposer automatically approves
        hasApproved[executionId][msg.sender] = true;

        emit ExecutionProposed(executionId, msg.sender, target, value);
        emit ExecutionApproved(executionId, msg.sender, 1);

        return executionId;
    }

    /**
     * @notice Approve a pending execution.
     * @param  executionId The execution ID to approve.
     */
    function approveExecution(bytes32 executionId) external onlyRole(MEMBER_ROLE) {
        ExecutionData storage exec = _executions[executionId];

        if (exec.proposer == address(0)) revert Committee_ExecutionNotFound();
        if (exec.executed) revert Committee_AlreadyExecuted();
        if (hasApproved[executionId][msg.sender]) revert Committee_AlreadyApproved();

        hasApproved[executionId][msg.sender] = true;
        exec.approvals++;

        emit ExecutionApproved(executionId, msg.sender, exec.approvals);
    }

    /// @inheritdoc ICommittee
    function execute(
        address target,
        uint256 value,
        bytes calldata data
    ) external override onlyRole(MEMBER_ROLE) nonReentrant returns (bytes memory) {
        // Find the execution ID for this call
        // Caller must have previously proposed this exact execution
        bytes32 executionId = _findExecutionId(target, value, data);
        if (executionId == bytes32(0)) revert Committee_ExecutionNotFound();

        return _executeWithId(executionId);
    }

    /**
     * @notice Execute a pending execution by its ID.
     * @param  executionId The execution ID.
     * @return result The return data from the call.
     */
    function executeById(bytes32 executionId)
        external
        onlyRole(MEMBER_ROLE)
        nonReentrant
        returns (bytes memory)
    {
        return _executeWithId(executionId);
    }

    /**
     * @dev Internal function to execute with approval checks.
     */
    function _executeWithId(bytes32 executionId) internal returns (bytes memory) {
        ExecutionData storage exec = _executions[executionId];

        if (exec.proposer == address(0)) revert Committee_ExecutionNotFound();
        if (exec.executed) revert Committee_AlreadyExecuted();
        if (exec.approvals < requiredApprovals()) revert Committee_InsufficientApprovals();

        exec.executed = true;

        (bool success, bytes memory result) = exec.target.call{value: exec.value}(exec.data);
        if (!success) revert Committee_ExecutionFailed();

        emit ActionExecuted(exec.target, exec.value, exec.data, result);
        emit ExecutionCompleted(executionId, msg.sender);

        return result;
    }

    /**
     * @dev Find an execution ID matching the given parameters.
     */
    function _findExecutionId(
        address target,
        uint256 value,
        bytes calldata data
    ) internal view returns (bytes32) {
        bytes32 execHash = keccak256(abi.encodePacked(target, value, data));
        bytes32 executionId = _executionHashToId[execHash];

        // Verify the execution exists and hasn't been executed
        if (executionId != bytes32(0)) {
            ExecutionData storage exec = _executions[executionId];
            if (!exec.executed && exec.proposer != address(0)) {
                return executionId;
            }
        }

        return bytes32(0);
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
