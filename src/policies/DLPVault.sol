// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "../Kernel.sol";
import {RolesConsumer, ROLESv1} from "../modules/ROLES/OlympusRoles.sol";
import {ERC4626} from "@solmate/mixins/ERC4626.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";

import "../interfaces/radiant-interfaces/IEligibilityDataProvider.sol";
import "../interfaces/radiant-interfaces/IMultiFeeDistribution.sol";
import "../interfaces/radiant-interfaces/IChefIncentivesController.sol";
import "../interfaces/aave/IFlashLoanSimpleReceiver.sol";
import "../interfaces/radiant-interfaces/ILendingPool.sol";
import "../interfaces/radiant-interfaces/ICreditDelegationToken.sol";

import "../interfaces/aave/IPool.sol";

contract DLPVault is Policy, RolesConsumer, ERC4626 {
    // =========  EVENTS ========= //
    event DefaultRelockIndexChanged(uint256 defaultLockIndex);
    event RewardAdded(uint256 reward);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event Borrow(address indexed _leverager, uint256 _amount);
    event Repay(address indexed _leverager, uint256 _amount);
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
    error DLPVault_provided_reward_rate_too_high(uint256 rewardRate);
    error DLPVault_WithdrawZero(address sender);
    error DLPVault_MintDisabled();
    error DLPVault_FeePercentTooHigh(uint256 _feePercent);

    //todo implement custom errors
    // =========  STATE ========= //
    ERC20 public immutable DLPAddress;
    ERC20 public immutable rewardsToken;
    address[] public rewardBaseTokens;
    uint256 public amountStaked;
    uint256 public feePercent; // Deposit Fee

    uint256 public withdrawalQueueIndex;

    IEligibilityDataProvider public eligibilityDataProvider =
        IEligibilityDataProvider(0xd4966DC49a10aa5467D65f4fA4b1449b5d874399);

    IMultiFeeDistribution public mfd =
        IMultiFeeDistribution(0x76ba3eC5f5adBf1C58c91e86502232317EeA72dE);

    /// @notice Aave lending pool address (for flashloans)
    IPool public constant aaveLendingPool =
        IPool(0x794a61358D6845594F94dc1DB02A252b5b4814aD);

    /// @notice Lending Pool address
    ILendingPool public constant lendingPool =
        ILendingPool(0xF4B1486DD74D07706052A33d31d7c0AAFD0659E1);

    uint256 public defaultLockIndex = 1;

    struct WithdrawalQueue {
        address caller;
        address owner;
        address receiver;
        uint256 assets;
    }

    WithdrawalQueue[] public withdrawalQueue;

    constructor(
        ERC20 _asset,
        ERC20 _rewardsToken,
        Kernel _kernel
    ) ERC4626(_asset, "Radiate-DLP Vault", "RD-DLP") Policy(_kernel) {
        DLPAddress = _asset;
        rewardsToken = _rewardsToken; // WETH
    }

    //============================================================================================//
    //                                     DEFAULT OVERRIDES                                      //
    //============================================================================================//

    function configureDependencies()
        external
        override
        returns (Keycode[] memory dependencies)
    {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");
        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
    }

    function requestPermissions()
        external
        pure
        override
        returns (Permissions[] memory requests)
    {
        requests = new Permissions[](0);
    }

    //============================================================================================//
    //                                     ADMIN                                                  //
    //============================================================================================//

    function setDepositFee(uint256 _feePercent) external onlyRole("admin") {
        if (_feePercent >= 1e4) revert DLPVault_FeePercentTooHigh(_feePercent);
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

    /**
     *
     * @param _amount Amount of WETH rewards for DLP lockers
     */
    function topUpRewards(uint256 _amount) external {
        rewardsToken.transferFrom(msg.sender, address(this), _amount);
        _notifyRewardAmount(_amount);
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

    function changeDefaultLockIndex(uint256 _index) external onlyRole("admin") {
        defaultLockIndex = _index;
        emit DefaultRelockIndexChanged(_index);
    }

    function withdrawTokens(ERC20 _token) external onlyRole("admin") {
        if (_token == DLPAddress) {
            processWithdrawalQueue();
            // todo
        }
        _token.transfer(msg.sender, _token.balanceOf(address(this)));
    }

    /**
     * @notice Exit DLP Position, take rewards penalty and repay DLP loan. Autoclaims rewards.
     * Exit can cause disqualification from rewards and penalty
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

        lendingPool.repay(address(asset), amount, 2, address(this));
        lendingPool.withdraw(address(asset), amount, initiator);
        return true;
    }

    function relock() external onlyRole("keeper") {
        uint256 withdrawnAmt = mfd.withdrawExpiredLocksFor(address(this));
        if (withdrawnAmt > 0) {
            processWithdrawalQueue();
        }
        mfd.stake(withdrawnAmt, address(this), defaultLockIndex);
    }

    // Protocol Owned liquidity (DLPvault tokens) -> normal DLP -> maxlock DLP into DLPvault
    // Manange lock logic outside with lock onbehalf

    //============================================================================================//
    //                               VAULT LOGIC                                                  //
    //============================================================================================//

    function deposit(
        uint256 amount,
        address receiver
    ) public override returns (uint256) {
        DLPAddress.transferFrom(msg.sender, address(this), amount);
        if (DLPAddress.allowance(address(this), address(mfd)) == 0) {
            DLPAddress.approve(address(this), type(uint256).max);
        }
        mfd.stake(amount, address(this), defaultLockIndex); // @wooark - defaultLockIndex of 1 for 1 month lock?
        amountStaked += amount;
        _mint(receiver, amount);
        return amount;
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override returns (uint256) {
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) {
                allowance[owner][msg.sender] = allowed - assets;
            }
        }
        amountStaked -= assets;
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
                if (balanceOf[queueItem.owner] >= queueItem.assets) {
                    beforeWithdraw(queueItem.assets);
                    _burn(queueItem.owner, queueItem.assets);
                    asset.transfer(queueItem.receiver, queueItem.assets);

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
    //                             4626 Overrides                                                 //
    //============================================================================================//

    function afterDeposit(uint256) internal {
        if (withdrawalQueueIndex != withdrawalQueue.length) {
            processWithdrawalQueue();
        }
        /// @dev removed updateReward bc it causes div by 0.
    }

    function beforeWithdraw(uint256 amount) internal updateReward(msg.sender) {
        if (amount == 0) revert DLPVault_WithdrawZero(msg.sender);
    }

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
        return
            ((rewardPerTokenStored +
                lastTimeRewardApplicable() -
                lastUpdateTime) *
                rewardRate *
                1e18) / totalSupply;
    }

    function earned(address account) public view returns (uint256) {
        return
            ((balanceOf[account] *
                rewardPerToken() -
                userRewardPerTokenPaid[account]) / 1e18) + rewards[account];
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
        uint256 balance = rewardsToken.balanceOf(address(this));
        if (rewardRate > balance / rewardsDuration)
            revert DLPVault_provided_reward_rate_too_high(rewardRate);

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration;
        emit RewardAdded(reward);
    }

    function setRewardsDuration(
        uint256 _rewardsDuration
    ) external onlyRole("admin") {
        if (block.timestamp < periodFinish)
            revert DLPVault_previous_reward_period_not_finished(periodFinish);
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
