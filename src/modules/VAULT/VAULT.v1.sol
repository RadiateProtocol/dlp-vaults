// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "src/Kernel.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

abstract contract VAULTv1 is Module, ERC4626 {
    uint256 public amountInvested;

    // Brick methods to allow for context to be passed in
    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {}

    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256) {}

    function deposit(uint256 assets, address receiver) public override returns (uint256) {}

    function mint(uint256 shares, address receiver) public override returns (uint256) {}

    function _withdraw(uint256 assets, address receiver, address owner, address sender)
        external
        virtual
        returns (uint256 shares);

    function _redeem(uint256 shares, address receiver, address owner, address sender)
        external
        virtual
        returns (uint256 assets);

    function _mint(uint256 shares, address receiver, address sender) external virtual returns (uint256 assets);

    function _deposit(uint256 assets, address receiver, address sender) external virtual returns (uint256 shares);

    function _invest(uint256 amount) external virtual;

    /// @dev ADD UNDERFLOW CHECKS IF ASSET IS INTEREST BEARING
    function _divest(uint256 amount) external virtual;
}
