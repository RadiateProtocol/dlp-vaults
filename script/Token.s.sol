// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "src/policies/RolesAdmin.sol";
import "src/Kernel.sol";
import {RADPresale} from "src/launch_contracts/PresaleContractFlattened.sol";
import "src/modules/ROLES/OlympusRoles.sol";
import "src/modules/TOKEN/RADToken.sol";
import "src/modules/TRSRY/TRSRY.sol";
import "src/policies/Initialization.sol";
import "src/Kernel.sol";

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Console2} from "forge-std/Console2.sol";

contract CounterScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address multisig = vm.envUint("RAD_MULTISIG");
        vm.startBroadcast(deployerPrivateKey);
        Kernel kernel = new Kernel();
        Token token = new Token(kernel);
        Treasury treasury = new Treasury(kernel);
        OlympusRoles roles = new OlympusRoles(kernel);
        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.InstallModule, address(treasury));
        kernel.executeAction(Actions.InstallModule, address(token));
        // Activate Policies
        RolesAdmin rolesAdmin = new RolesAdmin(kernel);
        Initialization initialization = new Initialization(
            kernel,
            vm.addr(deployerPrivateKey)
        );

        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(initialization));

        // deploy presale contracts
        RADPresale presale = new RADPresale(address(token), multisig);

        kernel.executeAction(Actions.ChangeExecutor, multisig);
        // Set up vesting (later)
    }
}
