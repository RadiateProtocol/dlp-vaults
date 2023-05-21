// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;
import "src/kernel.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {VAULTv1} from "./VAULT.v1.sol";

contract LeveragerVault is VAULTv1 {
    using SafeTransferLib for ERC20;

    constructor(
        Kernel kernel_,
        ERC20 asset_
    )
        ERC4626(
            asset_,
            string(abi.encodePacked("Radiate ", asset.name())),
            string(abi.encodePacked("RD-", asset.symbol()))
        )
        Module(kernel_)
    {}

    function VERSION()
        external
        pure
        override
        returns (uint8 major, uint8 minor)
    {
        major = 1;
        minor = 0;
    }

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("LVGVT");
    }

    uint256 public amountBorrowed;

    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this)) + amountBorrowed;
    }

    function _withdraw(
        uint256 assets,
        address receiver,
        address owner,
        address sender
    ) external override permissioned returns (uint256 shares) {
        shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

        if (sender != owner) {
            uint256 allowed = allowance[owner][sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max)
                allowance[owner][sender] = allowed - shares;
        }

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);
    }

    function _redeem(
        uint256 shares,
        address receiver,
        address owner,
        address sender
    ) external override permissioned returns (uint256 assets) {
        if (sender != owner) {
            uint256 allowed = allowance[owner][sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max)
                allowance[owner][sender] = allowed - shares;
        }

        // Check for rounding error since we round down in previewRedeem.
        require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);
    }

    function _mint(
        uint256 shares,
        address receiver,
        address sender
    ) external override permissioned returns (uint256 assets) {
        assets = previewMint(shares); // No need to check for rounding error, previewMint rounds up.

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(sender, receiver, assets, shares);

        afterDeposit(assets, shares);
    }

    function _deposit(
        uint256 assets,
        address receiver,
        address sender
    ) external override permissioned returns (uint256 shares) {
        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(sender, receiver, assets, shares);

        afterDeposit(assets, shares);
    }

    function _invest(uint256 amount) external override permissioned {
        asset.transfer(msg.sender, amount);
        amountBorrowed += amount;
    }

    function _divest(uint256 amount) external override permissioned {
        if (amountBorrowed > amount) {
            amountBorrowed -= amount;
        } else {
            amountBorrowed = 0;
        }
    }
}
