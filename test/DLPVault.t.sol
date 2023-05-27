// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import {DLPVault} from "../src/policies/DLPVault.sol";
import {MockERC20} from "./MockERC20.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Treasury} from "../src/modules/TRSRY/TRSRY.sol";
import {OlympusRoles} from "../src/modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "../src/policies/RolesAdmin.sol";
import "../src/Kernel.sol";

import {UserFactory} from "./lib/UserFactory.sol";

contract DLPVaultTest is Test {
    DLPVault public dlpVault;
    Treasury public treasury;
    Kernel public kernel;
    OlympusRoles public roles;
    RolesAdmin public rolesAdmin;
    MockERC20 public DLP;
    MockERC20 public WETH;
    uint256 public interestRate;

    UserFactory public userCreator;

    address public alice;
    address public bob;
    address public carol;
    address public admin;

    function setUp() public {
        userCreator = new UserFactory();

        address[] memory users = userCreator.create(4);
        alice = users[0];
        bob = users[1];
        carol = users[2];
        admin = users[3];

        kernel = new Kernel();
        treasury = new Treasury(kernel);
        roles = new OlympusRoles(kernel);
        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.InstallModule, address(treasury));

        rolesAdmin = new RolesAdmin(kernel);
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));

        DLP = new MockERC20("Dynamic Liquity Prov", "DLP", 18);
        WETH = new MockERC20("Wrapped Ether", "WETH", 18);

        interestRate = 100; // 10%
        dlpVault = new DLPVault(
            ERC20(address(DLP)),
            ERC20(address(WETH)),
            interestRate,
            kernel
        );
        kernel.executeAction(Actions.ActivatePolicy, address(dlpVault));
        bytes32 leveragerrole = "leverager";
        bytes32 adminrole = "admin";
        // Grant the Leverager role
        rolesAdmin.grantRole(leveragerrole, alice);
        rolesAdmin.grantRole(adminrole, address(this));
    }

    // Admin tests
    function testAdmin() public {
        dlpVault.setInterest(200);
        assertEq(dlpVault.interestfee(), 200);

        dlpVault.setDepositFee(200);
        assertEq(dlpVault.feePercent(), 200);

        // test add reward base tokens
    }

    // // Borrow tests
    function test_borrowSuccess() public {
        // deposit 100 DLP
        mintAndDeposit(bob, 100);

        vm.prank(alice);
        // borrow 50 DLP
        dlpVault.borrow(50);

        // check balances
        assertEq(DLP.balanceOf(address(dlpVault)), 50);
        assertEq(dlpVault.totalAssets(), 100);
        assertEq(dlpVault.amountBorrowed(), 50);
    }

    function test_RepaySuccess() public {
        // deposit 100 DLP
        mintAndDeposit(bob, 100);

        // borrow 50 DLP as Leverager
        vm.startPrank(alice);

        dlpVault.borrow(60);

        DLP.approve(address(dlpVault), 30);

        dlpVault.repayBorrow(30);

        // check balances
        assertEq(DLP.balanceOf(address(dlpVault)), 70);
        assertEq(dlpVault.totalAssets(), 100);
        assertEq(dlpVault.amountBorrowed(), 30);

        // Over repay 40 DLP
        DLP.mint(alice, 40);
        DLP.approve(address(dlpVault), 40);
        dlpVault.repayBorrow(40);

        // check balances
        assertEq(DLP.balanceOf(address(dlpVault)), 110);
        assertEq(dlpVault.totalAssets(), 110);
        assertEq(dlpVault.amountBorrowed(), 0);
    }

    function test_withdrawQueue() public {
        // deposit 100 DLP
        mintAndDeposit(alice, 100);
        vm.startPrank(alice);

        // withdraw 50 DLP
        dlpVault.withdraw(50, alice, alice);

        // borrow 40 DLP as Leverager
        dlpVault.borrow(50);

        // withdraw 20 DLP & enter withdrawal queue
        uint256 output = dlpVault.withdraw(20, bob, alice);

        vm.stopPrank();

        assertEq(output, 0);
        mintAndDeposit(carol, 19);

        // Deposit shouldn't trigger queue
        assertEq(dlpVault.withdrawalQueueIndex(), 0);

        mintAndDeposit(carol, 10);

        // Should trigger queue
        assertEq(DLP.balanceOf(bob), 20);
        assertEq(dlpVault.withdrawalQueueIndex(), 1);

        // Give approval to withdraw
        vm.prank(carol);
        dlpVault.approve(bob, 20);

        vm.prank(bob);
        dlpVault.withdraw(10, bob, carol);
        // Vault has a shortfall of 1 DLP, should enter queue

        vm.startPrank(carol);
        // Multiple withdraw requests
        dlpVault.withdraw(10, carol, carol);
        dlpVault.withdraw(1, carol, carol);
        dlpVault.withdraw(1, carol, carol);

        // Remove approval
        vm.prank(carol);
        dlpVault.approve(bob, 0);

        vm.startPrank(alice);
        DLP.approve(address(dlpVault), 100);
        dlpVault.repayBorrow(100);

        // Should trigger queue
        assertEq(dlpVault.withdrawalQueueIndex(), 3);
        
    }

    function testFailRedeem() public {
        mintAndDeposit(alice, 100);
        vm.startPrank(alice);
        dlpVault.redeem(100, alice, alice);
    }

    function testFailMint() public {
        vm.startPrank(alice);
        DLP.mint(alice, 100);
        DLP.approve(address(dlpVault), 100);
        dlpVault.mint(100, alice);
    }

    function mintAndDeposit(address _user, uint256 _amount) public {
        vm.startPrank(_user);
        DLP.mint(_user, _amount);
        DLP.approve(address(dlpVault), _amount);
        dlpVault.deposit(_amount, _user);
        vm.stopPrank();
    }

    // Skip testing for SNX staking logic since it's basically unmodified

    // Key diffs:
    // No safemath
    // Changed imports
    // No staking logic – logic handled by 4626 hooks
    
}
