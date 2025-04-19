// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

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
    address public bridgeContract;

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
        address indexed user,
        address token,
        uint256 amount,
        bytes32 indexed txHash
    );
    
    modifier updateReward(address token, address user) {
        if(user != address(0)) {
            userInfo[token][user].accumulatedRewards += currentRewards(token, user);
            updateReward(token, userInfo[token][user].previous);
        }
        _;
        totalFee[token] = 0;
    }

    constructor(uint256 _minAmount) {
        minAmount = _minAmount;
    }

    // Relase stable coin to receiver address
    function releaseTokens(
        address user,
        address token,
        uint256 amount,
        bytes32 txHash
    ) external nonReentrant onlyOwner {
        require(IERC20(token).balanceOf(address(this)) >= amount, "Insufficient bridge balance");
        
        processedTx[txHash] = true;
        IERC20(token).transfer(user, amount);
        
        emit TokensReleased(user, token, amount, transactionHash);
    }
    
    // Stake stablecoins to provide liquidity
    function stake(address token, uint256 amount) external nonReentrant updateReward(token, lastUser) {
        require(amount > minAmount, "Amount should be greater than minimum amount");
        
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        
        if(userInfo[token][msg.sender].amount == 0) {
            if(firstUser == address(0)) {
                firstUser = msg.sender;
                lastUser = msg.sender;
            } else {
                userInfo[token][msg.sender].previous = lastUser;
                userInfo[token][lastUser].next = msg.sender;
                lastUser = msg.sender;
            }
        }
        userInfo[token][msg.sender].amount += amount;
        totalStaked[token] += amount;
        
        emit Staked(msg.sender, token, amount);
    }

    // Withdraw staked tokens
    function withdraw(address token) external nonReentrant updateReward(token, lastUser) {
        require(userInfo[token][msg.sender].amount > 0, "No tokens staked");
        require(IERC20(token).balanceOf(address(this)) >= userInfo[token][msg.sender].amount, "Insufficient balance");
        
        address previous = userInfo[token][msg.sender].previous;
        address next = userInfo[token][msg.sender].next;
        if(previous == address(0)) {
            firstUser = next;
        } else {
            userInfo[token][previous].next = next;
        }

        if(next == address(0)) {
            lastUser = previous;
        } else {
            userInfo[token][next].previous = previous;
        }

        uint256 sendingAmount = userInfo[token][msg.sender].amount + userInfo[token][msg.sender].accumulatedRewards;
        userInfo[token][msg.sender].amount = 0;
        userInfo[token][msg.sender].accumulatedRewards = 0;
        userInfo[token][msg.sender].previous = address(0);
        userInfo[token][msg.sender].next = address(0);

        IERC20(token).transfer(msg.sender, sendingAmount);
    }

    // Set Bridge Contract address
    function setBridge(address bridge) external onlyOwner {
        bridgeContract = bridge;
    }

    // Add fee to total fee
    function addFee(address token, uint256 amount) external {
        require(msg.sender == bridgeContract, "Only Bridge Contract can call this function");
        totalFee[token] += amount;
    }

    // Calculate current rewards
    function currentRewards(address token, address user) public view returns (uint256) {
        return totalFee[token] * userInfo[token][user].amount / totalStaked[token];
    }
}
