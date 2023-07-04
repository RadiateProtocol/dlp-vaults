// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

import "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

// forge script DeployProxyAdmin --rpc-url $ARBITRUM_RPC_URL --broadcast --verify -slow -vv
// forge script DeployProxyAdmin --rpc-url $ARBITRUM_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify --skip-simulation --slow -vvvv
contract DeployProxyAdmin is Script {

    function run() public {
        console2.log("Broadcast sender", msg.sender);

        vm.startBroadcast();

        address admin = address(new ProxyAdmin());

        vm.stopBroadcast();

        console2.log("admin", admin);
        console2.log("\n");

        {
            string memory objName = "deploy";
            string memory json;
            json = vm.serializeAddress(objName, "admin", admin);

            string memory filename = "./json/admin.json";
            vm.writeJson(json, filename);
        }
    }
}
