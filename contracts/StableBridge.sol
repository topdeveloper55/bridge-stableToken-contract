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

contract StableBridge is ReentrancyGuard, Ownable {
    address public stakingPool;
    mapping(address => uint256) public minAmount;
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

    constructor(address _stakingPool) Ownable() {
        stakingPool = _stakingPool;
    }

    function lockTokens(address to, address token, uint256 amount, uint256 chainId) external nonReentrant {
        require(amount > minAmount[token], "Amount must be greater than minimum amount");

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

    function setMinAmount(address token, uint256 _minAmount) external onlyOwner {
        minAmount[token] = _minAmount;
    }
}