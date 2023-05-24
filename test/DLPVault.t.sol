// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {DLPVault} from "../src/policies/DLPVault.sol";
import {MockERC20} from "./MockERC20.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Treasury} from "../src/modules/TRSRY/TRSRY.sol";
import {OlympusRoles} from "../src/modules/ROLES/OlympusRoles.sol";

import "../src/Kernel.sol";

contract DLPVaultTest is Test {
    DLPVault public dlpVault;
    Treasury public treasury;
    Kernel public kernel;
    OlympusRoles public roles;
    MockERC20 public DLP;
    MockERC20 public WETH;
    uint256 public interestRate;

    function setUp() public {
        kernel = new Kernel();
        treasury = new Treasury(kernel);
        roles = new OlympusRoles(kernel);
        DLP = new MockERC20("Dynamic Liquity Prov", "DLP", 18);
        WETH = new MockERC20("Wrapped Ether", "WETH", 18);
        interestRate = 100; // 10%
        dlpVault = new DLPVault(ERC20(address(DLP)), ERC20(address(WETH)), interestRate, kernel);
    }

    // Admin tests
    function testAdmin() public {
        dlpVault.setInterest(200);
        assertEq(dlpVault.interestfee(), 200);

        dlpVault.setDepositFee(200);
        assertEq(dlpVault.feePercent(), 200);

        // test add reward base tokens
    }

    // Borrow tests
    function test_borrowSuccess() public {
        // Gratn 
        // deposit 100 DLP
        DLP.mint(address(this), 100);
        DLP.approve(address(dlpVault), 100);
        dlpVault.deposit(100);

        // borrow 50 DLP
        dlpVault.borrow(50);

        // check balances
        assertEq(DLP.balanceOf(address(this)), 50);
        assertEq(DLP.balanceOf(address(dlpVault)), 50);
        assertEq(dlpVault.totalAssets(), 100);
        assertEq(dlpVault.amountBorrowed(), 50);
    }


}
