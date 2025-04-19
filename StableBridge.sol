// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IBridgeLPStaking {
    function addFee(address token, uint256 amount) external;
}

contract StableBridge is ReentrancyGuard, Ownable {
    uint256 public minAmount;
    uint256 public uniqueID;
    
    // Supported stablecoins
    mapping(address => bool) public supportedTokens;
    // Token balances held in bridge
    mapping(uint256 => bytes32) public lockedTxHash;
    
    event TokensLocked(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 fee,
        uniqueID,
        bytes32 indexed transactionHash
    );
    
    constructor(address _stakingPool, uint256 _minAmount) {
        stakingPool = _stakingPool;
        minAmount = _minAmount;
    }
    
    function lockTokens(address token, uint256 amount) external nonReentrant {
        require(supportedTokens[token], "Token not supported");
        require(amount > minAmount, "Amount must be greater than minimum amount");
        
        // Transfer tokens from user
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        IERC20(token).transfer(stakingPool, amount);
        
        lockedBalances[token] += amountAfterFee;
        uniqueID += 1;
        
        bytes32 txHash = keccak256(abi.encodePacked(
            msg.sender,
            token,
            amountAfterFee,
            block.timestamp,
            uniqueID
        ));
        
        emit TokensLocked(msg.sender, token, amountAfterFee, fee, uniqueID, txHash);
    }
    
    // Admin functions
    function addSupportedToken(address token) external onlyOwner {
        supportedTokens[token] = true;
    }
    
    function removeSupportedToken(address token) external onlyOwner {
        supportedTokens[token] = false;
    }
    
    function setStakingPool(address _stakingPool) external onlyOwner {
        stakingPool = _stakingPool;
    }

    function setMinAmount(uint256 _minAmount) external onlyOwner {
        minAmount = _minAmount;
    }
}