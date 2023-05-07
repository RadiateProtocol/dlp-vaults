// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;
import "@openzeppelin/upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/upgradeable/contracts/access/OwnableUpgradeable.sol";

import "./Leverager.sol";

contract LeveragerFactory is Initializable, OwnableUpgradeable {
    leverager[] public leveragers;

    address public vault;
    address public treasury;
    uint256 public feePercent;
    address[] public rewardBaseTokens;

    /// @notice Emitted when fee ratio is updated
    event FeePercentUpdated(uint256 _feePercent);

    /// @notice Emitted when treasury is updated
    event TreasuryUpdated(address indexed _treasury);

    event LeveragerCreated(address leverager, address indexed owner);

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

    function createLeverager() external onlyOwner {
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

    function getLeveragers() external view returns (leverager[] memory) {
        return leveragers;
    }
}
