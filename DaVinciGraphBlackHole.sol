// SPDX-License-Identifier: MIT
// Specifies the license under which the code is distributed (MIT License).

// Website: davincigraph.io
// The website associated with this contract.

// Specifies the version of Solidity compiler to use.
pragma solidity ^0.8.0;

// Imports the SafeHTS library, which provides methods for safely interacting with Hedera Token Service (HTS).
import "./SafeHTS.sol";

contract DaVinciGraphBlackHole {
    // Declares a public variable to store the fee for burning tokens and increasing burned amount.
    uint256 public fee;

    constructor() {
        // Sets the initial fee value.
        fee = 300000000;
    }

    // Declares a receive function that accepts incoming Ether transfers.
    receive() external payable {}

    // Declares a fallback function that accepts incoming Ether transfers with non-empty data.
    fallback() external payable {}

    // Function to associate a token with the contract
    function associateToken(address token) external {
        // Ensures that the token address is not zero.
        require(token != address(0), "Token address must be provided");

        // Ensures that the token type is Fungible
        require( SafeHTS.safeGetTokenType(token) == 0, "Only fungible tokens are supported" );

        // Calls the safeAssociateToken function from SafeHTS library to associate the token with the contract.
        SafeHTS.safeAssociateToken(token, address(this));

        // emit token association event
        emit TokenAssociated(token);
    }

    // Function to burn tokens
    function burnToken( address token, int64 amount ) external payable {
        // Ensures that the HBAR sent with the transaction is greater than or equal to the required fee.
        require(msg.value >= fee, "Insufficient payment");

        // Ensures that the token address is not zero.
        require(token != address(0), "Token address must be provided");

        // Ensures that the burn amount is greater than zero.
        require(amount > 0, "Burn amount should be greater than 0");

        // Calls the safeTransferToken function from SafeHTS library to transfer the tokens from the user to the contract.
        SafeHTS.safeTransferToken(token, msg.sender, address(this), amount);

        // Emits a TokenBurned event with the user's address, token address, burn amount
        emit TokenBurned(msg.sender, token, amount);
    }

    // Defines events for logging actions performed by the contract
    event TokenAssociated(address indexed token);
    event TokenBurned(address indexed user, address indexed token, int64 amount);
}