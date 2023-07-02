// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "../Kernel.sol";
import {RolesConsumer, ROLESv1} from "../modules/ROLES/OlympusRoles.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";

import "../interfaces/radiant-interfaces/IEligibilityDataProvider.sol";
import "../interfaces/radiant-interfaces/IMultiFeeDistribution.sol";
import "../interfaces/radiant-interfaces/IChefIncentivesController.sol";
import "../interfaces/aave/IFlashLoanSimpleReceiver.sol";
import "../interfaces/radiant-interfaces/ILendingPool.sol";
import "../interfaces/radiant-interfaces/ICreditDelegationToken.sol";

import "../interfaces/aave/IPool.sol";

contract DLPVault is ERC4626Upgradeable, RolesConsumer {
    // =========  EVENTS ========= //
    event RewardAdded(uint256 reward);
    event RewardPaid(address indexed user, uint256 reward);
    event FeePercentUpdated(uint256 feePercent);
    event RewardBaseTokensUpdated(address[] rewardBaseTokens);
    event WithdrawalQueued(
        uint256 indexed withdrawalQueueIndex,
        address indexed owner,
        address indexed receiver,
        uint256 assets
    );
    // =========  ERRORS ========= //
    error DLPVault_ONLY_AAVE_LENDING_POOL();
    error DLPVault_previous_reward_period_not_finished(uint256 periodFinish);
    error DLPVault_WithdrawZero(address sender);
    error DLPVault_MintDisabled();
    error DLPVault_FeePercentTooHigh(uint256 _feePercent);
    error DLPVault_VaultCapExceeded(uint256 _vaultCap);

    // =========  STATE ========= //
    // Constants
    ERC20 public constant DLPAddress =
        ERC20(0x32dF62dc3aEd2cD6224193052Ce665DC18165841);
    ERC20 public constant rewardsToken =
        ERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IMultiFeeDistribution constant mfd =
        IMultiFeeDistribution(0x76ba3eC5f5adBf1C58c91e86502232317EeA72dE);

    /// @notice Aave lending pool address (for flashloans)
    IPool public constant aaveLendingPool =
        IPool(0x794a61358D6845594F94dc1DB02A252b5b4814aD);

    /// @notice Lending Pool address
    ILendingPool public constant lendingPool =
        ILendingPool(0xF4B1486DD74D07706052A33d31d7c0AAFD0659E1);

    uint256 public constant defaultLockIndex = 0; // 1 month lock

    // State
    Kernel kernel;
    address[] public rewardBaseTokens;
    uint256 public amountStaked;
    uint256 public vaultCap;
    uint256 public feePercent; // Deposit Fee

    uint256 public withdrawalQueueIndex;

    struct WithdrawalQueue {
        address caller;
        address owner;
        address receiver;
        uint256 assets;
    }

    WithdrawalQueue[] public withdrawalQueue;

    function initialize(Kernel _kernel) public {
        kernel = _kernel;
        __ERC4626_init(ERC20Upgradeable(address(DLPAddress)));
    }

    //============================================================================================//
    //                                     DEFAULT OVERRIDES                                      //
    //============================================================================================//
    function changeKernel(Kernel newKernel_) external {
        require(msg.sender == address(kernel), "DLPVault_onlyKernel"); //todo customerror
        kernel = newKernel_;
    }

    function isActive() external view returns (bool) {
        return kernel.isPolicyActive(Policy(address(this)));
    }

    function configureDependencies()
        external
        returns (Keycode[] memory dependencies)
    {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");
        ROLES = ROLESv1(address(kernel.getModuleForKeycode(dependencies[0])));
    }

    function requestPermissions()
        external
        pure
        returns (Permissions[] memory requests)
    {
        requests = new Permissions[](0);
    }

    //============================================================================================//
    //                                     ADMIN                                                  //
    //============================================================================================//
    // Deposit Fee for Leverager
    function setDepositFee(uint256 _feePercent) external onlyRole("admin") {
        if (_feePercent >= 1e6) revert DLPVault_FeePercentTooHigh(_feePercent);
        feePercent = _feePercent;
        emit FeePercentUpdated(_feePercent);
    }

    function addRewardBaseTokens(
        address[] memory _tokens
    ) external onlyRole("admin") {
        rewardBaseTokens = _tokens;
        emit RewardBaseTokensUpdated(_tokens);
    }

    function getRewardBaseTokens() external view returns (address[] memory) {
        return rewardBaseTokens;
    }

    function setVaultCap(uint256 _vaultCap) external onlyRole("admin") {
        vaultCap = _vaultCap;
    }

    // Enable credit delegation for the leverager contracts
    function enableCreditDelegation(
        ICreditDelegationToken _token,
        address _leverager
    ) external onlyRole("admin") {
        _token.approveDelegation(_leverager, type(uint256).max);
    }

    function disableCreditDelegation(
        ICreditDelegationToken _token,
        address _leverager
    ) external onlyRole("admin") {
        _token.approveDelegation(_leverager, 0);
    }

    function withdrawTokens(ERC20 _token) external onlyRole("admin") {
        if (_token == DLPAddress) {
            processWithdrawalQueue();
            // Possible to withdraw user DLP tokens if they are unlocked – should transfer in DLP.
        }
        _token.transfer(msg.sender, _token.balanceOf(address(this)));
    }

    /**
     * @notice Exit DLP Position, take rewards penalty and repay DLP loan. Autoclaims rewards.
     * Exit can cause disqualification from rewards and up to 50% penalty
     *
     */
    function forceWithdraw(uint256 amount_) external onlyRole("admin") {
        mfd.withdraw(amount_);
    }

    //============================================================================================//
    //                               REWARDS LOGIC                                                //
    //============================================================================================//

    /**
     * @notice Claim rewards
     * @dev Claim unlocked rewards, transfer to keeper, which will swap proportion of rewards to WETH
     * and vault assets.
     */
    function claim() external onlyRole("keeper") {
        mfd.exit(true);
        // transfer all rewards to keeper to convert
        for (uint i = 0; i < rewardBaseTokens.length; i++) {
            uint256 rewardBalance = IERC20(rewardBaseTokens[i]).balanceOf(
                address(this)
            );
            IERC20(rewardBaseTokens[i]).transfer(msg.sender, rewardBalance);
        }
    }

    /**
     * @notice Flashloan callback for Aave
     */
    function executeOperation(
        address _asset,
        uint256 amount,
        uint256,
        address initiator,
        bytes calldata
    ) external returns (bool success) {
        if (msg.sender != address(aaveLendingPool)) {
            revert DLPVault_ONLY_AAVE_LENDING_POOL();
        }
        ROLES.requireRole("leverager", initiator);
        // Repay approval
        if (
            IERC20(_asset).allowance(address(this), address(aaveLendingPool)) ==
            0
        ) {
            IERC20(_asset).approve(address(aaveLendingPool), type(uint256).max);
        }

        lendingPool.repay(_asset, amount, 2, address(this));
        lendingPool.withdraw(_asset, amount, initiator);
        return true;
    }

    function relock() external onlyRole("keeper") {
        uint256 withdrawnAmt = mfd.withdrawExpiredLocksFor(address(this));
        if (withdrawnAmt > 0) {
            processWithdrawalQueue();
        }
        mfd.stake(withdrawnAmt, address(this), defaultLockIndex);
    }

    function lock() external onlyRole("keeper") {
        uint256 amount = DLPAddress.balanceOf(address(this));
        mfd.stake(amount, address(this), defaultLockIndex); // @wooark - defaultLockIndex of 1 for 1 month lock?
        amountStaked += amount;
    }

    //============================================================================================//
    //                               VAULT LOGIC                                                  //
    //============================================================================================//

    function deposit(
        uint256 amount,
        address receiver
    ) public override updateReward(msg.sender) returns (uint256) {
        if (amount + amountStaked > vaultCap)
            revert DLPVault_VaultCapExceeded(amount + amountStaked);

        DLPAddress.transferFrom(msg.sender, address(this), amount);

        if (DLPAddress.allowance(address(this), address(mfd)) == 0)
            DLPAddress.approve(address(this), type(uint256).max);

        if (withdrawalQueueIndex != withdrawalQueue.length)
            processWithdrawalQueue();

        _mint(receiver, amount);
        return amount;
    }

    // Withdraw DLP tokens from the vault
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override updateReward(owner) returns (uint256) {
        getReward(owner);
        if (msg.sender != owner) {
            uint256 allowed = allowance(owner, msg.sender); // Saves gas for limited approvals.
            if (allowed != type(uint256).max) {
                _spendAllowance(owner, msg.sender, allowed - assets);
            }
        }

        if (assets == 0) revert DLPVault_WithdrawZero(msg.sender);
        // If there's enough cash and the queue is empty, process withdrawal
        if (
            assets <= DLPAddress.balanceOf(address(this)) &&
            withdrawalQueue.length == withdrawalQueueIndex
        ) {
            amountStaked -= assets;
            // Process withdrawal since there's enough cash
            _burn(owner, assets);

            emit Withdraw(msg.sender, receiver, owner, assets, assets);

            DLPAddress.transfer(receiver, assets);
            return assets;
        } else {
            // Add to withdrawal queue
            // Doesn't autoclaim rewards while you're in the withdrawal queue.
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
            return 0;
        }
    }

    // Process open withdrawal requests.
    function processWithdrawalQueue() public {
        for (
            uint256 i = withdrawalQueueIndex;
            i < withdrawalQueue.length;
            i++
        ) {
            WithdrawalQueue memory queueItem = withdrawalQueue[i];

            if (queueItem.assets <= DLPAddress.balanceOf(address(this))) {
                // Process withdrawal since there's enough cash
                // Approval check already done in withdraw()

                // If user balance dips below withdrawal amount, their withdraw request gets cancelled
                if (balanceOf(queueItem.owner) >= queueItem.assets) {
                    _burn(queueItem.owner, queueItem.assets);
                    DLPAddress.transfer(queueItem.receiver, queueItem.assets);
                    amountStaked -= queueItem.assets;

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

    //============================================================================================//
    //                             4626 OVERRIDES                                                 //
    //============================================================================================//

    function totalAssets() public view override returns (uint256) {
        // return balance of user assets, excluding PoL
        return amountStaked;
    }

    // Brick redeem() to prevent users from redeeming – withdraws only
    function previewRedeem(uint256) public pure override returns (uint256) {
        return 0;
    }

    // Brick mint() to prevent users from mints – deposits only
    function mint(uint256, address) public pure override returns (uint256) {
        revert DLPVault_MintDisabled();
    }

    // Brick previewMint() to prevent users from minting – deposits only
    function previewMint(uint256) public pure override returns (uint256) {
        return 0;
    }

    //============================================================================================//
    //                             ERC20 OVERRIDES                                                //
    //============================================================================================//
    // Overriding ERC20 transfer and transferFrom to update rewards
    function transfer(
        address to,
        uint256 amount
    )
        public
        override(IERC20Upgradeable, ERC20Upgradeable)
        updateReward(to)
        returns (bool)
    {
        getReward();

        _transfer(msg.sender, to, amount);

        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    )
        public
        override(IERC20Upgradeable, ERC20Upgradeable)
        updateReward(to)
        returns (bool)
    {
        getReward(from);
        _transfer(from, to, amount);
        return true;
    }

    //============================================================================================//
    //                             REWARDS LOGIC                                                  //
    //============================================================================================//
    // =========  STATE ========= //
    // Duration of rewards to be paid out (in seconds)
    uint public duration;
    // Timestamp of when the rewards finish
    uint public finishAt;
    // Minimum of last updated time and reward finish time
    uint public updatedAt;
    // Reward to be paid out per second
    uint public rewardRate;
    // Sum of (reward rate * dt * 1e18 / total supply)
    uint public rewardPerTokenStored;
    // User address => rewardPerTokenStored
    mapping(address => uint) public userRewardPerTokenPaid;
    // User address => rewards to be claimed
    mapping(address => uint) public rewards;

    modifier updateReward(address _account) {
        rewardPerTokenStored = rewardPerToken();
        updatedAt = lastTimeRewardApplicable();

        if (_account != address(0)) {
            rewards[_account] = earned(_account);
            userRewardPerTokenPaid[_account] = rewardPerTokenStored;
        }

        _;
    }

    function lastTimeRewardApplicable() public view returns (uint) {
        return _min(finishAt, block.timestamp);
    }

    function rewardPerToken() public view returns (uint) {
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }

        return
            rewardPerTokenStored +
            (rewardRate * (lastTimeRewardApplicable() - updatedAt) * 1e18) /
            totalSupply();
    }

    function earned(address _account) public view returns (uint) {
        return
            ((balanceOf(_account) *
                (rewardPerToken() - userRewardPerTokenPaid[_account])) / 1e18) +
            rewards[_account];
    }

    function getReward(address receiver) public updateReward(receiver) {
        uint reward = rewards[receiver];
        if (reward > 0) {
            rewards[receiver] = 0;
            rewardsToken.transfer(receiver, reward);
        }
        emit RewardPaid(receiver, reward);
    }

    function getReward() public {
        getReward(msg.sender);
    }

    function setRewardsDuration(uint _duration) external onlyRole("keeper") {
        if (finishAt >= block.timestamp)
            revert DLPVault_previous_reward_period_not_finished(finishAt);
        duration = _duration;
    }

    function notifyRewardAmount(
        uint _amount
    ) external onlyRole("keeper") updateReward(address(0)) {
        if (block.timestamp >= finishAt) {
            rewardRate = _amount / duration;
        } else {
            uint remainingRewards = (finishAt - block.timestamp) * rewardRate;
            rewardRate = (_amount + remainingRewards) / duration;
        }

        require(rewardRate > 0, "reward rate = 0");
        require(
            rewardRate * duration <= rewardsToken.balanceOf(address(this)),
            "reward amount > balance"
        );

        finishAt = block.timestamp + duration;
        updatedAt = block.timestamp;
        emit RewardAdded(_amount);
    }

    function _min(uint x, uint y) private pure returns (uint) {
        return x <= y ? x : y;
    }
}
