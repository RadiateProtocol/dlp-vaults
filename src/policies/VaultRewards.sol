// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "src/Kernel.sol";
import {RolesConsumer, ROLESv1} from "../modules/ROLES/OlympusRoles.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {ERC4626} from "@solmate/mixins/ERC4626.sol";
import {Treasury} from "src/modules/TRSRY/TRSRY.sol";

contract Rewards is Policy, RolesConsumer {
    constructor(Kernel kernel) Policy(kernel) {}

    ERC20 public esRADT;
    ERC4626[] public leveragers;
    uint256[] public rewardsPerShare;
    uint256 public epochRewards;
    uint256 public constant SCALAR = 1e6;

    function configureDependencies()
        external
        override
        returns (Keycode[] memory dependencies)
    {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");
        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
    }

    function requestPermissions()
        external
        pure
        override
        returns (Permissions[] memory requests)
    {
        requests = new Permissions[](1);
    }

    function setLeveragers(
        ERC4626[] memory _leveragers
    ) external onlyRole("ADMIN") {
        for (uint256 i = 0; i < _leveragers.length; i++) {
            leveragers.push(ERC4626(_leveragers[i]));
        }
    }

    function setRewardWeights(
        uint256[] memory _weights
    ) external onlyRole("ADMIN") {
        epochRewards = esRADT.balanceOf(address(this));
        // Log the number of shares
        for (uint i = 0; i < leveragers.length; i++) {
            uint256 poolRewards = (epochRewards * _weights[i]) / SCALAR;
            rewardsPerShare[i] =
                (poolRewards * SCALAR) /
                leveragers[i].totalSupply();
        }
    }

    function redeemRewards() external {
        // Rewards per share
        // Someone can deposit a large amount and withdraw but rewards are less than the deposit fee
        uint256 rewards;
        // Sum up all rewards
        for (uint256 i = 0; i < leveragers.length; i++) {
            uint256 balance = leveragers[i].balanceOf(msg.sender);
            if (balance == 0) continue;
            rewards += (balance * rewardsPerShare[i]) / SCALAR;
        }
        esRADT.transfer(msg.sender, rewards);
    }

    function recoverERC20(
        ERC20 _token,
        uint256 _amount
    ) external onlyRole("ADMIN") {
        _token.transfer(msg.sender, _amount);
    }
}
