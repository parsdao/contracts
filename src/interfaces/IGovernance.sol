// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

/**
 * @title  Pars Governance Interfaces
 * @author Pars Protocol
 * @notice Interfaces for the Pars governance system.
 * @dev    Based on PIP-0026 governance terminology.
 *
 *         Persian Governance Terms:
 *         - Council = Shura (شورا) - Main governance body
 *         - Charter = Manshur (منشور) - Governance constitution
 *         - Committee = Komiteh (کمیته) - Sub-DAO committee
 *         - Resolution = Qarardad (قرارداد) - Proposal/Resolution
 *         - Sanction = Tahrim (تحریم) - Enforcement action
 */

/**
 * @title  ICouncil Interface
 * @notice Interface for the main governance council.
 * @dev    Shura (شورا) = Council in Persian
 */
interface ICouncil {
    // =========  ENUMS ========= //

    /// @notice Resolution states.
    /// @dev    Vaziyat (وضعیت) = State in Persian
    enum ResolutionState {
        Pending,    // Dar Entezar (در انتظار)
        Active,     // Fa'al (فعال)
        Canceled,   // Laghv Shode (لغو شده)
        Defeated,   // Rad Shode (رد شده)
        Succeeded,  // Movaffagh (موفق)
        Queued,     // Dar Saf (در صف)
        Expired,    // Montazeh Shode (منقضی شده)
        Executed,   // Ejra Shode (اجرا شده)
        Vetoed      // Veto Shode (وتو شده)
    }

    // =========  STRUCTS ========= //

    /// @notice Resolution (proposal) structure.
    struct Resolution {
        uint256 id;
        address proposer;
        uint256 eta;
        address[] targets;
        uint256[] values;
        string[] signatures;
        bytes[] calldatas;
        uint256 startBlock;
        uint256 endBlock;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        bool canceled;
        bool executed;
        bool vetoed;
    }

    // =========  FUNCTIONS ========= //

    /// @notice Submit a new resolution.
    function propose(
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256);

    /// @notice Cast a vote on a resolution.
    function castVote(uint256 resolutionId, uint8 support) external;

    /// @notice Cast a vote with a reason.
    function castVoteWithReason(
        uint256 resolutionId,
        uint8 support,
        string calldata reason
    ) external;

    /// @notice Queue a successful resolution for execution.
    function queue(uint256 resolutionId) external;

    /// @notice Execute a queued resolution.
    function execute(uint256 resolutionId) external payable;

    /// @notice Cancel a resolution.
    function cancel(uint256 resolutionId) external;

    /// @notice Veto a resolution (guardian only).
    function veto(uint256 resolutionId) external;

    /// @notice Get the state of a resolution.
    function state(uint256 resolutionId) external view returns (ResolutionState);

    /// @notice Get the voting power threshold for proposals.
    function proposalThreshold() external view returns (uint256);

    /// @notice Get the quorum required for votes.
    function quorumVotes() external view returns (uint256);
}

/**
 * @title  ICharter Interface
 * @notice Interface for governance rules and parameters.
 * @dev    Manshur (منشور) = Charter/Constitution in Persian
 */
interface ICharter {
    /// @notice Get the voting delay (blocks before voting starts).
    function votingDelay() external view returns (uint256);

    /// @notice Get the voting period (blocks for voting).
    function votingPeriod() external view returns (uint256);

    /// @notice Get the proposal threshold percentage.
    function proposalThresholdPct() external view returns (uint256);

    /// @notice Get the quorum percentage.
    function quorumPct() external view returns (uint256);

    /// @notice Get the approval threshold percentage.
    function approvalThresholdPct() external view returns (uint256);

    /// @notice Get the timelock delay.
    function timelockDelay() external view returns (uint256);

    /// @notice Update the voting delay.
    function setVotingDelay(uint256 newDelay) external;

    /// @notice Update the voting period.
    function setVotingPeriod(uint256 newPeriod) external;

    /// @notice Update the proposal threshold.
    function setProposalThreshold(uint256 newThreshold) external;
}

/**
 * @title  ICommittee Interface
 * @notice Interface for sub-DAO committees.
 * @dev    Komiteh (کمیته) = Committee in Persian
 *
 *         Committees in the MIGA/Pars ecosystem:
 *         - FARHANG: Culture & Heritage
 *         - DANESH: Education & Research
 *         - RASANEH: Media & Journalism
 *         - FANNI: Technology & Infrastructure
 *         - SALAMAT: Health & Wellness
 *         - HOGHUGH: Legal & Advocacy
 *         - BAZARGANI: Economic & Enterprise
 *         - MOHIT: Environment & Sustainability
 *         - MIZ: Interfaith & Dialogue
 *         - HOZEH: Science & Innovation
 */
interface ICommittee {
    /// @notice The committee's name.
    function name() external view returns (string memory);

    /// @notice The committee's treasury allocation percentage.
    function allocationPct() external view returns (uint256);

    /// @notice Get the committee members.
    function members() external view returns (address[] memory);

    /// @notice Check if an address is a committee member.
    function isMember(address account) external view returns (bool);

    /// @notice Add a member to the committee.
    function addMember(address member) external;

    /// @notice Remove a member from the committee.
    function removeMember(address member) external;

    /// @notice Execute a committee-approved action.
    function execute(
        address target,
        uint256 value,
        bytes calldata data
    ) external returns (bytes memory);
}

/**
 * @title  ISanction Interface
 * @notice Interface for enforcement and veto mechanisms.
 * @dev    Tahrim (تحریم) = Sanction in Persian
 */
interface ISanction {
    /// @notice Sanction types.
    enum SanctionType {
        Warning,    // Akhtar (اخطار)
        Suspension, // Ta'liq (تعلیق)
        Removal,    // Barkanari (برکناری)
        Ban         // Mahromiyat (محرومیت)
    }

    /// @notice Apply a sanction to an address.
    function applySanction(
        address target,
        SanctionType sanctionType,
        string calldata reason
    ) external;

    /// @notice Remove a sanction from an address.
    function removeSanction(address target) external;

    /// @notice Check if an address is sanctioned.
    function isSanctioned(address target) external view returns (bool);

    /// @notice Get the sanction details for an address.
    function getSanction(address target) external view returns (
        SanctionType sanctionType,
        uint256 timestamp,
        string memory reason
    );
}

/**
 * @title  ITimelock Interface
 * @notice Interface for the governance timelock.
 * @dev    Zamanbandi (زمان‌بندی) = Timelock in Persian
 */
interface ITimelock {
    /// @notice Queue a transaction for execution.
    function queueTransaction(
        uint256 resolutionId,
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 eta
    ) external returns (bytes32);

    /// @notice Execute a queued transaction.
    function executeTransaction(
        uint256 resolutionId,
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        bytes32 codeHash,
        uint256 eta
    ) external payable returns (bytes memory);

    /// @notice Cancel a queued transaction.
    function cancelTransaction(
        uint256 resolutionId,
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 eta
    ) external;

    /// @notice Get the execution delay.
    function delay() external view returns (uint256);

    /// @notice Get the grace period after eta.
    function GRACE_PERIOD() external view returns (uint256);

    /// @notice Check if a transaction is queued.
    function queuedTransactions(bytes32 hash) external view returns (bool);
}
