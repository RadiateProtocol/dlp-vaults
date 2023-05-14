// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;
import "src/kernel.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

contract DLPVault is ERC4626, Module {
    using SafeTransferLib for ERC20;

    constructor(
        Kernel kernel_,
        ERC20 dlpaddress_
    ) ERC4626(dlpaddress_, "Radiate DLP Vault", "RD-DLP") Module(kernel_) {
        kernel = kernel_;
    }

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
        return toKeycode("DLPVT");
    }

    uint256 public amountBorrowed;

    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this)) + amountBorrowed;
    }

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
    ) external permissioned returns (uint256 shares) {
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

    function redeem(
        uint256 assets,
        address receiver,
        address owner,
        address sender
    ) external permissioned returns (uint256 shares) {
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

    function mint(
        uint256 assets,
        address receiver,
        address sender
    ) external permissioned returns (uint256 shares) {
        assets = previewMint(shares); // No need to check for rounding error, previewMint rounds up.

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(sender, receiver, assets, shares);

        afterDeposit(assets, shares);
    }

    function deposit(
        uint256 assets,
        address receiver,
        address sender
    ) external permissioned returns (uint256 shares) {
        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(sender, receiver, assets, shares);

        afterDeposit(assets, shares);
    }

    // Hook to update the amount
    function updateBorrowedAsset(int256 _amount) external permissioned {
        if (_amount > 0) {
            amountBorrowed += uint256(_amount);
        } else {
            amountBorrowed -= uint256(_amount);
        }
    }

    function beforeWithdraw(uint256 assets, uint256 shares) internal override {}

    function afterDeposit(uint256 assets, uint256 shares) internal override {}
}
