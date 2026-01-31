// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title  Pars Bond Interfaces
 * @author Pars Protocol
 * @notice Interfaces for the Pars bonding system.
 * @dev    Oraghe (اوراقه) = Bond in Persian
 *
 *         Bonds allow users to purchase PARS at a discount by providing
 *         liquidity or reserve assets to the protocol treasury.
 */

/**
 * @title  IBondDepository Interface
 * @notice Interface for bond market management.
 */
interface IBondDepository {
    // =========  STRUCTS ========= //

    /// @notice Bond market configuration.
    struct Market {
        uint256 capacity;        // Total capacity in payout token
        IERC20 quoteToken;       // Token accepted for payment
        bool capacityInQuote;    // Is capacity in quote or payout
        uint256 totalDebt;       // Total payout owed
        uint256 maxPayout;       // Max payout per bond
        uint256 sold;            // Quote tokens received
        uint256 purchased;       // Payout tokens purchased
    }

    /// @notice Bond term configuration.
    struct Terms {
        bool fixedTerm;          // Fixed term or fixed expiry
        uint256 controlVariable; // Price control variable
        uint256 vesting;         // Vesting length (seconds)
        uint256 conclusion;      // Market end timestamp
        uint256 maxDebt;         // Max debt at one time
    }

    /// @notice Bond market metadata.
    struct Metadata {
        uint256 lastTune;        // Last time price was tuned
        uint256 lastDecay;       // Last time debt decayed
        uint256 length;          // Market duration
        uint256 depositInterval; // Time between deposits
        uint256 tuneInterval;    // Time between price tunes
        uint256 tuneAdjustmentDelay;
        uint256 debtDecayInterval;
        uint256 tuneIntervalCapacity;
        uint256 tuneBelowCapacity;
        uint256 lastTuneDebt;
    }

    // =========  FUNCTIONS ========= //

    /// @notice Create a new bond market.
    function create(
        IERC20 quoteToken_,
        uint256 capacity_,
        bool capacityInQuote_,
        bool fixedTerm_,
        uint256 vesting_,
        uint256 conclusion_,
        uint256 initialPrice_,
        uint256 maxDebt_,
        uint256 maxPayout_,
        uint256 depositInterval_,
        uint256 tuneInterval_
    ) external returns (uint256 id_);

    /// @notice Close a bond market.
    function close(uint256 id_) external;

    /// @notice Purchase a bond.
    function deposit(
        uint256 id_,
        uint256 amount_,
        uint256 maxPrice_,
        address depositor_,
        address referrer_
    ) external returns (uint256 payout_, uint256 expiry_, uint256 index_);

    /// @notice Get the current market price.
    function marketPrice(uint256 id_) external view returns (uint256);

    /// @notice Get the current payout for an amount.
    function payoutFor(uint256 amount_, uint256 id_) external view returns (uint256);

    /// @notice Check if a market is active.
    function isLive(uint256 id_) external view returns (bool);
}

/**
 * @title  IBondTeller Interface
 * @notice Interface for bond redemption.
 */
interface IBondTeller {
    // =========  STRUCTS ========= //

    /// @notice Bond note (ownership of bond payout).
    struct Note {
        uint256 payout;          // PARS to be paid
        uint256 created;         // Creation timestamp
        uint256 matured;         // Maturity timestamp
        uint256 redeemed;        // Amount already redeemed
        uint256 marketId;        // Source market
    }

    // =========  FUNCTIONS ========= //

    /// @notice Redeem a matured bond.
    function redeem(address owner_, uint256[] memory indexes_) external returns (uint256);

    /// @notice Redeem all matured bonds for an owner.
    function redeemAll(address owner_) external returns (uint256);

    /// @notice Get bond notes for an owner.
    function indexesFor(address owner_) external view returns (uint256[] memory);

    /// @notice Get pending payout for an owner.
    function pendingFor(address owner_, uint256 index_) external view returns (uint256);
}

/**
 * @title  IBondPricing Interface
 * @notice Interface for bond price oracle.
 */
interface IBondPricing {
    /// @notice Get the current PARS price in a quote token.
    function currentPrice(address quoteToken_) external view returns (uint256);

    /// @notice Get the market price for a bond market.
    function marketPrice(uint256 marketId_) external view returns (uint256);

    /// @notice Calculate the discount for a bond purchase.
    function discount(uint256 marketId_) external view returns (uint256);
}

/**
 * @title  IBondCallback Interface
 * @notice Interface for bond purchase callbacks.
 */
interface IBondCallback {
    /// @notice Called when a bond is purchased.
    function callback(
        uint256 id_,
        uint256 inputAmount_,
        uint256 outputAmount_
    ) external;

    /// @notice Whitelist a market for callbacks.
    function whitelist(address teller_, uint256 id_) external;

    /// @notice Blacklist a market from callbacks.
    function blacklist(address teller_, uint256 id_) external;

    /// @notice Get amounts for a market.
    function amountsForMarket(uint256 id_) external view returns (uint256, uint256);
}
