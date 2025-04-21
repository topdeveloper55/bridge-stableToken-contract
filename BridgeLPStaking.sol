// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BridgeLPStaking is ReentrancyGuard, Ownable {
    struct UserInfo {
        address previous;
        address next;
        uint256 amount;
        uint256 accumulatedRewards;
    }
    // minimum stake amount
    uint256 public minAmount;
    uint256 public feeRate = 30; // 3%
    mapping(address => uint256) public ownerProfit;

    // first/last liquidation provider's address
    mapping(address => address) public firstUser; 
    mapping(address => address) public lastUser;

    // Info of each user that stakes tokens
    mapping(address => mapping(address => UserInfo)) public userInfo; // token => user => data

    mapping(bytes32 => bool) processedTx;
    
    // Total staked
    mapping(address => uint256) public totalStaked;
    mapping(address => uint256) public totalFee;
    
    event Staked(address indexed user, address token, uint256 amount);
    event Withdrawn(address indexed user, address token, uint256 amount, uint256 reward);
    event TokensReleased(
        address indexed to,
        address token,
        uint256 amountAfterFee,
        bytes32 indexed txHash
    );

    constructor(uint256 _minAmount) Ownable(_msgSender()) {
        minAmount = _minAmount;
    }

    // Relase stable coin to receiver address
    function releaseTokens(
        address user,
        address token,
        uint256 amount,
        bytes32 txHash
    ) external nonReentrant onlyOwner {
        uint256 amountAfterFee = amount - amount * feeRate / 1000;

        require(IERC20(token).balanceOf(address(this)) >= amountAfterFee, "Insufficient bridge balance");
        require(!processedTx[txHash], "Already processed transaction");
        
        processedTx[txHash] = true;
        totalFee[token] += (amount * feeRate / 1000);
        IERC20(token).transfer(user, amountAfterFee);
        
        emit TokensReleased(user, token, amountAfterFee, txHash);
    }
    
    // Stake stablecoins to provide liquidity
    function stake(address token, uint256 amount) external nonReentrant {
        require(amount > minAmount, "Amount should be greater than minimum amount");
        updateReward(token, lastUser[token]);

        IERC20(token).transferFrom(msg.sender, address(this), amount);
        
        if(userInfo[token][msg.sender].amount == 0) {
            if(firstUser[token] == address(0)) {
                firstUser[token] = msg.sender;
                lastUser[token] = msg.sender;
            } else {
                userInfo[token][msg.sender].previous = lastUser[token];
                userInfo[token][lastUser[token]].next = msg.sender;
                lastUser[token] = msg.sender;
            }
        }
        userInfo[token][msg.sender].amount += amount;
        totalStaked[token] += amount;
        
        emit Staked(msg.sender, token, amount);
    }

    // Withdraw staked tokens
    function withdraw(address token) external nonReentrant {
        updateReward(token, lastUser[token]);

        uint256 sendingAmount = userInfo[token][msg.sender].amount + userInfo[token][msg.sender].accumulatedRewards;

        require(userInfo[token][msg.sender].amount > 0, "No tokens staked");
        require(IERC20(token).balanceOf(address(this)) >= sendingAmount, "Insufficient balance"); 
        
        address previous = userInfo[token][msg.sender].previous;
        address next = userInfo[token][msg.sender].next;
        if(previous == address(0)) {
            firstUser[token] = next;
        } else {
            userInfo[token][previous].next = next;
        }

        if(next == address(0)) {
            lastUser[token] = previous;
        } else {
            userInfo[token][next].previous = previous;
        }

        emit Withdrawn(msg.sender, token, userInfo[token][msg.sender].amount, userInfo[token][msg.sender].accumulatedRewards);

        totalStaked[token] -= userInfo[token][msg.sender].amount;
        userInfo[token][msg.sender].amount = 0;
        userInfo[token][msg.sender].accumulatedRewards = 0;
        userInfo[token][msg.sender].previous = address(0);
        userInfo[token][msg.sender].next = address(0);

        IERC20(token).transfer(msg.sender, sendingAmount);
    }

    // update rewards each time user stake or withdraw
    function updateReward(address token, address user) private {
        if(user != address(0)) {
            userInfo[token][user].accumulatedRewards += currentRewards(token, user);
            updateReward(token, userInfo[token][user].previous);
        } else {
            ownerProfit[token] += totalFee[token] / 2;
            totalFee[token] = 0;
        }
    }

    // Set fee rate
    function setFeeRate(uint256 _feeRate) external onlyOwner {
        feeRate = _feeRate;
    } 

    // Claim owner rewards
    function claimOwnerRewards(address token) external onlyOwner {
        require(IERC20(token).balanceOf(address(this)) >= ownerProfit[token], "Insufficient balance");

        uint256 amount = ownerProfit[token];
        ownerProfit[token] = 0;
        IERC20(token).transfer(msg.sender, amount);
    }

    // Calculate current rewards
    function currentRewards(address token, address user) public view returns (uint256) {
        return (totalFee[token] / 2) * userInfo[token][user].amount / totalStaked[token];
    }
}
