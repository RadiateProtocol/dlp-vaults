/*
                         $$\ $$\            $$\               
                         $$ |\__|           $$ |              
 $$$$$$\  $$$$$$\   $$$$$$$ |$$\  $$$$$$\ $$$$$$\    $$$$$$\  
$$  __$$\ \____$$\ $$  __$$ |$$ | \____$$\\_$$  _|  $$  __$$\ 
$$ |  \__|$$$$$$$ |$$ /  $$ |$$ | $$$$$$$ | $$ |    $$$$$$$$ |
$$ |     $$  __$$ |$$ |  $$ |$$ |$$  __$$ | $$ |$$\ $$   ____|
$$ |     \$$$$$$$ |\$$$$$$$ |$$ |\$$$$$$$ | \$$$$  |\$$$$$$$\ 
\__|      \_______| \_______|\__| \_______|  \____/  \_______|
https://radiateprotocol.com/
*/
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract esRADT is ERC20("Escrowed RADT", "esRADT"), Ownable, ReentrancyGuard {
    constructor() {}

    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    struct UserInfo {
        uint256 totalVested;
        uint256 lastInteractionTime;
        uint256 VestPeriod;
    }

    mapping(address => bool) public whitelist;
    mapping(address => UserInfo) public userInfo;

    uint256 public vestingPeriod = 200 days;
    IERC20 public RADT = IERC20(0x7CA0B5Ca80291B1fEB2d45702FFE56a7A53E7a97);

    function burn(uint256 _amount) external {
        _burn(msg.sender, _amount);
    }

    function whitelistAddress(
        address _address,
        bool _value
    ) external onlyOwner {
        whitelist[_address] = _value;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        require(whitelist[sender], "Not whitelisted");
        _spendAllowance(sender, msg.sender, amount);
        _transfer(sender, recipient, amount);
        return true;
    }

    function claimableTokens(address _address) external view returns (uint256) {
        uint256 timePass = block.timestamp.sub(
            userInfo[_address].lastInteractionTime
        );
        uint256 claimable;
        if (timePass >= userInfo[msg.sender].VestPeriod) {
            claimable = userInfo[_address].totalVested;
        } else {
            claimable = userInfo[_address].totalVested.mul(timePass).div(
                userInfo[_address].VestPeriod
            );
        }
        return claimable;
    }

    function vest(uint256 _amount) external nonReentrant {
        require(
            this.balanceOf(msg.sender) >= _amount,
            "esRADT balance too low"
        );
        uint256 _amountin = _amount;
        uint256 amountOut = _amountin;

        userInfo[msg.sender].totalVested = userInfo[msg.sender].totalVested.add(
            amountOut
        );
        userInfo[msg.sender].lastInteractionTime = block.timestamp;
        userInfo[msg.sender].VestPeriod = vestingPeriod;

        _burn(msg.sender, _amount);
    }

    function lock(uint256 _amount) external nonReentrant {
        require(RADT.balanceOf(msg.sender) >= _amount, "RADT balance too low");
        uint256 amountOut = _amount;
        _mint(msg.sender, amountOut);
        RADT.safeTransferFrom(msg.sender, address(this), _amount);
    }

    function claim() public nonReentrant {
        require(userInfo[msg.sender].totalVested > 0, "no mint");
        uint256 timePass = block.timestamp.sub(
            userInfo[msg.sender].lastInteractionTime
        );
        uint256 claimable;
        if (timePass >= userInfo[msg.sender].VestPeriod) {
            claimable = userInfo[msg.sender].totalVested;
            userInfo[msg.sender].VestPeriod = 0;
        } else {
            claimable = userInfo[msg.sender].totalVested.mul(timePass).div(
                userInfo[msg.sender].VestPeriod
            );
            userInfo[msg.sender].VestPeriod = userInfo[msg.sender]
                .VestPeriod
                .sub(timePass);
        }
        userInfo[msg.sender].totalVested = userInfo[msg.sender].totalVested.sub(
            claimable
        );
        userInfo[msg.sender].lastInteractionTime = block.timestamp;

        RADT.transfer(msg.sender, claimable);
    }

    function exitEarly() external nonReentrant returns (uint256) {
        // 50% penalty for early exit – claim rewards first and then exit early
        uint256 claimable;
        if (whitelist[msg.sender] == true) {
            // Bypass penalty for whitelisted addresses
            claimable = userInfo[msg.sender].totalVested;
            userInfo[msg.sender].VestPeriod = 0;
            userInfo[msg.sender].totalVested = 0;
            userInfo[msg.sender].lastInteractionTime = block.timestamp;
        }
        uint256 timePass = block.timestamp.sub(
            userInfo[msg.sender].lastInteractionTime
        );
        if (userInfo[msg.sender].VestPeriod == 0) {
            return 0;
        } else {
            claimable =
                userInfo[msg.sender].totalVested.mul(timePass).div(
                    userInfo[msg.sender].VestPeriod
                ) /
                2; // 50% early exit penalty
            userInfo[msg.sender].VestPeriod = 0;
            userInfo[msg.sender].totalVested = 0;
            userInfo[msg.sender].lastInteractionTime = block.timestamp;
        }
        RADT.transfer(msg.sender, claimable);
        return claimable;
    }

    function remainingVestedTime() external view returns (uint256) {
        uint256 timePass = block.timestamp.sub(
            userInfo[msg.sender].lastInteractionTime
        );
        if (timePass >= userInfo[msg.sender].VestPeriod) {
            return 0;
        } else {
            return userInfo[msg.sender].VestPeriod.sub(timePass);
        }
    }
}
