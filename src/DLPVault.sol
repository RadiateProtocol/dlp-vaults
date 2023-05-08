// SPDX-License-Identifier: MIT
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./LeveragerFactory.sol";

pragma solidity 0.8.12;

contract DLPVault is ERC4626, Ownable {
    LeveragerFactory public factory;
    address public DLPAddress;
    address public rewardsToken;
    uint256 public amountBorrowed;
    uint256 public interestfee; // Scaled by RATIO_DIVISOR
    mapping(address => uint256) public borrowedBy;

    struct WithdrawalQueue {
        address caller;
        address owner;
        address receiver;
        uint256 assets;
    }
    WithdrawalQueue[] public withdrawalQueue;
    uint256 public withdrawalQueueIndex;
    /* ========== EVENTS ========== */
    event RewardAdded(uint256 reward);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event Borrow(
        address indexed _leverager,
        uint256 _amount,
        address indexed _borrower
    );
    event Repay(address indexed _leverager, uint256 _amount);
    event WithdrawalQueued(
        uint256 indexed withdrawalQueueIndex,
        address indexed owner,
        address indexed receiver,
        uint256 assets
    );

    constructor(
        ERC20 _asset,
        LeveragerFactory _factory,
        address _rewardsToken,
        uint256 _interestfee
    ) ERC4626(_asset, "Radiate DLP Vault", "RD-DLP") {
        DLPAddress = address(_asset);
        factory = _factory;
        rewardsToken = _rewardsToken; // WETH
        interest = _interest;
    }

    function setInterest(uint256 _interestfee) external onlyOwner {
        interestfee = _interestfee;
    }

    function sendRewards(uint256 _amount) external {
        ERC20(rewardsToken).transferFrom(msg.sender, address(this), _amount);
        _notifyRewardAmount(_amount);
    }

    function borrow(uint256 _amount, address _borrower) external {
        require(
            factory.isLeverager(msg.sender),
            "DLPVault: Only Leveragers can borrow"
        );
        ERC20(DLPAddress).transfer(msg.sender, _amount);
        amountBorrowed += _amount;
        borrowedBy[_borrower] += _amount;
        emit Borrow(msg.sender, _amount, _borrower);
    }

    function repayBorrow(uint256 _amount) external {
        ERC20(DLPAddress).transferFrom(msg.sender, address(this), _amount);
        if (borrowedBy[msg.sender] < _amount) {
            _amount = borrowedBy[msg.sender];
            // Prevent underflow if amount is higher than borrowed
            // Repaid borrow can exceed debt outstanding
        }
        amountBorrowed -= _amount;
        borrowedBy[msg.sender] -= _amount;
        emit Repay(msg.sender, _amount);
    }

    /* ========== 4626 Overrides ========== */
    function afterDeposit(
        uint256 amount
    ) internal override notPaused updateReward(msg.sender) {
        processWithdrawalQueue(); // ooo it's a punzeeeee
    }

    function beforeWithdraw(
        uint256 amount
    ) internal override updateReward(msg.sender) {
        require(amount > 0, "DLPVault: Cannot withdraw 0");
    }

    function totalAssets() public view override returns (uint256) {
        return ERC20(DLPAddress).balanceOf(address(this)) + amountBorrowed;
    }

    // Brick redeem() to prevent users from redeeming – withdraws only
    function previewRedeem() public view override returns (uint256) {
        return 0;
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override returns (uint256) {
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max)
                allowance[owner][msg.sender] = allowed - shares;
        }
        if (assets <= ERC20(DLPAddress).balanceOf(address(this))) {
            // Process withdrawal since there's enough cash
            beforeWithdraw(assets);
            _burn(owner, shares);

            emit Withdraw(msg.sender, receiver, owner, assets, shares);

            asset.safeTransfer(receiver, assets);
        } else {
            // Add to withdrawal queue
            uint256 queueIndex = withdrawalQueue.length - withdrawalQueueIndex;
            withdrawalQueue.push(
                WithdrawalQueue({
                    caller: msg.sender,
                    owner: owner,
                    receiver: receiver,
                    assets: assets
                })
            );
            emit WithdrawalQueued(queueIndex, owner, receiver, assets);
            processWithdrawalQueue();
        }
    }

    function processWithdrawalQueue() public {
        for (uint256 i = withdrawalQueueIndex; i < queueLength; i++) {
            WithdrawalQueue memory queueItem = withdrawalQueue[i];
            if (
                queueItem.assets <= ERC20(DLPAddress).balanceOf(address(this))
            ) {
                // Process withdrawal since there's enough cash
                // Approval check already done in withdraw()
                // Skip over invalid withdrawals
                if (balanceOf(queueItem.owner) >= queueItem.assets) {
                    beforeWithdraw(queueItem.assets);
                    _burn(queueItem.owner, queueItem.assets);
                    asset.safeTransfer(queueItem.receiver, queueItem.assets);
                    emit Withdraw(
                        queueItem.caller,
                        queueItem.receiver,
                        queueItem.owner,
                        queueItem.assets,
                        queueItem.assets
                    );
                }
                delete withdrawalQueue[i];
                withdrawalQueueIndex++;
            } else {
                break; // Break until there's enough cash in the vault again
            }
        }
    }

    /* ========== VIEWS ========== */
    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            ((rewardPerTokenStored +
                lastTimeRewardApplicable() -
                lastUpdateTime) *
                rewardRate *
                1e18) / totalSupply();
    }

    function earned(address account) public view returns (uint256) {
        return
            ((balanceOf(account) *
                rewardPerToken() -
                userRewardPerTokenPaid[account]) / 1e18) + rewards[account];
    }

    function getRewardForDuration() external view returns (uint256) {
        return rewardRate.mul(rewardsDuration);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function getReward() public updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardsToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function _notifyRewardAmount(
        uint256 reward
    ) internal updateReward(address(0)) {
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
        uint balance = rewardsToken.balanceOf(address(this));
        require(
            rewardRate <= balance / rewardsDuration,
            "Provided reward too high"
        );

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration;
        emit RewardAdded(reward);
    }

    function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
        require(
            block.timestamp > periodFinish,
            "Previous rewards period must be complete before changing the duration for the new period"
        );
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
