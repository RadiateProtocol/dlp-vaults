// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;
pragma abicoder v2;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin/upgradeable/contracts//security/PausableUpgradeable.sol";

import "./interfaces/radiant-interfaces/uniswap/IUniswapV2Router01.sol";
import "./interfaces/radiant-interfaces/ILendingPool.sol";
import "./interfaces/radiant-interfaces/IEligibilityDataProvider.sol";
import "./interfaces/radiant-interfaces/IChainlinkAggregator.sol";
import "./interfaces/radiant-interfaces/IChefIncentivesController.sol";
import "./interfaces/radiant-interfaces/IMultiFeeDistribution.sol";
import "./interfaces/radiant-interfaces/IAaveOracle.sol";
import "./interfaces/radiant-interfaces/AggregatorV3Interface.sol";
import "./DLPVault.sol";

/// @title Leverager Contract
/// @author w
/// @dev All function calls are currently implemented without side effects
contract Leverager is
    MFDLogic,
    Initializable,
    PausableUpgradeable,
    OwnableUpgradeable
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /// @notice Ratio Divisor
    uint256 public constant RATIO_DIVISOR = 10000;

    /// @notice Mock ETH address
    address public constant API_ETH_MOCK_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice WETH address on Arbitrum
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    /// @notice rdnt token address
    address public constant rdnt = 0x3082CC23568eA640225c2467653dB90e9250AaA0;

    /// @notice Lending Pool address
    ILendingPool public lendingPool;

    /// @notice Sushiswap router address
    IUniswapV2Router01 public uniswapRouter;

    /// @notice EligibilityDataProvider contract address
    IEligibilityDataProvider public eligibilityDataProvider;

    /// @notice ChefIncentivesController contract address
    IChefIncentivesController public cic;

    /// @notice DLPVault address
    DLPVault public vault;

    /// @notice Aave oracle address
    IAaveOracle public aaveOracle;

    /**
     * @notice Constructor
     * @param _lendingPool Lending Pool address.
     * @param _uniswapRouter Uniswap router address.
     * @param _rewardEligibleDataProvider EligibilityProvider address.
     * @param _aaveOracle address.
     * @param _cic ChefIncentivesController address.
     * @param _chainlink aggregatorV3 address.
     * @param _mfd MultiFeeDistribution address.
     * @param _vault DLP Vault address.
     * @param _userOwner Address of the user owner.
     */
    function initialize(
        ILendingPool _lendingPool,
        IUniswapV2Router01 _uniswapRouter,
        IEligibilityDataProvider _rewardEligibleDataProvider,
        IAaveOracle _aaveOracle,
        IChefIncentivesController _cic,
        AggregatorV3Interface _chainlink,
        IMultiFeeDistribution _mfd,
        DLPVault _vault,
        address _userOwner
    ) public MFDLogic(_mfd) initializer {
        require(address(_lendingPool) != (address(0)), "Not a valid address");
        require(address(_uniswapRouter) != (address(0)), "Not a valid address");
        require(
            address(_rewardEligibleDataProvider) != (address(0)),
            "Not a valid address"
        );
        require(address(_aaveOracle) != (address(0)), "Not a valid address");
        require(address(_cic) != (address(0)), "Not a valid address");
        require(address(_vault) != (address(0)), "Not a valid address");
        require(_treasury != address(0), "Not a valid address");
        require(_userOwner != address(0), "Not a valid address");
        lendingPool = _lendingPool;
        uniswapRouter = _uniswapRouter;
        eligibilityDataProvider = _rewardEligibleDataProvider;
        aaveOracle = _aaveOracle;
        cic = _cic;
        vault = _vault;
        userOwner = _userOwner;
        __Ownable_init();
        __Pausable_init();
    }

    /******************
     * Admin Logic    *
     ******************/

    /// @notice Treasury address
    address public treasury;

    /// @notice userOwner
    address public userOwner;

    /**
     * @notice Require UserOwner
     */
    modifier onlyUserOwner() {
        require(msg.sender == userOwner, "Not user owner");
        _;
    }

    /**
     * @notice Sets userOwner – transfers ownership of assets.
     * @param _newOwner address
     */
    function changeUserOwner(address _newOwner) external onlyUserOwner {
        owner.transferLeverager(userOwner, msg.sender);
        userOwner = _newOwner;
    }

    /**
     * @dev Revert fallback calls
     */
    fallback() external payable {
        revert("Fallback not allowed");
    }

    /*****************
     * Looping Logic  *
     ******************/

    /**
     * @dev Returns the configuration of the reserve
     * @param asset The address of the underlying asset of the reserve
     * @return The configuration of the reserve
     **/
    function getConfiguration(
        address asset
    ) external view returns (DataTypes.ReserveConfigurationMap memory) {
        return lendingPool.getConfiguration(asset);
    }

    /**
     * @dev Returns variable debt token address of asset
     * @param asset The address of the underlying asset of the reserve
     * @return varaiableDebtToken address of the asset
     **/
    function getVDebtToken(address asset) public view returns (address) {
        DataTypes.ReserveData memory reserveData = lendingPool.getReserveData(
            asset
        );
        return reserveData.variableDebtTokenAddress;
    }

    /**
     * @dev Returns loan to value
     * @param asset The address of the underlying asset of the reserve
     * @return ltv of the asset
     **/
    function ltv(address asset) public view returns (uint256) {
        DataTypes.ReserveConfigurationMap memory conf = lendingPool
            .getConfiguration(asset);
        return conf.data % (2 ** 16);
    }

    /**
     * @dev Loop the deposit and borrow of an asset (removed eth loop, deposit WETH directly)
     * @param asset for loop
     * @param amount for the initial deposit
     * @param interestRateMode stable or variable borrow mode
     * @param borrowRatio Ratio of tokens to borrow
     * @param loopCount Repeat count for loop
     * @param isBorrow true when the loop without deposit tokens
     **/
    function loop(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint256 borrowRatio,
        uint256 loopCount,
        uint256 lockIndex,
        bool isBorrow
    ) external onlyUserOwner {
        require(borrowRatio <= RATIO_DIVISOR, "Invalid ratio");
        uint16 referralCode = 0;
        address treasury = owner.treasury();
        uint256 feePercent = owner.feePercent();
        uint256 fee;
        if (!isBorrow) {
            IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
            fee = amount.mul(feePercent).div(RATIO_DIVISOR);
            IERC20(asset).safeTransfer(treasury, fee);
            amount = amount.sub(fee);
        }
        if (IERC20(asset).allowance(address(this), address(lendingPool)) == 0) {
            IERC20(asset).safeApprove(address(lendingPool), type(uint256).max);
        }
        if (IERC20(asset).allowance(address(this), address(treasury)) == 0) {
            IERC20(asset).safeApprove(treasury, type(uint256).max);
        }

        if (!isBorrow) {
            lendingPool.deposit(asset, amount, msg.sender, referralCode);
        }

        // cic.setEligibilityExempt(msg.sender, true);

        for (uint256 i = 0; i < loopCount; i += 1) {
            amount = amount.mul(borrowRatio).div(RATIO_DIVISOR);
            lendingPool.borrow(
                asset,
                amount,
                interestRateMode,
                referralCode,
                address(this)
            );

            fee = amount.mul(feePercent).div(RATIO_DIVISOR);
            IERC20(asset).safeTransfer(treasury, fee);
            lendingPool.deposit(
                asset,
                amount.sub(fee),
                address(this),
                referralCode
            );
        }
        // todo: ??
        // cic.setEligibilityExempt(msg.sender, false);
        uint256 requiredAmount = DLPToZapEstimation(
            address(this),
            asset,
            amount,
            borrowRatio,
            loopCount
        );

        uint256 dlpBorrowed = vault.borrow(requiredAmount, msg.sender);
        if (dlpBorrowed < requiredAmount) revert("Not enough borrow");
        if (
            IERC20(vault.DLPAddress).allowance(
                address(this),
                address(lendingPool)
            ) == 0
        ) {
            IERC20(vault.DLPAddress).safeApprove(
                address(mfd),
                type(uint256).max
            );
        }
        _stake(dlpBorrowed, lockIndex);
    }

    /**
     * @notice Return estimated zap DLP amount for eligbility after loop.
     * @param user for zap
     * @param asset src token
     * @param amount of `asset`
     * @param borrowRatio Single ratio of borrow
     * @param loopCount Repeat count for loop
     **/
    function DLPToZapEstimation(
        address user,
        address asset,
        uint256 amount,
        uint256 borrowRatio,
        uint256 loopCount
    ) external view returns (uint256) {
        if (asset == API_ETH_MOCK_ADDRESS) {
            asset = address(weth);
        }
        uint256 required = eligibilityDataProvider.requiredUsdValue(user);
        uint256 locked = eligibilityDataProvider.lockedUsdValue(user);

        uint256 fee = amount.mul(feePercent).div(RATIO_DIVISOR);
        amount = amount.sub(fee);

        required = required.add(requiredLocked(asset, amount));

        for (uint256 i = 0; i < loopCount; i += 1) {
            amount = amount.mul(borrowRatio).div(RATIO_DIVISOR);
            fee = amount.mul(feePercent).div(RATIO_DIVISOR);
            required = required.add(requiredLocked(asset, amount.sub(fee)));
        }

        if (locked >= required) {
            return 0;
        } else {
            return required.sub(locked);
        }
    }

    /**
     * @notice Returns required LP lock amount.
     * @param asset underlying asset
     * @param amount of tokens
     **/
    function requiredLocked(
        address asset,
        uint256 amount
    ) internal view returns (uint256) {
        uint256 assetPrice = aaveOracle.getAssetPrice(asset);
        uint8 assetDecimal = IERC20Metadata(asset).decimals();
        uint256 requiredVal = assetPrice
            .mul(amount)
            .div(10 ** assetDecimal)
            .mul(eligibilityDataProvider.requiredDepositRatio())
            .div(eligibilityDataProvider.RATIO_DIVISOR());
        return requiredVal;
    }

    /*****************
     * Rewards Logic  *
     ******************/

    /**
     * @notice Claim rewards
     * @dev Claim unlocked rewards, sell them for WETH and send portion of WETH to vault as interest.
     */
    function claim() external {
        _claim();
        repayLoan(0); // Repay DLP with any unlocked DLP
        uint256 amount = _rewardsToWETH();
        uint256 fee = amount.mul(vault.interestFee).div(RATIO_DIVISOR);
        amount = amount.sub(fee);
        if (IERC20(WETH).allowance(address(vault)) = 0) {
            IERC20(WETH).safeApprove(address(vault), type(uint256).max);
        }
        vault.sendRewards(fee);
        IERC20(WETH).safetransfer(userOwner, amount);
    }

    /**
     * @notice Claim rewards
     * @dev Sell all rewards to WETH on Uniswap
     */
    function _rewardsToWETH() internal returns (uint256) {
        address[] memory rewardBaseTokens = rewardPool.getRewardBaseTokens();
        uint256 ethAmount = 0;
        for (uint256 i = 0; i < rewardBaseTokens.length; i += 1) {
            address token = rewardBaseTokens[i];
            uint256 amount = IERC20(token).balanceOf(address(this));
            if (token == WETH) {
                ethAmount = ethAmount.add(amount);
            } else {
                uint256 ethAmountOut = _estimateETHTokensOut(token, amount);
                ethAmount = ethAmount.add(ethAmountOut);
                IERC20(token).safeApprove(address(uniswapRouter), amount);
                uniswapRouter.swapExactTokensForTokens(
                    amount,
                    _estimateETHTokensOut(token, amount).mul(99).div(100), // 1% slippage
                    [token, WETH],
                    address(this),
                    block.timestamp + 600
                );
            }
        }
        return ethAmount;
    }

    function _estimateETHTokensOut(
        address _in,
        uint256 _amtIn
    ) internal view returns (uint256 tokensOut) {
        if (rdnt == _in) {
            uint256 priceInAsset = chainlink.getPrice(); // 8 decimals
        } else {
            uint256 priceInAsset = aaveOracle.getAssetPrice(_in); //USDC: 100000000
        }

        uint256 priceOutAsset = aaveOracle.getAssetPrice(WETH); //WETH: 153359950000
        uint256 decimalsIn = IERC20(_in).decimals();
        tokensOut =
            (_amtIn * priceInAsset * (10 ** 18)) /
            (priceOutAsset * (10 ** decimalsIn));
    }

    /*
     * @notice Exit DLP Position, take penalty and repay loan. Autoclaims rewards.
     **/
    function exit() public onlyUserOwner {
        _exit();
        uint256 repayAmt = IERC20(vault.DLPAddress).balanceOf(address(this));
        vault.repayBorrow(repayAmt);
        DLPBorrowed -= repayAmt;
        // If user withdraws collateral and exits in same tx, could lead to shortfall
        require(
            healthFactor() <= MINHEALTHFACTOR,
            "Exit: Health factor too low"
        );
    }

    /*****************
     * Lending Logic  *
     ******************/

    /// @notice Loop collateral factor – 80%
    uint256 public LoopCollateralFactor = 8000;

    /// @notice Amount of DLP borrowed
    uint256 public DLPBorrowed;

    /// @notice Chainlink oracle address
    AggregatorV3Interface public chainlink;

    /// @notice User liquidation
    event userLiquidated(
        address indexed user,
        address indexed liquidator,
        uint256 amount
    );

    /**
     * @notice Return DLP (80-20 LP) price in ETH scaled by RATIO_DIVISOR (1e4)
     **/
    function DLPPrice() public view returns (uint256) {
        // RDNT Price (USD, 8 decimals) * ETH Price (USD, 8 decimals)/1e12 = RDNT Price (ETH, 4 decimals)
        uint256 radiantEthPrice = (chainlink.getPrice(rdnt) *
            aaveOracle.getAssetPrice(WETH)) / 1e12;
        // Transform by 80:20 ratio
        return (1e4 * 20 + radiantEthPrice * 80) / 10;
    }

    /**
     * @notice If there's DLP from someone calling withdrawExpiredLocksFor
     * Call function on tend rewards
     **/
    function repayLoan(uint256 amount) public {
        if (amount > 0) {
            vault.dlpaddress().safeTransferFrom(
                msg.sender,
                address(this),
                amount
            );
        }
        uint256 repayAmt = IERC20(vault.DLPAddress).balanceOf(address(this));
        if (repayAmt == 0) return;
        vault.repayBorrow(repayAmt);
        DLPBorrowed -= repayAmt;
    }

    /**
     * @notice Get the Health factor of the user
     * @param count loop count
     **/
    function healthFactor() external view returns (uint256) {
        (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            ,
            ,

        ) = lendingPool.getUserAccountData(address(this));
        uint256 accountLiquidity = totalCollateralETH
            .sub(totalDebtETH)
            .mul(LoopCollateralFactor)
            .div(RATIO_DIVISOR);
        uint256 DLPBorrowedETH = DLPPrice().mul(DLPBorrowed).div(RATIO_DIVISOR);
        uint256 hf = accountLiquidity.mul(RATIO_DIVISOR).div(DLPBorrowedETH);
        // Return minimum recoverable amount = total collateral - debt * 0.80 = hf
        // even if user gets liquidated, loses 15% of their collateral to liquidation penalty (15%)
        // Still significant buffer for DLP liquidation since collateral factor is fixed at 80%
        return hf;
    }

    /**
     *   @notice Liquidate the user DLP if they are under the threshold
     **/
    function liquidate() public returns (uint256) {
        require(healthFactor() > MINHEALTHFACTOR, "CANNOT LIQUIDATE");
        DLP.transferFrom(address(this), msg.sender, DLPBorrowed);
        vault.owner.transferLeverager(userOwner, msg.sender);
        // Allow liquidator the entire amount – alternatively could auto unloop user
        emit userLiquidated(userOwner, msg.sender, DLPBorrowed);
        userOwner = msg.sender;
    }
}
