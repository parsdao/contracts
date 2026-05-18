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
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title  Pars Protocol Local Deployment
 * @notice Deploys all core Pars contracts to local luxd dev mode (chain 96370)
 *         with mock tokens and pre-configured state for E2E testing.
 *
 *         Usage:
 *         ```
 *         lux network start --dev
 *         forge script script/DeployLocal.s.sol:DeployLocal \
 *           --rpc-url http://127.0.0.1:9650/ext/bc/C/rpc --broadcast
 *         ```
 */
contract DeployLocal is Script {
    // =========  CONSTANTS ========= //

    // luxd dev mode C-Chain ID (uses 1337 for local dev compatibility)
    uint256 public constant LOCAL_CHAIN_ID = 1337;

    // Charter governance parameters (relaxed for testing)
    uint256 public constant VOTING_DELAY = 43_200;
    uint256 public constant VOTING_PERIOD = 129_600;
    uint256 public constant PROPOSAL_THRESHOLD = 100_000;
    uint256 public constant QUORUM = 20_000_000;
    uint256 public constant APPROVAL_THRESHOLD = 60_000_000;
    uint256 public constant TIMELOCK_DELAY = 1 days;

    // ASHA decimals = 9, mint 1B for testing
    uint256 public constant INITIAL_ASHA_SUPPLY = 1_000_000_000 * 1e9;
    // DAI decimals = 18, mint 10M for testing
    uint256 public constant INITIAL_DAI_SUPPLY = 10_000_000 * 1e18;

    // =========  DEPLOYED CONTRACTS ========= //

    Kernel public kernel;
    ParsAuthority public authority;
    ASHA public asha;
    xASHA public xasha;
    veASHA public veasha;
    Treasury public treasury;
    FeeRouter public feeRouter;
    Charter public charter;
    MockDAI public dai;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("=== Pars Local Deployment ===");
        console2.log("Deployer:", deployer);
        console2.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Kernel
        kernel = new Kernel();

        // 2. Authority (deployer gets all roles initially)
        authority = new ParsAuthority(deployer, deployer, deployer, deployer);

        // 3. ASHA token
        asha = new ASHA(address(authority));

        // 4. xASHA (staking placeholder = deployer)
        xasha = new xASHA(address(asha), deployer);

        // 5. veASHA
        veasha = new veASHA(address(xasha));

        // 6. Treasury (register as kernel module)
        treasury = new Treasury(kernel);
        kernel.executeAction(Actions.InstallModule, address(treasury));

        // 8. FeeRouter
        feeRouter = new FeeRouter(deployer);

        // 9. Charter
        charter = new Charter(
            deployer,
            VOTING_DELAY,
            VOTING_PERIOD,
            PROPOSAL_THRESHOLD,
            QUORUM,
            APPROVAL_THRESHOLD,
            TIMELOCK_DELAY
        );

        // 10. Mock DAI for bond testing
        dai = new MockDAI();
        dai.mint(deployer, INITIAL_DAI_SUPPLY);

        // Mint initial ASHA supply to deployer (via authority vault role)
        asha.mint(deployer, INITIAL_ASHA_SUPPLY);

        vm.stopBroadcast();

        // Write deployment addresses to JSON
        _writeDeployment(deployer);

        // Summary
        console2.log("\n=== Deployment Complete ===");
        console2.log("Kernel:    ", address(kernel));
        console2.log("Authority: ", address(authority));
        console2.log("ASHA:      ", address(asha));
        console2.log("xASHA:     ", address(xasha));
        console2.log("veASHA:    ", address(veasha));
        console2.log("Treasury:  ", address(treasury));
        console2.log("FeeRouter: ", address(feeRouter));
        console2.log("Charter:   ", address(charter));
        console2.log("DAI (mock):", address(dai));
    }

    function _writeDeployment(address deployer) internal {
        string memory obj = "deployment";
        vm.serializeAddress(obj, "kernel", address(kernel));
        vm.serializeAddress(obj, "authority", address(authority));
        vm.serializeAddress(obj, "asha", address(asha));
        vm.serializeAddress(obj, "xasha", address(xasha));
        vm.serializeAddress(obj, "veasha", address(veasha));
        vm.serializeAddress(obj, "treasury", address(treasury));
        vm.serializeAddress(obj, "feeRouter", address(feeRouter));
        vm.serializeAddress(obj, "charter", address(charter));
        vm.serializeAddress(obj, "dai", address(dai));
        vm.serializeAddress(obj, "deployer", deployer);
        vm.serializeUint(obj, "chainId", LOCAL_CHAIN_ID);
        string memory json = vm.serializeUint(obj, "blockNumber", block.number);
        vm.writeJson(json, "deployments/local.json");
        console2.log("Wrote deployments/local.json");
    }
}

/**
 * @notice Mock DAI for local bond testing.
 */
contract MockDAI is ERC20 {
    constructor() ERC20("Mock DAI", "DAI") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }
}

/**
 * @notice Pars Authority implementation (same as Deploy.s.sol).
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

    function setGovernor(address v) external {
        require(msg.sender == _governor, "Authority: not governor");
        _governor = v;
    }

    function setGuardian(address v) external {
        require(msg.sender == _governor, "Authority: not governor");
        _guardian = v;
    }

    function setPolicy(address v) external {
        require(msg.sender == _governor, "Authority: not governor");
        _policy = v;
    }

    function setVault(address v) external {
        require(msg.sender == _governor, "Authority: not governor");
        _vault = v;
    }
}
