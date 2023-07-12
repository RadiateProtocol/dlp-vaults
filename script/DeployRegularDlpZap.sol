// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

import "../src/zap/regularDLPZap.sol";

// forge script DeployRegularDlpZap --rpc-url $ARBITRUM_RPC_URL --broadcast --verify -slow -vv
// forge script DeployRegularDlpZap --rpc-url $ARBITRUM_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify --skip-simulation --slow -vvvv
contract DeployRegularDlpZap is Script {

    function run() public {
        console2.log("Broadcast sender", msg.sender);

        vm.startBroadcast();

        address zap = address(new RegularDLPZap());

        vm.stopBroadcast();

        console2.log("zap", zap);
        console2.log("\n");

        {
            string memory objName = "deploy";
            string memory json;
            json = vm.serializeAddress(objName, "zap", zap);

            string memory filename = "./json/regular_zap.json";
            vm.writeJson(json, filename);
        }
    }
}
