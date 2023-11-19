// SPDX-License-Identifier: MIT
// Specifies the license under which the code is distributed (MIT License).

// Website: davincigraph.io
// The website associated with this contract.

// Specifies the version of Solidity compiler to use.
pragma solidity ^0.8.9;

// Imports the SafeHTS library, which provides methods for safely interacting with Hedera Token Service (HTS).
import "./hedera/SafeHTS.sol";

// Imports the ReentrancyGuard contract from the OpenZeppelin Contracts package, which helps protect against reentrancy attacks.
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract DaVinciGraphNFTLocker is ReentrancyGuard {
    uint256 public fee;
    address public owner;
    bool public onlyOwnerCanAssociate = true;
    uint256 public constant MAX_FEE = 10000000000;
    uint256 public constant AUTO_RENEW_CONTRACT_BALANCE = 10000000000; // HOLD 100 HBAR in The contract for AUTO_RENEW

    modifier onlyOwner() {
        require( msg.sender == owner, "Only the contract owner can perform this action." );
        _;
    }

    constructor() {
        fee = 5000000000; // Initial fee
        owner = msg.sender;
    }

    receive() external payable {}

    fallback() external payable {}

    // Struct to store information about locked NFTs
    struct LockedNFTs {
        mapping(int64 => bool) serialNumbers;
        uint256 lockTimestamp;
        uint256 lockDuration;
        int64 quantity;
    }

    // Creates a mapping to store LockedNFTs structs indexed by user and token addresses.
    mapping(address => mapping(address => LockedNFTs)) public _lockedNFTs;

    // associate tokens with the contract
    function associateToken(address token) external {
        require(token != address(0), "Token address must be provided");

        if( onlyOwnerCanAssociate == true){
            require( msg.sender == owner, "Currently only the contract owner can associate tokens to the contract." );
        }

        require( SafeHTS.safeGetTokenType(token) == 1, "Only non-fungible tokens are supported" );

        IHederaTokenService.TokenInfo memory tokenInfo = SafeHTS.safeGetTokenInfo(token);

        require(tokenInfo.fixedFees.length == 0, "Tokens with custom fixed fees are not supported" );

        require(tokenInfo.fractionalFees.length == 0, "Tokens with custom fractional fees are not supported" );

        require(tokenInfo.royaltyFees.length == 0, "Tokens with custom royalty fees are not supported" );

        // checks if fee schedule key is set or not
        for (uint i = 0; i < tokenInfo.token.tokenKeys.length; i++) {
            uint mask = 1 << 5; // Shift 1 to left by 5 places to create a mask for the 5th bit (the fee schedule key bit)
            if (tokenInfo.token.tokenKeys[i].keyType == mask) {
                require(tokenInfo.token.tokenKeys[i].key.contractId == address(0), "Tokens with fee schedule key are not supported");
                require(tokenInfo.token.tokenKeys[i].key.ed25519.length == 0, "Tokens with fee schedule key are not supported");
                require(tokenInfo.token.tokenKeys[i].key.ECDSA_secp256k1.length == 0, "Tokens with fee schedule key are not supported");
                require(tokenInfo.token.tokenKeys[i].key.delegatableContractId == address(0), "Tokens with fee schedule key are not supported");
            }
        }        

        SafeHTS.safeAssociateToken(token, address(this));

        emit TokenAssociated(token);
    }

    function lockNFT( address token, int64[] memory serialNumbers, uint256 lockDurationInSeconds ) external payable {
        require(msg.value >= fee, "Insufficient payment");

        require(token != address(0), "Token address must be provided");

        require(lockDurationInSeconds > 0, "Lock duration should be greater than 0" );

        require(serialNumbers.length > 0 && serialNumbers.length <= 10, "Serial numbers quantity must be between 1 to 10");

        require(_lockedNFTs[msg.sender][token].quantity == 0, "You have already locked this token" );

        int64 quantity = 0;
        address[] memory sender = new address[](serialNumbers.length);
        address[] memory receiver = new address[](serialNumbers.length);
        LockedNFTs storage lockedNft = _lockedNFTs[msg.sender][token];

        for (uint i = 0; i < serialNumbers.length; i++) {
            sender[i] = msg.sender;
            receiver[i] = address(this);
            if (_lockedNFTs[msg.sender][token].serialNumbers[serialNumbers[i]] == false) {
                quantity++;
                lockedNft.serialNumbers[serialNumbers[i]] = true;
            }
        }

        lockedNft.lockTimestamp = block.timestamp;
        lockedNft.lockDuration = lockDurationInSeconds;
        lockedNft.quantity = quantity;

        SafeHTS.safeTransferNFTs(token, sender, receiver, serialNumbers);

        emit NFTLocked(msg.sender, token, serialNumbers, lockDurationInSeconds);
    }

    function increaseLockedNfts(address token, int64[] memory additionalSerialNumbers) external payable {
        require(msg.value >= fee, "Insufficient payment");

        require(token != address(0), "Token address must be provided");

        uint256 additionalSerialNumberLength = additionalSerialNumbers.length;
        
        require(additionalSerialNumberLength > 0 && additionalSerialNumberLength <= 10, "Serial numbers quantity must be between 1 to 10");

        require(_lockedNFTs[msg.sender][token].quantity > 0, "You have not locked this token" );

        // Ensures overall user has only 20 nft locked of a token
        require(uint256(int256(_lockedNFTs[msg.sender][token].quantity)) + additionalSerialNumberLength <= 20, "You are only allowed to lock 30 NFTs of the same token");
        
        int64 quantity = 0; // counter of non-duplicated nfts
        address[] memory sender = new address[](additionalSerialNumberLength);
        address[] memory receiver = new address[](additionalSerialNumberLength);

        for (uint i = 0; i < additionalSerialNumberLength; i++) {
            sender[i] = msg.sender;
            receiver[i] = address(this);
            if (_lockedNFTs[msg.sender][token].serialNumbers[additionalSerialNumbers[i]] == false) {
                quantity++;
                _lockedNFTs[msg.sender][token].serialNumbers[additionalSerialNumbers[i]] = true;
            }
        }

        require(quantity > 0, "No new NFTs to lock.");

        _lockedNFTs[msg.sender][token].quantity += quantity;

        SafeHTS.safeTransferNFTs(token, sender, receiver, additionalSerialNumbers);

        emit LockedNFTsIncreased(msg.sender, token, additionalSerialNumbers);
    }

    function increaseLockDuration( address token, uint256 additionalDurationInSeconds ) external payable {
        require(msg.value >= fee, "Insufficient payment");

        require(token != address(0), "Token address cannot be zero");

        require(additionalDurationInSeconds > 0, "Increasing Duration should be greater than 0");

        require(_lockedNFTs[msg.sender][token].quantity > 0, "You have not locked this token");

        _lockedNFTs[msg.sender][token].lockDuration = _lockedNFTs[msg.sender][token].lockDuration + additionalDurationInSeconds;

        emit LockDurationIncreased(msg.sender, token, additionalDurationInSeconds);
    }

    function withdrawNFTs(address token, int64[] memory serialNumbers) external payable {
        require(token != address(0), "Token address must be provided");

        require(serialNumbers.length > 0 && serialNumbers.length <= 10, "Serial numbers quantity must be between 1 to 10");

        require(_lockedNFTs[msg.sender][token].quantity > 0, "You have not locked this token" );
        
        require( block.timestamp >= _lockedNFTs[msg.sender][token].lockTimestamp + _lockedNFTs[msg.sender][token].lockDuration, "Lock duration is not over" );

        (IHederaTokenService.FixedFee[] memory fixedFees, IHederaTokenService.FractionalFee[] memory fractionalFees, IHederaTokenService.RoyaltyFee[] memory royaltyFees) = SafeHTS.safeGetTokenCustomFees(token);

        require( fixedFees.length == 0, "Tokens with custom fixed fees cannot be withdrawn" );

        require( fractionalFees.length == 0, "Tokens with custom fractional fees cannot be withdrawn" );

        require( royaltyFees.length == 0, "Tokens with custom royalty fees cannot be withdrawn" );


        int64 quantity = 0;
        address[] memory sender = new address[](serialNumbers.length);
        address[] memory receiver = new address[](serialNumbers.length);

        for (uint i = 0; i < serialNumbers.length; i++) {
            sender[i] = address(this);
            receiver[i] = msg.sender;
            if (_lockedNFTs[msg.sender][token].serialNumbers[serialNumbers[i]] == true) {
                quantity++;
                delete _lockedNFTs[msg.sender][token].serialNumbers[serialNumbers[i]];
            }
        }

        if(quantity == _lockedNFTs[msg.sender][token].quantity){
            delete _lockedNFTs[msg.sender][token];
        } else {
            _lockedNFTs[msg.sender][token].quantity -= quantity;
        }

        SafeHTS.safeTransferNFTs(token, sender, receiver, serialNumbers);

        emit NFTWithdrawn(msg.sender, token, serialNumbers);
    }

    function changeOnlyOwnerCanAssociate(bool _onlyOwnerCanAssociate) public onlyOwner {
        if( _onlyOwnerCanAssociate != onlyOwnerCanAssociate ){
            onlyOwnerCanAssociate = _onlyOwnerCanAssociate;

            emit AssociationActorChanged(onlyOwnerCanAssociate);
        }
    }

    function updateFee(uint256 _fee) public onlyOwner {
        require(_fee <= MAX_FEE, "Fee exceeds maximum allowed.");

        fee = _fee;

        emit FeeUpdated(_fee);
    }

    function changeOwner(address _newOwner) public onlyOwner {
        require(_newOwner != address(0), "Invalid new owner address.");

        if( _newOwner != owner ){
            emit OwnerChanged(owner, _newOwner);

            owner = _newOwner;
        }
    }

    function withdrawFees() public onlyOwner nonReentrant {
        uint256 withdrawalAmount = address(this).balance - AUTO_RENEW_CONTRACT_BALANCE;

        require(withdrawalAmount > 0, "No balance to withdraw.");

        (bool success, ) = owner.call{value: withdrawalAmount}("");

        require(success, "Withdrawal failed.");

        emit FeeWithdrawn(owner, withdrawalAmount);
    }

    // Events
    event TokenAssociated(address indexed token);
    event NFTLocked(address indexed user, address indexed token, int64[] serialNumbers, uint256 lockDuration);
    event LockedNFTsIncreased(address indexed user, address indexed token, int64[] additionalSerialNumbers);
    event LockDurationIncreased(address indexed user, address indexed token, uint256 additionalDuration);
    event NFTWithdrawn(address indexed user, address indexed token, int64[] serialNumbers);
    event AssociationActorChanged(bool canOnlyOwnerAssociate);
    event FeeUpdated(uint256 newFee);
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);
    event FeeWithdrawn(address indexed receiver, uint256 amount);
}
