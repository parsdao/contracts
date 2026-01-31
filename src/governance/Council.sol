// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ICouncil, ITimelock} from "../interfaces/IGovernance.sol";
import {IvePARS} from "../interfaces/IPARS.sol";
import {Kernel, Policy, Keycode, toKeycode, Permissions} from "../Kernel.sol";

/**
 * @title  Pars Council
 * @author Pars Protocol
 * @notice Main governance contract for the Pars Protocol.
 * @dev    Shura (شورا) = Council in Persian
 *
 *         The Council manages protocol governance through resolutions (proposals).
 *         Based on Governor Bravo architecture with Pars-specific modifications.
 *
 *         Key features:
 *         - vePARS-based voting (time-weighted voting power)
 *         - Dynamic quorum based on total supply
 *         - Emergency proposal mechanism
 *         - Veto guardian for security
 *         - Integration with Pars Kernel system
 *
 *         Governance flow:
 *         1. Submit Resolution (Qarardad)
 *         2. Voting Period (Doreye Ray)
 *         3. Queue if Passed (Saf)
 *         4. Execute after Timelock (Ejra)
 */
contract Council is ICouncil, Policy {
    // =========  ERRORS ========= //

    error Council_OnlyAdmin();
    error Council_OnlyGuardian();
    error Council_AlreadyInitialized();
    error Council_InvalidAddress();
    error Council_InvalidPeriod();
    error Council_InvalidDelay();
    error Council_InvalidThreshold();
    error Council_SupplyTooLow();
    error Council_ThresholdNotMet();
    error Council_LengthMismatch();
    error Council_NoActions();
    error Council_TooManyActions();
    error Council_AlreadyActive();
    error Council_AlreadyPending();
    error Council_IdCollision();
    error Council_IdInvalid();
    error Council_TooEarly();
    error Council_AlreadyActivated();
    error Council_VoteClosed();
    error Council_InvalidVoteType();
    error Council_AlreadyVoted();
    error Council_FailedProposal();
    error Council_BelowThreshold();
    error Council_AlreadyQueued();
    error Council_NotQueued();
    error Council_AlreadyExecuted();
    error Council_AboveThreshold();
    error Council_NotEmergency();
    error Council_InvalidSignature();
    error Council_InvalidCalldata();

    // =========  EVENTS ========= //

    event ResolutionCreated(
        uint256 indexed id,
        address indexed proposer,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 startBlock,
        string description
    );
    event ResolutionQueued(uint256 indexed id, uint256 eta);
    event ResolutionExecuted(uint256 indexed id);
    event ResolutionCanceled(uint256 indexed id);
    event ResolutionVetoed(uint256 indexed id);
    event VoteCast(
        address indexed voter,
        uint256 indexed resolutionId,
        uint8 support,
        uint256 votes,
        string reason
    );
    event VotingStarted(uint256 indexed id);

    // =========  STRUCTS ========= //

    /// @notice Receipt for a vote cast.
    struct Receipt {
        bool hasVoted;
        uint8 support;
        uint256 votes;
    }

    /// @notice Internal resolution storage.
    struct ResolutionStorage {
        uint256 id;
        address proposer;
        uint256 eta;
        address[] targets;
        uint256[] values;
        string[] signatures;
        bytes[] calldatas;
        bytes32[] codeHashes;
        uint256 startBlock;
        uint256 endBlock;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        uint256 quorumVotes;
        uint256 proposalThreshold;
        bool votingStarted;
        bool canceled;
        bool executed;
        bool vetoed;
        mapping(address => Receipt) receipts;
    }

    // =========  CONSTANTS ========= //

    /// @notice Contract name for EIP-712.
    string public constant name = "Pars Council";

    /// @notice Minimum proposal threshold (0.015% of supply).
    uint256 public constant MIN_PROPOSAL_THRESHOLD_PCT = 15_000;

    /// @notice Maximum proposal threshold (1% of supply).
    uint256 public constant MAX_PROPOSAL_THRESHOLD_PCT = 1_000_000;

    /// @notice Minimum voting period (~3 days at 2s blocks for Pars).
    uint256 public constant MIN_VOTING_PERIOD = 129_600;

    /// @notice Maximum voting period (~2 weeks).
    uint256 public constant MAX_VOTING_PERIOD = 604_800;

    /// @notice Minimum voting delay (~1 day).
    uint256 public constant MIN_VOTING_DELAY = 43_200;

    /// @notice Maximum voting delay (~1 week).
    uint256 public constant MAX_VOTING_DELAY = 302_400;

    /// @notice Minimum vePARS supply for normal operations.
    uint256 public constant MIN_SUPPLY = 1_000e9;

    /// @notice Quorum percentage (20% of supply).
    uint256 public constant QUORUM_PCT = 20_000_000;

    /// @notice Approval threshold (60% of votes).
    uint256 public constant APPROVAL_THRESHOLD_PCT = 60_000_000;

    /// @notice Maximum actions per resolution.
    uint256 public constant MAX_OPERATIONS = 15;

    /// @notice Precision denominator.
    uint256 private constant PRECISION = 100_000_000;

    /// @notice EIP-712 domain typehash.
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice EIP-712 ballot typehash.
    bytes32 public constant BALLOT_TYPEHASH =
        keccak256("Ballot(uint256 resolutionId,uint8 support)");

    // =========  STATE ========= //

    /// @notice The timelock contract.
    ITimelock public timelock;

    /// @notice The vePARS token for voting.
    IvePARS public vepars;

    /// @notice The kernel address.
    address public kernelAddress;

    /// @notice The admin address.
    address public admin;

    /// @notice The pending admin address.
    address public pendingAdmin;

    /// @notice The veto guardian address.
    /// @dev    Negahban (نگهبان) = Guardian in Persian
    address public vetoGuardian;

    /// @notice Voting delay in blocks.
    uint256 public votingDelay;

    /// @notice Voting period in blocks.
    uint256 public votingPeriod;

    /// @notice Activation grace period in blocks.
    uint256 public activationGracePeriod;

    /// @notice Proposal threshold percentage (in PRECISION units).
    uint256 public proposalThresholdPct;

    /// @notice Total number of resolutions.
    uint256 public resolutionCount;

    /// @notice Mapping of resolution ID to resolution.
    mapping(uint256 => ResolutionStorage) public resolutions;

    /// @notice Mapping of proposer to latest resolution ID.
    mapping(address => uint256) public latestResolutionIds;

    /// @notice Mapping of keycode to high risk status.
    mapping(Keycode => bool) public isKeycodeHighRisk;

    // =========  CONSTRUCTOR ========= //

    constructor(Kernel kernel_) Policy(kernel_) {}

    // =========  POLICY SETUP ========= //

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](0);
    }

    /// @inheritdoc Policy
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        requests = new Permissions[](0);
    }

    // =========  INITIALIZATION ========= //

    /**
     * @notice Initialize the Council contract.
     * @param  timelock_             The timelock contract address.
     * @param  vepars_               The vePARS token address.
     * @param  kernel_               The kernel address.
     * @param  vetoGuardian_         The veto guardian address.
     * @param  votingPeriod_         The voting period in blocks.
     * @param  votingDelay_          The voting delay in blocks.
     * @param  activationGracePeriod_ The activation grace period.
     * @param  proposalThreshold_    The proposal threshold percentage.
     */
    function initialize(
        address timelock_,
        address vepars_,
        address kernel_,
        address vetoGuardian_,
        uint256 votingPeriod_,
        uint256 votingDelay_,
        uint256 activationGracePeriod_,
        uint256 proposalThreshold_
    ) external {
        if (msg.sender != admin) revert Council_OnlyAdmin();
        if (address(timelock) != address(0)) revert Council_AlreadyInitialized();
        if (
            timelock_ == address(0) ||
            vepars_ == address(0) ||
            kernel_ == address(0) ||
            vetoGuardian_ == address(0)
        ) revert Council_InvalidAddress();
        if (votingPeriod_ < MIN_VOTING_PERIOD || votingPeriod_ > MAX_VOTING_PERIOD)
            revert Council_InvalidPeriod();
        if (votingDelay_ < MIN_VOTING_DELAY || votingDelay_ > MAX_VOTING_DELAY)
            revert Council_InvalidDelay();
        if (
            proposalThreshold_ < MIN_PROPOSAL_THRESHOLD_PCT ||
            proposalThreshold_ > MAX_PROPOSAL_THRESHOLD_PCT
        ) revert Council_InvalidThreshold();

        timelock = ITimelock(timelock_);
        vepars = IvePARS(vepars_);
        kernelAddress = kernel_;
        vetoGuardian = vetoGuardian_;
        votingDelay = votingDelay_;
        votingPeriod = votingPeriod_;
        activationGracePeriod = activationGracePeriod_;
        proposalThresholdPct = proposalThreshold_;
    }

    // =========  RESOLUTION LIFECYCLE ========= //

    /**
     * @notice Submit a new resolution.
     * @dev    Pishnahad (پیشنهاد) = Proposal in Persian
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description
    ) external override returns (uint256) {
        if (_isEmergency()) revert Council_SupplyTooLow();
        if (vepars.getPriorVotes(msg.sender, block.number - 1) <= getProposalThresholdVotes())
            revert Council_ThresholdNotMet();
        if (
            targets.length != values.length ||
            targets.length != signatures.length ||
            targets.length != calldatas.length
        ) revert Council_LengthMismatch();
        if (targets.length == 0) revert Council_NoActions();
        if (targets.length > MAX_OPERATIONS) revert Council_TooManyActions();

        uint256 latestId = latestResolutionIds[msg.sender];
        if (latestId != 0) {
            ResolutionState proposerState = state(latestId);
            if (proposerState == ResolutionState.Active) revert Council_AlreadyActive();
            if (proposerState == ResolutionState.Pending) revert Council_AlreadyPending();
        }

        uint256 startBlock = block.number + votingDelay;
        resolutionCount++;
        uint256 newId = resolutionCount;

        // Get code hashes for verification
        bytes32[] memory codeHashes = new bytes32[](targets.length);
        for (uint256 i = 0; i < targets.length; ) {
            codeHashes[i] = targets[i].codehash;
            unchecked { ++i; }
        }

        ResolutionStorage storage newResolution = resolutions[newId];
        if (newResolution.id != 0) revert Council_IdCollision();

        latestResolutionIds[msg.sender] = newId;
        newResolution.startBlock = startBlock;
        newResolution.id = newId;
        newResolution.proposer = msg.sender;
        newResolution.proposalThreshold = getProposalThresholdVotes();
        newResolution.targets = targets;
        newResolution.values = values;
        newResolution.signatures = signatures;
        newResolution.calldatas = calldatas;
        newResolution.codeHashes = codeHashes;

        emit ResolutionCreated(
            newId,
            msg.sender,
            targets,
            values,
            signatures,
            calldatas,
            startBlock,
            description
        );

        return newId;
    }

    /**
     * @notice Activate voting for a resolution.
     */
    function activate(uint256 resolutionId) external {
        if (_isEmergency()) revert Council_SupplyTooLow();
        if (state(resolutionId) != ResolutionState.Pending) revert Council_VoteClosed();

        ResolutionStorage storage resolution = resolutions[resolutionId];
        if (block.number <= resolution.startBlock) revert Council_TooEarly();
        if (resolution.votingStarted || resolution.endBlock != 0)
            revert Council_AlreadyActivated();

        resolution.votingStarted = true;
        resolution.endBlock = block.number + votingPeriod;
        resolution.quorumVotes = getQuorumVotes();

        emit VotingStarted(resolutionId);
    }

    /**
     * @notice Cast a vote on a resolution.
     * @dev    Ray Dadan (رای دادن) = Cast Vote in Persian
     */
    function castVote(uint256 resolutionId, uint8 support) external override {
        emit VoteCast(
            msg.sender,
            resolutionId,
            support,
            _castVoteInternal(msg.sender, resolutionId, support),
            ""
        );
    }

    /**
     * @notice Cast a vote with a reason.
     */
    function castVoteWithReason(
        uint256 resolutionId,
        uint8 support,
        string calldata reason
    ) external override {
        emit VoteCast(
            msg.sender,
            resolutionId,
            support,
            _castVoteInternal(msg.sender, resolutionId, support),
            reason
        );
    }

    /**
     * @notice Cast a vote by signature.
     */
    function castVoteBySig(
        uint256 resolutionId,
        uint8 support,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        bytes32 domainSeparator = keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), block.chainid, address(this))
        );
        bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, resolutionId, support));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ECDSA.recover(digest, v, r, s);
        if (signatory == address(0)) revert Council_InvalidSignature();

        emit VoteCast(
            signatory,
            resolutionId,
            support,
            _castVoteInternal(signatory, resolutionId, support),
            ""
        );
    }

    function _castVoteInternal(
        address voter,
        uint256 resolutionId,
        uint8 support
    ) internal returns (uint256) {
        if (state(resolutionId) != ResolutionState.Active) revert Council_VoteClosed();
        if (support > 2) revert Council_InvalidVoteType();

        ResolutionStorage storage resolution = resolutions[resolutionId];
        Receipt storage receipt = resolution.receipts[voter];
        if (receipt.hasVoted) revert Council_AlreadyVoted();

        uint256 originalVotes = vepars.getPriorVotes(voter, resolution.startBlock);
        uint256 currentVotes = vepars.getPriorVotes(voter, block.number - 1);
        uint256 votes = currentVotes > originalVotes ? originalVotes : currentVotes;

        if (support == 0) {
            resolution.againstVotes += votes;
        } else if (support == 1) {
            resolution.forVotes += votes;
        } else {
            resolution.abstainVotes += votes;
        }

        receipt.hasVoted = true;
        receipt.support = support;
        receipt.votes = votes;

        return votes;
    }

    /**
     * @notice Queue a successful resolution.
     * @dev    Saf Kardan (صف کردن) = Queue in Persian
     */
    function queue(uint256 resolutionId) external override {
        if (state(resolutionId) != ResolutionState.Succeeded)
            revert Council_FailedProposal();

        ResolutionStorage storage resolution = resolutions[resolutionId];
        if (vepars.getPriorVotes(resolution.proposer, block.number - 1) < resolution.proposalThreshold)
            revert Council_BelowThreshold();

        uint256 eta = block.timestamp + timelock.delay();
        for (uint256 i = 0; i < resolution.targets.length; i++) {
            _queueOrRevert(
                resolutionId,
                resolution.targets[i],
                resolution.values[i],
                resolution.signatures[i],
                resolution.calldatas[i],
                eta
            );
        }
        resolution.eta = eta;

        emit ResolutionQueued(resolutionId, eta);
    }

    function _queueOrRevert(
        uint256 resolutionId,
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 eta
    ) internal {
        bytes32 txHash = keccak256(abi.encode(resolutionId, target, value, signature, data, eta));
        if (timelock.queuedTransactions(txHash)) revert Council_AlreadyQueued();
        timelock.queueTransaction(resolutionId, target, value, signature, data, eta);
    }

    /**
     * @notice Execute a queued resolution.
     * @dev    Ejra Kardan (اجرا کردن) = Execute in Persian
     */
    function execute(uint256 resolutionId) external payable override {
        if (state(resolutionId) != ResolutionState.Queued) revert Council_NotQueued();

        ResolutionStorage storage resolution = resolutions[resolutionId];
        if (vepars.getPriorVotes(resolution.proposer, block.number - 1) < resolution.proposalThreshold)
            revert Council_BelowThreshold();

        resolution.executed = true;
        for (uint256 i = 0; i < resolution.targets.length; i++) {
            timelock.executeTransaction{value: resolution.values[i]}(
                resolutionId,
                resolution.targets[i],
                resolution.values[i],
                resolution.signatures[i],
                resolution.calldatas[i],
                resolution.codeHashes[i],
                resolution.eta
            );
        }

        emit ResolutionExecuted(resolutionId);
    }

    /**
     * @notice Cancel a resolution.
     * @dev    Laghv Kardan (لغو کردن) = Cancel in Persian
     */
    function cancel(uint256 resolutionId) external override {
        if (state(resolutionId) == ResolutionState.Executed)
            revert Council_AlreadyExecuted();

        ResolutionStorage storage resolution = resolutions[resolutionId];
        if (msg.sender != resolution.proposer) {
            if (vepars.getPriorVotes(resolution.proposer, block.number - 1) >= resolution.proposalThreshold)
                revert Council_AboveThreshold();
        }

        resolution.canceled = true;
        for (uint256 i = 0; i < resolution.targets.length; i++) {
            timelock.cancelTransaction(
                resolutionId,
                resolution.targets[i],
                resolution.values[i],
                resolution.signatures[i],
                resolution.calldatas[i],
                resolution.eta
            );
        }

        emit ResolutionCanceled(resolutionId);
    }

    /**
     * @notice Veto a resolution (guardian only).
     * @dev    Veto Kardan (وتو کردن) = Veto in Persian
     */
    function veto(uint256 resolutionId) external override {
        if (msg.sender != vetoGuardian) revert Council_OnlyGuardian();
        if (state(resolutionId) == ResolutionState.Executed)
            revert Council_AlreadyExecuted();

        ResolutionStorage storage resolution = resolutions[resolutionId];
        resolution.vetoed = true;

        for (uint256 i = 0; i < resolution.targets.length; ) {
            bytes32 txHash = keccak256(
                abi.encode(
                    resolutionId,
                    resolution.targets[i],
                    resolution.values[i],
                    resolution.signatures[i],
                    resolution.calldatas[i],
                    resolution.eta
                )
            );
            if (timelock.queuedTransactions(txHash)) {
                timelock.cancelTransaction(
                    resolutionId,
                    resolution.targets[i],
                    resolution.values[i],
                    resolution.signatures[i],
                    resolution.calldatas[i],
                    resolution.eta
                );
            }
            unchecked { ++i; }
        }

        emit ResolutionVetoed(resolutionId);
    }

    // =========  VIEW FUNCTIONS ========= //

    /**
     * @notice Get the state of a resolution.
     */
    function state(uint256 resolutionId) public view override returns (ResolutionState) {
        if (resolutionCount < resolutionId) revert Council_IdInvalid();

        ResolutionStorage storage resolution = resolutions[resolutionId];

        if (resolution.vetoed) {
            return ResolutionState.Vetoed;
        } else if (resolution.canceled) {
            return ResolutionState.Canceled;
        } else if (
            block.number <= resolution.startBlock ||
            !resolution.votingStarted ||
            resolution.endBlock == 0
        ) {
            if (block.number > resolution.startBlock + activationGracePeriod) {
                return ResolutionState.Expired;
            }
            return ResolutionState.Pending;
        } else if (block.number <= resolution.endBlock) {
            return ResolutionState.Active;
        } else if (!_getVoteOutcome(resolutionId)) {
            return ResolutionState.Defeated;
        } else if (resolution.eta == 0) {
            return ResolutionState.Succeeded;
        } else if (resolution.executed) {
            return ResolutionState.Executed;
        } else if (block.timestamp > resolution.eta + timelock.GRACE_PERIOD()) {
            return ResolutionState.Expired;
        } else {
            return ResolutionState.Queued;
        }
    }

    function _getVoteOutcome(uint256 resolutionId) internal view returns (bool) {
        ResolutionStorage storage resolution = resolutions[resolutionId];

        if (resolution.forVotes == 0 && resolution.againstVotes == 0) {
            return false;
        }
        if (
            (resolution.forVotes * PRECISION) / (resolution.forVotes + resolution.againstVotes) <
            APPROVAL_THRESHOLD_PCT ||
            resolution.forVotes < resolution.quorumVotes
        ) {
            return false;
        }
        return true;
    }

    function _isEmergency() internal view returns (bool) {
        return vepars.totalVotingPower() < MIN_SUPPLY;
    }

    function getProposalThresholdVotes() public view returns (uint256) {
        return (vepars.totalVotingPower() * proposalThresholdPct) / PRECISION;
    }

    function getQuorumVotes() public view returns (uint256) {
        return (vepars.totalVotingPower() * QUORUM_PCT) / PRECISION;
    }

    function proposalThreshold() external view override returns (uint256) {
        return getProposalThresholdVotes();
    }

    function quorumVotes() external view override returns (uint256) {
        return getQuorumVotes();
    }

    // =========  ADMIN FUNCTIONS ========= //

    function setVotingDelay(uint256 newDelay) external {
        if (msg.sender != admin) revert Council_OnlyAdmin();
        if (newDelay < MIN_VOTING_DELAY || newDelay > MAX_VOTING_DELAY)
            revert Council_InvalidDelay();
        votingDelay = newDelay;
    }

    function setVotingPeriod(uint256 newPeriod) external {
        if (msg.sender != admin) revert Council_OnlyAdmin();
        if (newPeriod < MIN_VOTING_PERIOD || newPeriod > MAX_VOTING_PERIOD)
            revert Council_InvalidPeriod();
        votingPeriod = newPeriod;
    }

    function setProposalThreshold(uint256 newThreshold) external {
        if (msg.sender != admin) revert Council_OnlyAdmin();
        if (newThreshold < MIN_PROPOSAL_THRESHOLD_PCT || newThreshold > MAX_PROPOSAL_THRESHOLD_PCT)
            revert Council_InvalidThreshold();
        proposalThresholdPct = newThreshold;
    }

    function setVetoGuardian(address newGuardian) external {
        if (msg.sender != admin) revert Council_OnlyAdmin();
        vetoGuardian = newGuardian;
    }
}
