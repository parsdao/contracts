// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {Kernel} from "../src/Kernel.sol";
import {ASHA} from "../src/tokens/ASHA.sol";
import {xASHA} from "../src/tokens/xASHA.sol";
import {veASHA} from "../src/tokens/veASHA.sol";
import {Treasury} from "../src/treasury/Treasury.sol";
import {FeeRouter} from "../src/treasury/FeeRouter.sol";
import {Charter} from "../src/governance/Charter.sol";

/**
 * @title  Pars Protocol CREATE2 Deployment Script
 * @author Pars Protocol
 * @notice Deterministic deployment using CREATE2 for consistent addresses across chains.
 * @dev    Uses a deployer factory (CREATE2) so contract addresses are determined by:
 *         - Deployer factory address
 *         - Salt (derived from contract name)
 *         - Contract bytecode + constructor args
 *
 *         This means the SAME addresses are produced on any EVM chain when using
 *         the same factory, salt, and constructor arguments.
 *
 *         Usage:
 *         ```
 *         forge script script/DeployCreate2.s.sol:DeployParsCreate2 \
 *             --rpc-url $RPC_URL --broadcast --verify
 *         ```
 */
contract DeployParsCreate2 is Script {
    // =========  CONFIGURATION ========= //

    /// @notice Pars Network Chain ID.
    uint256 public constant PARS_CHAIN_ID = 6133;

    /// @notice CREATE2 salt prefix for deterministic deployment.
    bytes32 public constant SALT_PREFIX = keccak256("pars.protocol.v1");

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

    // =========  CREATE2 HELPERS ========= //

    /**
     * @notice Compute a deterministic salt from a contract name.
     * @param  name The contract name.
     * @return salt The deterministic salt.
     */
    function _salt(string memory name) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(SALT_PREFIX, name));
    }

    /**
     * @notice Predict the CREATE2 address for a deployment.
     * @param  salt_     The deployment salt.
     * @param  bytecode  The creation code + constructor args.
     * @return predicted  The predicted address.
     */
    function _predictAddress(
        bytes32 salt_,
        bytes memory bytecode
    ) internal view returns (address predicted) {
        predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            salt_,
                            keccak256(bytecode)
                        )
                    )
                )
            )
        );
    }

    // =========  DEPLOYMENT ========= //

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("=== Pars Protocol CREATE2 Deployment ===");
        console2.log("Deployer:", deployer);
        console2.log("Chain ID:", block.chainid);
        console2.log("Salt prefix:", vm.toString(SALT_PREFIX));

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Kernel (CREATE2)
        kernel = new Kernel{salt: _salt("Kernel")}();
        console2.log("Kernel:", address(kernel));

        // 2. Deploy Authority (CREATE2)
        authority = new ParsAuthority{salt: _salt("Authority")}(
            deployer, deployer, deployer, deployer
        );
        console2.log("Authority:", address(authority));

        // 3. Deploy ASHA token (CREATE2)
        asha = new ASHA{salt: _salt("ASHA")}(address(authority));
        console2.log("ASHA:", address(asha));

        // 4. Deploy xASHA (CREATE2)
        xasha = new xASHA{salt: _salt("xASHA")}(address(asha), deployer);
        console2.log("xASHA:", address(xasha));

        // 5. Deploy veASHA (CREATE2)
        veasha = new veASHA{salt: _salt("veASHA")}(address(xasha));
        console2.log("veASHA:", address(veasha));

        // 6. Deploy Treasury (CREATE2)
        treasury = new Treasury{salt: _salt("Treasury")}(kernel);
        console2.log("Treasury:", address(treasury));

        // 8. Deploy FeeRouter (CREATE2)
        feeRouter = new FeeRouter{salt: _salt("FeeRouter")}(deployer);
        console2.log("FeeRouter:", address(feeRouter));

        // 9. Deploy Charter (CREATE2)
        charter = new Charter{salt: _salt("Charter")}(
            deployer,
            INITIAL_VOTING_DELAY,
            INITIAL_VOTING_PERIOD,
            INITIAL_PROPOSAL_THRESHOLD,
            INITIAL_QUORUM,
            INITIAL_APPROVAL_THRESHOLD,
            INITIAL_TIMELOCK_DELAY
        );
        console2.log("Charter:", address(charter));

        vm.stopBroadcast();

        // Log deployment summary
        console2.log("\n=== CREATE2 Deployment Summary ===");
        console2.log("All addresses are deterministic based on:");
        console2.log("  - Deployer:", deployer);
        console2.log("  - Salt prefix: pars.protocol.v1");
        console2.log("");
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

    function governor() external view returns (address) { return _governor; }
    function guardian() external view returns (address) { return _guardian; }
    function policy() external view returns (address) { return _policy; }
    function vault() external view returns (address) { return _vault; }

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
