// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "src/Kernel.sol";
import {RolesConsumer, ROLESv1} from "../modules/ROLES/OlympusRoles.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Treasury} from "src/modules/TRSRY/TRSRY.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract veRADT is Policy, RolesConsumer, ERC20 {
    using SafeMath for uint256;

    constructor(
        Kernel kernel
    ) Policy(kernel) ERC20("Vote Escrowed Radiate", "veRADT") {}

    Treasury public TRSRY;
    ERC20 public RADT;
    uint256[7] public lockTimes = [
        14 days,
        30 days,
        90 days,
        180 days,
        365 days,
        547 days,
        730 days
    ];

    mapping(address => UserInfo) public userInfo;

    mapping(address => uint256) public locks;
    struct UserInfo {
        uint256 totalVested;
        uint256 lastInteractionTime;
        uint256 VestPeriod;
    }

    function configureDependencies()
        external
        override
        returns (Keycode[] memory dependencies)
    {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("ROLES");
        dependencies[1] = toKeycode("TOKEN");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        RADT = ERC20(getModuleAddress(dependencies[1]));
        // TRSRY = Treasury(getModuleAddress(dependencies[1]));
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

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override onlyRole("ADMIN") returns (bool) {
        _spendAllowance(sender, msg.sender, amount);
        _transfer(sender, recipient, amount);
        return true;
    }

    function transfer(
        address recipient,
        uint256 amount
    ) public override onlyRole("ADMIN") returns (bool) {
        _transfer(msg.sender, recipient, amount);
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

    function vest(uint256 _amount, uint256 _lockIndex) external {
        require(
            this.balanceOf(msg.sender) >= _amount,
            "veRADT balance too low"
        );

        uint256 _amountin = _amount;
        uint256 amountOut = _amountin;

        userInfo[msg.sender].totalVested = userInfo[msg.sender].totalVested.add(
            amountOut
        );
        userInfo[msg.sender].lastInteractionTime = block.timestamp;
        userInfo[msg.sender].VestPeriod = lockTimes[_lockIndex];

        _burn(msg.sender, _amount);
    }

    function lock(uint256 _amount, uint256 _lockIndex) external {
        require(RADT.balanceOf(msg.sender) >= _amount, "RADT balance too low");
        require(
            _lockIndex < lockTimes.length,
            "veRADT: lockIndex out of range"
        );
        uint256 amountOut = _amount;
        _mint(msg.sender, amountOut);
        RADT.transferFrom(msg.sender, address(this), _amount);
    }

    function claim() public {
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

    function exitEarly() external returns (uint256) {
        claim(); // Claim outstanding tokens first
        uint256 claimable;
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
            RADT.transfer(msg.sender, claimable);
            return claimable;
        }
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
