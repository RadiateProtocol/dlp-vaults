// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import "src/policies/SimpleDLPVault.sol";

contract deployDLP is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address multisig = vm.envAddress("RAD_MULTISIG");
        vm.startBroadcast(deployerPrivateKey);
        rDLP dlp = new rDLP();
        dlp.initialize(multisig);
        console2.log("New DLP address: ", address(dlp));
        vm.stopBroadcast();
    }
}
