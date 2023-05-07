// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;
pragma abicoder v2;

import "./interfaces/radiant-interfaces/IMultiFeeDistribution.sol";

/// @title MFDlogic
/// @notice MFDlogic is a contract that contains key logic for interacting with MFD.
contract MFDlogic {
    /// @notice mfd
    IMultiFeeDistribution public mfd;

    constructor(IMultiFeeDistribution _mfd) {
        require(address(_mfd) != address(0), "MFD can't be 0 address");
        mfd = _mfd;
    }

    function _stake(uint256 _dlpBorrowed, uint256 _lockIndex) internal {
        mfd.setDefaultRelockTypeIndex(_lockIndex);
        mfd.stake(_dlpBorrowed, address(this), _lockIndex);
    }

    function _exit() internal {
        mfd.exit(true);
    }

    // No withdraw logic – either exit or get liquidated.

    function _setDefaultRelock(uint256 _index) internal {
        mfd.setDefaultRelockTypeIndex(_index);
    }

    function _claim() internal {
        mfd.getAllRewards();
    }
}
