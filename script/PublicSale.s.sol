// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "src/launch_contracts/PresaleContractFlattened.sol";
import "forge-std/Script.sol";

contract LaunchScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address multisig = vm.envAddress("RAD_MULTISIG");

        RADPresale presale = new RADPresale(
            multisig,
            IERC20(0x7CA0B5Ca80291B1fEB2d45702FFE56a7A53E7a97), // RADT address
            IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8), // USDC.e on arbi
            3 days
        );
        console2.log("Public sale address: ", address(presale));
        vm.stopBroadcast();
    }
}
