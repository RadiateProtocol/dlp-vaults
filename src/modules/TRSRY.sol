// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Kernel, Module, Keycode} from "src/Kernel.sol";

contract DefaultTreasury is Module {
    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (Keycode) {
        return Keycode.wrap("TRSRY");
    }

    // Policy Interface

    // more convenient than "transferFrom", since users only have to approve the Treasury
    // and any policy can make approved transfers on the Treasury's behalf.
    // beware of approving malicious policies that can rug the user.

    function depositFrom(
        address depositor_,
        ERC20 asset_,
        uint256 amount_
    ) external permissioned {
        asset_.transferFrom(depositor_, address(this), amount_);
    }

    // must withdraw assets to approved policies, where withdrawn assets are handled in their internal logic.
    // no direct withdraws to arbitrary addresses allowed.
    function withdraw(ERC20 asset_, uint256 amount_) external permissioned {
        asset_.transfer(msg.sender, amount_);
    }
}
