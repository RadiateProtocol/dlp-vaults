// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAToken} from "src/interfaces/radiant-interfaces/IAToken.sol";
import {Leverager} from "src/policies/Leverager.sol";
import {DLPVault} from "src/policies/DLPVault.sol";
import {ILendingPool} from "src/interfaces/radiant-interfaces/ILendingPool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "src/interfaces/uniswap/IUniswapV2Router02.sol";
import "@solmate/mixins/ERC4626.sol";

contract GelatoKeeper {
    using SafeERC20 for IERC20;

    IUniswapV2Router02 public immutable uniswapRouter;
    uint256 public constant RATIO_DIVISOR = 10000;
    ILendingPool public constant pool =
        ILendingPool(0xF4B1486DD74D07706052A33d31d7c0AAFD0659E1);
    IAToken[] public aTokens;
    IERC20[] public rewardTokens;
    ERC4626[] public vaults;
    mapping(ERC4626 => uint) vaultAPY;
    ERC4626 public constant rdLP =
        ERC4626(0xC6dC7749781F7Ba1e9424704B2904f2F94D3eb63);
    ERC20 public constant WETH =
        ERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    uint256 public dlpAPY;
    address public immutable owner;

    constructor(IUniswapV2Router02 _uniswapRouter) {
        uniswapRouter = _uniswapRouter;
        owner = msg.sender;
    }

    function addAtoken(IAToken[] memory _tokens) external {
        require(msg.sender == owner, "Only owner can add tokens");
        aTokens = _tokens;
    }

    function addRewardToken(IERC20[] memory _tokens) external {
        require(msg.sender == owner, "Only owner can add tokens");
        rewardTokens = _tokens;
        // Should be ordered by vaults array and then any extra tokens should be added to the end
        // last vault token should be WETH
    }

    function addRewardToken(IERC20 token) external {
        require(msg.sender == owner, "Only owner can add tokens");
        rewardTokens.push(token);
    }

    function addVault(ERC4626[] memory _vaults) external {
        require(msg.sender == owner, "Only owner can add vaults");
        vaults = _vaults;
        // should be ordered in order of yield priority
    }

    function addVault(ERC4626 _vault) external {
        require(msg.sender == owner, "Only owner can add vaults");
        vaults.push(_vault);
    }

    function setAPY(uint256 _apy, ERC4626 _vault) external {
        require(msg.sender == owner, "Only owner can set APY");
        vaultAPY[_vault] = _apy;
    }

    function setdLPAPY(uint256 _apy) external {
        require(msg.sender == owner, "Only owner can set APY");
        dlpAPY = _apy;
    }

    function getAPY(ERC4626 _vault) external view returns (uint256) {
        return vaultAPY[_vault];
    }

    function processATokens() internal {
        for (uint i = 0; i < aTokens.length; i++) {
            address _underlying = aTokens[i].UNDERLYING_ASSET_ADDRESS();

            // Withdraw the aToken to get the underlying asset
            uint256 aTokenBalance = aTokens[i].balanceOf(address(this));

            pool.withdraw(_underlying, aTokenBalance, address(this));
        }
    }

    function disperseRewards() external {
        // convert any non aToken rewards to aTokens
        processATokens();
        uint256[] memory rewardsNeeded = calculateAPYs();

        // Process rdLP rewards
        uint256 rewardAmt = (rdLP.totalAssets() * dlpAPY) / RATIO_DIVISOR >=
            WETH.balanceOf(address(this))
            ? WETH.balanceOf(address(this))
            : (rdLP.totalAssets() * dlpAPY) / RATIO_DIVISOR;

        WETH.transfer(address(rdLP), rewardAmt);

        for (uint i = 0; i < vaults.length; i++) {
            if (rewardsNeeded[i] == 0) {
                continue;
            } else {
                // Need to swap any reward tokens to the vault asset to pay down rewards
                for (uint j = 0; j < rewardTokens.length; j++) {
                    uint256 _balance = rewardTokens[i].balanceOf(address(this));
                    if (rewardsNeeded[i] == 0) {
                        break;
                    } else if (
                        _balance > 0 &&
                        address(rewardTokens[j]) == address(vaults[i].asset())
                    ) {
                        // pay out balance with any rewards
                        uint256 rewardPayoff = rewardsNeeded[i] <= _balance
                            ? rewardsNeeded[i]
                            : _balance;
                        rewardsNeeded[i] -= rewardPayoff;
                        rewardTokens[i].transfer(
                            address(vaults[i]),
                            rewardPayoff
                        );
                    } else if (_balance == 0) {
                        continue;
                    } else {
                        // Swap the asset for the respective asset of the vault
                        if (
                            rewardTokens[i].allowance(
                                address(this),
                                address(uniswapRouter)
                            ) == 0
                        ) {
                            rewardTokens[i].approve(
                                address(uniswapRouter),
                                type(uint256).max
                            );
                        }
                        uint256[] memory amounts = uniswapRouter
                            .swapExactTokensForTokens(
                                _balance,
                                0, // slippage is ignored for simplicity
                                getSwapPath(
                                    address(rewardTokens[j]),
                                    address(vaults[i].asset())
                                ),
                                address(this),
                                block.timestamp
                            );
                        // pay out balance with any rewards
                        uint256 rewardPayoff = rewardsNeeded[i] <= amounts[0]
                            ? rewardsNeeded[i]
                            : amounts[0];
                        rewardsNeeded[i] = _balance - rewardPayoff;
                        rewardTokens[i].transfer(
                            address(vaults[i]),
                            rewardPayoff
                        );
                    }
                }
            }
        }
    }

    function calculateAPYs() internal returns (uint256[] memory) {
        uint256[] memory rewardAmt = new uint256[](vaults.length);
        for (uint i = 0; i < vaults.length; i++) {
            rewardAmt[i] =
                (vaultAPY[vaults[i]] * vaults[i].totalAssets()) /
                RATIO_DIVISOR;

            // pay out balance with any rewards
            uint256 rewardPayoff = rewardAmt[i] <=
                rewardTokens[i].balanceOf(address(this))
                ? rewardAmt[i]
                : rewardTokens[i].balanceOf(address(this));
            rewardAmt[i] -= rewardPayoff;
            rewardTokens[i].transfer(address(vaults[i]), rewardPayoff);
        }
        return rewardAmt;
    }

    function getSwapPath(
        address token0,
        address token1
    ) private pure returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = token0;
        path[1] = token1;
        if (path[0] > path[1]) {
            (path[0], path[1]) = (path[1], path[0]);
        }
        return path;
    }

    function recoverTokens(IERC20 token) external {
        require(msg.sender == owner, "Only owner can recover tokens");
        token.transfer(owner, token.balanceOf(address(this)));
    }
}
