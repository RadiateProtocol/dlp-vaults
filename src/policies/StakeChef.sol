// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {RolesConsumer, ROLESv1} from "src/modules/ROLES/OlympusRoles.sol";
import {RADToken} from "src/modules/TOKEN/RADToken.sol";
import {DLPVault} from "./DLPVault.sol";
import "forge-std/console2.sol";

import "src/Kernel.sol";

contract StakeChef is Policy, RolesConsumer {
    // =========  EVENTS ========= //

    event Deposit(address indexed _user, uint256 _amount);
    event Withdraw(address indexed _user, uint256 _amount);
    event RewardClaimed(address indexed _user, uint256 _amount);

    // =========  ERRORS ========= //

    error WithdrawTooMuch(address _user, uint256 _amount);
    error InvalidInterestRate(uint256 _interestPerBlock);
    error InvalidEndBlock(uint256 _endBlock);
    error InvalidRewardPerBlock(uint256 _rewardPerBlock);

    // =========  STATE  ========= //
    RADToken public TOKEN;
    address public TRSRY;
    DLPVault public immutable dlptoken;
    IERC20 public immutable weth;
    uint256 public constant SCALAR = 1e6; // SCALAR IS 1e6 BC BLOCKTIMES ON ARBI ARE SO QUICK
    uint256 public rewardPerBlock;
    uint256 public interestPerBlock;
    uint256 public endBlock;
    uint256 public lastRewardBlock;
    uint256 public accRewardPerShare; // Initialized at 0, increases over time
    uint256 public accDiscountPerShare; // Initialized at 0, increases over time
    uint256 public totalUserAssets; // Will always be slightly inflated

    mapping(address => UserInfo) public userInfo;

    struct UserInfo {
        uint256 amount; // How many tokens the user has provided.
        uint256 rewardDebt; // Reward debt.
        uint256 interestDebt; // Amount taken from principal for POL
    }

    constructor(DLPVault _token, IERC20 _weth, Kernel _kernel) Policy(_kernel) {
        dlptoken = _token;
        weth = _weth;
    }

    //============================================================================================//
    //                                     DEFAULT OVERRIDES                                          //
    //============================================================================================//

    function configureDependencies()
        external
        override
        returns (Keycode[] memory dependencies)
    {
        dependencies = new Keycode[](3);
        dependencies[0] = toKeycode("TOKEN");
        dependencies[1] = toKeycode("ROLES");
        dependencies[2] = toKeycode("TRSRY");
        ROLES = ROLESv1(getModuleAddress(dependencies[1]));
        TOKEN = RADToken(getModuleAddress(dependencies[0]));
        TRSRY = getModuleAddress(toKeycode("TRSRY"));
    }

    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory requests)
    {
        Keycode TOKEN_KEYCODE = toKeycode("TOKEN");
        requests = new Permissions[](1);
        requests[0] = Permissions(TOKEN_KEYCODE, TOKEN.mint.selector);
    }

    //============================================================================================//
    //                                     ADMIN                                                  //
    //============================================================================================//

    function updateEndBlock(uint256 _endBlock) public onlyRole("admin") {
        if (_endBlock <= block.number) {
            revert InvalidEndBlock(_endBlock);
        }
        endBlock = _endBlock;
    }

    function updateRewardPerBlock(
        uint256 _rewardPerBlock
    ) public onlyRole("admin") {
        if (_rewardPerBlock >= SCALAR) {
            revert InvalidRewardPerBlock(_rewardPerBlock);
        }
        rewardPerBlock = _rewardPerBlock;
    }

    function updateInterestPerBlock(
        uint256 _interestPerBlock
    ) public onlyRole("admin") {
        if (_interestPerBlock >= SCALAR) {
            revert InvalidInterestRate(_interestPerBlock);
        }
        interestPerBlock = _interestPerBlock;
    }

    function withdrawPOL(uint256 amount) external onlyRole("admin") {
        if (dlptoken.balanceOf(address(this)) >= totalUserAssets + amount) {
            dlptoken.transfer(TRSRY, amount);
        } else {
            revert WithdrawTooMuch(address(this), amount);
        }
    }

    function _mint(address to, uint256 amount) internal {
        if (amount > 0) {
            TOKEN.mint(to, amount);
        }
    }

    //============================================================================================//
    //                                     STAKING                                                //
    //============================================================================================//
    function updatePool() public {
        if (block.number == lastRewardBlock || totalUserAssets == 0) {
            return;
        }

        dlptoken.getReward();
        uint256 _wethBalance = weth.balanceOf(address(this));
        if (_wethBalance > 0) {
            weth.transfer(TRSRY, _wethBalance);
        }

        uint256 multiplier = block.number - lastRewardBlock;
        uint256 reward = multiplier * rewardPerBlock;
        accRewardPerShare += (reward * SCALAR) / totalUserAssets;
        accDiscountPerShare += multiplier * interestPerBlock; // Fixed rate
        lastRewardBlock = block.number;
    }

    function deposit(uint256 _amount) public {
        UserInfo storage user = userInfo[msg.sender];
        updatePool();
        if (user.amount > 0) {
            uint256 pending = (user.amount * accRewardPerShare) /
                SCALAR -
                user.rewardDebt;
            _mint(msg.sender, pending);
        }
        dlptoken.transferFrom(msg.sender, address(this), _amount);
        user.amount += _amount;
        user.rewardDebt = (user.amount * accRewardPerShare) / SCALAR;
        user.interestDebt = (user.amount * accDiscountPerShare) / SCALAR;
        totalUserAssets += _amount;
        emit Deposit(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) public {
        UserInfo storage user = userInfo[msg.sender];
        updatePool();
        uint256 _accDiscountPerShare = accDiscountPerShare; // Save sloads
        // initial userinterest debt is debt that user DOESN't OWE
        uint256 _currentDebt = (user.amount * _accDiscountPerShare) / SCALAR;
        if (user.amount + user.interestDebt < _currentDebt) {
            totalUserAssets -= user.amount;
            user.amount = 0;
        } else if (user.amount + user.interestDebt < _currentDebt + _amount) {
            revert WithdrawTooMuch(msg.sender, _amount);
        } else {
            totalUserAssets -= (_amount + _currentDebt);
            user.amount += user.interestDebt - (_amount + _currentDebt);
        }
        if (_amount != 0) {
            claimRewards(msg.sender);
        }
        emit Withdraw(msg.sender, _amount);
    }

    function claimRewards(address _user) public returns (uint256) {
        withdraw(0); // Eject user if their principal is all bonded
        return _claimRewards(_user);
    }

    function _claimRewards(address _user) internal returns (uint256) {
        uint256 currentDebt = rewardsBalanceOf(_user);
        if (currentDebt > 0) {
            _mint(_user, currentDebt);
            UserInfo storage user = userInfo[_user];
            user.rewardDebt += currentDebt;
        }
        emit RewardClaimed(_user, currentDebt);
        return currentDebt;
    }

    //============================================================================================//
    //                                     VIEW                                                   //
    //============================================================================================//

    function rewardsBalanceOf(address _user) public view returns (uint256) {
        UserInfo memory user = userInfo[_user];
        uint256 _accRewardPerShare = accRewardPerShare;

        if (block.number > lastRewardBlock && totalUserAssets != 0) {
            uint256 multiplier = block.number - lastRewardBlock;
            uint256 reward = multiplier * rewardPerBlock;
            _accRewardPerShare += (reward * SCALAR) / totalUserAssets;
        }

        uint256 _currentDebt = user.amount + user.interestDebt;
        uint256 _interest = (user.amount * accDiscountPerShare) / SCALAR;

        uint256 _netOutput = (_currentDebt > _interest)
            ? _currentDebt - _interest
            : 0;

        uint256 _avgRewards = ((_currentDebt + _netOutput) *
            _accRewardPerShare) / SCALAR;
        return
            (user.rewardDebt < _avgRewards) ? _avgRewards - user.rewardDebt : 0;
    }

    function balanceOf(address _user) public view returns (uint256) {
        UserInfo memory user = userInfo[_user];
        uint256 _accDiscountPerShare = accDiscountPerShare;

        if (block.number > lastRewardBlock) {
            _accDiscountPerShare +=
                (lastRewardBlock - block.number) *
                interestPerBlock;
        }
        uint256 _currentDebt = user.amount + user.interestDebt;
        uint256 _interest = (_currentDebt * _accDiscountPerShare) / SCALAR;
        if (_currentDebt > _interest) {
            return _currentDebt - _interest;
        } else {
            return 0;
        }
    }
}
