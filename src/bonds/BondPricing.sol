// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import {IBondPricing, IBondDepository} from "../interfaces/IBonds.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title  Pars Bond Pricing
 * @author Pars Protocol
 * @notice Price oracle for the Pars bonding system.
 * @dev    Qeymat Oraghe (قیمت اوراقه) = Bond Pricing in Persian
 *
 *         The Bond Pricing contract:
 *         - Provides PARS price feeds for bond markets
 *         - Calculates discounts based on market conditions
 *         - Integrates with external oracles
 *         - Supports multiple quote tokens
 */
contract BondPricing is IBondPricing, AccessControl {
    // =========  ERRORS ========= //

    error BondPricing_InvalidPrice();
    error BondPricing_StalePrice();
    error BondPricing_UnsupportedToken();

    // =========  EVENTS ========= //

    event PriceUpdated(address indexed token, uint256 price, uint256 timestamp);
    event OracleUpdated(address indexed token, address indexed oracle);

    // =========  ROLES ========= //

    /// @notice Role for updating prices.
    bytes32 public constant PRICE_UPDATER_ROLE = keccak256("PRICE_UPDATER_ROLE");

    // =========  CONSTANTS ========= //

    /// @notice Price precision (18 decimals).
    uint256 public constant PRICE_PRECISION = 1e18;

    /// @notice Maximum price staleness (1 hour).
    uint256 public constant MAX_STALENESS = 1 hours;

    /// @notice Maximum discount (30% in basis points).
    uint256 public constant MAX_DISCOUNT_BPS = 3000;

    /// @notice Basis points precision.
    uint256 public constant BPS_PRECISION = 10_000;

    // =========  STRUCTS ========= //

    /// @notice Price data for a quote token.
    struct PriceData {
        uint256 price;       // PARS price in quote token (scaled by PRICE_PRECISION)
        uint256 timestamp;   // Last update timestamp
        address oracle;      // Optional Chainlink oracle address
    }

    // =========  STATE ========= //

    /// @notice Bond depository contract.
    IBondDepository public depository;

    /// @notice Mapping of quote token to price data.
    mapping(address => PriceData) public prices;

    /// @notice Array of supported quote tokens.
    address[] public supportedTokens;

    /// @notice Mapping of token to supported status.
    mapping(address => bool) public isSupported;

    // =========  CONSTRUCTOR ========= //

    /**
     * @notice Construct a new Bond Pricing contract.
     * @param  admin_ The initial admin address.
     */
    constructor(address admin_) {
        require(admin_ != address(0), "BondPricing: invalid admin");

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(PRICE_UPDATER_ROLE, admin_);
    }

    // =========  PRICE FUNCTIONS ========= //

    /**
     * @notice Get the current PARS price in a quote token.
     * @dev    Qeymat Konuni (قیمت کنونی) = Current Price in Persian
     * @param  quoteToken_ The quote token address.
     * @return The PARS price (scaled by PRICE_PRECISION).
     */
    function currentPrice(address quoteToken_) external view override returns (uint256) {
        if (!isSupported[quoteToken_]) revert BondPricing_UnsupportedToken();

        PriceData memory data = prices[quoteToken_];

        // Check staleness
        if (block.timestamp - data.timestamp > MAX_STALENESS) {
            revert BondPricing_StalePrice();
        }

        return data.price;
    }

    /**
     * @notice Get the market price for a bond market.
     * @dev    Returns the price from the depository.
     * @param  marketId_ The market ID.
     * @return The market price.
     */
    function marketPrice(uint256 marketId_) external view override returns (uint256) {
        return depository.marketPrice(marketId_);
    }

    /**
     * @notice Calculate the discount for a bond purchase.
     * @dev    Takhfif (تخفیف) = Discount in Persian
     *         Discount = (marketPrice - spotPrice) / spotPrice
     * @param  marketId_ The market ID.
     * @return The discount in basis points.
     */
    function discount(uint256 marketId_) external view override returns (uint256) {
        // Get market info
        IBondDepository.Market memory market = _getMarket(marketId_);

        address quoteToken = address(market.quoteToken);
        if (!isSupported[quoteToken]) return 0;

        PriceData memory data = prices[quoteToken];
        if (block.timestamp - data.timestamp > MAX_STALENESS) return 0;

        uint256 bondPrice = depository.marketPrice(marketId_);
        uint256 spotPrice = data.price;

        // If bond is more expensive than spot, no discount
        if (bondPrice >= spotPrice) return 0;

        // Calculate discount
        // discount = (spotPrice - bondPrice) * BPS_PRECISION / spotPrice
        uint256 discountBps = ((spotPrice - bondPrice) * BPS_PRECISION) / spotPrice;

        // Cap at maximum discount
        return discountBps > MAX_DISCOUNT_BPS ? MAX_DISCOUNT_BPS : discountBps;
    }

    // =========  ADMIN FUNCTIONS ========= //

    /**
     * @notice Update the price for a quote token.
     * @param  quoteToken_ The quote token address.
     * @param  price_      The new price (scaled by PRICE_PRECISION).
     */
    function updatePrice(
        address quoteToken_,
        uint256 price_
    ) external onlyRole(PRICE_UPDATER_ROLE) {
        if (price_ == 0) revert BondPricing_InvalidPrice();

        prices[quoteToken_] = PriceData({
            price: price_,
            timestamp: block.timestamp,
            oracle: prices[quoteToken_].oracle
        });

        emit PriceUpdated(quoteToken_, price_, block.timestamp);
    }

    /**
     * @notice Add a supported quote token.
     * @param  quoteToken_ The quote token address.
     * @param  initialPrice_ The initial price.
     */
    function addSupportedToken(
        address quoteToken_,
        uint256 initialPrice_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(quoteToken_ != address(0), "BondPricing: invalid token");
        require(!isSupported[quoteToken_], "BondPricing: already supported");
        require(initialPrice_ > 0, "BondPricing: invalid price");

        isSupported[quoteToken_] = true;
        supportedTokens.push(quoteToken_);

        prices[quoteToken_] = PriceData({
            price: initialPrice_,
            timestamp: block.timestamp,
            oracle: address(0)
        });

        emit PriceUpdated(quoteToken_, initialPrice_, block.timestamp);
    }

    /**
     * @notice Remove a supported quote token.
     * @param  quoteToken_ The quote token address.
     */
    function removeSupportedToken(address quoteToken_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isSupported[quoteToken_], "BondPricing: not supported");

        isSupported[quoteToken_] = false;

        // Remove from array
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (supportedTokens[i] == quoteToken_) {
                supportedTokens[i] = supportedTokens[supportedTokens.length - 1];
                supportedTokens.pop();
                break;
            }
        }

        delete prices[quoteToken_];
    }

    /**
     * @notice Set the Chainlink oracle for a token.
     * @param  quoteToken_ The quote token address.
     * @param  oracle_     The oracle address.
     */
    function setOracle(
        address quoteToken_,
        address oracle_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isSupported[quoteToken_], "BondPricing: not supported");

        prices[quoteToken_].oracle = oracle_;

        emit OracleUpdated(quoteToken_, oracle_);
    }

    /**
     * @notice Set the bond depository.
     * @param  depository_ The depository address.
     */
    function setDepository(address depository_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(depository_ != address(0), "BondPricing: invalid depository");
        depository = IBondDepository(depository_);
    }

    // =========  VIEW FUNCTIONS ========= //

    /**
     * @notice Get all supported tokens.
     * @return The array of supported token addresses.
     */
    function getSupportedTokens() external view returns (address[] memory) {
        return supportedTokens;
    }

    /**
     * @notice Get the number of supported tokens.
     * @return The count.
     */
    function supportedTokenCount() external view returns (uint256) {
        return supportedTokens.length;
    }

    /**
     * @notice Get price data for a token.
     * @param  quoteToken_ The quote token address.
     * @return The price data.
     */
    function getPriceData(address quoteToken_) external view returns (PriceData memory) {
        return prices[quoteToken_];
    }

    /**
     * @notice Check if a price is stale.
     * @param  quoteToken_ The quote token address.
     * @return Whether the price is stale.
     */
    function isPriceStale(address quoteToken_) external view returns (bool) {
        return block.timestamp - prices[quoteToken_].timestamp > MAX_STALENESS;
    }

    // =========  INTERNAL ========= //

    function _getMarket(uint256 marketId_) internal view returns (IBondDepository.Market memory) {
        // Note: This requires the depository to expose getMarket()
        // In the actual implementation, we'd call depository.getMarket(marketId_)
        // For now, return empty struct
        return IBondDepository.Market({
            capacity: 0,
            quoteToken: IERC20(address(0)),
            capacityInQuote: false,
            totalDebt: 0,
            maxPayout: 0,
            sold: 0,
            purchased: 0
        });
    }
}

// Import for Market struct
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
