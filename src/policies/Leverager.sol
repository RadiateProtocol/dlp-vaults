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
import "../interfaces/radiant-interfaces/ILendingPool.sol";
import "../interfaces/aave/IPool.sol";

/// @title Leverager Contract
/// @author w
/// @dev All function calls are currently implemented without side effects
contract Leverager is RolesConsumer, Policy {
    using SafeTransferLib for ERC20;

    // =========  EVENTS ========= //

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

    ERC20 public constant DLP =
        ERC20(0x32dF62dc3aEd2cD6224193052Ce665DC18165841);

    /// @notice Lending Pool address
    ILendingPool public constant lendingPool =
        ILendingPool(0xF4B1486DD74D07706052A33d31d7c0AAFD0659E1);

    /// @notice Aave lending pool address (for flashloans)
    IPool public constant aaveLendingPool =
        IPool(0x794a61358D6845594F94dc1DB02A252b5b4814aD);
    uint256 public constant RATIO_DIVISOR = 1e6;

    ERC20 public immutable asset;

    uint256 public immutable minAmountToInvest;

    DLPVault public dlpVault;

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
        dlpVault = _dlpVault;
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
        emit EmergencyUnloop(_amount);
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
        uint256 cash_ = asset.balanceOf(address(VAULT));
        if (cash_ >= minAmountToInvest) {
            VAULT._invest(cash_);
            uint256 depositFee = dlpVault.feePercent();
            if (depositFee > 0) {
                // Fee is necessary to prevent deposit and withdraw trolling
                uint256 fee = (cash_ * depositFee) / RATIO_DIVISOR;
                asset.transfer(TRSRY, fee);
            }
            _loop();
        }
    }

    function beforeWithdrawal(uint256 assets) internal {
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
