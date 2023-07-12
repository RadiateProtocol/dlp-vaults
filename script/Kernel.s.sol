// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "src/Kernel.sol";
import "src/modules/ROLES/OlympusRoles.sol";
import "src/modules/TRSRY/TRSRY.sol";

contract KernelScript is Script {
    function run() public {
        vm.startBroadcast();

        Kernel kernel = new Kernel();

        OlympusRoles roles = new OlympusRoles(kernel);

        Treasury treasury = new Treasury(kernel);

        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.InstallModule, address(treasury));

        console2.log("Roles address: ", address(roles));
        console2.log("Treasury address: ", address(treasury));
        console2.log("Kernel address: ", address(kernel));

        vm.stopBroadcast();

        {
            string memory objName = "deploy";
            string memory json;
            json = vm.serializeAddress(objName, "roles", address(roles));
            json = vm.serializeAddress(objName, "trsry", address(treasury));
            json = vm.serializeAddress(objName, "kernel", address(kernel));

            string memory filename = "./json/kernel.json";
            vm.writeJson(json, filename);
        }
    }
}
