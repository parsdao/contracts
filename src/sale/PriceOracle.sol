// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IPriceOracle} from "../interfaces/ISale.sol";

/**
 * @title  PriceOracle
 * @author Pars Protocol
 * @notice Admin-updated price oracle for converting deposit asset amounts to BTC satoshis.
 * @dev    Prices are stored as satoshis per 1 whole unit of the asset.
 *         For example, if ETH = 50 BTC and 1 BTC = 1e8 sats, then
 *         ETH price = 50 * 1e8 = 5_000_000_000 sats per 1 ETH.
 *
 *         Supported assets and their native decimals:
 *         - BTC:  8 decimals (satoshis)
 *         - ETH:  18 decimals
 *         - SOL:  9 decimals
 *         - TON:  9 decimals
 *         - XRP:  6 decimals
 *         - LUX:  18 decimals (EVM-native)
 *         - PARS: 18 decimals (EVM-native)
 */
contract PriceOracle is AccessControl, IPriceOracle {
    // =========  ROLES ========= //

    /// @notice Role for addresses that can update prices.
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    // =========  ERRORS ========= //

    error PriceOracle_InvalidPrice();
    error PriceOracle_PriceNotSet(uint8 chain);

    // =========  STATE ========= //

    /// @notice Price of each asset in satoshis per 1 whole unit.
    /// @dev    Indexed by SourceChain enum value.
    mapping(uint8 => uint256) public prices;

    /// @notice Timestamp of last price update per chain.
    mapping(uint8 => uint256) public lastUpdated;

    // =========  EVENTS ========= //

    event PriceUpdated(uint8 indexed chain, uint256 priceInSats, uint256 timestamp);

    // =========  CONSTRUCTOR ========= //

    /**
     * @notice Construct a new PriceOracle.
     * @param  admin_ The initial admin and oracle address.
     */
    constructor(address admin_) {
        require(admin_ != address(0), "PriceOracle: invalid admin");

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(ORACLE_ROLE, admin_);
    }

    // =========  ORACLE FUNCTIONS ========= //

    /**
     * @notice Set the price of an asset in satoshis per 1 whole unit.
     * @dev    Only callable by addresses with ORACLE_ROLE.
     *         BTC price is always 1e8 (1 BTC = 100,000,000 sats).
     * @param  chain       The source chain enum value (0-6).
     * @param  priceInSats Price in satoshis per 1 whole unit of the asset.
     */
    function setPrice(uint8 chain, uint256 priceInSats) external onlyRole(ORACLE_ROLE) {
        if (priceInSats == 0) revert PriceOracle_InvalidPrice();
        if (chain > 6) revert PriceOracle_PriceNotSet(chain);

        prices[chain] = priceInSats;
        lastUpdated[chain] = block.timestamp;

        emit PriceUpdated(chain, priceInSats, block.timestamp);
    }

    /**
     * @notice Batch-set prices for multiple assets.
     * @param  chains       Array of chain enum values.
     * @param  pricesInSats Array of prices in satoshis.
     */
    function setPrices(
        uint8[] calldata chains,
        uint256[] calldata pricesInSats
    ) external onlyRole(ORACLE_ROLE) {
        require(chains.length == pricesInSats.length, "PriceOracle: length mismatch");

        for (uint256 i = 0; i < chains.length; i++) {
            if (pricesInSats[i] == 0) revert PriceOracle_InvalidPrice();
            if (chains[i] > 6) revert PriceOracle_PriceNotSet(chains[i]);

            prices[chains[i]] = pricesInSats[i];
            lastUpdated[chains[i]] = block.timestamp;

            emit PriceUpdated(chains[i], pricesInSats[i], block.timestamp);
        }
    }

    // =========  VIEW FUNCTIONS ========= //

    /**
     * @notice Get the price of an asset in satoshis per 1 whole unit.
     * @param  chain The source chain enum value.
     * @return Price in satoshis per 1 whole unit.
     */
    function getPrice(uint8 chain) external view override returns (uint256) {
        uint256 price = prices[chain];
        if (price == 0) revert PriceOracle_PriceNotSet(chain);
        return price;
    }

    /**
     * @notice Convert an asset amount to BTC satoshi equivalent.
     * @dev    Formula: sats = amount * priceInSats / (10 ** decimals)
     *         Example: 1.5 ETH (1.5e18 wei) at 50 BTC/ETH (5e9 sats/ETH):
     *                  sats = 1.5e18 * 5e9 / 1e18 = 7.5e9 = 7,500,000,000 sats = 75 BTC
     * @param  chain    The source chain enum value.
     * @param  amount   The raw amount in the asset's native decimals.
     * @param  decimals The number of decimals for the asset.
     * @return Equivalent value in BTC satoshis.
     */
    function convertToSats(
        uint8 chain,
        uint256 amount,
        uint8 decimals
    ) external view override returns (uint256) {
        uint256 price = prices[chain];
        if (price == 0) revert PriceOracle_PriceNotSet(chain);

        return (amount * price) / (10 ** decimals);
    }
}
