// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./RADToken.sol";
import "./DLPVault.sol";

contract StakeChef is Ownable {
    DLPVault public immutable token;
    IERC20 public immutable weth;
    IERC20 public immutable rewardToken;
    address public treasury;

    uint256 public rewardPerBlock;
    uint256 public interestPerBlock;
    uint256 public endBlock;
    uint256 public lastRewardBlock;
    uint256 public accRewardPerShare;
    uint256 public accDiscountPerShare;
    uint256 public totalUserAssets;

    struct UserInfo {
        uint256 amount; // How many tokens the user has provided.
        uint256 rewardDebt; // Reward debt.
        uint256 interestDebt; // Amount taken from principal for POL
    }

    mapping(address => UserInfo) public userInfo;

    constructor(
        DLPVault _token,
        IERC20 _rewardToken,
        address _treasury,
        IERC20 _weth
    ) {
        token = _token;
        rewardToken = _rewardToken;
        treasury = _treasury;
        weth = _weth;
    }

    function updateEndBlock(uint256 _endBlock) public onlyOwner {
        endBlock = _endBlock;
    }

    function updateRewardPerBlock(uint256 _rewardPerBlock) public onlyOwner {
        rewardPerBlock = _rewardPerBlock;
    }

    function updateInterestPerBlock(
        uint256 _interestPerBlock
    ) public onlyOwner {
        interestPerBlock = _interestPerBlock;
    }

    function updatePool() public {
        if (block.number <= lastRewardBlock) {
            return;
        }
        uint256 tokenSupply = token.balanceOf(address(this));
        if (tokenSupply == 0) {
            lastRewardBlock = block.number;
            return;
        }

        // claim rewards or other logic here
        token.claimRewards();
        // transfer to treasury
        weth.transfer(treasury, weth.balanceOf(address(this)));
        // add new minting logic here
        uint256 multiplier = block.number - lastRewardBlock;
        uint256 reward = multiplier * rewardPerBlock;
        accRewardPerShare += (reward * 1e12) / tokenSupply;
        accDiscountPerShare += multiplier * interestPerBlock; // Fixed rate
        lastRewardBlock = block.number;
    }

    function deposit(uint256 _amount) public {
        UserInfo storage user = userInfo[msg.sender];
        updatePool();
        if (user.amount > 0) {
            uint256 pending = (user.amount * accRewardPerShare) /
                1e12 -
                user.rewardDebt;
            rewardToken.transfer(msg.sender, pending);
        }
        token.transferFrom(msg.sender, address(this), _amount);
        user.amount += _amount;
        user.rewardDebt = (user.amount * accRewardPerShare) / 1e12;
        user.interestDebt = (user.amount * accDiscountPerShare) / 1e12;
        totalUserAssets += _amount;
    }

    function withdraw(uint256 _amount) public {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool();
        uint256 _accDiscountPerShare = accDiscountPerShare; // Save sloads
        uint256 _accRewardPerShare = accRewardPerShare; // Save sloads
        uint256 netInterest = (user.amount * _accDiscountPerShare) /
            1e12 -
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
                rewardToken.transfer(msg.sender, _pending);
            }

            delete userInfo[msg.sender];
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
            (2 * 1e12) -
            user.rewardDebt;
        if (pending > 0) {
            rewardToken.transfer(msg.sender, pending);
        }
        user.amount -= _amount;
        user.interestDebt = (user.amount * _accDiscountPerShare) / 1e12;
        user.rewardDebt = (user.amount * _accRewardPerShare) / 1e12;
        totalUserAssets -= _amount;
        token.transfer(msg.sender, _amount);
    }

    function pendingReward(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 _accRewardPerShare = accRewardPerShare;
        uint256 lpSupply = token.balanceOf(address(this));
        if (block.number > lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = block.number - lastRewardBlock;
            uint256 reward = multiplier * rewardPerBlock;
            _accRewardPerShare += (reward * 1e12) / lpSupply;
        }
        return (user.amount * _accRewardPerShare) / 1e12 - user.rewardDebt;
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
        return (user.amount * _accDiscountPerShare) / 1e12 - user.interestDebt;
    }

    function withdrawPOL(uint256 amount) external onlyOwner {
        if (token.balanceOf(address(this)) > totalUserAssets + amount) {
            token.transfer(treasury, amount);
        }
    }
}
