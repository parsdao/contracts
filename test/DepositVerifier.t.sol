// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {PriceOracle} from "../src/sale/PriceOracle.sol";
import {SaleConfig} from "../src/sale/SaleConfig.sol";
import {DepositVerifier} from "../src/sale/DepositVerifier.sol";
import {IDepositVerifier} from "../src/interfaces/ISale.sol";

/**
 * @title  DepositVerifier Tests
 * @notice Comprehensive test suite for multi-chain deposit verification.
 */
contract DepositVerifierTest is Test {
    PriceOracle public oracle;
    SaleConfig public config;
    DepositVerifier public verifier;
    MockMintable public token;

    address public admin = address(1);
    address public relayer = address(2);
    address public alice = address(3);
    address public bob = address(4);
    address public attacker = address(5);

    uint256 public constant SATS_PER_TOKEN = 100; // 1 token = 100 sats

    // Source chain constants
    uint8 public constant BTC = 0;
    uint8 public constant ETH = 1;
    uint8 public constant SOL = 2;
    uint8 public constant TON = 3;
    uint8 public constant XRP = 4;
    uint8 public constant LUX = 5;
    uint8 public constant PARS = 6;

    function setUp() public {
        vm.startPrank(admin);

        // Deploy mock token
        token = new MockMintable();

        // Deploy oracle
        oracle = new PriceOracle(admin);

        // Set prices (sats per 1 whole unit)
        oracle.setPrice(BTC, 100_000_000);   // 1 BTC = 1e8 sats
        oracle.setPrice(ETH, 3_800_000);     // 1 ETH = 3.8M sats
        oracle.setPrice(SOL, 180_000);       // 1 SOL = 180k sats
        oracle.setPrice(TON, 5_000);         // 1 TON = 5k sats
        oracle.setPrice(XRP, 2_500);         // 1 XRP = 2.5k sats
        oracle.setPrice(LUX, 50_000);        // 1 LUX = 50k sats
        oracle.setPrice(PARS, 1_000);        // 1 PARS = 1k sats

        // Deploy config
        config = new SaleConfig(admin);

        // Deploy verifier
        verifier = new DepositVerifier(admin, address(config), address(token), SATS_PER_TOKEN);

        // Configure
        config.setSaleToken(address(token));
        config.setDepositVerifier(address(verifier));

        // Grant relayer role
        verifier.grantRole(verifier.RELAYER_ROLE(), relayer);

        vm.stopPrank();
    }

    // =========  HELPER FUNCTIONS ========= //

    function _makeDeposit(
        bytes32 txHash,
        uint8 chain,
        address depositor,
        uint256 sats,
        uint256 time
    ) internal pure returns (IDepositVerifier.Deposit memory) {
        return IDepositVerifier.Deposit({
            sourceTxHash: txHash,
            sourceChain: chain,
            depositor: depositor,
            amountSats: sats,
            depositTime: time,
            claimed: false
        });
    }

    function _leafHash(IDepositVerifier.Deposit memory d) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(d.sourceTxHash, d.sourceChain, d.depositor, d.amountSats, d.depositTime)
        );
    }

    /// @dev Build a merkle tree from deposits and return (root, leaves, proofs).
    ///      Uses a simple 2-element tree for clarity. For larger trees, extend.
    function _buildTree(
        IDepositVerifier.Deposit[] memory deposits
    ) internal pure returns (bytes32 root, bytes32[] memory leaves, bytes32[][] memory proofs) {
        leaves = new bytes32[](deposits.length);
        for (uint256 i = 0; i < deposits.length; i++) {
            leaves[i] = _leafHash(deposits[i]);
        }

        if (deposits.length == 1) {
            // Single leaf tree: root = leaf, proof = empty
            root = leaves[0];
            proofs = new bytes32[][](1);
            proofs[0] = new bytes32[](0);
        } else if (deposits.length == 2) {
            // Two-leaf tree
            bytes32 left = leaves[0];
            bytes32 right = leaves[1];
            // OZ MerkleProof expects sorted pairs
            if (left < right) {
                root = keccak256(abi.encodePacked(left, right));
            } else {
                root = keccak256(abi.encodePacked(right, left));
            }
            proofs = new bytes32[][](2);
            proofs[0] = new bytes32[](1);
            proofs[0][0] = right;
            proofs[1] = new bytes32[](1);
            proofs[1][0] = left;
        } else {
            revert("Use murky for >2 leaves");
        }
    }

    // =========  MERKLE ROOT SUBMISSION ========= //

    function test_submitRoot() public {
        bytes32 root = keccak256("root1");

        vm.prank(relayer);
        verifier.submitRoot(root, 10);

        assertEq(verifier.batchCount(), 1);
        assertEq(verifier.getRoot(0), root);
        assertEq(verifier.totalDepositsRecorded(), 10);
    }

    function test_submitRoot_multipleBatches() public {
        bytes32 root1 = keccak256("root1");
        bytes32 root2 = keccak256("root2");

        vm.startPrank(relayer);
        verifier.submitRoot(root1, 5);
        verifier.submitRoot(root2, 8);
        vm.stopPrank();

        assertEq(verifier.batchCount(), 2);
        assertEq(verifier.getRoot(0), root1);
        assertEq(verifier.getRoot(1), root2);
        assertEq(verifier.totalDepositsRecorded(), 13);
    }

    function test_submitRoot_revertNotRelayer() public {
        vm.prank(attacker);
        vm.expectRevert();
        verifier.submitRoot(keccak256("root"), 10);
    }

    function test_submitRoot_revertZeroRoot() public {
        vm.prank(relayer);
        vm.expectRevert(DepositVerifier.DepositVerifier_InvalidRoot.selector);
        verifier.submitRoot(bytes32(0), 10);
    }

    // =========  CLAIM WITH VALID PROOF ========= //

    function test_claim_singleDeposit() public {
        // Create deposit
        IDepositVerifier.Deposit memory deposit =
            _makeDeposit(keccak256("btc_tx_1"), BTC, alice, 10_000_000, block.timestamp); // 0.1 BTC

        // Build single-leaf tree
        IDepositVerifier.Deposit[] memory deposits = new IDepositVerifier.Deposit[](1);
        deposits[0] = deposit;
        (bytes32 root,, bytes32[][] memory proofs) = _buildTree(deposits);

        // Submit root
        vm.prank(relayer);
        verifier.submitRoot(root, 1);

        // Claim
        vm.prank(alice);
        verifier.claim(proofs[0], deposit);

        // Verify: 10,000,000 sats * 1e18 / 100 = 1e23 tokens
        uint256 expectedTokens = (10_000_000 * 1e18) / SATS_PER_TOKEN;
        assertEq(token.balanceOf(alice), expectedTokens);
        assertTrue(verifier.isClaimed(keccak256("btc_tx_1")));

        // Verify sale config totals
        assertEq(config.totalRaised(), 10_000_000);
        assertEq(config.totalMinted(), expectedTokens);
    }

    function test_claim_twoDeposits() public {
        IDepositVerifier.Deposit memory d1 =
            _makeDeposit(keccak256("eth_tx_1"), ETH, alice, 3_800_000, block.timestamp);
        IDepositVerifier.Deposit memory d2 =
            _makeDeposit(keccak256("sol_tx_1"), SOL, bob, 180_000, block.timestamp);

        IDepositVerifier.Deposit[] memory deposits = new IDepositVerifier.Deposit[](2);
        deposits[0] = d1;
        deposits[1] = d2;
        (bytes32 root,, bytes32[][] memory proofs) = _buildTree(deposits);

        vm.prank(relayer);
        verifier.submitRoot(root, 2);

        // Alice claims
        vm.prank(alice);
        verifier.claim(proofs[0], d1);
        assertEq(token.balanceOf(alice), (3_800_000 * 1e18) / SATS_PER_TOKEN);

        // Bob claims
        vm.prank(bob);
        verifier.claim(proofs[1], d2);
        assertEq(token.balanceOf(bob), (180_000 * 1e18) / SATS_PER_TOKEN);
    }

    function test_claim_thirdPartyCanClaim() public {
        // Bob can claim on behalf of alice (tokens go to alice)
        IDepositVerifier.Deposit memory deposit =
            _makeDeposit(keccak256("btc_tx_2"), BTC, alice, 5_000_000, block.timestamp);

        IDepositVerifier.Deposit[] memory deposits = new IDepositVerifier.Deposit[](1);
        deposits[0] = deposit;
        (bytes32 root,, bytes32[][] memory proofs) = _buildTree(deposits);

        vm.prank(relayer);
        verifier.submitRoot(root, 1);

        vm.prank(bob); // Bob calls claim, tokens go to alice
        verifier.claim(proofs[0], deposit);

        uint256 expectedTokens = (5_000_000 * 1e18) / SATS_PER_TOKEN;
        assertEq(token.balanceOf(alice), expectedTokens);
        assertEq(token.balanceOf(bob), 0);
    }

    // =========  CLAIM WITH INVALID PROOF ========= //

    function test_claim_revertInvalidProof() public {
        IDepositVerifier.Deposit memory deposit =
            _makeDeposit(keccak256("btc_tx_3"), BTC, alice, 1_000_000, block.timestamp);

        // Submit some root
        vm.prank(relayer);
        verifier.submitRoot(keccak256("different_root"), 1);

        // Try to claim with empty proof (will not match)
        bytes32[] memory badProof = new bytes32[](0);

        vm.prank(alice);
        vm.expectRevert(DepositVerifier.DepositVerifier_InvalidProof.selector);
        verifier.claim(badProof, deposit);
    }

    function test_claim_revertWrongDepositor() public {
        IDepositVerifier.Deposit memory realDeposit =
            _makeDeposit(keccak256("btc_tx_4"), BTC, alice, 1_000_000, block.timestamp);

        IDepositVerifier.Deposit[] memory deposits = new IDepositVerifier.Deposit[](1);
        deposits[0] = realDeposit;
        (bytes32 root,, bytes32[][] memory proofs) = _buildTree(deposits);

        vm.prank(relayer);
        verifier.submitRoot(root, 1);

        // Attacker tries to claim with modified depositor
        IDepositVerifier.Deposit memory fakeDeposit =
            _makeDeposit(keccak256("btc_tx_4"), BTC, attacker, 1_000_000, block.timestamp);

        vm.prank(attacker);
        vm.expectRevert(DepositVerifier.DepositVerifier_InvalidProof.selector);
        verifier.claim(proofs[0], fakeDeposit);
    }

    function test_claim_revertWrongAmount() public {
        IDepositVerifier.Deposit memory realDeposit =
            _makeDeposit(keccak256("btc_tx_5"), BTC, alice, 1_000_000, block.timestamp);

        IDepositVerifier.Deposit[] memory deposits = new IDepositVerifier.Deposit[](1);
        deposits[0] = realDeposit;
        (bytes32 root,, bytes32[][] memory proofs) = _buildTree(deposits);

        vm.prank(relayer);
        verifier.submitRoot(root, 1);

        // Try to claim with inflated amount
        IDepositVerifier.Deposit memory inflated =
            _makeDeposit(keccak256("btc_tx_5"), BTC, alice, 100_000_000, block.timestamp);

        vm.prank(alice);
        vm.expectRevert(DepositVerifier.DepositVerifier_InvalidProof.selector);
        verifier.claim(proofs[0], inflated);
    }

    // =========  DOUBLE-CLAIM PREVENTION ========= //

    function test_claim_revertDoubleClaim() public {
        IDepositVerifier.Deposit memory deposit =
            _makeDeposit(keccak256("btc_tx_6"), BTC, alice, 1_000_000, block.timestamp);

        IDepositVerifier.Deposit[] memory deposits = new IDepositVerifier.Deposit[](1);
        deposits[0] = deposit;
        (bytes32 root,, bytes32[][] memory proofs) = _buildTree(deposits);

        vm.prank(relayer);
        verifier.submitRoot(root, 1);

        // First claim succeeds
        vm.prank(alice);
        verifier.claim(proofs[0], deposit);

        // Second claim reverts
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                DepositVerifier.DepositVerifier_AlreadyClaimed.selector, keccak256("btc_tx_6")
            )
        );
        verifier.claim(proofs[0], deposit);
    }

    // =========  BATCH CLAIM ========= //

    function test_claimBatch() public {
        IDepositVerifier.Deposit memory d1 =
            _makeDeposit(keccak256("batch_tx_1"), BTC, alice, 5_000_000, block.timestamp);
        IDepositVerifier.Deposit memory d2 =
            _makeDeposit(keccak256("batch_tx_2"), ETH, bob, 1_900_000, block.timestamp);

        IDepositVerifier.Deposit[] memory deposits = new IDepositVerifier.Deposit[](2);
        deposits[0] = d1;
        deposits[1] = d2;
        (bytes32 root,, bytes32[][] memory proofs) = _buildTree(deposits);

        vm.prank(relayer);
        verifier.submitRoot(root, 2);

        // Batch claim both
        vm.prank(alice);
        verifier.claimBatch(proofs, deposits);

        assertEq(token.balanceOf(alice), (5_000_000 * 1e18) / SATS_PER_TOKEN);
        assertEq(token.balanceOf(bob), (1_900_000 * 1e18) / SATS_PER_TOKEN);
        assertTrue(verifier.isClaimed(keccak256("batch_tx_1")));
        assertTrue(verifier.isClaimed(keccak256("batch_tx_2")));
    }

    function test_claimBatch_revertLengthMismatch() public {
        bytes32[][] memory proofs = new bytes32[][](2);
        IDepositVerifier.Deposit[] memory deposits = new IDepositVerifier.Deposit[](1);

        vm.prank(alice);
        vm.expectRevert(DepositVerifier.DepositVerifier_LengthMismatch.selector);
        verifier.claimBatch(proofs, deposits);
    }

    // =========  PRICE ORACLE ========= //

    function test_oracle_getPrice() public view {
        assertEq(oracle.getPrice(BTC), 100_000_000);
        assertEq(oracle.getPrice(ETH), 3_800_000);
        assertEq(oracle.getPrice(SOL), 180_000);
    }

    function test_oracle_convertToSats() public view {
        // 1 BTC (1e8 sats) = 100_000_000 sats
        assertEq(oracle.convertToSats(BTC, 1e8, 8), 100_000_000);

        // 1 ETH (1e18 wei) = 3_800_000 sats
        assertEq(oracle.convertToSats(ETH, 1e18, 18), 3_800_000);

        // 10 SOL (10e9 lamports) = 1_800_000 sats
        assertEq(oracle.convertToSats(SOL, 10e9, 9), 1_800_000);
    }

    function test_oracle_setPrice() public {
        vm.prank(admin);
        oracle.setPrice(ETH, 4_000_000); // ETH price increase

        assertEq(oracle.getPrice(ETH), 4_000_000);
    }

    function test_oracle_revertInvalidPrice() public {
        vm.prank(admin);
        vm.expectRevert(PriceOracle.PriceOracle_InvalidPrice.selector);
        oracle.setPrice(BTC, 0);
    }

    function test_oracle_revertNotOracle() public {
        vm.prank(attacker);
        vm.expectRevert();
        oracle.setPrice(BTC, 100_000_000);
    }

    function test_oracle_batchSetPrices() public {
        uint8[] memory chains = new uint8[](3);
        chains[0] = BTC;
        chains[1] = ETH;
        chains[2] = SOL;

        uint256[] memory newPrices = new uint256[](3);
        newPrices[0] = 100_000_000;
        newPrices[1] = 4_200_000;
        newPrices[2] = 200_000;

        vm.prank(admin);
        oracle.setPrices(chains, newPrices);

        assertEq(oracle.getPrice(ETH), 4_200_000);
        assertEq(oracle.getPrice(SOL), 200_000);
    }

    // =========  MINT RATE ========= //

    function test_setMintRate() public {
        vm.prank(admin);
        verifier.setMintRate(200); // 1 token = 200 sats

        assertEq(verifier.satsPerToken(), 200);
    }

    function test_setMintRate_affectsCalculation() public {
        // Create and claim a deposit at rate 100
        IDepositVerifier.Deposit memory d1 =
            _makeDeposit(keccak256("rate_tx_1"), BTC, alice, 10_000, block.timestamp);

        IDepositVerifier.Deposit[] memory deposits1 = new IDepositVerifier.Deposit[](1);
        deposits1[0] = d1;
        (bytes32 root1,, bytes32[][] memory proofs1) = _buildTree(deposits1);

        vm.prank(relayer);
        verifier.submitRoot(root1, 1);
        vm.prank(alice);
        verifier.claim(proofs1[0], d1);

        uint256 tokensAtRate100 = token.balanceOf(alice);
        assertEq(tokensAtRate100, (10_000 * 1e18) / 100);

        // Change rate to 200
        vm.prank(admin);
        verifier.setMintRate(200);

        // Claim another deposit at new rate
        IDepositVerifier.Deposit memory d2 =
            _makeDeposit(keccak256("rate_tx_2"), BTC, bob, 10_000, block.timestamp);

        IDepositVerifier.Deposit[] memory deposits2 = new IDepositVerifier.Deposit[](1);
        deposits2[0] = d2;
        (bytes32 root2,, bytes32[][] memory proofs2) = _buildTree(deposits2);

        vm.prank(relayer);
        verifier.submitRoot(root2, 1);
        vm.prank(bob);
        verifier.claim(proofs2[0], d2);

        uint256 tokensAtRate200 = token.balanceOf(bob);
        assertEq(tokensAtRate200, (10_000 * 1e18) / 200);

        // Half the tokens at double the rate
        assertEq(tokensAtRate100, tokensAtRate200 * 2);
    }

    function test_setMintRate_revertZero() public {
        vm.prank(admin);
        vm.expectRevert(DepositVerifier.DepositVerifier_InvalidMintRate.selector);
        verifier.setMintRate(0);
    }

    function test_setMintRate_revertNotAdmin() public {
        vm.prank(attacker);
        vm.expectRevert();
        verifier.setMintRate(200);
    }

    function test_calculateMint() public view {
        // 10,000 sats at 100 sats/token = 100 tokens (100e18)
        assertEq(verifier.calculateMint(10_000), 100e18);

        // 1 sat at 100 sats/token = 0.01 tokens (1e16)
        assertEq(verifier.calculateMint(1), 1e16);

        // 100,000,000 sats (1 BTC) at 100 sats/token = 1,000,000 tokens
        assertEq(verifier.calculateMint(100_000_000), 1_000_000e18);
    }

    // =========  PAUSE / UNPAUSE ========= //

    function test_pause() public {
        vm.prank(admin);
        verifier.pause();

        // Cannot submit roots when paused
        vm.prank(relayer);
        vm.expectRevert();
        verifier.submitRoot(keccak256("root"), 1);
    }

    function test_unpause() public {
        vm.startPrank(admin);
        verifier.pause();
        verifier.unpause();
        vm.stopPrank();

        // Can submit roots after unpause
        vm.prank(relayer);
        verifier.submitRoot(keccak256("root"), 1);
        assertEq(verifier.batchCount(), 1);
    }

    function test_pause_blocksClaim() public {
        IDepositVerifier.Deposit memory deposit =
            _makeDeposit(keccak256("pause_tx"), BTC, alice, 1_000_000, block.timestamp);

        IDepositVerifier.Deposit[] memory deposits = new IDepositVerifier.Deposit[](1);
        deposits[0] = deposit;
        (bytes32 root,, bytes32[][] memory proofs) = _buildTree(deposits);

        vm.prank(relayer);
        verifier.submitRoot(root, 1);

        // Pause
        vm.prank(admin);
        verifier.pause();

        // Claim should fail
        vm.prank(alice);
        vm.expectRevert();
        verifier.claim(proofs[0], deposit);

        // Unpause and claim succeeds
        vm.prank(admin);
        verifier.unpause();

        vm.prank(alice);
        verifier.claim(proofs[0], deposit);
        assertTrue(verifier.isClaimed(keccak256("pause_tx")));
    }

    function test_pause_revertNotAdmin() public {
        vm.prank(attacker);
        vm.expectRevert();
        verifier.pause();
    }

    // =========  ACCESS CONTROL ========= //

    function test_onlyAdminCanSetMintToken() public {
        vm.prank(attacker);
        vm.expectRevert();
        verifier.setMintToken(address(token));
    }

    function test_setMintToken() public {
        MockMintable newToken = new MockMintable();

        vm.prank(admin);
        verifier.setMintToken(address(newToken));

        assertEq(verifier.mintToken(), address(newToken));
    }

    function test_setMintToken_revertZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(DepositVerifier.DepositVerifier_InvalidToken.selector);
        verifier.setMintToken(address(0));
    }

    // =========  WITHDRAW ========= //

    function test_withdraw() public {
        // Send some tokens to verifier by accident
        MockMintable stray = new MockMintable();
        stray.mint(address(verifier), 1000e18);

        uint256 balBefore = stray.balanceOf(admin);
        vm.prank(admin);
        verifier.withdraw(address(stray), 1000e18);

        assertEq(stray.balanceOf(admin), balBefore + 1000e18);
        assertEq(stray.balanceOf(address(verifier)), 0);
    }

    function test_withdraw_revertNotAdmin() public {
        vm.prank(attacker);
        vm.expectRevert();
        verifier.withdraw(address(token), 100);
    }

    // =========  SALE CONFIG ========= //

    function test_saleConfig_totals() public {
        IDepositVerifier.Deposit memory d1 =
            _makeDeposit(keccak256("cfg_tx_1"), BTC, alice, 5_000_000, block.timestamp);
        IDepositVerifier.Deposit memory d2 =
            _makeDeposit(keccak256("cfg_tx_2"), ETH, bob, 2_000_000, block.timestamp);

        IDepositVerifier.Deposit[] memory deposits = new IDepositVerifier.Deposit[](2);
        deposits[0] = d1;
        deposits[1] = d2;
        (bytes32 root,, bytes32[][] memory proofs) = _buildTree(deposits);

        vm.prank(relayer);
        verifier.submitRoot(root, 2);

        vm.prank(alice);
        verifier.claim(proofs[0], d1);

        vm.prank(bob);
        verifier.claim(proofs[1], d2);

        assertEq(config.totalRaised(), 7_000_000);
        uint256 expectedMinted =
            (5_000_000 * 1e18) / SATS_PER_TOKEN + (2_000_000 * 1e18) / SATS_PER_TOKEN;
        assertEq(config.totalMinted(), expectedMinted);
    }

    function test_saleConfig_setMinDeposit() public {
        vm.prank(admin);
        config.setMinDeposit(BTC, 100_000); // 0.001 BTC min

        assertEq(config.minDeposit(BTC), 100_000);
    }

    function test_saleConfig_setMaxDeposit() public {
        vm.prank(admin);
        config.setMaxDeposit(BTC, 10_000_000_000); // 100 BTC max

        assertEq(config.maxDeposit(BTC), 10_000_000_000);
    }

    function test_saleConfig_setSaleWindow() public {
        uint256 start = block.timestamp + 1 days;
        uint256 end = block.timestamp + 30 days;

        vm.startPrank(admin);
        config.setSaleStart(start);
        config.setSaleEnd(end);
        vm.stopPrank();

        assertEq(config.saleStart(), start);
        assertEq(config.saleEnd(), end);
    }

    function test_saleConfig_recordSale_revertNotVerifier() public {
        vm.prank(attacker);
        vm.expectRevert(SaleConfig.SaleConfig_OnlyVerifier.selector);
        config.recordSale(1_000_000, 1e18);
    }

    // =========  PROCESS DEPOSIT (DIRECT RELAY) ========= //

    function test_processDeposit_success() public {
        bytes32 txHash = keccak256("direct_btc_tx_1");

        vm.prank(relayer);
        verifier.processDeposit(txHash, BTC, alice, 5_000_000, block.timestamp);

        // Verify mint: 5,000,000 sats * 1e18 / 100 = 5e22
        uint256 expectedTokens = (5_000_000 * 1e18) / SATS_PER_TOKEN;
        assertEq(token.balanceOf(alice), expectedTokens);
        assertTrue(verifier.isClaimed(txHash));

        // Verify sale config totals
        assertEq(config.totalRaised(), 5_000_000);
        assertEq(config.totalMinted(), expectedTokens);
    }

    function test_processDeposit_allChains() public {
        vm.startPrank(relayer);

        verifier.processDeposit(keccak256("d_btc"), BTC, alice, 100_000, block.timestamp);
        verifier.processDeposit(keccak256("d_eth"), ETH, alice, 200_000, block.timestamp);
        verifier.processDeposit(keccak256("d_sol"), SOL, alice, 300_000, block.timestamp);
        verifier.processDeposit(keccak256("d_ton"), TON, alice, 400_000, block.timestamp);
        verifier.processDeposit(keccak256("d_xrp"), XRP, alice, 500_000, block.timestamp);
        verifier.processDeposit(keccak256("d_lux"), LUX, alice, 600_000, block.timestamp);
        verifier.processDeposit(keccak256("d_pars"), PARS, alice, 700_000, block.timestamp);

        vm.stopPrank();

        uint256 totalSats = 100_000 + 200_000 + 300_000 + 400_000 + 500_000 + 600_000 + 700_000;
        uint256 expectedTokens = (totalSats * 1e18) / SATS_PER_TOKEN;
        assertEq(token.balanceOf(alice), expectedTokens);
        assertEq(config.totalRaised(), totalSats);
    }

    function test_processDeposit_revertDoubleProcess() public {
        bytes32 txHash = keccak256("direct_btc_tx_dup");

        vm.startPrank(relayer);
        verifier.processDeposit(txHash, BTC, alice, 1_000_000, block.timestamp);

        vm.expectRevert(
            abi.encodeWithSelector(DepositVerifier.DepositVerifier_AlreadyClaimed.selector, txHash)
        );
        verifier.processDeposit(txHash, BTC, alice, 1_000_000, block.timestamp);
        vm.stopPrank();
    }

    function test_processDeposit_revertNotRelayer() public {
        vm.prank(attacker);
        vm.expectRevert();
        verifier.processDeposit(keccak256("bad_tx"), BTC, alice, 1_000_000, block.timestamp);
    }

    function test_processDeposit_revertWhenPaused() public {
        vm.prank(admin);
        verifier.pause();

        vm.prank(relayer);
        vm.expectRevert();
        verifier.processDeposit(keccak256("paused_tx"), BTC, alice, 1_000_000, block.timestamp);
    }

    function test_processDeposit_revertZeroAmount() public {
        vm.prank(relayer);
        vm.expectRevert(DepositVerifier.DepositVerifier_ZeroAmount.selector);
        verifier.processDeposit(keccak256("zero_tx_d"), BTC, alice, 0, block.timestamp);
    }

    function test_processDeposit_revertInvalidChain() public {
        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(DepositVerifier.DepositVerifier_InvalidChain.selector, 7)
        );
        verifier.processDeposit(keccak256("bad_chain_d"), 7, alice, 1_000_000, block.timestamp);
    }

    function test_processDeposit_emitsEvent() public {
        bytes32 txHash = keccak256("event_direct_tx");
        uint256 expectedTokens = (2_000_000 * 1e18) / SATS_PER_TOKEN;

        vm.expectEmit(true, true, false, true);
        emit IDepositVerifier.DepositClaimed(alice, txHash, ETH, 2_000_000, expectedTokens);

        vm.prank(relayer);
        verifier.processDeposit(txHash, ETH, alice, 2_000_000, block.timestamp);
    }

    // =========  PROCESS DEPOSIT BATCH ========= //

    function test_processDepositBatch_success() public {
        bytes32[] memory txHashes = new bytes32[](3);
        txHashes[0] = keccak256("batch_d_1");
        txHashes[1] = keccak256("batch_d_2");
        txHashes[2] = keccak256("batch_d_3");

        uint8[] memory chains = new uint8[](3);
        chains[0] = BTC;
        chains[1] = ETH;
        chains[2] = SOL;

        address[] memory depositors = new address[](3);
        depositors[0] = alice;
        depositors[1] = bob;
        depositors[2] = alice;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1_000_000;
        amounts[1] = 2_000_000;
        amounts[2] = 3_000_000;

        uint256[] memory times = new uint256[](3);
        times[0] = block.timestamp;
        times[1] = block.timestamp;
        times[2] = block.timestamp;

        vm.prank(relayer);
        verifier.processDepositBatch(txHashes, chains, depositors, amounts, times);

        // Alice: 1M + 3M = 4M sats worth of tokens
        uint256 aliceExpected = ((1_000_000 + 3_000_000) * 1e18) / SATS_PER_TOKEN;
        assertEq(token.balanceOf(alice), aliceExpected);

        // Bob: 2M sats worth of tokens
        uint256 bobExpected = (2_000_000 * 1e18) / SATS_PER_TOKEN;
        assertEq(token.balanceOf(bob), bobExpected);

        // All marked as claimed
        assertTrue(verifier.isClaimed(keccak256("batch_d_1")));
        assertTrue(verifier.isClaimed(keccak256("batch_d_2")));
        assertTrue(verifier.isClaimed(keccak256("batch_d_3")));

        // Sale config totals
        assertEq(config.totalRaised(), 6_000_000);
    }

    function test_processDepositBatch_revertLengthMismatch() public {
        bytes32[] memory txHashes = new bytes32[](2);
        uint8[] memory chains = new uint8[](1); // mismatch
        address[] memory depositors = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        uint256[] memory times = new uint256[](2);

        vm.prank(relayer);
        vm.expectRevert(DepositVerifier.DepositVerifier_LengthMismatch.selector);
        verifier.processDepositBatch(txHashes, chains, depositors, amounts, times);
    }

    function test_processDepositBatch_revertNotRelayer() public {
        bytes32[] memory txHashes = new bytes32[](1);
        txHashes[0] = keccak256("batch_bad");
        uint8[] memory chains = new uint8[](1);
        address[] memory depositors = new address[](1);
        depositors[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1_000_000;
        uint256[] memory times = new uint256[](1);
        times[0] = block.timestamp;

        vm.prank(attacker);
        vm.expectRevert();
        verifier.processDepositBatch(txHashes, chains, depositors, amounts, times);
    }

    function test_processDepositBatch_revertDuplicateInBatch() public {
        bytes32[] memory txHashes = new bytes32[](2);
        txHashes[0] = keccak256("dup_batch_tx");
        txHashes[1] = keccak256("dup_batch_tx"); // same hash

        uint8[] memory chains = new uint8[](2);
        chains[0] = BTC;
        chains[1] = BTC;

        address[] memory depositors = new address[](2);
        depositors[0] = alice;
        depositors[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000;
        amounts[1] = 2_000_000;

        uint256[] memory times = new uint256[](2);
        times[0] = block.timestamp;
        times[1] = block.timestamp;

        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(
                DepositVerifier.DepositVerifier_AlreadyClaimed.selector,
                keccak256("dup_batch_tx")
            )
        );
        verifier.processDepositBatch(txHashes, chains, depositors, amounts, times);
    }

    // =========  CROSS-PATH: processDeposit blocks merkle claim ========= //

    function test_processDeposit_blocksMerkleClaim() public {
        // Process deposit directly
        bytes32 txHash = keccak256("cross_tx_1");
        vm.prank(relayer);
        verifier.processDeposit(txHash, BTC, alice, 1_000_000, block.timestamp);

        // Try to merkle-claim the same tx hash -- should revert
        IDepositVerifier.Deposit memory deposit =
            _makeDeposit(txHash, BTC, alice, 1_000_000, block.timestamp);

        IDepositVerifier.Deposit[] memory deposits = new IDepositVerifier.Deposit[](1);
        deposits[0] = deposit;
        (bytes32 root,, bytes32[][] memory proofs) = _buildTree(deposits);

        vm.prank(relayer);
        verifier.submitRoot(root, 1);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                DepositVerifier.DepositVerifier_AlreadyClaimed.selector, txHash
            )
        );
        verifier.claim(proofs[0], deposit);
    }

    // =========  EDGE CASES ========= //

    function test_claim_revertZeroAmount() public {
        IDepositVerifier.Deposit memory deposit =
            _makeDeposit(keccak256("zero_tx"), BTC, alice, 0, block.timestamp);

        bytes32[] memory proof = new bytes32[](0);

        vm.prank(alice);
        vm.expectRevert(DepositVerifier.DepositVerifier_ZeroAmount.selector);
        verifier.claim(proof, deposit);
    }

    function test_claim_revertInvalidChain() public {
        IDepositVerifier.Deposit memory deposit =
            _makeDeposit(keccak256("bad_chain"), 7, alice, 1_000_000, block.timestamp);

        bytes32[] memory proof = new bytes32[](0);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(DepositVerifier.DepositVerifier_InvalidChain.selector, 7));
        verifier.claim(proof, deposit);
    }

    function test_claim_fromSecondBatch() public {
        // First batch
        vm.prank(relayer);
        verifier.submitRoot(keccak256("old_root"), 5);

        // Second batch with our deposit
        IDepositVerifier.Deposit memory deposit =
            _makeDeposit(keccak256("batch2_tx"), SOL, alice, 360_000, block.timestamp);

        IDepositVerifier.Deposit[] memory deposits = new IDepositVerifier.Deposit[](1);
        deposits[0] = deposit;
        (bytes32 root,, bytes32[][] memory proofs) = _buildTree(deposits);

        vm.prank(relayer);
        verifier.submitRoot(root, 1);

        // Claim from second batch should work
        vm.prank(alice);
        verifier.claim(proofs[0], deposit);

        assertEq(token.balanceOf(alice), (360_000 * 1e18) / SATS_PER_TOKEN);
    }

    // =========  FUZZ TESTS ========= //

    function testFuzz_claimWithRandomAmounts(uint256 amountSats) public {
        // Bound to reasonable range: 1 sat to 100 BTC
        amountSats = bound(amountSats, 1, 10_000_000_000);

        IDepositVerifier.Deposit memory deposit = _makeDeposit(
            keccak256(abi.encode("fuzz_tx", amountSats)), BTC, alice, amountSats, block.timestamp
        );

        IDepositVerifier.Deposit[] memory deposits = new IDepositVerifier.Deposit[](1);
        deposits[0] = deposit;
        (bytes32 root,, bytes32[][] memory proofs) = _buildTree(deposits);

        vm.prank(relayer);
        verifier.submitRoot(root, 1);

        vm.prank(alice);
        verifier.claim(proofs[0], deposit);

        uint256 expectedTokens = (amountSats * 1e18) / SATS_PER_TOKEN;
        assertEq(token.balanceOf(alice), expectedTokens);
        assertTrue(verifier.isClaimed(deposit.sourceTxHash));
    }

    function testFuzz_mintRateCalculation(uint256 sats, uint256 rate) public pure {
        sats = bound(sats, 1, 10_000_000_000);
        rate = bound(rate, 1, 1_000_000);

        uint256 tokens = (sats * 1e18) / rate;

        // Tokens should always be > 0 if sats > 0 and rate > 0
        assertTrue(tokens > 0);

        // Tokens should decrease as rate increases
        if (rate > 1) {
            uint256 tokensAtLowerRate = (sats * 1e18) / (rate - 1);
            assertTrue(tokensAtLowerRate >= tokens);
        }
    }

    // =========  EVENT TESTS ========= //

    function test_emitsDepositClaimed() public {
        IDepositVerifier.Deposit memory deposit =
            _makeDeposit(keccak256("event_tx"), BTC, alice, 1_000_000, block.timestamp);

        IDepositVerifier.Deposit[] memory deposits = new IDepositVerifier.Deposit[](1);
        deposits[0] = deposit;
        (bytes32 root,, bytes32[][] memory proofs) = _buildTree(deposits);

        vm.prank(relayer);
        verifier.submitRoot(root, 1);

        uint256 expectedTokens = (1_000_000 * 1e18) / SATS_PER_TOKEN;

        vm.expectEmit(true, true, false, true);
        emit IDepositVerifier.DepositClaimed(alice, keccak256("event_tx"), BTC, 1_000_000, expectedTokens);

        vm.prank(alice);
        verifier.claim(proofs[0], deposit);
    }

    function test_emitsRootSubmitted() public {
        bytes32 root = keccak256("emit_root");

        vm.expectEmit(true, false, false, true);
        emit IDepositVerifier.RootSubmitted(root, 10, 0);

        vm.prank(relayer);
        verifier.submitRoot(root, 10);
    }
}

/**
 * @notice Mock mintable token for testing.
 */
contract MockMintable {
    string public name = "MockToken";
    string public symbol = "MOCK";
    uint8 public decimals = 18;

    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address, uint256) external pure returns (bool) {
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function allowance(address, address) external pure returns (uint256) {
        return type(uint256).max;
    }
}
