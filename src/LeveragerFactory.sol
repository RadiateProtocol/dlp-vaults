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

    event RewardBaseTokensUpdated(address[] tokens);

    event LeveragerCreated(address leverager, address asset);

    mapping(address => bool) public isLeverager;

    function initialize(
        address _vault,
        address _treasury,
        uint256 _feePercent,
        address[] memory _rewardBaseTokens
    ) external initializer {
        vault = _vault;
        treasury = _treasury;
        feePercent = _feePercent;
        rewardBaseTokens = _rewardBaseTokens;
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

    /**
     * @notice Array of reward tokens
     * @param _tokens array of tokens to be used as base tokens for rewards
     */
    function addRewardBaseTokens(address[] memory _tokens) external onlyOwner {
        rewardBaseTokens = _tokens;
        emit RewardBaseTokensUpdated(_tokens);
    }

    function createLeverager(
        uint256 _minAmountToInvest,
        uint256 _vaultCap,
        uint256 _loopCount,
        uint256 _borrowRatio,
        address _vault,
        address _asset
    ) external onlyOwner {
        bytes memory _name = abi.encodePacked(
            "Radiate Leverager - ",
            ERC20(_asset).name()
        );
        bytes memory _symbol = abi.encodePacked(
            "RD-LV-",
            ERC20(_asset).symbol()
        );
        Leverager leverager = new Leverager(
            owner,
            _minAmountToInvest,
            _vaultCap,
            _loopCount,
            _borrowRatio,
            _vault,
            _asset,
            _name,
            _symbol
        );
        leveragers.push(leverager);

        emit LeveragerCreated(address(leverager, msg.sender));
    }

    function getRewardBaseTokens() external view returns (address[] memory) {
        return rewardBaseTokens;
    }

    function getLeveragers() external view returns (leverager[] memory) {
        return leveragers;
    }
}
