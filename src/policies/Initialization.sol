// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;
import "src/Kernel.sol";
import "src/modules/TOKEN/RADToken.sol";

contract Initialization is Policy {
    RADToken public token;
    address public immutable CONFIGURATOR;

    constructor(Kernel _kernel) Policy(_kernel) {
        CONFIGURATOR = msg.sender;
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
        requests = new Permissions[](2);
        requests[0] = Permissions(toKeycode("TOKEN"), RADToken.mint.selector);
        requests[1] = Permissions(
            toKeycode("TOKEN"),
            RADToken.setMaxSupply.selector
        );
    }

    function mint(address _to, uint256 _amount) external {
        require(msg.sender == CONFIGURATOR, "Only configurator can mint");
        token.mint(_to, _amount);
    }

    function setMaxSupply() external {
        require(msg.sender == CONFIGURATOR, "Only configurator can set max");
        token.setMaxSupply(2e6 ether); // 200k supply
    }
}
