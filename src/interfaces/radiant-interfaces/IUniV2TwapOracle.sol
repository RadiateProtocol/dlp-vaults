// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

interface IUniV2TwapOracle {
    function latestAnswer() external view returns (uint256 price);

    function latestAnswerInEth() external view returns (uint256 price);

    function update() external;

    function canUpdate() external view returns (bool);
}
