// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import {Script, console2} from "forge-std/Script.sol";
import {Kernel} from "../src/Kernel.sol";
import {PARS} from "../src/tokens/PARS.sol";
import {xPARS} from "../src/tokens/xPARS.sol";
import {vePARS} from "../src/tokens/vePARS.sol";
import {MIGA} from "../src/tokens/MIGA.sol";
import {Treasury} from "../src/treasury/Treasury.sol";
import {FeeRouter} from "../src/treasury/FeeRouter.sol";
import {Charter} from "../src/governance/Charter.sol";

/**
 * @title  Pars Protocol Deployment Script
 * @author Pars Protocol
 * @notice Deployment script for the Pars Protocol contracts.
 * @dev    Deploys all core contracts for the Pars Network (Chain ID: 6133).
 *
 *         Deployment order:
 *         1. Kernel - Central registry
 *         2. Authority - Permission management
 *         3. PARS - Governance token
 *         4. xPARS - Staked token
 *         5. vePARS - Vote-escrow token
 *         6. MIGA - Bridged token
 *         7. Treasury - Reserve management
 *         8. FeeRouter - Fee distribution
 *         9. Charter - Governance parameters
 *
 *         Usage:
 *         ```
 *         forge script script/Deploy.s.sol:DeployPars --rpc-url $RPC_URL --broadcast
 *         ```
 */
contract DeployPars is Script {
    // =========  CONFIGURATION ========= //

    /// @notice Pars Network Chain ID.
    uint256 public constant PARS_CHAIN_ID = 6133;

    /// @notice Initial voting delay (1 day at 2s blocks).
    uint256 public constant INITIAL_VOTING_DELAY = 43_200;

    /// @notice Initial voting period (3 days).
    uint256 public constant INITIAL_VOTING_PERIOD = 129_600;

    /// @notice Initial proposal threshold (0.1% of supply).
    uint256 public constant INITIAL_PROPOSAL_THRESHOLD = 100_000;

    /// @notice Initial quorum (20% of supply).
    uint256 public constant INITIAL_QUORUM = 20_000_000;

    /// @notice Initial approval threshold (60%).
    uint256 public constant INITIAL_APPROVAL_THRESHOLD = 60_000_000;

    /// @notice Initial timelock delay (2 days).
    uint256 public constant INITIAL_TIMELOCK_DELAY = 2 days;

    // =========  DEPLOYED CONTRACTS ========= //

    Kernel public kernel;
    ParsAuthority public authority;
    PARS public pars;
    xPARS public xpars;
    vePARS public vepars;
    MIGA public miga;
    Treasury public treasury;
    FeeRouter public feeRouter;
    Charter public charter;

    // =========  DEPLOYMENT ========= //

    function run() external {
        // Get deployer
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("Deploying Pars Protocol contracts...");
        console2.log("Deployer:", deployer);
        console2.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Kernel
        kernel = new Kernel();
        console2.log("Kernel deployed:", address(kernel));

        // 2. Deploy Authority
        authority = new ParsAuthority(deployer, deployer, deployer, deployer);
        console2.log("Authority deployed:", address(authority));

        // 3. Deploy PARS token
        pars = new PARS(address(authority));
        console2.log("PARS deployed:", address(pars));

        // 4. Deploy Staking (placeholder for xPARS)
        // Note: xPARS requires staking contract, deploy a placeholder first
        address stakingPlaceholder = deployer; // Temporary
        xpars = new xPARS(address(pars), stakingPlaceholder);
        console2.log("xPARS deployed:", address(xpars));

        // 5. Deploy vePARS
        vepars = new vePARS(address(xpars));
        console2.log("vePARS deployed:", address(vepars));

        // 6. Deploy MIGA (bridged token)
        miga = new MIGA(deployer);
        console2.log("MIGA deployed:", address(miga));

        // 7. Deploy Treasury
        treasury = new Treasury(kernel);
        console2.log("Treasury deployed:", address(treasury));

        // 8. Deploy FeeRouter
        feeRouter = new FeeRouter(deployer);
        console2.log("FeeRouter deployed:", address(feeRouter));

        // 9. Deploy Charter
        charter = new Charter(
            deployer,
            INITIAL_VOTING_DELAY,
            INITIAL_VOTING_PERIOD,
            INITIAL_PROPOSAL_THRESHOLD,
            INITIAL_QUORUM,
            INITIAL_APPROVAL_THRESHOLD,
            INITIAL_TIMELOCK_DELAY
        );
        console2.log("Charter deployed:", address(charter));

        vm.stopBroadcast();

        // Log deployment summary
        console2.log("\n=== Deployment Summary ===");
        console2.log("Kernel:    ", address(kernel));
        console2.log("Authority: ", address(authority));
        console2.log("PARS:      ", address(pars));
        console2.log("xPARS:     ", address(xpars));
        console2.log("vePARS:    ", address(vepars));
        console2.log("MIGA:      ", address(miga));
        console2.log("Treasury:  ", address(treasury));
        console2.log("FeeRouter: ", address(feeRouter));
        console2.log("Charter:   ", address(charter));
    }
}

/**
 * @notice Pars Authority implementation for deployment.
 */
contract ParsAuthority {
    address private _governor;
    address private _guardian;
    address private _policy;
    address private _vault;

    constructor(
        address governor_,
        address guardian_,
        address policy_,
        address vault_
    ) {
        _governor = governor_;
        _guardian = guardian_;
        _policy = policy_;
        _vault = vault_;
    }

    function governor() external view returns (address) {
        return _governor;
    }

    function guardian() external view returns (address) {
        return _guardian;
    }

    function policy() external view returns (address) {
        return _policy;
    }

    function vault() external view returns (address) {
        return _vault;
    }

    function setGovernor(address newGovernor) external {
        require(msg.sender == _governor, "Authority: not governor");
        _governor = newGovernor;
    }

    function setGuardian(address newGuardian) external {
        require(msg.sender == _governor, "Authority: not governor");
        _guardian = newGuardian;
    }

    function setPolicy(address newPolicy) external {
        require(msg.sender == _governor, "Authority: not governor");
        _policy = newPolicy;
    }

    function setVault(address newVault) external {
        require(msg.sender == _governor, "Authority: not governor");
        _vault = newVault;
    }
}
