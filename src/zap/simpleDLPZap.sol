// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {rDLP} from "../SimpleDLPVault.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import {IVault, IWETH, IAsset} from "../interfaces/balancer/IVault.sol";
import {IWeightedPool} from "../interfaces/balancer/IWeightedPoolFactory.sol";

contract dLPZap is Ownable {
    using SafeERC20 for IERC20;
    uint256 public constant RATIO_DIVISOR = 10000;

    IWETH public constant WETH =
        IWETH(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    IERC20 public constant RDNT =
        IERC20(0x3082CC23568eA640225c2467653dB90e9250AaA0);

    IVault public constant BALANCER =
        IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    rDLP public constant rdLPVault =
        rDLP(0xC6dC7749781F7Ba1e9424704B2904f2F94D3eb63);

    bytes32 public constant balPool =
        0x32df62dc3aed2cd6224193052ce665dc181658410002000000000000000003bd;

    IERC20 public constant BALANCER_LP =
        IERC20(0x32dF62dc3aEd2cD6224193052Ce665DC18165841);

    constructor() Ownable() {}

    function zap(uint256 rdntAmt) external payable returns (uint256) {
        RDNT.transferFrom(
            msg.sender,
            address(this),
            rdntAmt
        );
        WETH.deposit{value: msg.value}();
        return joinPool();
    }

    function joinPool() internal returns (uint256 liquidity) {
        uint256 wethAmt = WETH.balanceOf(address(this));
        uint256 rdntAmt = RDNT.balanceOf(address(this));
        WETH.approve(address(BALANCER), type(uint256).max);
        RDNT.approve(address(BALANCER), type(uint256).max);

		(address token0, address token1) = sortTokens(address(RDNT), address(WETH));
        IAsset[] memory assets = new IAsset[](2);
        assets[0] = IAsset(token0);
        assets[1] = IAsset(token1);

        uint256[] memory maxAmountsIn = new uint256[](2);
		if (token0 == address(WETH)) {
			maxAmountsIn[0] = wethAmt;
			maxAmountsIn[1] = rdntAmt;
		} else {
			maxAmountsIn[0] = rdntAmt;
			maxAmountsIn[1] = wethAmt;
		}

		bytes memory userDataEncoded = abi.encode(IWeightedPool.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, maxAmountsIn, 0);
		IVault.JoinPoolRequest memory inRequest = IVault.JoinPoolRequest(assets, maxAmountsIn, userDataEncoded, false);
        BALANCER.joinPool(balPool, address(this), address(this), inRequest);

		liquidity = BALANCER_LP.balanceOf(address(this));
        BALANCER_LP.approve(address(rdLPVault), liquidity);
        rdLPVault.mint(msg.sender, liquidity);
    }    

	function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
		require(tokenA != tokenB, "identical addresses");
		(token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
		require(token0 != address(0), "address zero");
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
