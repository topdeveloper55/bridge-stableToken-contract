// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IBridgeLPStaking {
    function addFee(address token, uint256 amount) external;
}

contract StableBridge is ReentrancyGuard, Ownable {
    uint256 public constant FEE_RATE = 3;  // 3%
    uint256 public minAmount;
    uint256 public uniqueID;
    
    // Token balances held in bridge
    mapping(uint256 => bytes32) public lockedTxHash;
    
    event TokensLocked(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 id,
        bytes32 indexed txHash
    );
    
    constructor(address _stakingPool, uint256 _minAmount) {
        stakingPool = _stakingPool;
        minAmount = _minAmount;
    }
    
    function lockTokens(address token, uint256 amount) external nonReentrant {
        require(amount > minAmount, "Amount must be greater than minimum amount");
        
        // Transfer tokens from user
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        IERC20(token).transfer(stakingPool, amount);
        IBridgeLPStaking(stakingPool).addFee(token, amount * FEE_RATE / 100);
        
        uniqueID += 1;
        
        bytes32 txHash = keccak256(abi.encodePacked(
            msg.sender,
            token,
            amount,
            block.timestamp,
            uniqueID
        ));
        
        emit TokensLocked(msg.sender, token, amount, uniqueID, txHash);
    }
    
    function setStakingPool(address _stakingPool) external onlyOwner {
        stakingPool = _stakingPool;
    }

    function setMinAmount(uint256 _minAmount) external onlyOwner {
        minAmount = _minAmount;
    }
}