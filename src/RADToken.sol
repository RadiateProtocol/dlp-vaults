// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title RADToken
/// @notice RADToken is a contract for the RAD token.
contract RADToken is ERC20 {
    /// @notice Initializes the contract.
    constructor() ERC20("Radiance Token", "RAD") {}

    /// @notice Mints tokens.
    /// @param _to The address to mint to.
    /// @param _amount The amount to mint.
    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }

    /// @notice Burns tokens.
    /// @param _from The address to burn from.
    /// @param _amount The amount to burn.
    function burn(address _from, uint256 _amount) external {
        _burn(_from, _amount);
    }
}
