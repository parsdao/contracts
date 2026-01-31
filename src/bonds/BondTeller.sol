// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IBondTeller, IBondDepository} from "../interfaces/IBonds.sol";
import {Kernel, Policy, Keycode, Permissions} from "../Kernel.sol";

/**
 * @title  Pars Bond Teller
 * @author Pars Protocol
 * @notice Manages bond notes and redemptions for the Pars Protocol.
 * @dev    Gisheh Oraghe (گیشه اوراقه) = Bond Teller in Persian
 *
 *         The Bond Teller:
 *         - Creates bond notes when bonds are purchased
 *         - Manages vesting schedules
 *         - Handles redemption of matured bonds
 *         - Tracks bond ownership
 */
contract BondTeller is IBondTeller, Policy, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =========  ERRORS ========= //

    error BondTeller_NotOwner();
    error BondTeller_NotMatured();
    error BondTeller_NothingToRedeem();
    error BondTeller_AlreadyRedeemed();
    error BondTeller_InvalidIndex();
    error BondTeller_OnlyDepository();

    // =========  EVENTS ========= //

    event BondCreated(
        address indexed owner,
        uint256 indexed index,
        uint256 payout,
        uint256 matured,
        uint256 marketId
    );
    event BondRedeemed(
        address indexed owner,
        uint256 indexed index,
        uint256 payout
    );

    // =========  STATE ========= //

    /// @notice PARS token address.
    IERC20 public immutable pars;

    /// @notice Bond depository contract.
    IBondDepository public depository;

    /// @notice Mapping of owner -> array of notes.
    mapping(address => Note[]) public notes;

    /// @notice Total bonds created.
    uint256 public totalBondsCreated;

    /// @notice Total PARS paid out.
    uint256 public totalPaidOut;

    // =========  CONSTRUCTOR ========= //

    /**
     * @notice Construct a new Bond Teller.
     * @param  kernel_ The kernel contract address.
     * @param  pars_   The PARS token address.
     */
    constructor(Kernel kernel_, address pars_) Policy(kernel_) {
        require(pars_ != address(0), "BondTeller: invalid PARS");
        pars = IERC20(pars_);
    }

    // =========  POLICY SETUP ========= //

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](0);
    }

    /// @inheritdoc Policy
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        requests = new Permissions[](0);
    }

    // =========  MODIFIERS ========= //

    modifier onlyDepository() {
        if (msg.sender != address(depository)) revert BondTeller_OnlyDepository();
        _;
    }

    // =========  BOND CREATION ========= //

    /**
     * @notice Create a bond note (called by depository).
     * @dev    Ijad Oraghe (ایجاد اوراقه) = Create Bond in Persian
     * @param  owner_    The bond owner.
     * @param  payout_   The PARS payout amount.
     * @param  expiry_   The maturity timestamp.
     * @param  marketId_ The source market ID.
     * @return index_    The bond index for the owner.
     */
    function create(
        address owner_,
        uint256 payout_,
        uint256 expiry_,
        uint256 marketId_
    ) external onlyDepository returns (uint256 index_) {
        index_ = notes[owner_].length;

        notes[owner_].push(Note({
            payout: payout_,
            created: block.timestamp,
            matured: expiry_,
            redeemed: 0,
            marketId: marketId_
        }));

        totalBondsCreated++;

        emit BondCreated(owner_, index_, payout_, expiry_, marketId_);
    }

    // =========  REDEMPTION ========= //

    /**
     * @notice Redeem matured bonds.
     * @dev    Bazkhаrid (بازخرید) = Redemption in Persian
     * @param  owner_   The bond owner.
     * @param  indexes_ The bond indexes to redeem.
     * @return payout_  The total PARS redeemed.
     */
    function redeem(
        address owner_,
        uint256[] memory indexes_
    ) external override nonReentrant returns (uint256 payout_) {
        for (uint256 i = 0; i < indexes_.length; i++) {
            uint256 index = indexes_[i];

            if (index >= notes[owner_].length) revert BondTeller_InvalidIndex();

            Note storage note = notes[owner_][index];

            if (note.payout == 0) continue; // Already fully redeemed
            if (block.timestamp < note.matured) continue; // Not matured

            uint256 amount = note.payout - note.redeemed;
            if (amount == 0) continue; // Nothing to redeem

            note.redeemed = note.payout;
            payout_ += amount;

            emit BondRedeemed(owner_, index, amount);
        }

        if (payout_ == 0) revert BondTeller_NothingToRedeem();

        totalPaidOut += payout_;
        pars.safeTransfer(owner_, payout_);
    }

    /**
     * @notice Redeem all matured bonds for an owner.
     * @param  owner_  The bond owner.
     * @return payout_ The total PARS redeemed.
     */
    function redeemAll(address owner_) external override nonReentrant returns (uint256 payout_) {
        Note[] storage ownerNotes = notes[owner_];

        for (uint256 i = 0; i < ownerNotes.length; i++) {
            Note storage note = ownerNotes[i];

            if (note.payout == 0) continue;
            if (block.timestamp < note.matured) continue;

            uint256 amount = note.payout - note.redeemed;
            if (amount == 0) continue;

            note.redeemed = note.payout;
            payout_ += amount;

            emit BondRedeemed(owner_, i, amount);
        }

        if (payout_ == 0) revert BondTeller_NothingToRedeem();

        totalPaidOut += payout_;
        pars.safeTransfer(owner_, payout_);
    }

    // =========  VIEW FUNCTIONS ========= //

    /**
     * @notice Get bond indexes for an owner.
     * @param  owner_ The bond owner.
     * @return The array of indexes.
     */
    function indexesFor(address owner_) external view override returns (uint256[] memory) {
        Note[] memory ownerNotes = notes[owner_];
        uint256[] memory indexes = new uint256[](ownerNotes.length);

        for (uint256 i = 0; i < ownerNotes.length; i++) {
            indexes[i] = i;
        }

        return indexes;
    }

    /**
     * @notice Get pending payout for a specific bond.
     * @param  owner_ The bond owner.
     * @param  index_ The bond index.
     * @return The pending payout amount.
     */
    function pendingFor(
        address owner_,
        uint256 index_
    ) external view override returns (uint256) {
        if (index_ >= notes[owner_].length) return 0;

        Note memory note = notes[owner_][index_];

        if (block.timestamp < note.matured) return 0;

        return note.payout - note.redeemed;
    }

    /**
     * @notice Get total pending payout for an owner.
     * @param  owner_ The bond owner.
     * @return Total pending payout.
     */
    function totalPendingFor(address owner_) external view returns (uint256) {
        Note[] memory ownerNotes = notes[owner_];
        uint256 total = 0;

        for (uint256 i = 0; i < ownerNotes.length; i++) {
            if (block.timestamp >= ownerNotes[i].matured) {
                total += ownerNotes[i].payout - ownerNotes[i].redeemed;
            }
        }

        return total;
    }

    /**
     * @notice Get the number of bonds for an owner.
     * @param  owner_ The bond owner.
     * @return The bond count.
     */
    function bondCount(address owner_) external view returns (uint256) {
        return notes[owner_].length;
    }

    /**
     * @notice Get a bond note.
     * @param  owner_ The bond owner.
     * @param  index_ The bond index.
     * @return The note struct.
     */
    function getNote(address owner_, uint256 index_) external view returns (Note memory) {
        return notes[owner_][index_];
    }

    /**
     * @notice Get all notes for an owner.
     * @param  owner_ The bond owner.
     * @return The array of notes.
     */
    function getNotes(address owner_) external view returns (Note[] memory) {
        return notes[owner_];
    }

    /**
     * @notice Get active (unredeemed) bonds for an owner.
     * @param  owner_ The bond owner.
     * @return Active note indexes.
     */
    function activeIndexesFor(address owner_) external view returns (uint256[] memory) {
        Note[] memory ownerNotes = notes[owner_];

        // Count active
        uint256 count = 0;
        for (uint256 i = 0; i < ownerNotes.length; i++) {
            if (ownerNotes[i].payout > ownerNotes[i].redeemed) {
                count++;
            }
        }

        // Populate
        uint256[] memory indexes = new uint256[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < ownerNotes.length; i++) {
            if (ownerNotes[i].payout > ownerNotes[i].redeemed) {
                indexes[j++] = i;
            }
        }

        return indexes;
    }

    // =========  ADMIN ========= //

    /**
     * @notice Set the depository contract.
     * @param  depository_ The depository address.
     */
    function setDepository(address depository_) external {
        // In a full implementation, this would be permissioned
        depository = IBondDepository(depository_);
    }
}
