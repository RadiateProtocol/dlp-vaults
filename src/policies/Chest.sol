// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "src/Kernel.sol";
import {RolesConsumer, ROLESv1} from "../modules/ROLES/OlympusRoles.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Treasury} from "src/modules/TRSRY/TRSRY.sol";

contract Chest is Policy, RolesConsumer {
    constructor(Kernel kernel) Policy(kernel) {}

    Treasury public TRSRY;

    function configureDependencies()
        external
        override
        returns (Keycode[] memory dependencies)
    {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("ROLES");
        dependencies[1] = toKeycode("TRSRY");
        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        TRSRY = Treasury(getModuleAddress(dependencies[1]));
    }

    function requestPermissions()
        external
        pure
        override
        returns (Permissions[] memory requests)
    {
        requests = new Permissions[](1);
        requests[0] = Permissions(
            toKeycode("TRSRY"),
            Treasury.withdraw.selector
        );
    }

    function withdraw(
        ERC20 _token,
        uint256 _amount
    ) external onlyRole("ADMIN") {
        TRSRY.withdraw(_token, _amount);
    }
}
