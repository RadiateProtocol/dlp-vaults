pragma solidity 0.8.12;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./Leverager.sol";

contract LeveragerFactory is Initializable, OwnableUpgradeable {
    constructor(address owner) {}
 =
        0xF4B1486DD74D07706052A33d31d7c0AAFD0659E1
   
 =
        0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506

    function createLeverager() external {
        Leverager leverager = new Leverager();
        leverager.initialize(
        IEligibilityDataProvider _rewardEligibleDataProvider,
        IAaveOracle _aaveOracle,
        IChefIncentivesController _cic,
        AggregatorV3Interface _chainlink,
        IMultiFeeDistribution _mfd,
        DLPVault _vault,
        address _treasury
        uint256 _feePercent,


            
        );
    }
}
