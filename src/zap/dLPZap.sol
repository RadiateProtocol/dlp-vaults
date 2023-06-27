// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {rDLP} from "../policies/SimpleDLPVault.sol";

import "src/interfaces/uniswap/IUniswapV2Factory.sol";
import "src/interfaces/uniswap/IUNiswapV2Router02.sol";
import "src/interfaces/radiant-interfaces/IChainlinkAggregator.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import {IVault, IWETH, IAsset} from "src/interfaces/balancer/IVault.sol";
import {IWeightedPool} from "src/interfaces/balancer/IWeightedPoolFactory.sol";

contract dLPZap is Ownable {
    using SafeERC20 for IERC20;
    uint256 public constant RATIO_DIVISOR = 10000;
    uint256 public constant BALANCER_RATIO = 8000;
    /// @notice ETH oracle contract
    AggregatorV3Interface public ethChainlink =
        AggregatorV3Interface(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612);

    /// @notice Chainlink oracle address for RDNT/USD
    AggregatorV3Interface public rdntChainlink =
        AggregatorV3Interface(0x20d0Fcab0ECFD078B036b6CAf1FaC69A6453b352);

    /// @notice Sushiswap router
    IUniswapV2Router02 public uniswapRouter =
        IUniswapV2Router02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);

    IWETH public constant WETH =
        IWETH(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    IERC20 public constant RDNT =
        IERC20(0x3082CC23568eA640225c2467653dB90e9250AaA0);

    IVault public constant BALANCER =
        IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    rDLP public constant rdLPVault =
        rDLP(0x32dF62dc3aEd2cD6224193052Ce665DC18165841);

    bytes32 public constant balPool =
        0x32df62dc3aed2cd6224193052ce665dc181658410002000000000000000003bd;

    IERC20 public constant BALANCER_LP =
        IERC20(0x32dF62dc3aEd2cD6224193052Ce665DC18165841);

    constructor() Ownable() {}

    /// @dev Return estimated amount of Asset tokens to receive for given amount of tokens
    function _estimateRDNTout(
        uint256 _amtIn
    ) internal view returns (uint256 tokensOut) {
        (, int256 rdntAnswer, , , ) = rdntChainlink.latestRoundData(); // 8 decimals
        uint256 priceInAsset = uint256(rdntAnswer);
        (, int256 ethAnswer, , , ) = ethChainlink.latestRoundData(); // 8 decimals
        uint256 priceInEth = uint256(ethAnswer);
        tokensOut = (priceInAsset * _amtIn) / priceInEth; // 18 decimals
    }

    function zap(uint256 amountIn) public returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = address(WETH);
        path[1] = address(RDNT);
        if (
            IERC20(address(WETH)).allowance(
                address(uniswapRouter),
                address(uniswapRouter)
            ) == 0
        ) {
            IERC20(address(WETH)).approve(
                address(uniswapRouter),
                type(uint256).max
            );
        }
        uint256 swapped = (amountIn * BALANCER_RATIO) / RATIO_DIVISOR;
        uniswapRouter.swapExactTokensForTokens(
            swapped,
            (_estimateRDNTout(swapped) * 99) / 100, // 1% slippage
            path,
            address(this),
            block.timestamp + 1
        );
        IAsset[] memory assets = new IAsset[](2);
        assets[0] = IAsset(address(RDNT));
        assets[1] = IAsset(address(WETH));

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = RDNT.balanceOf(address(this));
        maxAmountsIn[1] = RDNT.balanceOf(address(this));

        // https://github.com/radiant-capital/v2/blob/main/contracts/radiant/zap/helpers/BalancerPoolHelper.sol
        bytes memory userDataEncoded = abi.encode(
            IWeightedPool.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
            maxAmountsIn,
            0
        );
        IVault.JoinPoolRequest memory inRequest = IVault.JoinPoolRequest(
            assets,
            maxAmountsIn,
            userDataEncoded,
            false
        );
        BALANCER.joinPool(balPool, address(this), address(this), inRequest);

        rdLPVault.mint(msg.sender, BALANCER_LP.balanceOf(address(this)));
    }

    function ethZap() external payable returns (uint256) {
        // Wrap incoming ETH into WETH
        WETH.deposit{value: msg.value}();
        // Call zap function with WETH
        uint256 wethAmount = WETH.balanceOf(address(this));
        return zap(wethAmount);
    }

    function recoverERC20(
        address tokenAddress,
        uint256 tokenAmount
    ) external onlyOwner returns (bool) {
        require(
            msg.sender == address(rdLPVault),
            "Only rdLPVault can recover tokens"
        );
        IERC20(tokenAddress).safeTransfer(msg.sender, tokenAmount);
        return true;
    }
}
