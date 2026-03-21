// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ASHA, IParsAuthority} from "../src/tokens/ASHA.sol";

/**
 * @title  ASHA Token Tests
 * @notice Test suite for the ASHA governance/reserve token.
 */
contract ASHATest is Test {
    ASHA public asha;
    MockAuthority public authority;

    address public governor = address(1);
    address public guardian = address(2);
    address public policy = address(3);
    address public vault = address(4);
    address public alice = address(5);
    address public bob = address(6);

    function setUp() public {
        // Deploy mock authority
        authority = new MockAuthority(governor, guardian, policy, vault);

        // Deploy ASHA token
        asha = new ASHA(address(authority));
    }

    // =========  BASIC TESTS ========= //

    function test_name() public view {
        assertEq(asha.name(), "Asha");
    }

    function test_symbol() public view {
        assertEq(asha.symbol(), "ASHA");
    }

    function test_decimals() public view {
        assertEq(asha.decimals(), 9);
    }

    function test_initialSupply() public view {
        assertEq(asha.totalSupply(), 0);
    }

    // =========  MINT TESTS ========= //

    function test_mint_onlyVault() public {
        vm.prank(vault);
        asha.mint(alice, 1000e9);
        assertEq(asha.balanceOf(alice), 1000e9);
    }

    function test_mint_revertNotVault() public {
        vm.expectRevert(ASHA.ASHA_OnlyVault.selector);
        vm.prank(alice);
        asha.mint(alice, 1000e9);
    }

    function test_mint_multipleRecipients() public {
        vm.startPrank(vault);
        asha.mint(alice, 1000e9);
        asha.mint(bob, 2000e9);
        vm.stopPrank();

        assertEq(asha.balanceOf(alice), 1000e9);
        assertEq(asha.balanceOf(bob), 2000e9);
        assertEq(asha.totalSupply(), 3000e9);
    }

    // =========  BURN TESTS ========= //

    function test_burn() public {
        // Mint first
        vm.prank(vault);
        asha.mint(alice, 1000e9);

        // Burn
        vm.prank(alice);
        asha.burn(400e9);

        assertEq(asha.balanceOf(alice), 600e9);
        assertEq(asha.totalSupply(), 600e9);
    }

    function test_burnFrom_withApproval() public {
        // Mint first
        vm.prank(vault);
        asha.mint(alice, 1000e9);

        // Approve bob
        vm.prank(alice);
        asha.approve(bob, 500e9);

        // Burn from alice
        vm.prank(bob);
        asha.burnFrom(alice, 500e9);

        assertEq(asha.balanceOf(alice), 500e9);
        assertEq(asha.allowance(alice, bob), 0);
    }

    // =========  TRANSFER TESTS ========= //

    function test_transfer() public {
        vm.prank(vault);
        asha.mint(alice, 1000e9);

        vm.prank(alice);
        asha.transfer(bob, 300e9);

        assertEq(asha.balanceOf(alice), 700e9);
        assertEq(asha.balanceOf(bob), 300e9);
    }

    function test_transferFrom() public {
        vm.prank(vault);
        asha.mint(alice, 1000e9);

        vm.prank(alice);
        asha.approve(bob, 500e9);

        vm.prank(bob);
        asha.transferFrom(alice, bob, 400e9);

        assertEq(asha.balanceOf(alice), 600e9);
        assertEq(asha.balanceOf(bob), 400e9);
        assertEq(asha.allowance(alice, bob), 100e9);
    }

    // =========  AUTHORITY TESTS ========= //

    function test_setAuthority_onlyGovernor() public {
        MockAuthority newAuthority = new MockAuthority(
            governor,
            guardian,
            policy,
            vault
        );

        vm.prank(governor);
        asha.setAuthority(IParsAuthority(address(newAuthority)));

        assertEq(address(asha.authority()), address(newAuthority));
    }

    function test_setAuthority_revertNotGovernor() public {
        MockAuthority newAuthority = new MockAuthority(
            governor,
            guardian,
            policy,
            vault
        );

        vm.expectRevert(ASHA.ASHA_OnlyGovernor.selector);
        vm.prank(alice);
        asha.setAuthority(IParsAuthority(address(newAuthority)));
    }

    // =========  FUZZ TESTS ========= //

    function testFuzz_mint(uint256 amount) public {
        vm.assume(amount > 0 && amount < type(uint128).max);

        vm.prank(vault);
        asha.mint(alice, amount);

        assertEq(asha.balanceOf(alice), amount);
        assertEq(asha.totalSupply(), amount);
    }

    function testFuzz_transfer(uint256 mintAmount, uint256 transferAmount) public {
        vm.assume(mintAmount > 0 && mintAmount < type(uint128).max);
        vm.assume(transferAmount > 0 && transferAmount <= mintAmount);

        vm.prank(vault);
        asha.mint(alice, mintAmount);

        vm.prank(alice);
        asha.transfer(bob, transferAmount);

        assertEq(asha.balanceOf(alice), mintAmount - transferAmount);
        assertEq(asha.balanceOf(bob), transferAmount);
    }
}

/**
 * @notice Mock Pars Authority for testing.
 */
contract MockAuthority is IParsAuthority {
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

    function governor() external view override returns (address) {
        return _governor;
    }

    function guardian() external view override returns (address) {
        return _guardian;
    }

    function policy() external view override returns (address) {
        return _policy;
    }

    function vault() external view override returns (address) {
        return _vault;
    }
}
