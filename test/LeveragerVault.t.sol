// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {RADToken} from "src/modules/TOKEN/RADToken.sol";
import {Treasury} from "src/modules/TRSRY/TRSRY.sol";
import {LeveragerVault} from "src/modules/VAULT/LeveragerVault.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {StakeChef} from "src/policies/StakeChef.sol";
import {DLPVault} from "src/policies/DLPVault.sol";
import {Leverager} from "src/policies/Leverager.sol";

import {MockDLPVault} from "./mocks/MockDLPVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import "src/Kernel.sol";
import "forge-std/console2.sol";

import {UserFactory} from "./lib/UserFactory.sol";

contract LVGVTtest is Test {
    DLPVault public dlpVault;
    Treasury public treasury;
    Kernel public kernel;
    OlympusRoles public roles;
    RolesAdmin public rolesAdmin;
    MockERC20 public DLP;
    MockERC20 public WETH;
    uint256 public interestRate;
    LeveragerVault public leveragerVault;
    Leverager public leveragerUSDC;
    UserFactory public userCreator;
    address public dlpWhale = 0x1119C4ce8F56d96a51b5A38260Fede037C7126F5;
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
        // treasury = new Treasury(kernel);
        // roles = new OlympusRoles(kernel);
        DLP = new MockERC20("Dynamic Liquity Prov", "DLP", 18);
        leveragerVault = new LeveragerVault(kernel, DLP);

        // // kernel.executeAction(Actions.InstallModule, address(leveragerVault));
        // kernel.executeAction(Actions.InstallModule, address(roles));
        // kernel.executeAction(Actions.InstallModule, address(treasury));

        // rolesAdmin = new RolesAdmin(kernel);

        // kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));

        // WETH = new MockERC20("Wrapped Ether", "WETH", 18);

        // kernel.executeAction(Actions.ActivatePolicy, address(dlpVault));
    }
    function test_default() public {
        assertTrue(true);
    }


}
