// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "src/policies/DLPVault.sol";
import "src/policies/Leverager.sol";
import "src/policies/StakeChef.sol";
import "src/policies/RolesAdmin.sol";

import "src/Kernel.sol";

contract CounterScript is Script {
    function setUp() public {}

    function run() public {
        vm.broadcast();
    }
}
