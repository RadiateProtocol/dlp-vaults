// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;
import "src/policies/Leverager.sol";
import "./interfaces/aave/IFlashLoanSimpleReceiver.sol";
import "./interfaces/aave/IPool.sol";
import "./interfaces/radiant-interfaces/ILendingPool.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";

contract MigratorZap is IFlashLoanSimpleReceiver, Ownable {
    // =========  EVENTS ========= //

    // =========  ERRORS ========= //

    error Migrator_ONLY_AAVE_LENDING_POOL(address sender);
    error Migrator_ONLY_SELF_INIT(address initiator);

    // =========  STATE ========= //

    IPool public constant aaveLendingPool =
        IPool(0x794a61358D6845594F94dc1DB02A252b5b4814aD);

    ILendingPool public constant radiantLendingPool =
        ILendingPool(0xF4B1486DD74D07706052A33d31d7c0AAFD0659E1);

    mapping(address => Leverager) public leveragers;

    constructor() {}

    function addLeverager(address _asset, address _leverager) public onlyOwner {
        leveragers[_asset] = Leverager(_leverager);
    }

    // No ETH unlooping support
    function migrate(uint256 _amount, address _asset) public {
        bytes memory params = "";
        bool success = aaveLendingPool.flashLoanSimple(
            address(this),
            _asset,
            _amount,
            params
        );
        require(success, "Migrator: Flashloan failed");
        Leverager leverager = leveragers[asset];
        leverager.deposit(ERC20(_asset).balanceOf(address(this)), msg.sender);
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256,
        address initiator,
        bytes calldata
    ) external returns (bool success) {
        if (msg.sender != address(aaveLendingPool)) {
            revert Migrator_ONLY_AAVE_LENDING_POOL(msg.sender);
        }
        if (initiator != address(this))
            revert Migrator_ONLY_SELF_INIT(initiator);
        if (asset.allowance(address(this), address(aaveLendingPool)) == 0) {
            ERC20(asset).approve(address(aaveLendingPool), type(uint256).max);
        }
        if (asset.allowance(address(this), address(radiantLendingPool)) == 0) {
            ERC20(asset).approve(
                address(radiantLendingPool),
                type(uint256).max
            );
        }

        lendingPool.repay(asset, amount, 2, msg.sender);
        lendingPool.withdraw(asset, amount, msg.sender);
    }
}
