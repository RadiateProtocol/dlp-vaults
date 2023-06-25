// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ERC20Upgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IMultiFeeDistribution as MFD} from "../interfaces/radiant-interfaces/IMultiFeeDistribution.sol";

contract rDLP is Initializable, ERC20Upgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    MFD public constant mfd = MFD(0x76ba3eC5f5adBf1C58c91e86502232317EeA72dE);
    IERC20 public constant dlp =
        IERC20(0x32dF62dc3aEd2cD6224193052Ce665DC18165841);

    function initialize(address owner) public initializer {
        __ERC20_init("Radiate dLP", "dDLP");
        __Ownable_init();
        transferOwnership(owner);
    }

    function mint(address to, uint256 amount) public {
        dlp.safeTransferFrom(msg.sender, address(this), amount);
        _mint(to, amount);
    }

    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
        dlp.safeTransfer(msg.sender, amount);
    }

    function stake(uint256 amount) public {
        mfd.stake(amount, address(this), 1);
    }

    // Recover reward tokens and any other tokens
    function recoverTokens(
        address tokenAddress,
        uint256 tokenAmount
    ) public onlyOwner {
        IERC20(tokenAddress).safeTransfer(owner(), tokenAmount);
    }

    function lock() external onlyOwner {
        uint256 amount = dlp.balanceOf(address(this));
        if (dlp.allowance(address(this), address(mfd)) < amount) {
            dlp.safeApprove(address(mfd), type(uint256).max);
        }
        mfd.stake(amount, address(this), 1);
    }

    // Exit any unlocked dLP and claim any pending rewards if _claim is true
    function exit() external onlyOwner {
        mfd.exit(true);
        mfd.withdrawExpiredLocksFor(address(this));
        mfd.getAllRewards();
    }
}
