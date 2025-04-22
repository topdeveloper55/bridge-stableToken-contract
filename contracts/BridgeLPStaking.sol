// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        this; 
        return msg.data;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor () {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract BridgeLPStaking is ReentrancyGuard, Ownable {
    struct UserInfo {
        address previous;
        address next;
        uint256 amount;
        uint256 accumulatedRewards;
    }
    // minimum stake amount
    mapping(address => uint256) public minAmount;
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

    constructor() Ownable() {
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
        require(amount > minAmount[token], "Amount should be greater than minimum amount");
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

    //Set the minimum staking amount
    function setMinAmount(address token, uint256 _minAmount) external onlyOwner {
        minAmount[token] = _minAmount;
    }
}