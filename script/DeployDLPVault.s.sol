// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

import "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../src/policies/DLPVault.sol";

// forge script DeployDLPVault --rpc-url $ARBITRUM_RPC_URL --broadcast --verify -slow -vv
// forge script DeployDLPVault --rpc-url $ARBITRUM_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify --skip-simulation --slow -vvvv
contract DeployDLPVault is Script {
    // Deploy config
    address constant proxyAdmin = 0xEA871D39057E94691FA7323042CC015601eA4AF2;
    address constant kernel = 0xEA871D39057E94691FA7323042CC015601eA4AF2;

    function run() public {
        console2.log("Broadcast sender", msg.sender);
        console2.log("Proxy Admin", proxyAdmin);

        vm.startBroadcast();

        address impl = address(new DLPVault());
        address proxy = address(new TransparentUpgradeableProxy(
            impl,
            proxyAdmin,
            abi.encodeWithSignature("initialize(address)", kernel)
        ));

        vm.stopBroadcast();

        console2.log("Impl", impl);
        console2.log("Proxy", proxy);

        console2.log("\n");

        {
            string memory objName = "deploy";
            string memory json;
            json = vm.serializeAddress(objName, "admin", proxyAdmin);
            json = vm.serializeAddress(objName, "impl", impl);
            json = vm.serializeAddress(objName, "proxy", proxy);

            string memory filename = "./json/leverager.json";
            vm.writeJson(json, filename);
        }
    }
}
