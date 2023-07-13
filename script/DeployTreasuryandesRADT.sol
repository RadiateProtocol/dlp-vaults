// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "src/Kernel.sol";
import {Chest, ERC20} from "src/policies/CHEST.sol";
import {esRADT} from "src/policies/esRADT.sol";

contract DeployTresasury is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address deployer = vm.addr(deployerPrivateKey);
        ERC20 RADT = ERC20(0x7CA0B5Ca80291B1fEB2d45702FFE56a7A53E7a97);
        Kernel kernel = Kernel(0x6d37F6eeDc9ED384E56C67827001901F9Af2EA5F);
        Chest chest = new Chest(kernel);
        console2.log("New chest address: ", address(chest));
        kernel.executeAction(Actions.ActivatePolicy, address(chest));
        esRADT esradt = new esRADT();
        console2.log("New esradt address: ", address(esradt));
        esradt.whitelistAddress(
            0x94b23c2233BC7c9Fe75B22950335d7F792b00E8e,
            true
        ); //wl msig
        esradt.whitelistAddress(
            0xa50FC8Fc0b7845b07DCD00ef6bdE46E5160E3835,
            true
        ); //wl deployer

        chest.withdraw(RADT, 20000 * 1e18); //withdraw 20k RADT for liquidity mining
        RADT.transfer(0x94b23c2233BC7c9Fe75B22950335d7F792b00E8e, 20000 * 1e18); //send 20k RADT to msig
        vm.stopBroadcast();
    }
}
