// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "src/launch_contracts/RADTPublicClaim.sol";
import "forge-std/Script.sol";

contract LaunchScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        RADTClaim claim = new RADTClaim();
        console2.log("New Claim address: ", address(claim));
        vm.stopBroadcast();
    }
}
