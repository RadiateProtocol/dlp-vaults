// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;
import "src/Kernel.sol";
import "src/modules/TOKEN/RADToken.sol";

contract Initialization is Policy {
    RADToken public token;
    address public immutable CONFIGURATOR;

    constructor(Kernel _kernel, address _configurator) Policy(_kernel) {
        CONFIGURATOR = _configurator;
    }

    function configureDependencies()
        external
        override
        returns (Keycode[] memory dependencies)
    {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("TOKEN");
        token = RADToken(getModuleAddress(dependencies[0]));
    }

    function requestPermissions()
        external
        pure
        override
        returns (Permissions[] memory requests)
    {
        requests = new Permissions[](1);
        requests[0] = Permissions(toKeycode("TOKEN"), RADToken.mint.selector);
    }

    function mint(address _to, uint256 _amount) external {
        require(msg.sender == CONFIGURATOR, "Only configurator can mint");
        token.mint(_to, _amount);
    }
}
