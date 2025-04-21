// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract StableBridge is ReentrancyGuard, Ownable {
    address public stakingPool;
    uint256 public minAmount;
    uint256 public uniqueID;

    struct TxInfo {
        address from;
        address to;
        address token;
        uint256 amount;
        uint256 chainId;
        bytes32 txHash;
    }
    
    // Token balances held in bridge
    mapping(uint256 => TxInfo) public txInfo;
    
    event TokensLocked(
        address indexed user,
        address indexed to,
        address token,
        uint256 amount,
        uint256 chainId,
        uint256 id,
        bytes32 indexed txHash
    );
    
    constructor(address _stakingPool, uint256 _minAmount) Ownable(msg.sender) {
        stakingPool = _stakingPool;
        minAmount = _minAmount;
    }
    
    function lockTokens(address to, address token, uint256 amount, uint256 chainId) external nonReentrant {
        require(amount > minAmount, "Amount must be greater than minimum amount");
        
        // Transfer tokens from user
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        IERC20(token).transfer(stakingPool, amount);
        
        uniqueID += 1;
        
        bytes32 txHash = keccak256(abi.encodePacked(
            msg.sender,
            to,
            token,
            amount,
            chainId,
            block.timestamp,
            uniqueID
        ));

        txInfo[uniqueID].from = msg.sender;
        txInfo[uniqueID].to = to;
        txInfo[uniqueID].token = token;
        txInfo[uniqueID].amount = amount;
        txInfo[uniqueID].chainId = chainId;
        txInfo[uniqueID].txHash = txHash;
        
        emit TokensLocked(msg.sender, to, token, amount, chainId, uniqueID, txHash);
    }
    
    function setStakingPool(address _stakingPool) external onlyOwner {
        stakingPool = _stakingPool;
    }

    function setMinAmount(uint256 _minAmount) external onlyOwner {
        minAmount = _minAmount;
    }
}