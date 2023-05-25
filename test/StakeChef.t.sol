// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {DLPVault} from "../src/policies/DLPVault.sol";
import {RADToken} from "../src/modules/TOKEN/RADToken.sol";
import {MockERC20} from "./MockERC20.sol";
import {Treasury} from "../src/modules/TRSRY/TRSRY.sol";
import {OlympusRoles} from "../src/modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "../src/policies/RolesAdmin.sol";

import {ERC20} from "@solmate/tokens/ERC20.sol";

import "../src/Kernel.sol";
import "forge-std/console2.sol";

import {UserFactory} from "./lib/UserFactory.sol";

contract StakeChefTest is Test {
    DLPVault public dlpVault;
    Treasury public treasury;
    Kernel public kernel;
    RADToken public token;
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
        kernel.executeAction(Actions.InstallModule, address(token));

        rolesAdmin = new RolesAdmin(kernel);
        token = new RADToken(kernel);
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(token));



        dlpVault = new DLPVault(
            ERC20(address(DLP)),
            ERC20(address(WETH)),
            100,
            kernel
        );
        kernel.executeAction(Actions.ActivatePolicy, address(dlpVault));
        
        bytes32 adminrole = "admin";
        rolesAdmin.grantRole(adminrole, admin);
    }

    function test_admin() public {
        
    }

}