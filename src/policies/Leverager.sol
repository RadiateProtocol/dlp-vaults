// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;
pragma abicoder v2;

import "../Kernel.sol";
import {DLPVault} from "./DLPVault.sol";
import {RolesConsumer, ROLESv1} from "../modules/ROLES/OlympusRoles.sol";
import {Treasury} from "../modules/TRSRY/TRSRY.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {ERC4626} from "@solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import "../interfaces/radiant-interfaces/ILendingPool.sol";
import "../interfaces/aave/IPool.sol";

/// @title Leverager Contract
/// @author w
/// @dev All function calls are currently implemented without side effects
contract Leverager is RolesConsumer, Policy, ERC4626 {
    using SafeTransferLib for ERC20;

    // =========  EVENTS ========= //

    event BorrowRatioChanged(uint256 borrowRatio);
    event Unloop(uint256 amount);
    event EmergencyUnloop(uint256 amount);

    // =========  ERRORS ========= //

    error Leverager_VAULT_CAP_REACHED();
    error Leverager_ERROR_BORROW_RATIO(uint256 borrowRatio);
    error Leverager_CANNOT_WITHDRAW_AFTER_EMERGENCY_UNLOOP();
    error Leverager_NO_ETHER();

    // =========  STATE ========= //
    address internal TRSRY;
    bool public emergencyUnlooping;
    ERC20 public constant DLP =
        ERC20(0x32dF62dc3aEd2cD6224193052Ce665DC18165841);

    /// @notice Lending Pool address
    ILendingPool public constant lendingPool =
        ILendingPool(0xF4B1486DD74D07706052A33d31d7c0AAFD0659E1);

    /// @notice Aave lending pool address (for flashloans)
    IPool public constant aaveLendingPool =
        IPool(0x794a61358D6845594F94dc1DB02A252b5b4814aD);
    uint256 public constant RATIO_DIVISOR = 1e6;

    uint256 public immutable minAmountToInvest;
    uint256 public amountInvested;

    DLPVault public dlpVault;

    constructor(
        uint256 _minAmountToInvest,
        uint256 _vaultCap,
        uint256 _loopCount,
        uint256 _borrowRatio,
        DLPVault _dlpVault,
        ERC20 _asset,
        Kernel _kernel
    )
        Policy(_kernel)
        ERC4626(
            _asset,
            string(abi.encodePacked("Radiate ", _asset.name)),
            string(abi.encodePacked("rd-", _asset.symbol))
        )
    {
        require(
            _minAmountToInvest > 0,
            "Leverager: minAmountToInvest must be greater than 0"
        );
        minAmountToInvest = _minAmountToInvest;
        vaultCap = _vaultCap;
        loopCount = _loopCount;
        borrowRatio = _borrowRatio;
        dlpVault = _dlpVault;
    }

    //============================================================================================//
    //                                     DEFAULT OVERRIDES                                      //
    //============================================================================================//

    function configureDependencies()
        external
        override
        returns (Keycode[] memory dependencies)
    {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("ROLES");
        dependencies[1] = toKeycode("TRSRY");
        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        TRSRY = getModuleAddress(dependencies[1]);
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

    /// @notice vault cap
    uint256 public vaultCap;

    /// @notice Loop count
    uint256 public loopCount;

    /// @notice Borrow ratio
    uint256 public borrowRatio;

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

    /// @dev Emergency Unloop – withdraws all funds from Radiant to vault
    /// For migrations, or in case of emergency
    function emergencyUnloop(uint256 _amount) external onlyRole("admin") {
        _unloop(_amount);
        emergencyUnlooping = true;
        emit EmergencyUnloop(_amount);
    }

    function recoverERC20(
        ERC20 token,
        uint256 tokenAmount
    ) external onlyRole("admin") {
        if (token == asset && emergencyUnlooping) {
            revert Leverager_CANNOT_WITHDRAW_AFTER_EMERGENCY_UNLOOP();
        }
        token.safeTransfer(msg.sender, tokenAmount);
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
                address(dlpVault)
            );

            lendingPool.deposit(
                address(asset),
                amount,
                address(dlpVault),
                referralCode
            );
        }
    }

    /**
     *
     * @param _amount of tokens to free from loop
     */
    function _unloop(uint256 _amount) internal {
        bytes memory params = "";
        aaveLendingPool.flashLoanSimple(
            address(dlpVault),
            address(asset),
            _amount,
            params,
            0
        );
        emit Unloop(_amount);
    }

    // Rewards logic is moved into the DLP Vault

    //============================================================================================//
    //                               4626 OVERRIDES                                               //
    //============================================================================================//

    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this)) + amountInvested;
    }

    function afterDeposit(uint256 assets, uint256) internal override {
        if (assets + totalAssets() >= vaultCap) {
            revert Leverager_VAULT_CAP_REACHED();
        }
        uint256 cash_ = asset.balanceOf(address(this));
        if (cash_ >= minAmountToInvest) {
            uint256 depositFee = dlpVault.feePercent();
            if (depositFee > 0) {
                // Fee is necessary to prevent deposit and withdraw trolling
                uint256 fee = (cash_ * depositFee) / RATIO_DIVISOR;
                asset.transfer(TRSRY, fee);
            }
            _loop();
        }
        amountInvested += assets;
    }

    function beforeWithdraw(uint256 assets, uint256) internal override {
        if (assets > asset.balanceOf(address(this))) {
            uint256 amountToWithdraw = assets - asset.balanceOf(address(this));
            _unloop(amountToWithdraw);
            amountInvested -= amountToWithdraw;
        }
    }

    receive() external payable {
        revert Leverager_NO_ETHER();
    }
}
