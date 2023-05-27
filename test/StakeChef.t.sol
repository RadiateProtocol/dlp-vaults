// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {RADToken} from "src/modules/TOKEN/RADToken.sol";
import {Treasury} from "src/modules/TRSRY/TRSRY.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {StakeChef} from "src/policies/StakeChef.sol";
import {DLPVault} from "src/policies/DLPVault.sol";

import {MockDLPVault} from "./mocks/MockDLPVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import "src/Kernel.sol";
import "forge-std/console2.sol";

import {UserFactory} from "./lib/UserFactory.sol";

contract StakeChefTest is Test {
    Kernel public kernel;
    RADToken public token;
    MockDLPVault public dlpVault;
    StakeChef public stakeChef;
    Treasury public treasury;
    OlympusRoles public roles;
    RolesAdmin public rolesAdmin;

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
        token = new RADToken(address(kernel));
        treasury = new Treasury(kernel);
        roles = new OlympusRoles(kernel);
        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.InstallModule, address(treasury));
        kernel.executeAction(Actions.InstallModule, address(token));

        rolesAdmin = new RolesAdmin(kernel);
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        WETH = new MockERC20("Wrapped Ether", "WETH", 18);
        dlpVault = new MockDLPVault(WETH);
        stakeChef = new StakeChef(DLPVault(address(dlpVault)), WETH, kernel);
        kernel.executeAction(Actions.ActivatePolicy, address(stakeChef));

        bytes32 adminrole = "admin";
        rolesAdmin.grantRole(adminrole, admin);
    }

    function test_admin() public {
        // Donate 100 DLPVault
        dlpVault.mint(address(this), 100);
        dlpVault.transfer(address(stakeChef), 100);

        // Remove PoL
        vm.prank(admin);
        stakeChef.withdrawPOL(100);
        assertEq(dlpVault.balanceOf(address(treasury)), 100);
    }

    function test_depositSuccess() public {
        uint256 amount = 100;
        dlpVault.mint(alice, amount);
        vm.startPrank(alice);
        dlpVault.approve(address(stakeChef), amount);
        stakeChef.deposit(amount);
        // assertEq(stakeChef.balanceOf(alice), amount);
    }

    function test_depositWithdraw() public {
        uint256 amount = 100;
        dlpVault.mint(alice, amount);
        vm.startPrank(alice);
        dlpVault.approve(address(stakeChef), amount);
        stakeChef.deposit(amount);
        stakeChef.withdraw(amount);
        assertEq(stakeChef.balanceOf(alice), 0);
    }

    function test_interestReward() public {
        vm.startPrank(admin);
        stakeChef.updateEndBlock(1000);
        stakeChef.updateRewardPerBlock(10);
        stakeChef.updateInterestPerBlock(1000); //
        uint256 amount = 100;
        mintAndDeposit(alice, amount);

        assertEq(stakeChef.balanceOf(alice), amount);
        assertEq(stakeChef.rewardsBalanceOf(alice), 0);
        uint256 rewards = stakeChef.claimRewards(alice);
        console2.log("rewards", rewards);
        console2.log("block", block.timestamp);
        vm.warp(10000); // approx 9 hours
        // stakeChef.updatePool();
        console2.log("block_1", block.timestamp);
        console2.log("stakeChef.balanceOf(alice)", stakeChef.balanceOf(alice));
        console2.log(
            "stakeChef.rewardsBalance(alice)",
            stakeChef.rewardsBalanceOf(alice) // shows high rewards but will be diluted with other deposits
        );
    }

    function mintAndDeposit(address user, uint256 amount) public {
        dlpVault.mint(user, amount);
        vm.startPrank(user);
        dlpVault.approve(address(stakeChef), amount);
        stakeChef.deposit(amount);
        // fix rewards logic

    }
}

