// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IMultiFeeDistribution as MFD} from "../interfaces/radiant-interfaces/IMultiFeeDistribution.sol";

contract rDLP is ERC20Upgradeable, OwnableUpgradeable, UUPSUpgradeable {
    MFD public constant mfd = MFD(0x76ba3eC5f5adBf1C58c91e86502232317EeA72dE);
    ERC20 public constant dlp =
        ERC20(0x32dF62dc3aEd2cD6224193052Ce665DC18165841);

    function initialize(address owner) public initializer {
        __ERC20_init("Radiate DLP", "rDLP");
        __Ownable_init();
        __UUPSUpgradeable_init();
        transferOwnership(owner);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function mint(address to, uint256 amount) public {
        dlp.transferFrom(msg.sender, address(this), amount);
        _mint(to, amount);
    }

    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
        dlp.transfer(msg.sender, amount);
    }

    function stake(uint256 amount) public {
        _burn(msg.sender, amount);
    }

    // Recover reward tokens and any other tokens
    function recoverTokens(
        address tokenAddress,
        uint256 tokenAmount
    ) public onlyOwner {
        ERC20(tokenAddress).transfer(owner(), tokenAmount);
    }

    function lock() external onlyOwner {
        uint256 amount = dlp.balanceOf(address(this));
        if (dlp.allowance(address(this), address(mfd)) < amount) {
            dlp.approve(address(mfd), type(uint256).max);
        }
        mfd.stake(amount, address(this), 1);
    }

    function exit() external onlyOwner {
        mfd.exit(true);
    }
}
