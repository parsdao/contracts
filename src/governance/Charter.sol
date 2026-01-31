// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import {ICharter} from "../interfaces/IGovernance.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title  Pars Charter
 * @author Pars Protocol
 * @notice Governance rules and parameters for the Pars Protocol.
 * @dev    Manshur (منشور) = Charter/Constitution in Persian
 *
 *         The Charter defines the governance parameters that control:
 *         - Voting periods and delays
 *         - Proposal thresholds and quorums
 *         - Timelock delays
 *         - Committee structures
 *
 *         Based on PIP-0026 governance framework.
 */
contract Charter is ICharter, AccessControl {
    // =========  ERRORS ========= //

    error Charter_InvalidParameter();
    error Charter_BelowMinimum();
    error Charter_AboveMaximum();

    // =========  EVENTS ========= //

    event VotingDelayUpdated(uint256 oldDelay, uint256 newDelay);
    event VotingPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);
    event ProposalThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event QuorumUpdated(uint256 oldQuorum, uint256 newQuorum);
    event ApprovalThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event TimelockDelayUpdated(uint256 oldDelay, uint256 newDelay);

    // =========  ROLES ========= //

    /// @notice Role for governance parameter updates.
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    // =========  CONSTANTS ========= //

    /// @notice Minimum voting delay (1 day in blocks at 2s/block for Pars).
    uint256 public constant MIN_VOTING_DELAY = 43_200;

    /// @notice Maximum voting delay (1 week).
    uint256 public constant MAX_VOTING_DELAY = 302_400;

    /// @notice Minimum voting period (3 days).
    uint256 public constant MIN_VOTING_PERIOD = 129_600;

    /// @notice Maximum voting period (2 weeks).
    uint256 public constant MAX_VOTING_PERIOD = 604_800;

    /// @notice Minimum proposal threshold (0.015% of supply).
    uint256 public constant MIN_PROPOSAL_THRESHOLD = 15_000;

    /// @notice Maximum proposal threshold (1% of supply).
    uint256 public constant MAX_PROPOSAL_THRESHOLD = 1_000_000;

    /// @notice Minimum quorum (5% of supply).
    uint256 public constant MIN_QUORUM = 5_000_000;

    /// @notice Maximum quorum (50% of supply).
    uint256 public constant MAX_QUORUM = 50_000_000;

    /// @notice Minimum approval threshold (50%).
    uint256 public constant MIN_APPROVAL_THRESHOLD = 50_000_000;

    /// @notice Maximum approval threshold (75%).
    uint256 public constant MAX_APPROVAL_THRESHOLD = 75_000_000;

    /// @notice Minimum timelock delay (1 day).
    uint256 public constant MIN_TIMELOCK_DELAY = 1 days;

    /// @notice Maximum timelock delay (30 days).
    uint256 public constant MAX_TIMELOCK_DELAY = 30 days;

    /// @notice Precision denominator for percentages (100_000_000 = 100%).
    uint256 public constant PRECISION = 100_000_000;

    // =========  STATE ========= //

    /// @notice Voting delay in blocks (time before voting starts).
    /// @dev    Ta'khir Ray (تاخیر رای) = Voting Delay in Persian
    uint256 private _votingDelay;

    /// @notice Voting period in blocks.
    /// @dev    Doreye Ray (دوره رای) = Voting Period in Persian
    uint256 private _votingPeriod;

    /// @notice Proposal threshold percentage (scaled by PRECISION).
    /// @dev    Astar Pishnahad (آستانه پیشنهاد) = Proposal Threshold in Persian
    uint256 private _proposalThresholdPct;

    /// @notice Quorum percentage (scaled by PRECISION).
    /// @dev    Hadde Nasab (حد نصاب) = Quorum in Persian
    uint256 private _quorumPct;

    /// @notice Approval threshold percentage (scaled by PRECISION).
    /// @dev    Astar Tasvib (آستانه تصویب) = Approval Threshold in Persian
    uint256 private _approvalThresholdPct;

    /// @notice Timelock delay in seconds.
    /// @dev    Ta'khir Ejra (تاخیر اجرا) = Execution Delay in Persian
    uint256 private _timelockDelay;

    // =========  CONSTRUCTOR ========= //

    /**
     * @notice Construct a new Charter.
     * @param  admin_              The initial admin address.
     * @param  votingDelay_        Initial voting delay in blocks.
     * @param  votingPeriod_       Initial voting period in blocks.
     * @param  proposalThreshold_  Initial proposal threshold percentage.
     * @param  quorumPct_          Initial quorum percentage.
     * @param  approvalThreshold_  Initial approval threshold percentage.
     * @param  timelockDelay_      Initial timelock delay in seconds.
     */
    constructor(
        address admin_,
        uint256 votingDelay_,
        uint256 votingPeriod_,
        uint256 proposalThreshold_,
        uint256 quorumPct_,
        uint256 approvalThreshold_,
        uint256 timelockDelay_
    ) {
        require(admin_ != address(0), "Charter: invalid admin");

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(GOVERNANCE_ROLE, admin_);

        // Validate and set initial parameters
        _setVotingDelay(votingDelay_);
        _setVotingPeriod(votingPeriod_);
        _setProposalThreshold(proposalThreshold_);
        _setQuorum(quorumPct_);
        _setApprovalThreshold(approvalThreshold_);
        _setTimelockDelay(timelockDelay_);
    }

    // =========  VIEW FUNCTIONS ========= //

    /// @inheritdoc ICharter
    function votingDelay() external view override returns (uint256) {
        return _votingDelay;
    }

    /// @inheritdoc ICharter
    function votingPeriod() external view override returns (uint256) {
        return _votingPeriod;
    }

    /// @inheritdoc ICharter
    function proposalThresholdPct() external view override returns (uint256) {
        return _proposalThresholdPct;
    }

    /// @inheritdoc ICharter
    function quorumPct() external view override returns (uint256) {
        return _quorumPct;
    }

    /// @inheritdoc ICharter
    function approvalThresholdPct() external view override returns (uint256) {
        return _approvalThresholdPct;
    }

    /// @inheritdoc ICharter
    function timelockDelay() external view override returns (uint256) {
        return _timelockDelay;
    }

    // =========  GOVERNANCE FUNCTIONS ========= //

    /// @inheritdoc ICharter
    function setVotingDelay(uint256 newDelay) external override onlyRole(GOVERNANCE_ROLE) {
        _setVotingDelay(newDelay);
    }

    /// @inheritdoc ICharter
    function setVotingPeriod(uint256 newPeriod) external override onlyRole(GOVERNANCE_ROLE) {
        _setVotingPeriod(newPeriod);
    }

    /// @inheritdoc ICharter
    function setProposalThreshold(uint256 newThreshold) external override onlyRole(GOVERNANCE_ROLE) {
        _setProposalThreshold(newThreshold);
    }

    /**
     * @notice Update the quorum percentage.
     * @param  newQuorum The new quorum percentage (scaled by PRECISION).
     */
    function setQuorum(uint256 newQuorum) external onlyRole(GOVERNANCE_ROLE) {
        _setQuorum(newQuorum);
    }

    /**
     * @notice Update the approval threshold percentage.
     * @param  newThreshold The new approval threshold (scaled by PRECISION).
     */
    function setApprovalThreshold(uint256 newThreshold) external onlyRole(GOVERNANCE_ROLE) {
        _setApprovalThreshold(newThreshold);
    }

    /**
     * @notice Update the timelock delay.
     * @param  newDelay The new timelock delay in seconds.
     */
    function setTimelockDelay(uint256 newDelay) external onlyRole(GOVERNANCE_ROLE) {
        _setTimelockDelay(newDelay);
    }

    // =========  INTERNAL FUNCTIONS ========= //

    function _setVotingDelay(uint256 newDelay) internal {
        if (newDelay < MIN_VOTING_DELAY) revert Charter_BelowMinimum();
        if (newDelay > MAX_VOTING_DELAY) revert Charter_AboveMaximum();

        uint256 oldDelay = _votingDelay;
        _votingDelay = newDelay;

        emit VotingDelayUpdated(oldDelay, newDelay);
    }

    function _setVotingPeriod(uint256 newPeriod) internal {
        if (newPeriod < MIN_VOTING_PERIOD) revert Charter_BelowMinimum();
        if (newPeriod > MAX_VOTING_PERIOD) revert Charter_AboveMaximum();

        uint256 oldPeriod = _votingPeriod;
        _votingPeriod = newPeriod;

        emit VotingPeriodUpdated(oldPeriod, newPeriod);
    }

    function _setProposalThreshold(uint256 newThreshold) internal {
        if (newThreshold < MIN_PROPOSAL_THRESHOLD) revert Charter_BelowMinimum();
        if (newThreshold > MAX_PROPOSAL_THRESHOLD) revert Charter_AboveMaximum();

        uint256 oldThreshold = _proposalThresholdPct;
        _proposalThresholdPct = newThreshold;

        emit ProposalThresholdUpdated(oldThreshold, newThreshold);
    }

    function _setQuorum(uint256 newQuorum) internal {
        if (newQuorum < MIN_QUORUM) revert Charter_BelowMinimum();
        if (newQuorum > MAX_QUORUM) revert Charter_AboveMaximum();

        uint256 oldQuorum = _quorumPct;
        _quorumPct = newQuorum;

        emit QuorumUpdated(oldQuorum, newQuorum);
    }

    function _setApprovalThreshold(uint256 newThreshold) internal {
        if (newThreshold < MIN_APPROVAL_THRESHOLD) revert Charter_BelowMinimum();
        if (newThreshold > MAX_APPROVAL_THRESHOLD) revert Charter_AboveMaximum();

        uint256 oldThreshold = _approvalThresholdPct;
        _approvalThresholdPct = newThreshold;

        emit ApprovalThresholdUpdated(oldThreshold, newThreshold);
    }

    function _setTimelockDelay(uint256 newDelay) internal {
        if (newDelay < MIN_TIMELOCK_DELAY) revert Charter_BelowMinimum();
        if (newDelay > MAX_TIMELOCK_DELAY) revert Charter_AboveMaximum();

        uint256 oldDelay = _timelockDelay;
        _timelockDelay = newDelay;

        emit TimelockDelayUpdated(oldDelay, newDelay);
    }
}
