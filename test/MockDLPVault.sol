// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;
import "./MockERC20.sol";


contract MockDLPVault is MockERC20 {
    MockERC20 public weth;
    constructor(MockERC20 _weth) MockERC20("DLP Vault", "DLPV", 0) {
        weth = _weth;
    }

    function getReward() external {
        weth.mint(msg.sender, 1e5);
    }

    
}
