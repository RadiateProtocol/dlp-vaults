// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {RolesConsumer, ROLESv1} from "src/modules/ROLES/OlympusRoles.sol";
import {RADToken} from "src/modules/TOKEN/RADToken.sol";
import {DLPVault} from "./DLPVault.sol";
// import "forge-std/console2.sol";

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
    uint256 public constant SCALAR = 1e6;
    uint256 public rewardPerBlock;
    uint256 public interestPerBlock;
    uint256 public endBlock; // End block timestamp
    uint256 public lastRewardBlock; // End block timestamp
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
        lastRewardBlock = block.timestamp;
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
        if (_endBlock <= block.timestamp) {
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
        if (block.timestamp == lastRewardBlock || totalUserAssets == 0) {
            return;
        }

        dlptoken.getReward();
        uint256 _wethBalance = weth.balanceOf(address(this));
        if (_wethBalance > 0) {
            weth.transfer(TRSRY, _wethBalance);
        }
        uint256 lastBlock = (block.timestamp < endBlock)
            ? block.timestamp
            : endBlock;
        uint256 multiplier = lastBlock - lastRewardBlock;
        uint256 reward = multiplier * rewardPerBlock;
        accRewardPerShare += reward / totalUserAssets;
        accDiscountPerShare += multiplier * interestPerBlock; // Fixed rate
        lastRewardBlock = lastBlock;
    }

    function deposit(uint256 _amount) public {
        UserInfo storage user = userInfo[msg.sender];
        updatePool();
        if (user.amount > 0) {
            _claimRewards(msg.sender);
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
            totalUserAssets -= (_amount + _currentDebt); // todo check this
            user.amount =
                (user.interestDebt + user.amount) -
                (_amount + _currentDebt);
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
        uint256 _rewards = rewardsBalanceOf(_user);
        if (_rewards > 0) {
            _mint(_user, _rewards);
            UserInfo storage user = userInfo[_user];
            user.rewardDebt += _rewards;
        }
        emit RewardClaimed(_user, _rewards);
        return _rewards;
    }

    //============================================================================================//
    //                                     VIEW                                                   //
    //============================================================================================//

    function rewardsBalanceOf(
        address _user
    ) public view returns (uint256 _netRewards) {
        UserInfo memory user = userInfo[_user];
        uint256 _accRewardPerShare = accRewardPerShare;
        uint256 _accDiscountPerShare = accDiscountPerShare;
        uint256 lastBlock = (block.timestamp < endBlock)
            ? block.timestamp
            : endBlock;
        if (lastBlock > lastRewardBlock && totalUserAssets != 0) {
            uint256 multiplier = lastBlock - lastRewardBlock;
            uint256 reward = (multiplier * rewardPerBlock);
            _accRewardPerShare += reward / totalUserAssets;

            // update accDiscountPerShare
            _accDiscountPerShare += multiplier * interestPerBlock;
        }

        uint256 _currentAmount = user.amount + user.interestDebt;
        uint256 _interest = (user.amount * _accDiscountPerShare) / SCALAR;
        uint256 _netOutput = (_currentAmount > _interest)
            ? _currentAmount - _interest
            : 0;

        uint256 _avgRewards = ((_currentAmount + _netOutput) *
            _accRewardPerShare) / 2;

        _netRewards = (user.rewardDebt < _avgRewards)
            ? _avgRewards - user.rewardDebt
            : 0;
    }

    function balanceOf(address _user) public view returns (uint256) {
        UserInfo memory user = userInfo[_user];
        uint256 _accDiscountPerShare = accDiscountPerShare;
        // If endBlock has already passed
        uint256 lastBlock = (block.timestamp < endBlock)
            ? block.timestamp
            : endBlock;
        if (lastBlock > lastRewardBlock && totalUserAssets != 0) {
            _accDiscountPerShare +=
                (lastBlock - lastRewardBlock) *
                interestPerBlock;
        }
        uint256 _currentAmount = user.amount + user.interestDebt;
        uint256 _interest = (user.amount * _accDiscountPerShare) / SCALAR;
        if (_currentAmount > _interest) {
            return _currentAmount - _interest;
        } else {
            return 0;
        }
    }
}
