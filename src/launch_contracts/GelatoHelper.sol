// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAToken} from "src/interfaces/radiant-interfaces/IAToken.sol";
import {Leverager} from "src/policies/Leverager.sol";
import {DLPVault} from "src/policies/DLPVault.sol";
import {ILendingPool} from "src/interfaces/radiant-interfaces/ILendingPool.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {DLPVault} from "src/policies/DLPVault.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "src/interfaces/uniswap/IUniswapV2Router02.sol";
import "@solmate/mixins/ERC4626.sol";

contract GelatoKeeper is Ownable {
    using SafeERC20 for IERC20;

    ///////////// STATE ///////////////
    IUniswapV2Router02 public immutable uniswapRouter;
    uint256 public constant RATIO_DIVISOR = 10000;
    ILendingPool public constant pool =
        ILendingPool(0xF4B1486DD74D07706052A33d31d7c0AAFD0659E1);
    DLPVault public constant rdLP =
        DLPVault(0xC6dC7749781F7Ba1e9424704B2904f2F94D3eb63);
    ERC20 public constant WETH =
        ERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    address public gelatoExecutor;
    uint256 public dlpAPY;
    IAToken[] public aTokens;
    IERC20[] public rewardTokens;
    ERC4626[] public vaults;
    mapping(ERC4626 => uint) vaultAPY;
    uint256 public lastExecuted;

    constructor(IUniswapV2Router02 _uniswapRouter) Ownable() {
        uniswapRouter = _uniswapRouter;
        // Ensure that the contract is approved as a Keeper role
    }

    ///////////// ADMIN FUNCTIONS ///////////////

    function addAtoken(IAToken[] memory _tokens) external onlyOwner {
        aTokens = _tokens;
    }

    function addRewardToken(IERC20[] memory _tokens) external onlyOwner {
        rewardTokens = _tokens;
        for (uint i = 0; i < _tokens.length; i++) {
            if (
                _tokens[i].allowance(address(this), address(uniswapRouter)) == 0
            ) {
                _tokens[i].approve(address(uniswapRouter), type(uint256).max);
            }
        }
        // Should be ordered by vaults array and then any extra tokens should be added to the end
        // last vault token should be WETH
    }

    function addRewardToken(IERC20 token) external onlyOwner {
        rewardTokens.push(token);
        if (token.allowance(address(this), address(uniswapRouter)) == 0) {
            token.approve(address(uniswapRouter), type(uint256).max);
        }
    }

    function addVault(ERC4626[] memory _vaults) external onlyOwner {
        vaults = _vaults;
        // should be ordered in order of yield priority
    }

    function addVault(ERC4626 _vault) external onlyOwner {
        vaults.push(_vault);
    }

    function setAPY(uint256 _apy, ERC4626 _vault) external onlyOwner {
        vaultAPY[_vault] = _apy;
    }

    function setdLPAPY(uint256 _apy) external onlyOwner {
        dlpAPY = _apy;
    }

    function setGelatoExecutor(address _executor) external onlyOwner {
        gelatoExecutor = _executor;
    }

    function recoverTokens(IERC20 token) external onlyOwner {
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }

    function getAPY(ERC4626 _vault) external view returns (uint256) {
        return vaultAPY[_vault];
    }

    function disperseRewards() external {
        require(msg.sender == gelatoExecutor, "Not gelato executor");

        rdLP.claim();
        // convert any non aToken rewards to aTokens
        // ??? we convert any aTokens to underlying asset
        processATokens();
        // Pay down tokens where underlying is greater than reward debt, and then receive rewards needed
        uint256[] memory rewardsNeeded = payAndCalculate();

        // Process rdLP rewards
        // TODO: @wooark rewrite with custom calculation
        uint256 rewardAmt = (rdLP.totalAssets() * dlpAPY) / RATIO_DIVISOR >=
            WETH.balanceOf(address(this))
            ? WETH.balanceOf(address(this))
            : (rdLP.totalAssets() * dlpAPY) / RATIO_DIVISOR;

        WETH.transfer(address(rdLP), rewardAmt);
        updaterDLPPeriod();
        rdLP.notifyRewardAmount(rewardAmt);

        // Process each vault reward
        for (uint i = 0; i < vaults.length; i++) {
            if (rewardsNeeded[i] == 0) {
                continue;
            } else {
                // Need to swap any reward tokens to the vault asset to pay down rewards
                for (uint256 j = 0; j < rewardTokens.length; j++) {
                    uint256 _balance = rewardTokens[i].balanceOf(address(this));
                    if (rewardsNeeded[i] == 0) {
                        // Rewards paid down
                        break;
                    } else if (_balance == 0) {
                        // No reward tokens to swap
                        continue;
                    } else if (
                        _balance > 0 &&
                        address(rewardTokens[j]) == address(vaults[i].asset())
                    ) {
                        // pay out rewards with current balance of Reward token
                        uint256 rewardPayoff = rewardsNeeded[i] <= _balance
                            ? rewardsNeeded[i]
                            : _balance;
                        rewardsNeeded[i] -= rewardPayoff;
                        rewardTokens[i].transfer(
                            address(vaults[i]),
                            rewardPayoff
                        );
                    } else {
                        // Approve is done when tokens are added
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
        lastExecuted = block.timestamp;
    }

    ///////////// INTERNAL FUNCTIONS ///////////////

    function processATokens() internal {
        for (uint i = 0; i < aTokens.length; i++) {
            address _underlying = aTokens[i].UNDERLYING_ASSET_ADDRESS();

            // Withdraw the aToken to get the underlying asset
            uint256 aTokenBalance = aTokens[i].balanceOf(address(this));

            pool.withdraw(_underlying, aTokenBalance, address(this));
        }
    }

    function payAndCalculate() internal returns (uint256[] memory) {
        uint256[] memory rewardAmt = new uint256[](vaults.length);
        for (uint i = 0; i < vaults.length; i++) {
            rewardAmt[i] =
                (vaultAPY[vaults[i]] * vaults[i].totalAssets()) /
                RATIO_DIVISOR;

            // pay out balance with any rewards
            // TODO: @wooark why is this?
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

    function updaterDLPPeriod() public {
        if (rdLP.finishAt() < block.timestamp) {
            // Need to reset it
            rdLP.setRewardsDuration(7 days);
        }
    }

    // Checker for Gelato Keeper
    function checker() external view returns (bool, bytes memory) {
        if (lastExecuted > block.timestamp - 7 days) {
            return (false, "");
        } else {
            return (
                true,
                abi.encodeWithSelector(this.disperseRewards.selector)
            );
        }
    }
}
