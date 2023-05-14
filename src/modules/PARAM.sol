pragma solidity ^0.8.15;
import "src/kernel.sol";

contract PARAM is Module {
    constructor(Kernel kernel_) Module(kernel_) {}

    function KEYCODE() public pure override returns (Keycode) {
        return Keycode.wrap("PARAM");
    }

    function VERSION()
        external
        pure
        override
        returns (uint8 major, uint8 minor)
    {
        major = 1;
        minor = 0;
    }

    function setInterestRate(uint256 value_) external permissioned {
        params["interestRate"] = value_;
    }

    function saveParam(bytes32 param_, uint256 value_) external permissioned {
        params[param_] = value_;
    }

    function getParam(bytes32 param_) external view returns (uint256 value_) {
        value_ = params[param_];
    }

    mapping(bytes32 => uint256) public params;
}
