// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
}

library ZkLib {
    function verifyProof(bytes memory _proof) public pure returns (bool) {
        return true;
    }
}

contract MultiTokenDeposit {
    // Define a struct to keep track of deposits
    struct Deposit {
        address token;
        uint256 amount;
        uint256 timestamp;
        uint256 nonce;
    }

    // Mapping from user address to their deposit record
    mapping(address => Deposit) public deposits;

    // Mapping from user address to their current nonce
    mapping(address => uint256) public nonces;

    // Event to be emitted when a deposit is made
    event DepositMade(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 timestamp,
        uint256 nonce
    );

    // Event to be emitted when a withdrawal is made
    event WithdrawalMade(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 timestamp,
        uint256 nonce
    );

    // Function to deposit tokens
    function deposit(address token, uint256 amount) external {
        require(amount > 0, "Amount must be greater than zero");

        // Transfer tokens from the sender to this contract
        require(
            IERC20(token).transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );

        // Get the current nonce for the user
        uint256 nonce = nonces[msg.sender];

        // Record the deposit
        deposits[msg.sender] = Deposit({
            token: token,
            amount: amount,
            timestamp: block.timestamp,
            nonce: nonce
        });

        // Increment the nonce for the user
        nonces[msg.sender]++;

        // Emit the event
        emit DepositMade(msg.sender, token, amount, block.timestamp, nonce);
    }

    // Function to get the details of a specific deposit for a user
    function getDepositDetails(
        address user
    )
        external
        view
        returns (
            address token,
            uint256 amount,
            uint256 timestamp,
            uint256 nonce
        )
    {
        Deposit storage deposit = deposits[user];
        return (
            deposit.token,
            deposit.amount,
            deposit.timestamp,
            deposit.nonce
        );
    }

    // Function to withdraw tokens
    function withdraw() external {
        Deposit memory deposit = deposits[msg.sender];

        // Check if 10 minutes have passed since the deposit
        require(
            block.timestamp >= deposit.timestamp + 10 minutes,
            "Withdrawal not allowed yet"
        );

        // Clear the deposit record
        delete deposits[msg.sender];

        // Transfer the tokens to the user
        require(
            IERC20(deposit.token).transfer(msg.sender, deposit.amount),
            "Transfer failed"
        );

        // Emit the withdrawal event
        emit WithdrawalMade(
            msg.sender,
            deposit.token,
            deposit.amount,
            block.timestamp,
            deposit.nonce
        );
    }

    function getDepositNonce(address user) external view returns (uint256) {
        return nonces[user];
    }

    function fullFillOrder(
        address user,
        uint256 nonce,
        bytes memory proof
    ) external {
        Deposit memory deposit = deposits[user];

        require(ZkLib.verifyProof(proof), "Invalid proof");
        require(deposit.nonce == nonce, "Invalid nonce");

        require(
            IERC20(deposit.token).transfer(msg.sender, deposit.amount),
            "Transfer failed"
        );
        delete deposits[user];

        emit WithdrawalMade(
            user,
            deposit.token,
            deposit.amount,
            block.timestamp,
            deposit.nonce
        );
    }
}
