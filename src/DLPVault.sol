import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

pragma solidity 0.8.11;

contract DLPVault is ERC4626 {
    constructor(ERC20 _asset) ERC4626(_asset, "Radiate DLP Vault", "RD-DLP") {}
}
