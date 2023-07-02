// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
                         $$\ $$\            $$\               
                         $$ |\__|           $$ |              
 $$$$$$\  $$$$$$\   $$$$$$$ |$$\  $$$$$$\ $$$$$$\    $$$$$$\  
$$  __$$\ \____$$\ $$  __$$ |$$ | \____$$\\_$$  _|  $$  __$$\ 
$$ |  \__|$$$$$$$ |$$ /  $$ |$$ | $$$$$$$ | $$ |    $$$$$$$$ |
$$ |     $$  __$$ |$$ |  $$ |$$ |$$  __$$ | $$ |$$\ $$   ____|
$$ |     \$$$$$$$ |\$$$$$$$ |$$ |\$$$$$$$ | \$$$$  |\$$$$$$$\ 
\__|      \_______| \_______|\__| \_______|  \____/  \_______|
https://radiateprotocol.com/

 */
contract MerkleDistributor is Ownable {
    address public immutable token;
    bytes32 public immutable merkleRoot;
    uint256 public immutable startTime;
    uint256 public immutable endTime;

    // This is a packed array of booleans.
    mapping(uint256 => uint256) private claimedBitMap;

    constructor(
        address token_,
        bytes32 merkleRoot_,
        uint256 startTime_,
        uint256 endTime_
    ) {
        token = token_;
        merkleRoot = merkleRoot_;
        startTime = startTime_;
        endTime = endTime_;
    }

    function isClaimed(uint256 index) public view returns (bool) {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        uint256 claimedWord = claimedBitMap[claimedWordIndex];
        uint256 mask = (1 << claimedBitIndex);
        return claimedWord & mask == mask;
    }

    function _setClaimed(uint256 index) private {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        claimedBitMap[claimedWordIndex] =
            claimedBitMap[claimedWordIndex] |
            (1 << claimedBitIndex);
    }

    function claim(
        uint256 index,
        address account,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external {
        require(!isClaimed(index), "MerkleDistributor: Drop already claimed.");
        require(
            MerkleProof.verify(
                merkleProof,
                merkleRoot,
                keccak256(abi.encodePacked(index, account, amount))
            ),
            "MerkleDistributor: Invalid proof."
        );
        require(
            block.timestamp >= startTime,
            "MerkleDistributor: Drop not started."
        );
        if (block.timestamp > endTime) {
            revert("MerkleDistributor: Drop ended.");
        }

        _setClaimed(index);
        IERC20(token).transfer(account, amount);

        emit Claimed(index, account, amount);
    }

    function _end() external onlyOwner {
        IERC20(token).transfer(
            msg.sender,
            IERC20(token).balanceOf(address(this))
        );
    }

    event Claimed(
        uint256 indexed index,
        address indexed account,
        uint256 indexed amount
    );
}
