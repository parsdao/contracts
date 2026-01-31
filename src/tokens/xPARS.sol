// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IxPARS} from "../interfaces/IPARS.sol";

/**
 * @title  xPARS Token
 * @author Pars Protocol
 * @notice Staked PARS token with rebasing mechanism.
 * @dev    xPARS represents staked PARS that accrues rebase rewards over time.
 *         The rebase mechanism distributes protocol profits to stakers by
 *         increasing the index, which increases the PARS value of each xPARS.
 *
 *         xPARS = Staked Pars
 *         Equivalent to sOHM in Olympus
 *
 *         Key mechanics:
 *         - Index starts at 1e18 and increases with each rebase
 *         - xPARS balance * index / 1e18 = underlying PARS value
 *         - Rebases happen periodically (every epoch)
 */
contract xPARS is ERC20, ERC20Permit, IxPARS {
    using SafeERC20 for IERC20;

    // =========  ERRORS ========= //

    error xPARS_OnlyStaking();
    error xPARS_InvalidAmount();
    error xPARS_RebaseOverflow();

    // =========  STATE ========= //

    /// @notice The PARS token contract.
    IERC20 public immutable pars;

    /// @notice The staking contract that manages deposits/withdrawals.
    address public staking;

    /// @notice The rebase index (starts at 1e18).
    /// @dev    Index is scaled by 1e18 for precision.
    ///         xPARS balance * index / 1e18 = PARS value
    uint256 public override index;

    /// @notice Rebases array for historical tracking.
    Rebase[] public rebases;

    /// @notice Struct to track rebase history.
    struct Rebase {
        uint256 epoch;      // Epoch number
        uint256 rebase;     // Rebase percentage (scaled by 1e18)
        uint256 totalStaked;// Total PARS staked at rebase
        uint256 index;      // Index after rebase
        uint256 timestamp;  // Block timestamp
    }

    // =========  CONSTANTS ========= //

    uint256 private constant INITIAL_INDEX = 1e18;
    uint256 private constant MAX_UINT256 = type(uint256).max;

    // =========  CONSTRUCTOR ========= //

    /**
     * @notice Construct a new xPARS token.
     * @param  pars_    The PARS token address.
     * @param  staking_ The staking contract address.
     */
    constructor(
        address pars_,
        address staking_
    ) ERC20("Staked Pars", "xPARS") ERC20Permit("Staked Pars") {
        require(pars_ != address(0), "xPARS: invalid PARS");
        require(staking_ != address(0), "xPARS: invalid staking");

        pars = IERC20(pars_);
        staking = staking_;
        index = INITIAL_INDEX;
    }

    // =========  MODIFIERS ========= //

    modifier onlyStaking() {
        if (msg.sender != staking) revert xPARS_OnlyStaking();
        _;
    }

    // =========  ERC20 OVERRIDES ========= //

    /**
     * @notice Returns the number of decimals for the token.
     * @dev    xPARS uses 9 decimals to match PARS.
     */
    function decimals() public pure override returns (uint8) {
        return 9;
    }

    // =========  STAKING FUNCTIONS ========= //

    /**
     * @notice Mint xPARS tokens during staking.
     * @dev    Called by staking contract when user stakes PARS.
     *         Calculates xPARS amount based on current index.
     * @param  to_     The address to mint to.
     * @param  amount_ The amount of xPARS to mint (in xPARS terms).
     */
    function mint(address to_, uint256 amount_) external override onlyStaking {
        if (amount_ == 0) revert xPARS_InvalidAmount();
        _mint(to_, amount_);
    }

    /**
     * @notice Burn xPARS tokens during unstaking.
     * @dev    Called by staking contract when user unstakes.
     * @param  from_   The address to burn from.
     * @param  amount_ The amount of xPARS to burn.
     */
    function burn(address from_, uint256 amount_) external override onlyStaking {
        if (amount_ == 0) revert xPARS_InvalidAmount();
        _burn(from_, amount_);
    }

    // =========  REBASE ========= //

    /**
     * @notice Trigger a rebase to distribute staking rewards.
     * @dev    Called by the distributor contract each epoch.
     *         Increases the index proportionally to profit.
     *
     *         Rebase (بازتوزیع) = Redistribution in Persian
     *
     * @param  profit_ The amount of PARS profit to distribute.
     */
    function rebase(uint256 profit_) external override onlyStaking {
        uint256 totalStaked = circulatingSupply();

        if (totalStaked == 0) {
            return; // No stakers, nothing to distribute
        }

        // Calculate rebase percentage
        // rebasePercent = profit / totalStaked
        uint256 rebasePercent = (profit_ * 1e18) / totalStaked;

        // Update index
        // newIndex = oldIndex * (1 + rebasePercent)
        uint256 newIndex = (index * (1e18 + rebasePercent)) / 1e18;

        // Overflow check
        if (newIndex < index) revert xPARS_RebaseOverflow();

        index = newIndex;

        // Record rebase for history
        rebases.push(Rebase({
            epoch: rebases.length,
            rebase: rebasePercent,
            totalStaked: totalStaked,
            index: newIndex,
            timestamp: block.timestamp
        }));
    }

    // =========  VIEW FUNCTIONS ========= //

    /**
     * @notice Convert xPARS amount to underlying PARS amount.
     * @dev    PARS = xPARS * index / 1e18
     * @param  amount_ The xPARS amount to convert.
     * @return The equivalent PARS amount.
     */
    function balanceFrom(uint256 amount_) public view override returns (uint256) {
        return (amount_ * index) / 1e18;
    }

    /**
     * @notice Convert PARS amount to xPARS amount.
     * @dev    xPARS = PARS * 1e18 / index
     * @param  amount_ The PARS amount to convert.
     * @return The equivalent xPARS amount.
     */
    function balanceTo(uint256 amount_) public view override returns (uint256) {
        return (amount_ * 1e18) / index;
    }

    /**
     * @notice Get the circulating supply of xPARS in PARS terms.
     * @dev    Returns total xPARS supply converted to PARS value.
     * @return The circulating supply in PARS.
     */
    function circulatingSupply() public view override returns (uint256) {
        return balanceFrom(totalSupply());
    }

    /**
     * @notice Get the number of rebases that have occurred.
     * @return The total number of rebases.
     */
    function rebaseCount() external view returns (uint256) {
        return rebases.length;
    }

    /**
     * @notice Get the rebase at a specific index.
     * @param  index_ The rebase index to retrieve.
     * @return The rebase data.
     */
    function getRebase(uint256 index_) external view returns (Rebase memory) {
        return rebases[index_];
    }

    // =========  ADMIN ========= //

    /**
     * @notice Set a new staking contract address.
     * @dev    Only callable by current staking contract.
     *         Used for migrations.
     * @param  newStaking_ The new staking contract address.
     */
    function setStaking(address newStaking_) external onlyStaking {
        require(newStaking_ != address(0), "xPARS: invalid staking");
        staking = newStaking_;
    }
}
