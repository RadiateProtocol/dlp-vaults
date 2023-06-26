// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ERC20Upgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {IERC20Upgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IMultiFeeDistribution as MFD} from "../interfaces/radiant-interfaces/IMultiFeeDistribution.sol";

contract rDLP is Initializable, ERC20Upgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    MFD public constant mfd = MFD(0x76ba3eC5f5adBf1C58c91e86502232317EeA72dE);
    IERC20Upgradeable public constant dlp =
        IERC20Upgradeable(0x32dF62dc3aEd2cD6224193052Ce665DC18165841);

    function initialize(address owner) public initializer {
        __ERC20_init("Radiate dLP", "rdLP");
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
        IERC20Upgradeable(tokenAddress).safeTransfer(owner(), tokenAmount);
    }

    function lock() external onlyOwner {
        uint256 amount = dlp.balanceOf(address(this));
        if (dlp.allowance(address(this), address(mfd)) < amount) {
            dlp.safeApprove(address(mfd), type(uint256).max);
        }
        mfd.stake(amount, address(this), 1);
    }

    function exit() external onlyOwner {
        mfd.exit(true);
        mfd.withdrawExpiredLocksFor(address(this));
        mfd.getAllRewards();
    }
}
