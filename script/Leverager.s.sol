// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "src/Kernel.sol";
import {StakeChef} from "src/policies/StakeChef.sol";
import {DLPVault} from "src/policies/DLPVault.sol";
import {Leverager} from "src/policies/Leverager.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";

contract LeveragerScript is Script {
    function run() public {
        address _kernelAddress = vm.envAddress("KERNEL_ADDRESS");
        Kernel kernel = Kernel(_kernelAddress);
        uint256 _privateKey = vm.envUint("PRIVATE_KEY");
        address dlp = 0x32dF62dc3aEd2cD6224193052Ce665DC18165841;
        address weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        address dai = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
        DLPVault dlpVault = new DLPVault(
            ERC20(dlp),
            ERC20(weth),
            0.1 * 1e4, // 10% interest rate
            kernel
        );

        vm.startBroadcast(_privateKey);

        Leverager daiLeverager = new Leverager(
            500e18,
            1000000e18,
            8,
            0.90 * 1e6,
            dlpVault,
            ERC20(dai),
            kernel
        );

        kernel.executeAction(Actions.ActivatePolicy, address(daiLeverager));

        console2.log("Dai Leverager address: ", address(daiLeverager));

        // // Do a small deposit to prevent 4626 inflation attacks
        // daiLeverager.deposit(1000e18, address(this));

        vm.stopBroadcast();
    }
}
