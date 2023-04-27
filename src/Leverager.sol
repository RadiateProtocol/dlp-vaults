// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;
pragma abicoder v2;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/radiant-interfaces/ILendingPool.sol";
import "./interfaces/radiant-interfaces/IEligibilityDataProvider.sol";
import "./interfaces/radiant-interfaces/IChainlinkAggregator.sol";
import "./interfaces/radiant-interfaces/IChefIncentivesController.sol";
import "./interfaces/radiant-interfaces/IMultiFeeDistribution.sol";
// import "./interfaces/radiant-interfaces/ILockZap.sol";
import "./interfaces/radiant-interfaces/IAaveOracle.sol";
// import "./interfaces/radiant-interfaces/IWETH.sol";
import "./interfaces/radiant-interfaces/AggregatorV3Interface.sol";
import "./DLPVault.sol";

/// @title Leverager Contract
/// @author Radiant
/// @dev All function calls are currently implemented without side effects
contract Leverager is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /// @notice Ratio Divisor
    uint256 public constant RATIO_DIVISOR = 10000;

    /// @notice Loop collateral factor – 80%
    uint256 public LoopCollateralFactor = 8000;

    /// @notice Amount of DLP borrowed
    uint256 public DLPBorrowed;

    /// @notice Mock ETH address
    address public constant API_ETH_MOCK_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice Lending Pool address
    ILendingPool public lendingPool;

    /// @notice EligibilityDataProvider contract address
    IEligibilityDataProvider public eligibilityDataProvider;

    /// @notice ChefIncentivesController contract address
    IChefIncentivesController public cic;

    /// @notice Chainlink oracle address
    AggregatorV3Interface public chainlink;

    /// @notice DLPVault address
    DLPVault public vault;

    /// @notice Aave oracle address
    IAaveOracle public aaveOracle;

    /// @notice Fee ratio
    uint256 public feePercent;

    /// @notice RDNT address
    address public rdnt;

    /// @notice mfd
    IMultiFeeDistribution public mfd;

    /// @notice Treasury address
    address public treasury;

    /// @notice userOwner
    address public userOwner;

    /// @notice Owner address
    address public owner;

    /// @notice Emitted when fee ratio is updated
    event FeePercentUpdated(uint256 _feePercent);

    /// @notice Emitted when treasury is updated
    event TreasuryUpdated(address indexed _treasury);

    /**
     * @notice Constructor
     * @param _lendingPool Address of lending pool.
     * @param _rewardEligibleDataProvider EligibilityProvider address.
     * @param _aaveOracle address.
     * @param _cic ChefIncentivesController address.
     * @param _chainlink aggregatorV3 address.
     * @param _mfd MultiFeeDistribution address.
     * @param _rdnt Radiant Token address.
     * @param _vault DLPVault address.
     * @param _feePercent leveraging fee ratio.
     * @param _treasury address.
     */
    constructor(
        ILendingPool _lendingPool,
        IEligibilityDataProvider _rewardEligibleDataProvider,
        IAaveOracle _aaveOracle,
        IChefIncentivesController _cic,
        AggregatorV3Interface _chainlink,
        IMultiFeeDistribution _mfd,
        address _owner,
        address _rdnt,
        DLPVault _vault,
        uint256 _feePercent,
        address _treasury
    ) {
        require(address(_lendingPool) != (address(0)), "Not a valid address");
        require(
            address(_rewardEligibleDataProvider) != (address(0)),
            "Not a valid address"
        );
        require(address(_aaveOracle) != (address(0)), "Not a valid address");
        require(address(_cic) != (address(0)), "Not a valid address");
        require(address(_chainlink) != (address(0)), "Not a valid address");
        require(address(_mfd) != (address(0)), "Not a valid address");
        require(address(_rdnt) != (address(0)), "Not a valid address");
        require(address(_vault) != (address(0)), "Not a valid address");
        require(_treasury != address(0), "Not a valid address");
        require(_feePercent <= 1e4, "Invalid ratio");

        lendingPool = _lendingPool;
        eligibilityDataProvider = _rewardEligibleDataProvider;
        aaveOracle = _aaveOracle;
        cic = _cic;
        mfd = _mfd;
        chainlink = _chainlink;
        rdnt = _rdnt;
        vault = _vault;
        feePercent = _feePercent;
        treasury = _treasury;
        owner = _owner;
    }
    

    /**
     * @notice Require Owner
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    /**
     * @notice Require UserOwner
     */
    modifier onlyUserOwner() {
        require(msg.sender == userOwner, "Not user owner");
        _;
    }

    /**
     * @notice Sets userOwner
     * @param _newUserOwner address
     */
    function changeUserOwner(address _newUserOwner) external onlyUserOwner {
        userOwner = _newUserOwner;
    }

    /**
     * @notice Sets userOwner
     * @param _newOwner address
     */
    function changeUserOwner(address _newOwner) external onlyOwner {
        owner = _newOwner;
    }

    /**
     * @dev Revert fallback calls
     */
    fallback() external payable {
        revert("Fallback not allowed");
    }

    /**
     * @notice Sets fee ratio
     * @param _feePercent fee ratio.
     */
    function setFeePercent(uint256 _feePercent) external onlyOwner {
        require(_feePercent <= 1e4, "Invalid ratio");
        feePercent = _feePercent;
        emit FeePercentUpdated(_feePercent);
    }

    /**
     * @notice Sets fee ratio
     * @param _treasury address
     */
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "treasury is 0 address");
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

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
        bool isBorrow
    ) external onlyUserOwner {
        require(borrowRatio <= RATIO_DIVISOR, "Invalid ratio");
        uint16 referralCode = 0;
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
        mfd.stake()
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

    /**
     * @dev transfer ETH to an address, revert if it fails.
     * @param to recipient of the transfer
     * @param value the amount to send
     */
    function _safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, "ETH_TRANSFER_FAILED");
    }

    /**
     * @notice Set Multi fee distribution contract.
     * @param _mfdAddr New contract address.
     */
    function setMfd(address _mfdAddr) external onlyOwner {
        require(address(_mfdAddr) != address(0), "MFD can't be 0 address");
        mfd = IMultiFeeDistribution(_mfdAddr);
    }

    /*
     * @notice Return DLP price scaled by RATIO_DIVISOR (1e4)
     **/
    function DLPPrice() public view returns (uint256) {
        // Calculate price of 80-20 Balancer LP scaled by 1e6
        return 1e6 * 80 + (chainlink.getPrice(rdnt) * 20) / 100;
    }

    /*
     * @notice Get the Health factor of the user
     * @param count loop count
     **/
    function healthFactor() external view returns (uint256) {
        (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
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

    /*
     *   @notice Liquidate the user DLP if they are under the threshold
     **/
    function liquidate() external view returns (uint256) {
        require(healthFactor() > MINHEALTHFACTOR, "CANNOT LIQUIDATE");
        DLP.transferFrom(address(this), msg.sender, DLPBorrowed);
        // Allow liquidator the entire amount – alternatively could auto unloop user
        userOwner = msg.sender;
    }
}
