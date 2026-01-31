// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IBondDepository, IBondTeller} from "../interfaces/IBonds.sol";
import {Kernel, Policy, Keycode, toKeycode, Permissions} from "../Kernel.sol";

/**
 * @title  Pars Bond Depository
 * @author Pars Protocol
 * @notice Manages bond markets for the Pars Protocol.
 * @dev    Oraghe Forushi (اوراقه فروشی) = Bond Depository in Persian
 *
 *         The Bond Depository:
 *         - Creates and manages bond markets
 *         - Accepts quote tokens for discounted PARS
 *         - Uses Sequential Dutch Auction (SDA) pricing
 *         - Supports multiple concurrent markets
 *
 *         Based on Olympus Bond system with Pars adaptations.
 */
contract BondDepository is IBondDepository, Policy, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =========  ERRORS ========= //

    error BondDepository_MarketNotActive();
    error BondDepository_MaxPriceExceeded();
    error BondDepository_MaxPayoutExceeded();
    error BondDepository_ZeroAmount();
    error BondDepository_InvalidParams();
    error BondDepository_OnlyMarketOwner();
    error BondDepository_MarketConcluded();

    // =========  EVENTS ========= //

    event MarketCreated(
        uint256 indexed id,
        address indexed quoteToken,
        uint256 capacity,
        uint256 initialPrice
    );
    event MarketClosed(uint256 indexed id);
    event BondPurchased(
        uint256 indexed id,
        address indexed depositor,
        uint256 amount,
        uint256 payout,
        uint256 price
    );

    // =========  CONSTANTS ========= //

    /// @notice Precision for price calculations.
    uint256 public constant PRICE_DECIMALS = 36;

    /// @notice Minimum market duration (1 day).
    uint256 public constant MIN_MARKET_DURATION = 1 days;

    /// @notice Maximum discount (30%).
    uint256 public constant MAX_DISCOUNT = 3000; // 30% in basis points

    // =========  STATE ========= //

    /// @notice PARS token address.
    IERC20 public immutable pars;

    /// @notice Bond teller contract.
    IBondTeller public teller;

    /// @notice Mapping of market ID to Market.
    mapping(uint256 => Market) public markets;

    /// @notice Mapping of market ID to Terms.
    mapping(uint256 => Terms) public terms;

    /// @notice Mapping of market ID to Metadata.
    mapping(uint256 => Metadata) public metadata;

    /// @notice Mapping of market ID to owner.
    mapping(uint256 => address) public marketOwner;

    /// @notice Total number of markets created.
    uint256 public marketCount;

    // =========  CONSTRUCTOR ========= //

    /**
     * @notice Construct a new Bond Depository.
     * @param  kernel_ The kernel contract address.
     * @param  pars_   The PARS token address.
     */
    constructor(Kernel kernel_, address pars_) Policy(kernel_) {
        require(pars_ != address(0), "BondDepository: invalid PARS");
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

    // =========  MARKET CREATION ========= //

    /**
     * @notice Create a new bond market.
     * @dev    Ijad Bazar (ایجاد بازار) = Create Market in Persian
     */
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
    ) external override returns (uint256 id_) {
        // Validate parameters
        if (address(quoteToken_) == address(0)) revert BondDepository_InvalidParams();
        if (capacity_ == 0) revert BondDepository_InvalidParams();
        if (conclusion_ <= block.timestamp + MIN_MARKET_DURATION) revert BondDepository_InvalidParams();
        if (initialPrice_ == 0) revert BondDepository_InvalidParams();
        if (vesting_ == 0) revert BondDepository_InvalidParams();

        id_ = marketCount++;

        // Set market
        markets[id_] = Market({
            capacity: capacity_,
            quoteToken: quoteToken_,
            capacityInQuote: capacityInQuote_,
            totalDebt: 0,
            maxPayout: maxPayout_,
            sold: 0,
            purchased: 0
        });

        // Set terms
        terms[id_] = Terms({
            fixedTerm: fixedTerm_,
            controlVariable: initialPrice_,
            vesting: vesting_,
            conclusion: conclusion_,
            maxDebt: maxDebt_
        });

        // Set metadata
        metadata[id_] = Metadata({
            lastTune: block.timestamp,
            lastDecay: block.timestamp,
            length: conclusion_ - block.timestamp,
            depositInterval: depositInterval_,
            tuneInterval: tuneInterval_,
            tuneAdjustmentDelay: 0,
            debtDecayInterval: 0,
            tuneIntervalCapacity: 0,
            tuneBelowCapacity: 0,
            lastTuneDebt: 0
        });

        // Set owner
        marketOwner[id_] = msg.sender;

        emit MarketCreated(id_, address(quoteToken_), capacity_, initialPrice_);
    }

    /**
     * @notice Close a bond market.
     * @dev    Bastan Bazar (بستن بازار) = Close Market in Persian
     * @param  id_ The market ID.
     */
    function close(uint256 id_) external override {
        if (msg.sender != marketOwner[id_]) revert BondDepository_OnlyMarketOwner();

        terms[id_].conclusion = block.timestamp;
        markets[id_].capacity = 0;

        emit MarketClosed(id_);
    }

    // =========  BOND PURCHASE ========= //

    /**
     * @notice Purchase a bond.
     * @dev    Kharid Oraghe (خرید اوراقه) = Bond Purchase in Persian
     * @param  id_        The market ID.
     * @param  amount_    The amount of quote token to spend.
     * @param  maxPrice_  Maximum acceptable price.
     * @param  depositor_ The address to receive the bond.
     * @param  referrer_  Optional referrer address.
     * @return payout_    The PARS payout amount.
     * @return expiry_    The bond expiry timestamp.
     * @return index_     The bond index for the depositor.
     */
    function deposit(
        uint256 id_,
        uint256 amount_,
        uint256 maxPrice_,
        address depositor_,
        address referrer_
    ) external override nonReentrant returns (uint256 payout_, uint256 expiry_, uint256 index_) {
        if (amount_ == 0) revert BondDepository_ZeroAmount();
        if (!isLive(id_)) revert BondDepository_MarketNotActive();

        Market storage market = markets[id_];
        Terms memory term = terms[id_];

        // Calculate payout
        uint256 price = marketPrice(id_);
        if (price > maxPrice_) revert BondDepository_MaxPriceExceeded();

        payout_ = payoutFor(amount_, id_);
        if (payout_ > market.maxPayout) revert BondDepository_MaxPayoutExceeded();

        // Update market
        market.sold += amount_;
        market.purchased += payout_;
        market.totalDebt += payout_;

        // Reduce capacity
        if (market.capacityInQuote) {
            market.capacity -= amount_;
        } else {
            market.capacity -= payout_;
        }

        // Calculate expiry
        if (term.fixedTerm) {
            expiry_ = block.timestamp + term.vesting;
        } else {
            expiry_ = term.vesting;
        }

        // Transfer quote token
        market.quoteToken.safeTransferFrom(msg.sender, address(this), amount_);

        // Create bond note via teller
        // In a full implementation, this would call teller.create()
        index_ = 0; // Placeholder

        emit BondPurchased(id_, depositor_, amount_, payout_, price);

        // Silence unused variable warning
        referrer_;
    }

    // =========  PRICING ========= //

    /**
     * @notice Get the current market price.
     * @dev    Qeymat (قیمت) = Price in Persian
     *         Uses a simplified pricing model.
     * @param  id_ The market ID.
     * @return The current price (scaled by PRICE_DECIMALS).
     */
    function marketPrice(uint256 id_) public view override returns (uint256) {
        return terms[id_].controlVariable;
    }

    /**
     * @notice Get the payout for a given amount.
     * @dev    Pardakht (پرداخت) = Payout in Persian
     * @param  amount_ The quote token amount.
     * @param  id_     The market ID.
     * @return The PARS payout amount.
     */
    function payoutFor(uint256 amount_, uint256 id_) public view override returns (uint256) {
        uint256 price = marketPrice(id_);
        // payout = amount * 10^PRICE_DECIMALS / price
        return (amount_ * 10**PRICE_DECIMALS) / price;
    }

    // =========  VIEW FUNCTIONS ========= //

    /**
     * @notice Check if a market is active.
     * @dev    Fa'al (فعال) = Active in Persian
     * @param  id_ The market ID.
     * @return Whether the market is live.
     */
    function isLive(uint256 id_) public view override returns (bool) {
        Terms memory term = terms[id_];
        Market memory market = markets[id_];

        return (
            block.timestamp < term.conclusion &&
            market.capacity > 0 &&
            market.totalDebt < term.maxDebt
        );
    }

    /**
     * @notice Get market info.
     * @param  id_ The market ID.
     * @return The market struct.
     */
    function getMarket(uint256 id_) external view returns (Market memory) {
        return markets[id_];
    }

    /**
     * @notice Get market terms.
     * @param  id_ The market ID.
     * @return The terms struct.
     */
    function getTerms(uint256 id_) external view returns (Terms memory) {
        return terms[id_];
    }

    /**
     * @notice Get all active markets.
     * @return ids The active market IDs.
     */
    function liveMarkets() external view returns (uint256[] memory ids) {
        uint256 count = 0;

        // First, count active markets
        for (uint256 i = 0; i < marketCount; i++) {
            if (isLive(i)) count++;
        }

        // Then, populate array
        ids = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < marketCount; i++) {
            if (isLive(i)) {
                ids[index++] = i;
            }
        }
    }

    // =========  ADMIN ========= //

    /**
     * @notice Set the teller contract.
     * @param  teller_ The teller address.
     */
    function setTeller(address teller_) external {
        // In a full implementation, this would be permissioned
        teller = IBondTeller(teller_);
    }
}
