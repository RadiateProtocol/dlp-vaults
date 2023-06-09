// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;
pragma abicoder v2;

import "../Kernel.sol";
import {DLPVault} from "./DLPVault.sol";
import {RolesConsumer, ROLESv1} from "../modules/ROLES/OlympusRoles.sol";
import {LeveragerVault, VAULTv1} from "../modules/VAULT/LeveragerVault.sol";
import {Treasury} from "../modules/TRSRY/TRSRY.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import "../interfaces/uniswap/IUniswapV2Router01.sol";
import "../interfaces/radiant-interfaces/IEligibilityDataProvider.sol";
import "../interfaces/radiant-interfaces/ILendingPool.sol";
import "../interfaces/radiant-interfaces/IChainlinkAggregator.sol";
import "../interfaces/radiant-interfaces/IMultiFeeDistribution.sol";
import "../interfaces/radiant-interfaces/IChefIncentivesController.sol";
import "../interfaces/radiant-interfaces/IAaveOracle.sol";
import "../interfaces/radiant-interfaces/AggregatorV3Interface.sol";
import "../interfaces/aave/IFlashLoanSimpleReceiver.sol";
import "../interfaces/aave/IPool.sol";

/// @title Leverager Contract
/// @author w
/// @dev All function calls are currently implemented without side effects
contract Leverager is IFlashLoanSimpleReceiver, RolesConsumer, Policy {
    using SafeTransferLib for ERC20;

    // =========  EVENTS ========= //

    event BorrowDLP(uint256 DLPBorrowed, address caller);
    event DefaultRelockIndexChanged(uint256 defaultLockIndex);
    event DLPHealthFactorChanged(uint256 healthfactor);
    event BorrowRatioChanged(uint256 borrowRatio);
    event RewardsToAsset(uint256 fee, uint256 assetAmount);
    event Unloop(uint256 amount);
    event EmergencyUnloop(uint256 amount);
    event NotEnoughDLP(uint256 required, uint256 borrowed);

    // =========  ERRORS ========= //

    error Leverager_VAULT_CAP_REACHED();
    error Leverager_ONLY_SELF_INIT(address initiator);
    error Leverager_ONLY_AAVE_LENDING_POOL(address caller);
    error Leverager_ERROR_BORROW_RATIO(uint256 borrowRatio);
    error Leverager_NOT_ENOUGH_BORROW(uint256 shortfall);

    // =========  STATE ========= //
    VAULTv1 internal VAULT;
    address internal TRSRY;

    /// @notice WETH on Arbitrum
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    address public constant RDNT = 0x3082CC23568eA640225c2467653dB90e9250AaA0;

    ERC20 public constant DLP =
        ERC20(0x32dF62dc3aEd2cD6224193052Ce665DC18165841);

    IAaveOracle public constant aaveOracle =
        IAaveOracle(0xFf785dE8a851048a65CbE92C84d4167eF3Ce9BAC);

    uint256 public constant RATIO_DIVISOR = 10000;

    ERC20 public immutable asset;

    uint256 public immutable minAmountToInvest;

    /// @notice Aave lending pool address (for flashloans)
    IPool public constant aaveLendingPool =
        IPool(0x794a61358D6845594F94dc1DB02A252b5b4814aD);

    /// @notice Lending Pool address
    ILendingPool public constant lendingPool =
        ILendingPool(0xF4B1486DD74D07706052A33d31d7c0AAFD0659E1);

    /// @notice Sushiswap router address
    IUniswapV2Router01 public uniswapRouter =
        IUniswapV2Router01(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);

    IEligibilityDataProvider public eligibilityDataProvider =
        IEligibilityDataProvider(0xd4966DC49a10aa5467D65f4fA4b1449b5d874399);

    IMultiFeeDistribution public mfd =
        IMultiFeeDistribution(0x76ba3eC5f5adBf1C58c91e86502232317EeA72dE);

    DLPVault public DLPvault;

    constructor(
        uint256 _minAmountToInvest,
        uint256 _vaultCap,
        uint256 _loopCount,
        uint256 _borrowRatio,
        DLPVault _dlpVault,
        ERC20 _asset,
        Kernel _kernel
    ) Policy(_kernel) {
        require(
            _minAmountToInvest > 0,
            "Leverager: minAmountToInvest must be greater than 0"
        );
        minAmountToInvest = _minAmountToInvest;
        vaultCap = _vaultCap;
        loopCount = _loopCount;
        borrowRatio = _borrowRatio;
        DLPvault = _dlpVault;
        asset = _asset;
    }

    //============================================================================================//
    //                                     DEFAULT OVERRIDES                                      //
    //============================================================================================//

    function configureDependencies()
        external
        override
        returns (Keycode[] memory dependencies)
    {
        dependencies = new Keycode[](3);
        dependencies[0] = toKeycode("ROLES");
        dependencies[1] = toKeycode("LVGVT");
        dependencies[2] = toKeycode("TRSRY");
        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        VAULT = VAULTv1(getModuleAddress(dependencies[1]));
        TRSRY = getModuleAddress(dependencies[2]);
    }

    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory requests)
    {
        Keycode VAULT_KEYCODE = toKeycode("LVGVT");

        requests = new Permissions[](6);
        requests[0] = Permissions(VAULT_KEYCODE, VAULT._redeem.selector);
        requests[1] = Permissions(VAULT_KEYCODE, VAULT._withdraw.selector);
        requests[2] = Permissions(VAULT_KEYCODE, VAULT._mint.selector);
        requests[3] = Permissions(VAULT_KEYCODE, VAULT._deposit.selector);
        requests[4] = Permissions(VAULT_KEYCODE, VAULT._invest.selector);
        requests[5] = Permissions(VAULT_KEYCODE, VAULT._divest.selector);
    }

    //============================================================================================//
    //                                     ADMIN                                                  //
    //============================================================================================//

    /// @notice vault cap
    uint256 public vaultCap;

    /// @notice Loop count
    uint256 public loopCount;

    /// @notice Borrow ratio
    uint256 public borrowRatio;

    /// @notice DLP Health Factor – default for Leverager is 6%
    uint256 public healthFactor = 600;

    function changeVaultCap(uint256 _vaultCap) external onlyRole("admin") {
        // Scaled by asset.decimals
        vaultCap = _vaultCap;
    }

    /// @dev Change loop count for any new deposits
    function changeLoopCount(uint256 _loopCount) external onlyRole("admin") {
        loopCount = _loopCount;
    }

    /// @dev Change borrow ratio for any new deposits
    function changeBorrowRatio(
        uint256 _borrowRatio
    ) external onlyRole("admin") {
        borrowRatio = _borrowRatio;
        emit BorrowRatioChanged(_borrowRatio);
    }

    /// @dev Change DLP health factor
    function changeDLPHealthFactor(
        uint256 _healthfactor
    ) external onlyRole("admin") {
        healthFactor = _healthfactor;
        emit DLPHealthFactorChanged(_healthfactor);
    }

    /// @dev Set default lock index
    function setDefaultRelockIndex(
        uint256 _defaultLockIndex
    ) external onlyRole("admin") {
        mfd.setDefaultRelockTypeIndex(_defaultLockIndex);
        emit DefaultRelockIndexChanged(_defaultLockIndex);
    }

    /// @dev Emergency Unloop – withdraws all funds from Radiant to vault
    /// For migrations, or in case of emergency
    function emergencyUnloop(uint256 _amount) external onlyRole("admin") {
        _unloop(_amount);
        emit EmergencyUnloop(_amount);
    }

    /**
     * @notice Exit DLP Position, take rewards penalty and repay DLP loan. Autoclaims rewards.
     * Exit can cause disqualification from rewards and penalty
     *
     */
    function forceWithdraw(uint256 amount_) public onlyRole("admin") {
        mfd.withdraw(amount_);
        uint256 repayAmt = DLP.balanceOf(address(this));
        DLPvault.repayBorrow(repayAmt);
        DLPBorrowed -= repayAmt;
    }

    //============================================================================================//
    //                             LOOPING LOGIC                                                  //
    //============================================================================================//

    /**
     * @dev Returns the configuration of the reserve
     * @param asset_ The address of the underlying asset of the reserve
     * @return The configuration of the reserve
     *
     */
    function getConfiguration(
        address asset_
    ) public view returns (DataTypes.ReserveConfigurationMap memory) {
        return lendingPool.getConfiguration(asset_);
    }

    /**
     * @dev Returns variable debt token address of asset
     * @param asset_ The address of the underlying asset of the reserve
     * @return varaiableDebtToken address of the asset
     *
     */
    function getVDebtToken(address asset_) public view returns (address) {
        DataTypes.ReserveData memory reserveData = lendingPool.getReserveData(
            asset_
        );
        return reserveData.variableDebtTokenAddress;
    }

    /**
     * @dev Returns loan to value
     * @param asset_ The address of the underlying asset of the reserve
     * @return ltv of the asset
     *
     */
    function ltv(address asset_) public view returns (uint256) {
        DataTypes.ReserveConfigurationMap memory conf = lendingPool
            .getConfiguration(asset_);
        return conf.data % (2 ** 16);
    }

    /**
     * @dev Loop the deposit and borrow of an asset (removed eth loop, deposit WETH directly)
     *
     */
    function _loop() internal {
        if (borrowRatio <= RATIO_DIVISOR)
            revert Leverager_ERROR_BORROW_RATIO(borrowRatio);

        uint16 referralCode = 0;
        uint256 amount = asset.balanceOf(address(this));
        uint256 interestRateMode = 2; // variable
        if (asset.allowance(address(this), address(lendingPool)) == 0) {
            asset.safeApprove(address(lendingPool), type(uint256).max);
        }
        if (asset.allowance(address(this), TRSRY) == 0) {
            asset.safeApprove(TRSRY, type(uint256).max);
        }
        for (uint256 i = 0; i < loopCount; i += 1) {
            amount = (amount * borrowRatio) / RATIO_DIVISOR;
            lendingPool.borrow(
                address(asset),
                amount,
                interestRateMode,
                referralCode,
                address(this)
            );

            lendingPool.deposit(
                address(asset),
                amount,
                address(this),
                referralCode
            );
        }
        uint256 requiredAmount = DLPToZapEstimation(amount);

        uint256 _dlpBorrowed = DLPvault.borrow(requiredAmount);
        if (_dlpBorrowed < requiredAmount) {
            revert Leverager_NOT_ENOUGH_BORROW(requiredAmount - _dlpBorrowed);
        }
        if (DLP.allowance(address(this), address(lendingPool)) == 0) {
            DLP.safeApprove(address(mfd), type(uint256).max);
        }
        uint256 duration = mfd.defaultLockIndex(address(this));
        mfd.stake(_dlpBorrowed, address(this), duration);
        DLPBorrowed += _dlpBorrowed;
    }

    /**
     * @notice Return estimated zap DLP amount for eligbility after loop – denominated in DLP.
     * @param amount of `asset`
     *
     */
    function DLPToZapEstimation(uint256 amount) public view returns (uint256) {
        uint256 required = eligibilityDataProvider.requiredUsdValue(
            address(this)
        );
        uint256 locked = eligibilityDataProvider.lockedUsdValue(address(this));

        // Add health factor amount to required
        required =
            ((required + requiredLocked(amount)) * healthFactor) /
            RATIO_DIVISOR;

        for (uint256 i = 0; i < loopCount; i += 1) {
            amount = (amount * borrowRatio) / RATIO_DIVISOR;
            required += requiredLocked(amount);
        }

        if (locked >= required) {
            return 0;
        } else {
            // Transform USD to DLP price
            uint256 deltaUsdValue = required - locked; //decimals === 8
            uint256 wethPrice = aaveOracle.getAssetPrice(address(WETH));
            uint8 priceDecimal = IChainlinkAggregator(
                aaveOracle.getSourceOfAsset(WETH)
            ).decimals();
            uint256 deltaDLPvalue = (deltaUsdValue *
                ((DLPPrice() * wethPrice) / 10 ** priceDecimal)) *
                10 ** (18 - 2 * priceDecimal);
            // 10e8 + 10e8 + 10e8 - 10e8 + 10e2 = 10e18
            return deltaDLPvalue;
        }
    }

    /**
     * @notice Returns required LP lock amount denominated in USD
     * @param _amount of tokens
     *
     */
    function requiredLocked(uint256 _amount) internal view returns (uint256) {
        uint256 assetPrice = aaveOracle.getAssetPrice(address(asset));
        uint8 assetDecimal = asset.decimals();
        uint256 requiredVal = (((assetPrice * _amount) / (10 ** assetDecimal)) *
            eligibilityDataProvider.requiredDepositRatio()) /
            eligibilityDataProvider.RATIO_DIVISOR();

        return requiredVal;
    }

    /**
     *
     * @param _amount of tokens to free from loop
     */
    function _unloop(uint256 _amount) internal {
        bytes memory params = "";
        aaveLendingPool.flashLoanSimple(
            address(this),
            address(asset),
            _amount,
            params,
            0
        );
        emit Unloop(_amount);
    }

    /**
     * @notice Flashloan callback for Aave
     */
    function executeOperation(
        address,
        uint256 amount,
        uint256,
        address initiator,
        bytes calldata
    ) external returns (bool success) {
        if (msg.sender != address(aaveLendingPool)) {
            revert Leverager_ONLY_AAVE_LENDING_POOL(msg.sender);
        }
        if (initiator != address(this))
            revert Leverager_ONLY_SELF_INIT(initiator);
        // Repay approval
        if (asset.allowance(address(this), address(aaveLendingPool)) == 0) {
            asset.safeApprove(address(aaveLendingPool), type(uint256).max);
        }

        lendingPool.repay(address(asset), amount, 2, address(this));
        lendingPool.withdraw(address(asset), amount, address(this));
        return true;
    }

    //============================================================================================//
    //                                REWARDS LOGIC                                               //
    //============================================================================================//

    /**
     * @notice Claim rewards
     * @dev Claim unlocked rewards, sell them for asset and send portion of WETH to vault as interest.
     */
    function claim() public {
        mfd.exit(true);
        topUp(); // Ensure eligibility is maintained
        uint256 fee = _rewardsToAsset();
        if (asset.allowance(address(this), address(DLPvault)) == 0) {
            asset.safeApprove(address(DLPvault), type(uint256).max);
        }
        DLPvault.sendRewards(fee);
    }

    /**
     * @notice Claim rewards
     * @dev Sell all rewards to base asset on Sushiswap via swaprouter
     */
    function _rewardsToAsset() internal returns (uint256) {
        address[] memory rewardBaseTokens = DLPvault.getRewardBaseTokens();
        uint256 assetAmount = 0;
        address[] memory path = new address[](2);
        for (uint256 i = 0; i < rewardBaseTokens.length; i += 1) {
            address token = rewardBaseTokens[i];
            if (token == address(asset)) continue; // Skip if token is base asset
            uint256 amount = ERC20(token).balanceOf(address(this));

            if (token == address(asset)) {
                assetAmount += amount;
            } else {
                uint256 assetAmountOut = _estimateAssetTokensOut(
                    token,
                    address(asset),
                    amount
                );
                assetAmount += assetAmountOut;
                ERC20(token).safeApprove(address(uniswapRouter), amount);
                path[0] = token;
                path[1] = address(asset);
                uniswapRouter.swapExactTokensForTokens(
                    amount,
                    (assetAmountOut * 99) / 100, // 1% slippage
                    path,
                    address(this),
                    block.timestamp + 1
                );
            }
        }
        uint256 _fee = (DLPvault.interestfee() * assetAmount) / RATIO_DIVISOR;
        // Swap portion of asset to WETH for fee
        _fee = _estimateAssetTokensOut(address(asset), WETH, _fee);
        path[0] = address(asset);
        path[1] = WETH;
        uniswapRouter.swapExactTokensForTokens(
            _fee,
            (_fee * 99) / 100, // 1% slippage
            path,
            address(this),
            block.timestamp
        );

        emit RewardsToAsset(_fee, assetAmount);
        return _fee;
    }

    /// @dev Return estimated amount of Asset tokens to receive for given amount of tokens
    function _estimateAssetTokensOut(
        address _in,
        address _out,
        uint256 _amtIn
    ) internal view returns (uint256 tokensOut) {
        uint256 priceInAsset;
        if (RDNT == _in) {
            (, int256 answer, , , ) = chainlink.latestRoundData(); // 8 decimals
            priceInAsset = uint256(answer);
        } else {
            priceInAsset = aaveOracle.getAssetPrice(_in); //USDC: 100000000
        }

        uint256 priceOutAsset = aaveOracle.getAssetPrice(_out); //WETH: 153359950000
        uint256 decimalsIn = ERC20(_in).decimals();
        uint256 decimalsOut = ERC20(_out).decimals();
        tokensOut =
            (_amtIn * priceInAsset * (10 ** decimalsOut)) /
            (priceOutAsset * (10 ** decimalsIn));
    }

    //============================================================================================//
    //                               LENDING LOGIC                                                //
    //============================================================================================//

    /// @notice Amount of DLP borrowed
    uint256 public DLPBorrowed;

    /// @notice Chainlink oracle address for RDNT/USD
    AggregatorV3Interface public chainlink =
        AggregatorV3Interface(0x20d0Fcab0ECFD078B036b6CAf1FaC69A6453b352);

    /**
     * @notice Return DLP (80-20 LP) price in ETH scaled by 1e8
     *
     */
    function DLPPrice() public view returns (uint256) {
        (, int256 answer, , , ) = chainlink.latestRoundData(); // 8 decimals
        // RDNT Price (USD, 8 decimals) * ETH Price (USD, 8 decimals)/1e12 = RDNT Price (ETH, 8 decimals)
        uint256 radiantEthPrice = (uint256(answer) *
            aaveOracle.getAssetPrice(WETH)) / 10e8;
        // Transform by 80:20 ratio
        return (10e8 * 20 + radiantEthPrice * 80) / 100;
    }

    /**
     * @notice If there's DLP from someone calling withdrawExpiredLocksFor
     * Call function on tend rewards
     *
     */
    function repayLoan() public {
        uint256 repayAmt = DLP.balanceOf(address(this));
        if (repayAmt == 0) return;
        DLPvault.repayBorrow(repayAmt);
        DLPBorrowed -= repayAmt;
    }

    /// @notice Keeper calls up top up DLP health factor to 1 + healthFactorBuffer
    function topUp() public {
        uint256 requiredAmount = DLPToZapEstimation(0);
        uint256 bal_ = DLP.balanceOf(address(this));
        if (requiredAmount > 0) {
            // Need to borrow
            if (bal_ < requiredAmount) {
                requiredAmount -= bal_;
                uint256 _dlpBorrowed = DLPvault.borrow(requiredAmount);
                if (_dlpBorrowed < requiredAmount) {
                    emit NotEnoughDLP(requiredAmount, _dlpBorrowed);
                    // Don't revert to prevent reverts on claim()
                }
                DLPBorrowed += _dlpBorrowed;
            }

            if (
                DLP.allowance(address(this), address(DLPvault)) < requiredAmount
            ) {
                DLP.safeApprove(address(DLPvault), type(uint256).max);
            }
            bal_ = DLP.balanceOf(address(this));
            uint256 duration = mfd.defaultLockIndex(address(this));
            mfd.stake(bal_, address(this), duration);
        }
        emit BorrowDLP(bal_, msg.sender);
    }

    //============================================================================================//
    //                               4626 LOGIC                                                   //
    //============================================================================================//

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public returns (uint256) {
        beforeWithdrawal(assets);
        return VAULT._withdraw(assets, receiver, owner, msg.sender);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public returns (uint256) {
        uint256 assets_ = VAULT.previewRedeem(shares);
        beforeWithdrawal(assets_);
        return VAULT._withdraw(assets_, receiver, owner, msg.sender);
    }

    function deposit(uint256 assets, address owner) public returns (uint256) {
        if (assets + VAULT.totalAssets() >= vaultCap) {
            revert Leverager_VAULT_CAP_REACHED();
        }
        uint256 shares_ = VAULT._deposit(assets, owner, msg.sender);
        afterDeposit();
        return shares_;
    }

    function mint(
        uint256 shares,
        address sender,
        address owner
    ) public returns (uint256) {
        if (shares + VAULT.totalSupply() >= vaultCap) {
            revert Leverager_VAULT_CAP_REACHED();
        }
        uint256 assets_ = VAULT._mint(shares, sender, owner);
        afterDeposit();
        return assets_;
    }

    function afterDeposit() internal {
        claim();
        repayLoan();
        uint256 cash_ = asset.balanceOf(address(VAULT));
        if (cash_ >= minAmountToInvest) {
            VAULT._invest(cash_);
            uint256 depositFee = DLPvault.feePercent();
            if (depositFee > 0) {
                // Fee is necessary to prevent deposit and withdraw trolling
                uint256 fee = (cash_ * depositFee) / RATIO_DIVISOR;
                asset.transfer(TRSRY, fee);
            }
            _loop();
        }
    }

    function beforeWithdrawal(uint256 assets) internal {
        claim();
        if (assets > asset.balanceOf(address(VAULT))) {
            uint256 amountToWithdraw = assets - asset.balanceOf(address(this));
            _unloop(amountToWithdraw);
        }
        VAULT._divest(assets);
    }

    // Lightly modified from Mudgen's Diamond-3
    /// @dev Delegatecalls LeveragerVault any non core function call
    //solhint-disable-next-line no-complex-fallback
    fallback() external payable {
        address vaultAddress = address(VAULT);
        assembly {
            // copy function selector and any arguments
            calldatacopy(0, 0, calldatasize())
            // execute function call using the facet
            let result := delegatecall(
                gas(),
                vaultAddress,
                0,
                calldatasize(),
                0,
                0
            )
            // get any return value
            returndatacopy(0, 0, returndatasize())
            // return any return value or error back to the caller
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    receive() external payable {}
}
