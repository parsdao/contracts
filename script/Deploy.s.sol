// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {Kernel, Actions} from "../src/Kernel.sol";
import {ASHA} from "../src/tokens/ASHA.sol";
import {xASHA} from "../src/tokens/xASHA.sol";
import {veASHA} from "../src/tokens/veASHA.sol";
import {Treasury} from "../src/treasury/Treasury.sol";
import {FeeRouter} from "../src/treasury/FeeRouter.sol";
import {Charter} from "../src/governance/Charter.sol";

/**
 * @title  Pars Protocol Deployment Script
 * @author Pars Protocol
 * @notice Deployment script for the Pars Protocol contracts.
 * @dev    Deploys all core contracts for the Pars Network (Chain ID: 7070).
 *
 *         Deployment order:
 *         1. Kernel - Central registry
 *         2. Authority - Permission management
 *         3. ASHA - Governance/reserve token
 *         4. xASHA - Staked token
 *         5. veASHA - Vote-escrow token
 *         6. Treasury - Reserve management
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
    uint256 public constant PARS_CHAIN_ID = 7070;

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
    ASHA public asha;
    xASHA public xasha;
    veASHA public veasha;
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

        // 3. Deploy ASHA token
        asha = new ASHA(address(authority));
        console2.log("ASHA deployed:", address(asha));

        // 4. Deploy Staking (placeholder for xASHA)
        // Note: xASHA requires staking contract, deploy a placeholder first
        address stakingPlaceholder = deployer; // Temporary
        xasha = new xASHA(address(asha), stakingPlaceholder);
        console2.log("xASHA deployed:", address(xasha));

        // 5. Deploy veASHA
        veasha = new veASHA(address(xasha));
        console2.log("veASHA deployed:", address(veasha));

        // 6. Deploy Treasury and register as kernel module
        treasury = new Treasury(kernel);
        kernel.executeAction(Actions.InstallModule, address(treasury));
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
        console2.log("ASHA:      ", address(asha));
        console2.log("xASHA:     ", address(xasha));
        console2.log("veASHA:    ", address(veasha));
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
