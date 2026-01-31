// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {PARS, IParsAuthority} from "../src/tokens/PARS.sol";

/**
 * @title  PARS Token Tests
 * @notice Test suite for the PARS governance token.
 */
contract PARSTest is Test {
    PARS public pars;
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

        // Deploy PARS token
        pars = new PARS(address(authority));
    }

    // =========  BASIC TESTS ========= //

    function test_name() public view {
        assertEq(pars.name(), "Pars");
    }

    function test_symbol() public view {
        assertEq(pars.symbol(), "PARS");
    }

    function test_decimals() public view {
        assertEq(pars.decimals(), 9);
    }

    function test_initialSupply() public view {
        assertEq(pars.totalSupply(), 0);
    }

    // =========  MINT TESTS ========= //

    function test_mint_onlyVault() public {
        vm.prank(vault);
        pars.mint(alice, 1000e9);
        assertEq(pars.balanceOf(alice), 1000e9);
    }

    function test_mint_revertNotVault() public {
        vm.expectRevert(PARS.PARS_OnlyVault.selector);
        vm.prank(alice);
        pars.mint(alice, 1000e9);
    }

    function test_mint_multipleRecipients() public {
        vm.startPrank(vault);
        pars.mint(alice, 1000e9);
        pars.mint(bob, 2000e9);
        vm.stopPrank();

        assertEq(pars.balanceOf(alice), 1000e9);
        assertEq(pars.balanceOf(bob), 2000e9);
        assertEq(pars.totalSupply(), 3000e9);
    }

    // =========  BURN TESTS ========= //

    function test_burn() public {
        // Mint first
        vm.prank(vault);
        pars.mint(alice, 1000e9);

        // Burn
        vm.prank(alice);
        pars.burn(400e9);

        assertEq(pars.balanceOf(alice), 600e9);
        assertEq(pars.totalSupply(), 600e9);
    }

    function test_burnFrom_withApproval() public {
        // Mint first
        vm.prank(vault);
        pars.mint(alice, 1000e9);

        // Approve bob
        vm.prank(alice);
        pars.approve(bob, 500e9);

        // Burn from alice
        vm.prank(bob);
        pars.burnFrom(alice, 500e9);

        assertEq(pars.balanceOf(alice), 500e9);
        assertEq(pars.allowance(alice, bob), 0);
    }

    // =========  TRANSFER TESTS ========= //

    function test_transfer() public {
        vm.prank(vault);
        pars.mint(alice, 1000e9);

        vm.prank(alice);
        pars.transfer(bob, 300e9);

        assertEq(pars.balanceOf(alice), 700e9);
        assertEq(pars.balanceOf(bob), 300e9);
    }

    function test_transferFrom() public {
        vm.prank(vault);
        pars.mint(alice, 1000e9);

        vm.prank(alice);
        pars.approve(bob, 500e9);

        vm.prank(bob);
        pars.transferFrom(alice, bob, 400e9);

        assertEq(pars.balanceOf(alice), 600e9);
        assertEq(pars.balanceOf(bob), 400e9);
        assertEq(pars.allowance(alice, bob), 100e9);
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
        pars.setAuthority(IParsAuthority(address(newAuthority)));

        assertEq(address(pars.authority()), address(newAuthority));
    }

    function test_setAuthority_revertNotGovernor() public {
        MockAuthority newAuthority = new MockAuthority(
            governor,
            guardian,
            policy,
            vault
        );

        vm.expectRevert(PARS.PARS_OnlyGovernor.selector);
        vm.prank(alice);
        pars.setAuthority(IParsAuthority(address(newAuthority)));
    }

    // =========  FUZZ TESTS ========= //

    function testFuzz_mint(uint256 amount) public {
        vm.assume(amount > 0 && amount < type(uint128).max);

        vm.prank(vault);
        pars.mint(alice, amount);

        assertEq(pars.balanceOf(alice), amount);
        assertEq(pars.totalSupply(), amount);
    }

    function testFuzz_transfer(uint256 mintAmount, uint256 transferAmount) public {
        vm.assume(mintAmount > 0 && mintAmount < type(uint128).max);
        vm.assume(transferAmount > 0 && transferAmount <= mintAmount);

        vm.prank(vault);
        pars.mint(alice, mintAmount);

        vm.prank(alice);
        pars.transfer(bob, transferAmount);

        assertEq(pars.balanceOf(alice), mintAmount - transferAmount);
        assertEq(pars.balanceOf(bob), transferAmount);
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
