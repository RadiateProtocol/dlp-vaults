// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "src/kernel.sol";

/// @title RADToken
/// @notice RADToken is a contract for the RAD token.
contract RADToken is ERC20, Module {
    //============================================================================================//
    //                                        MODULE SETUP                                        //
    //============================================================================================//

    /// @notice Initializes the contract.
    constructor(
        Kernel kernel_
    ) ERC20("Radiance Token", "RAD") Module(kernel_) {}

    /// @inheritdoc Module
    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("TOKEN");
    }

    /// @inheritdoc Module
    function VERSION()
        external
        pure
        override
        returns (uint8 major, uint8 minor)
    {
        major = 1;
        minor = 0;
    }

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    function mint(address _to, uint256 _amount) external permissioned {
        _mint(_to, _amount);
    }
}
