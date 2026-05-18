// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

/**
 * @title  SaleConstants
 * @author Pars Protocol
 * @notice Shared constants for the sale subsystem.
 * @dev    Single source of truth for the source-chain enum bound used by
 *         DepositVerifier, SaleConfig, and PriceOracle. The on-chain
 *         representation is `uint8 sourceChain` valued 0..MAX_SUPPORTED_CHAIN
 *         (inclusive).
 *
 *         Supported source chains (sourceChain value -> chain):
 *           0  = BTC
 *           1  = ETH
 *           2  = SOL
 *           3  = TON
 *           4  = XRP
 *           5  = LUX
 *           6  = PARS
 *           7  = BSC
 *           8  = BASE
 *           9  = ARB
 *           10 = POLYGON
 *           11 = ZOO
 *           12 = HANZO
 */
library SaleConstants {
    /// @notice Maximum (inclusive) valid value of the source-chain enum.
    uint8 internal constant MAX_SUPPORTED_CHAIN = 12;
}
