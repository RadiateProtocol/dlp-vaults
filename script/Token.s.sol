// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "src/Kernel.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import "src/launch_contracts/PresaleContractFlattened.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {RADToken as Token} from "src/modules/TOKEN/RADToken.sol";
import {Treasury} from "src/modules/TRSRY/TRSRY.sol";
import {Initialization} from "src/policies/Initialization.sol";

contract TokenScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address multisig = vm.envAddress("RAD_MULTISIG");
        vm.startBroadcast(deployerPrivateKey);
        Kernel kernel = new Kernel();
        Token token = new Token(kernel);
        console2.log("Kernel address: ", address(kernel));

        Treasury treasury = new Treasury(kernel);
        OlympusRoles roles = new OlympusRoles(kernel);
        kernel.executeAction(Actions.InstallModule, address(roles));
        console2.log("Roles address: ", address(roles));

        kernel.executeAction(Actions.InstallModule, address(treasury));
        console2.log("Treasury address: ", address(roles));
        kernel.executeAction(Actions.InstallModule, address(token));
        console2.log("Token address: ", address(roles));
        // Activate Policies
        RolesAdmin rolesAdmin = new RolesAdmin(kernel);
        console2.log("Roles Admin address: ", address(roles));
        Initialization initialization = new Initialization(kernel);
        console2.log("Initialization address: ", address(roles));

        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(initialization));

        // deploy Private presale
        RADPresale presale = new RADPresale(
            multisig,
            IERC20(address(token)),
            7 days
        );
        initialization.mint(address(presale), 10000 * 1e18);

        console2.log("Presale address: ", address(presale));

        // Deploy public presale later
        initialization.mint(multisig, 45000 * 1e18); // Team tokens + public presale tokens + airdrop tokens

        initialization.mint(address(treasury), 96000 * 1e18); // DAO treasury tokens

        // Set up roles
        roles.saveRole("admin", multisig);

        kernel.executeAction(Actions.ChangeExecutor, multisig);
    }
}
