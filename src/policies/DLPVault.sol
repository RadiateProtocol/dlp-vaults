// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "../Kernel.sol";
import {RolesConsumer, ROLESv1} from "../modules/ROLES/OlympusRoles.sol";
import {ERC4626} from "@solmate/mixins/ERC4626.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";

contract DLPVault is Policy, RolesConsumer, ERC4626 {
    // =========  EVENTS ========= //
    event RewardAdded(uint256 reward);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event Borrow(address indexed _leverager, uint256 _amount);
    event Repay(address indexed _leverager, uint256 _amount);
    event FeePercentUpdated(uint256 feePercent);
    event RewardBaseTokensUpdated(address[] rewardBaseTokens);
    event WithdrawalQueued(
        uint256 indexed withdrawalQueueIndex, address indexed owner, address indexed receiver, uint256 assets
    );
    // =========  ERRORS ========= //

    error DLPVault_previous_reward_period_not_finished(uint256 periodFinish);
    error DLPVault_provided_reward_rate_too_high(uint256 rewardRate);
    error DLPVault_WithdrawZero(address sender);
    error DLPVault_FeePercentTooHigh(uint256 _feePercent);

    //todo implement custom errors
    // =========  STATE ========= //
    ERC20 public DLPAddress;
    ERC20 public rewardsToken;
    address[] public rewardBaseTokens;
    uint256 public amountBorrowed;
    uint256 public interestfee; // Scaled by RATIO_DIVISOR
    uint256 public feePercent; // Deposit Fee
    mapping(address => uint256) public borrowedBy;

    uint256 public withdrawalQueueIndex;

    struct WithdrawalQueue {
        address caller;
        address owner;
        address receiver;
        uint256 assets;
    }

    WithdrawalQueue[] public withdrawalQueue;

    constructor(ERC20 _asset, ERC20 _rewardsToken, uint256 _interestfee, Kernel _kernel)
        ERC4626(_asset, "Radiate-DLP Vault", "RD-DLP")
        Policy(_kernel)
    {
        DLPAddress = _asset;
        rewardsToken = _rewardsToken; // WETH
        interestfee = _interestfee;
    }

    //============================================================================================//
    //                                     DEFAULT OVERRIDES                                      //
    //============================================================================================//

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");
        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
    }

    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        requests = new Permissions[](0);
    }

    //============================================================================================//
    //                                     ADMIN                                                  //
    //============================================================================================//

    function setInterest(uint256 _interestfee) external onlyRole("admin") {
        interestfee = _interestfee;
    }

    function setDepositFee(uint256 _feePercent) external onlyRole("admin") {
        if (_feePercent <= 1e4) revert DLPVault_FeePercentTooHigh(_feePercent);
        feePercent = _feePercent;
        emit FeePercentUpdated(_feePercent);
    }

    function addRewardBaseTokens(address[] memory _tokens) external onlyRole("admin") {
        rewardBaseTokens = _tokens;
        emit RewardBaseTokensUpdated(_tokens);
    }

    function getRewardBaseTokens() external view returns (address[] memory) {
        return rewardBaseTokens;
    }

    //============================================================================================//
    //                                     BORROW                                                 //
    //============================================================================================//
    function borrow(uint256 _amount) external onlyRole("leverager") returns (uint256) {
        DLPAddress.transfer(msg.sender, _amount);
        amountBorrowed += _amount;
        borrowedBy[msg.sender] += _amount;
        emit Borrow(msg.sender, _amount);
        return _amount;
    }

    function repayBorrow(uint256 _amount) external {
        DLPAddress.transferFrom(msg.sender, address(this), _amount);
        if (borrowedBy[msg.sender] < _amount) {
            _amount = borrowedBy[msg.sender];
            // Prevent underflow if amount is higher than borrowed
            // Repaid borrow can exceed debt outstanding
        }
        amountBorrowed -= _amount;
        borrowedBy[msg.sender] -= _amount;
        emit Repay(msg.sender, _amount);
    }

    function sendRewards(uint256 _amount) external {
        rewardsToken.transferFrom(msg.sender, address(this), _amount);
        _notifyRewardAmount(_amount);
    }

    //============================================================================================//
    //                               VAULT LOGIC                                                  //
    //============================================================================================//

    function deposit(uint256 amount) external {
        DLPAddress.transferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount);
    }

    function afterDeposit(uint256) internal updateReward(msg.sender) {
        processWithdrawalQueue(); // ooo it's a punzeeeee
    }

    function beforeWithdraw(uint256 amount) internal updateReward(msg.sender) {
        if (amount > 0) revert DLPVault_WithdrawZero(msg.sender);
    }

    // Brick redeem() to prevent users from redeeming – withdraws only
    function previewRedeem(uint256) public pure override returns (uint256) {
        return 0;
    }

    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) {
                allowance[owner][msg.sender] = allowed - assets;
            }
        }
        if (assets <= DLPAddress.balanceOf(address(this))) {
            // Process withdrawal since there's enough cash
            beforeWithdraw(assets);
            _burn(owner, assets);

            emit Withdraw(msg.sender, receiver, owner, assets, assets);

            asset.transfer(receiver, assets);
            return assets;
        } else {
            // Add to withdrawal queue
            uint256 queueIndex = withdrawalQueue.length - withdrawalQueueIndex;
            withdrawalQueue.push(
                WithdrawalQueue({caller: msg.sender, owner: owner, receiver: receiver, assets: assets})
            );
            emit WithdrawalQueued(queueIndex, owner, receiver, assets);
            processWithdrawalQueue();
            return 0;
        }
    }

    function processWithdrawalQueue() public {
        for (uint256 i = withdrawalQueueIndex; i < withdrawalQueue.length; i++) {
            WithdrawalQueue memory queueItem = withdrawalQueue[i];
            if (queueItem.assets <= DLPAddress.balanceOf(address(this))) {
                // Process withdrawal since there's enough cash
                // Approval check already done in withdraw()
                // Skip over invalid withdrawals
                if (balanceOf[queueItem.owner] >= queueItem.assets) {
                    beforeWithdraw(queueItem.assets);
                    _burn(queueItem.owner, queueItem.assets);
                    asset.transfer(queueItem.receiver, queueItem.assets);
                    emit Withdraw(
                        queueItem.caller, queueItem.receiver, queueItem.owner, queueItem.assets, queueItem.assets
                    );
                }
                delete withdrawalQueue[i];
                withdrawalQueueIndex++;
            } else {
                break; // Break until there's enough cash in the vault again
            }
        }
    }

    function totalAssets() public view override returns (uint256) {
        return amountBorrowed + DLPAddress.balanceOf(address(this));
    }

    //============================================================================================//
    //                             REWARDS LOGIC                                                  //
    //============================================================================================//

    /* ========== STATE VARIABLES ========== */

    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public rewardsDuration = 7 days;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    /* ========== VIEWS ========== */
    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalAssets() == 0) {
            return rewardPerTokenStored;
        }
        return ((rewardPerTokenStored + lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18) / totalSupply;
    }

    function earned(address account) public view returns (uint256) {
        return ((balanceOf[account] * rewardPerToken() - userRewardPerTokenPaid[account]) / 1e18) + rewards[account];
    }

    function getRewardForDuration() external view returns (uint256) {
        return rewardRate * rewardsDuration;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function getReward() public updateReward(msg.sender) {
        //overrides
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardsToken.transfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function _notifyRewardAmount(uint256 reward) internal updateReward(address(0)) {
        if (block.timestamp >= periodFinish) {
            rewardRate = reward / rewardsDuration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (reward + leftover) / rewardsDuration;
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint256 balance = rewardsToken.balanceOf(address(this));
        if (rewardRate <= balance / rewardsDuration) revert DLPVault_provided_reward_rate_too_high(rewardRate);

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration;
        emit RewardAdded(reward);
    }

    function setRewardsDuration(uint256 _rewardsDuration) external onlyRole("admin") {
        if (block.timestamp > periodFinish) revert DLPVault_previous_reward_period_not_finished(periodFinish);
        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(rewardsDuration);
    }

    /* ========== MODIFIERS ========== */

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }
}
