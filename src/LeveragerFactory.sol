// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

import "./Leverager.sol";

contract LeveragerFactory is Initializable, OwnableUpgradeable {
    leverager[] public leveragers;
    // Leverager parameters
    address public lendingPool = 0xF4B1486DD74D07706052A33d31d7c0AAFD0659E1;
    address public swapRouter = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;
    address public rewardEligibleDataProvider =
        0xd4966DC49a10aa5467D65f4fA4b1449b5d874399;
    address public aaveOracle = 0xFf785dE8a851048a65CbE92C84d4167eF3Ce9BAC;
    address public cic = 0xebC85d44cefb1293707b11f707bd3CEc34B4D5fA;
    address public aggregatorV3 = 0x20d0Fcab0ECFD078B036b6CAf1FaC69A6453b352;
    address public mfd = 0x76ba3eC5f5adBf1C58c91e86502232317EeA72dE;
    address public vault;
    address public treasury;
    uint256 public feePercent;
    address[] public rewardBaseTokens;

    /// @notice Emitted when fee ratio is updated
    event FeePercentUpdated(uint256 _feePercent);

    /// @notice Emitted when treasury is updated
    event TreasuryUpdated(address indexed _treasury);

    event LeveragerCreated(address leverager, address indexed owner);
    event LeveragerOwnershipTransferred(
        address leverager,
        address indexed currentOwner,
        address indexed newOwner
    );

    mapping(address => leverager[]) public userToLeveragers;

    mapping(address => bool) public isLeverager;

    function initialize(
        address _vault,
        address _treasury,
        uint256 _feePercent
    ) external initializer {
        vault = _vault;
        treasury = _treasury;
        feePercent = _feePercent;
        __Ownable_init();
    }

    /**
     * @notice Sets Looping fee ratio
     * @param _feePercent fee ratio.
     */
    function setFeePercent(uint256 _feePercent) external onlyOwner {
        require(_feePercent <= 1e4, "Invalid ratio");
        feePercent = _feePercent;
        emit FeePercentUpdated(_feePercent);
    }

    /**
     * @notice Sets new treasury address
     * @param _treasury address
     */
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "treasury is 0 address");
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    event RewardBaseTokensUpdated(address[] tokens);

    /**
     * @notice Array of reward tokens
     * @param _tokens array of tokens to be used as base tokens for rewards
     */
    function addRewardBaseTokens(address[] memory _tokens) external onlyOwner {
        rewardBaseTokens = _tokens;
        emit RewardBaseTokensUpdated(_tokens);
    }

    function getRewardBaseTokens() external view returns (address[] memory) {
        return rewardBaseTokens;
    }

    function createLeverager() external {
        Leverager leverager = new Leverager();
        leveragers.push(leverager);
        leverager.initialize(
            lendingPool,
            swapRouter,
            rewardEligibleDataProvider,
            aaveOracle,
            cic,
            aggregatorV3,
            mfd,
            vault,
            msg.sender
        );

        emit LeveragerCreated(address(leverager, msg.sender));
    }

    function isLeverager(address _leverager) external view returns (bool) {
        return isLeverager[_leverager];
    }

    function getLeveragers() external view returns (leverager[] memory) {
        return leveragers;
    }

    function transferLeveragerOwnership(
        address _currentOwner,
        address _newOwner
    ) external {
        require(isLeverager[msg.sender], "Not Leverager");
        leveragers[] storage userLeveragers = userToLeveragers[_currentOwner];
        for (uint256 i = 0; i < userLeveragers.length; i++) {
            if (address(userLeveragers[i]) == msg.sender) {
                userLeveragers[i] = userLeveragers[userLeveragers.length - 1];
                userLeveragers.pop();
                leveragers[] storage newUserLeveragers = userToLeveragers[
                    _newOwner
                ];
                newUserLeveragers.push(_leverager);
                return;
            }
        }
        revert("Leverager not found"); // Should never happen
    }

    function getUserLeveragers(
        address _user
    ) external view returns (leverager[] memory) {
        return userToLeveragers[_user];
    }
}
