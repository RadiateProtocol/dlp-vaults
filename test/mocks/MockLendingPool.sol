// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockLendingPool {
    mapping(address => uint256) public depositBalances;
    mapping(address => uint256) public borrowBalances;
    mapping(address => uint256) public borrowRates;
    mapping(address => uint256) public liquidationThresholds;

    IERC20 public underlyingAsset;

    constructor(IERC20 underlyingAsset_) {
        underlyingAsset = underlyingAsset_;
    }

    function deposit(uint256 amount) external {
        underlyingAsset.transferFrom(msg.sender, address(this), amount);
        depositBalances[msg.sender] += amount;
    }

    function withdraw(uint256 amount) external {
        require(
            depositBalances[msg.sender] >= amount,
            "MockLendingPool: Insufficient deposit balance."
        );
        depositBalances[msg.sender] -= amount;
        underlyingAsset.transfer(msg.sender, amount);
    }

    function borrow(uint256 amount) external {
        require(
            borrowRates[msg.sender] > 0,
            "MockLendingPool: Borrow rate not set."
        );
        require(
            borrowBalances[msg.sender] + amount <=
                depositBalances[msg.sender] * borrowRates[msg.sender],
            "MockLendingPool: Borrow limit exceeded."
        );
        borrowBalances[msg.sender] += amount;
        underlyingAsset.transfer(msg.sender, amount);
    }

    function repay(uint256 amount) external {
        require(
            borrowBalances[msg.sender] >= amount,
            "MockLendingPool: Insufficient borrow balance."
        );
        borrowBalances[msg.sender] -= amount;
        underlyingAsset.transferFrom(msg.sender, address(this), amount);
    }

    function setBorrowRate(address user, uint256 rate) external {
        borrowRates[user] = rate;
    }

    function setLiquidationThreshold(address user, uint256 threshold) external {
        liquidationThresholds[user] = threshold;
    }

    function liquidate(address user) external {
        require(
            borrowBalances[user] > liquidationThresholds[user],
            "MockLendingPool: Cannot liquidate user."
        );
        uint256 amount = borrowBalances[user];
        borrowBalances[user] = 0;
        depositBalances[user] -= amount;
        underlyingAsset.transfer(msg.sender, amount);
    }
}
