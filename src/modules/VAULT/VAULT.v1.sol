// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;
import "src/kernel.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

abstract contract VAULTv1 is ERC4626, Module {
    using SafeTransferLib for ERC20;

    uint256 public amountInvested;

    // Brick methods to allow for context to be passed in
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override permissioned returns (uint256) {}

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override permissioned returns (uint256) {}

    function deposit(
        uint256 assets,
        address receiver
    ) public override permissioned returns (uint256) {}

    function mint(
        uint256 shares,
        address receiver
    ) public override permissioned returns (uint256) {}

    function withdraw(
        uint256 assets,
        address receiver,
        address owner,
        address sender
    ) external virtual returns (uint256 shares);

    function redeem(
        uint256 assets,
        address receiver,
        address owner,
        address sender
    ) external virtual returns (uint256 shares);

    function mint(
        uint256 assets,
        address receiver,
        address sender
    ) external virtual returns (uint256 shares);

    function deposit(
        uint256 assets,
        address receiver,
        address sender
    ) external virtual returns (uint256 shares);

    function incrementAmountInvested(uint256 amount) external virtual;

    function decrementAmountInvested(uint256 amount) external virtual;
}