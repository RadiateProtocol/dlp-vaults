// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;
pragma abicoder v2;

import "./interfaces/radiant-interfaces/IMultiFeeDistribution.sol";

// relock
// individual early exit
// getReward
// withdraw
// exit
contract MFDlogic {
    /// @notice mfd
    IMultiFeeDistribution public mfd;

    constructor(IMultiFeeDistribution _mfd) {
        require(address(_mfd) != address(0), "MFD can't be 0 address");
        mfd = _mfd;
    }

    /**
     * @notice Set Multi fee distribution contract.
     * @param _mfdAddr New contract address.
     */
    function setMfd(IMultiFeeDistribution _mfdAddr) external onlyOwner {
        require(address(_mfdAddr) != address(0), "MFD can't be 0 address");
        mfd = _mfdAddr;
    }

    function _stake(uint256 _dlpBorrowed, uint256 _lockIndex) internal {
        mfd.setDefaultRelockTypeIndex(lockIndex);
        mfd.stake(dlpBorrowed, address(this), lockIndex);
    }

    function _exit() internal {
        mfd.exit(True);
    }

    // No withdraw logic – either exit or get liquidated, or
}
