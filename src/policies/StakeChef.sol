// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {RolesConsumer} from "src/modules/ROLES/OlympusRoles.sol";
import {RADToken} from "src/modules/TOKEN/RADToken.sol";
import {DLPVault} from "./DLPVault.sol";
import "src/Kernel.sol";

contract StakeChef is Policy, RolesConsumer {
    // =========  EVENTS ========= //

    event Deposit(address indexed _user, uint256 _amount);
    event Withdraw(address indexed _user, uint256 _amount, uint256 _reward);

    // =========  ERRORS ========= //

    error WithdrawTooMuch(address _user, uint256 _amount);

    // =========  STATE  ========= //
    DLPVault public immutable dlptoken;
    RADToken public immutable TOKEN;
    IERC20 public immutable weth;
    uint256 public constant SCALAR = 1e12;
    uint256 public rewardPerBlock;
    uint256 public interestPerBlock;
    uint256 public endBlock;
    uint256 public lastRewardBlock;
    uint256 public accRewardPerShare;
    uint256 public accDiscountPerShare;
    uint256 public totalUserAssets;

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

    function withdrawPOL(
        uint256 amount
    ) external requirePermission(ADMIN_ROLE) {
        if (dlptoken.balanceOf(address(this)) > totalUserAssets + amount) {
            dlptoken.transfer(TRSRY, amount);
        }
    }

    //============================================================================================//
    //                                     ADMIN                                                  //
    //============================================================================================//

    function updateEndBlock(
        uint256 _endBlock
    ) public requirePermission(ADMIN_ROLE) {
        endBlock = _endBlock;
    }

    function updateRewardPerBlock(
        uint256 _rewardPerBlock
    ) public requirePermission(ADMIN_ROLE) {
        rewardPerBlock = _rewardPerBlock;
    }

    function updateInterestPerBlock(
        uint256 _interestPerBlock
    ) public requirePermission(ADMIN_ROLE) {
        interestPerBlock = _interestPerBlock;
    }

    function withdrawPOL(
        uint256 amount
    ) external requirePermission(ADMIN_ROLE) {
        if (dlptoken.balanceOf(address(this)) > totalUserAssets + amount) {
            dlptoken.transfer(TRSRY, amount);
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
        if (block.number <= lastRewardBlock) {
            return;
        }
        uint256 tokenSupply = dlptoken.balanceOf(address(this));
        if (tokenSupply == 0) {
            lastRewardBlock = block.number;
            return;
        }

        // claim rewards or other logic here
        dlptoken.claimRewards();
        // transfer to treasury
        weth.transfer(TRSRY, weth.balanceOf(address(this)));
        // add new minting logic here
        uint256 multiplier = block.number - lastRewardBlock;
        uint256 reward = multiplier * rewardPerBlock;
        accRewardPerShare += (reward * SCALAR) / tokenSupply;
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
        token.transferFrom(msg.sender, address(this), _amount);
        user.amount += _amount;
        user.rewardDebt = (user.amount * accRewardPerShare) / SCALAR;
        user.interestDebt = (user.amount * accDiscountPerShare) / SCALAR;
        totalUserAssets += _amount;
        emit Deposit(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) public {
        UserInfo storage user = userInfo[msg.sender];
        if (user.amount >= _amount) WithdrawTooMuch(msg.sender, _amount);
        updatePool();
        uint256 _accDiscountPerShare = accDiscountPerShare; // Save sloads
        uint256 _accRewardPerShare = accRewardPerShare; // Save sloads
        uint256 netInterest = (user.amount * _accDiscountPerShare) /
            SCALAR -
            user.interestDebt;
        if (netInterest >= user.amount) {
            // Accrued interest is greater than principal – only withdraw rewards
            _amount = 0;
            totalUserAssets -= user.amount;
            // User can still accrue rewards if their position is underwater and they never claim
            // 10% "liquidation penalty" for underwater positions
            uint256 _pending = ((user.amount) * _accRewardPerShare) /
                (21 * 1e11) -
                user.rewardDebt;
            if (_pending > 0) {
                _mint(msg.sender, _pending);
            }

            delete userInfo[msg.sender];
            emit Withdraw(msg.sender, 0, _pending);
            return;
        } else {
            uint256 interest = user.amount - netInterest;
            user.interestDebt -= interest;
            // If amount > interest, currently accrued interest is wiped, otherwise subtract amount
            user.interestDebt -= (_amount > interest)
                ? interest - _amount
                : interest;
            _amount = (_amount > interest) ? _amount - interest : 0;
        }
        // Get midpoint of initial and net principal - assume constant reward rate
        uint256 pending = ((user.amount * 2 - netInterest) *
            _accRewardPerShare) /
            (2 * SCALAR) -
            user.rewardDebt;
        if (pending > 0) {
            _mint(msg.sender, pending);
        }
        user.amount -= _amount;
        user.interestDebt = (user.amount * _accDiscountPerShare) / SCALAR;
        user.rewardDebt = (user.amount * _accRewardPerShare) / SCALAR;
        totalUserAssets -= _amount;
        dlptoken.transfer(msg.sender, _amount);
        emit Withdraw(msg.sender, _amount, pending);
    }

    //============================================================================================//
    //                                     VIEW                                                   //
    //============================================================================================//

    function pendingReward(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 _accRewardPerShare = accRewardPerShare;
        uint256 lpSupply = token.balanceOf(address(this));
        if (block.number > lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = block.number - lastRewardBlock;
            uint256 reward = multiplier * rewardPerBlock;
            _accRewardPerShare += (reward * SCALAR) / lpSupply;
        }
        return (user.amount * _accRewardPerShare) / SCALAR - user.rewardDebt;
    }

    function pendingInterest(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 _accDiscountPerShare = accDiscountPerShare;
        uint256 lpSupply = token.balanceOf(address(this));
        if (block.number > lastRewardBlock && lpSupply != 0) {
            _accDiscountPerShare +=
                (lastRewardBlock - block.number) *
                interestPerBlock;
        }
        return
            (user.amount * _accDiscountPerShare) / SCALAR - user.interestDebt;
    }
}
