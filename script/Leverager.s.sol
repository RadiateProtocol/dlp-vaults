// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "src/Kernel.sol";
import {StakeChef} from "src/policies/StakeChef.sol";
import {DLPVault} from "src/policies/DLPVault.sol";
import {Leverager} from "src/policies/Leverager.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract LeveragerScript is Script {
    function run() public {
        address dlp = 0x09E1C5d000C9E12db9b349662aAc6c9E2ACfa7f6;
        address weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        address dai = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
        address usdc = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
        address _kernel = 0xD85317aA40c4258318Dc7EdE5491B38e92F41ddb;

        DLPVault dlpVault = DLPVault(dlp);
        Kernel kernel = Kernel(_kernel);

        vm.startBroadcast();

        // Leverager daiLeverager = new Leverager(
        //     500e18,
        //     1000000e18,
        //     8,
        //     0.90 * 1e6,
        //     dlpVault,
        //     ERC20(dai),
        //     kernel
        // );
        Leverager wethLeverager = new Leverager(
            500e18,
            1000000e18,
            7,
            0.90 * 1e6,
            dlpVault,
            ERC20(weth),
            kernel
        );
        Leverager usdcLeverager = new Leverager(
            500e18,
            1000000e18,
            7,
            0.90 * 1e6,
            dlpVault,
            ERC20(usdc),
            kernel
        );

        // kernel.executeAction(Actions.ActivatePolicy, address(daiLeverager));
        kernel.executeAction(Actions.ActivatePolicy, address(wethLeverager));
        kernel.executeAction(Actions.ActivatePolicy, address(usdcLeverager));

        // console2.log("Dai Leverager address: ", address(daiLeverager));
        console2.log("Usdc Leverager address: ", address(usdcLeverager));
        console2.log("Weth Leverager address: ", address(wethLeverager));

        console2.log("Kernel address: ", address(kernel));

        // // Do a small deposit to prevent 4626 inflation attacks
        // daiLeverager.deposit(1000e18, address(this));

        vm.stopBroadcast();
    }
}
