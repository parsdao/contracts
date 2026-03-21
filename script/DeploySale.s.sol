// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {PriceOracle} from "../src/sale/PriceOracle.sol";
import {SaleConfig} from "../src/sale/SaleConfig.sol";
import {DepositVerifier} from "../src/sale/DepositVerifier.sol";

/**
 * @title  DeploySale
 * @author Pars Protocol
 * @notice Deployment script for the multi-chain deposit verifier sale system.
 * @dev    Deploys PriceOracle, SaleConfig, and DepositVerifier.
 *         Sets initial approximate prices and configures CYRUS as mint token.
 *
 *         Prerequisites:
 *         - CYRUS or MIGA token deployed and address known
 *         - PRIVATE_KEY env var set
 *         - SALE_TOKEN env var set to CYRUS or MIGA address
 *
 *         Usage:
 *         ```
 *         PRIVATE_KEY=0x... SALE_TOKEN=0x... \
 *           forge script script/DeploySale.s.sol:DeploySale --rpc-url $RPC_URL --broadcast
 *         ```
 *
 *         Post-deployment:
 *         - Grant DepositVerifier minting authority on the sale token
 *           (vault role for ASHA, BRIDGE_ROLE for MIGA)
 *         - Transfer RELAYER_ROLE to the actual relay address
 *         - Set sale start/end timestamps
 */
contract DeploySale is Script {
    // =========  APPROXIMATE PRICES (March 2026) ========= //
    // Prices in satoshis per 1 whole unit of the asset.

    /// @notice 1 BTC = 100,000,000 sats (identity)
    uint256 public constant BTC_PRICE = 100_000_000;

    /// @notice 1 ETH ~ 0.038 BTC = 3,800,000 sats
    uint256 public constant ETH_PRICE = 3_800_000;

    /// @notice 1 SOL ~ 0.0018 BTC = 180,000 sats
    uint256 public constant SOL_PRICE = 180_000;

    /// @notice 1 TON ~ 0.00005 BTC = 5,000 sats
    uint256 public constant TON_PRICE = 5_000;

    /// @notice 1 XRP ~ 0.000025 BTC = 2,500 sats
    uint256 public constant XRP_PRICE = 2_500;

    /// @notice 1 LUX ~ 0.0005 BTC = 50,000 sats
    uint256 public constant LUX_PRICE = 50_000;

    /// @notice 1 PARS ~ 0.00001 BTC = 1,000 sats
    uint256 public constant PARS_PRICE = 1_000;

    /// @notice Default sats per token rate (1 token = 100 sats)
    uint256 public constant DEFAULT_SATS_PER_TOKEN = 100;

    // =========  DEPLOYED CONTRACTS ========= //

    PriceOracle public oracle;
    SaleConfig public config;
    DepositVerifier public verifier;

    // =========  DEPLOYMENT ========= //

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address saleToken = vm.envAddress("SALE_TOKEN");

        console2.log("Deploying Sale contracts...");
        console2.log("Deployer:", deployer);
        console2.log("Sale Token:", saleToken);
        console2.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy PriceOracle
        oracle = new PriceOracle(deployer);
        console2.log("PriceOracle deployed:", address(oracle));

        // 2. Deploy SaleConfig
        config = new SaleConfig(deployer);
        console2.log("SaleConfig deployed:", address(config));

        // 3. Deploy DepositVerifier
        verifier = new DepositVerifier(
            deployer,
            address(config),
            saleToken,
            DEFAULT_SATS_PER_TOKEN
        );
        console2.log("DepositVerifier deployed:", address(verifier));

        // 4. Configure SaleConfig
        config.setSaleToken(saleToken);
        config.setDepositVerifier(address(verifier));

        // 5. Set initial prices
        oracle.setPrice(0, BTC_PRICE);   // BTC
        oracle.setPrice(1, ETH_PRICE);   // ETH
        oracle.setPrice(2, SOL_PRICE);   // SOL
        oracle.setPrice(3, TON_PRICE);   // TON
        oracle.setPrice(4, XRP_PRICE);   // XRP
        oracle.setPrice(5, LUX_PRICE);   // LUX
        oracle.setPrice(6, PARS_PRICE);  // PARS

        vm.stopBroadcast();

        // Log deployment summary
        console2.log("\n=== Sale Deployment Summary ===");
        console2.log("PriceOracle:     ", address(oracle));
        console2.log("SaleConfig:      ", address(config));
        console2.log("DepositVerifier: ", address(verifier));
        console2.log("Sale Token:      ", saleToken);
        console2.log("Sats/Token:      ", DEFAULT_SATS_PER_TOKEN);
        console2.log("\nPost-deployment steps:");
        console2.log("1. Grant DepositVerifier minting authority on sale token");
        console2.log("2. Transfer RELAYER_ROLE to actual relay address");
        console2.log("3. Set sale start/end timestamps via SaleConfig");
    }
}
