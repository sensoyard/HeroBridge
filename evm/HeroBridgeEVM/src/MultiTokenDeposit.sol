// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IFactsRegistry} from "./interfaces/IFactsRegistry.sol";

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

contract MultiTokenDeposit {
    struct Deposit {
        uint256 depositId;
        address user;
        address token;
        uint256 amount;
        uint256 timestamp;
    }

    struct FulfillmentOrder {
        uint256 orderId;
        uint256 depositId;
        address user;
        address token;
        uint256 amount;
        uint256 timestamp;
    }

    IFactsRegistry public immutable factsRegistry;
    address public immutable remoteContract;
    mapping(uint256 => Deposit) public deposits;
    mapping(uint256 => FulfillmentOrder) public fulfillmentOrders;
    uint256 public depositNonce;
    uint256 public orderNonce;

    event DepositMade(
        address indexed user,
        uint256 depositId,
        address indexed token,
        uint256 amount,
        uint256 timestamp
    );
    event WithdrawalMade(
        address indexed user,
        uint256 depositId,
        address indexed token,
        uint256 amount,
        uint256 timestamp
    );
    event FulfillmentOrderCreated(
        uint256 orderId,
        uint256 depositId,
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 timestamp
    );
    event ClaimedWithProof(
        address indexed user,
        uint256 depositId,
        uint256 amount
    );

    constructor(address _factsRegistry, address _remoteContract) {
        factsRegistry = IFactsRegistry(_factsRegistry);
        remoteContract = _remoteContract;
    }

    function deposit(address token, uint256 amount) external {
        require(amount > 0, "Amount must be greater than zero");

        require(
            IERC20(token).transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );

        uint256 depositId = depositNonce++;
        deposits[depositId] = Deposit({
            depositId: depositId,
            user: msg.sender,
            token: token,
            amount: amount,
            timestamp: block.timestamp
        });

        emit DepositMade(msg.sender, depositId, token, amount, block.timestamp);
    }

    function withdraw(uint256 depositId) external {
        Deposit memory deposit = deposits[depositId];
        require(deposit.user == msg.sender, "Not the deposit owner");
        require(deposit.amount > 0, "Invalid deposit");

        require(
            block.timestamp >= deposit.timestamp + 10 minutes,
            "Withdrawal not allowed yet"
        );

        delete deposits[depositId];

        require(
            IERC20(deposit.token).transfer(msg.sender, deposit.amount),
            "Transfer failed"
        );

        emit WithdrawalMade(
            msg.sender,
            depositId,
            deposit.token,
            deposit.amount,
            block.timestamp
        );
    }

    function createFulfillmentOrder(
        uint256 depositId,
        uint256 amount,
        address token
    ) external {
        // Deposit storage deposit = deposits[depositId];
        // require(deposit.amount >= amount, "Insufficient deposit amount");

        uint256 orderId = orderNonce++;
        fulfillmentOrders[orderId] = FulfillmentOrder({
            orderId: orderId,
            depositId: depositId,
            user: msg.sender,
            token: token,
            amount: amount,
            timestamp: block.timestamp
        });

        emit FulfillmentOrderCreated(
            orderId,
            depositId,
            msg.sender,
            token,
            amount,
            block.timestamp
        );
    }

    function claimWithProof(
        uint256 depositId,
        uint256 amount,
        uint256 blockNumber,
        uint256 orderId
    ) external {
        // Compute the base storage slot for the mapping
        bytes32 baseSlot = keccak256(abi.encode(orderId, uint256(1))); // assuming mapping is at slot 1

        // Compute the storage slots for each field in the FulfillmentOrder struct
        bytes32 depositIdSlot = keccak256(abi.encode(uint256(0), baseSlot));
        bytes32 userSlot = keccak256(abi.encode(uint256(1), baseSlot));
        bytes32 tokenSlot = keccak256(abi.encode(uint256(2), baseSlot));
        bytes32 amountSlot = keccak256(abi.encode(uint256(3), baseSlot));
        bytes32 timestampSlot = keccak256(abi.encode(uint256(4), baseSlot));

        // Verify each field of the FulfillmentOrder using FactsRegistry
        bytes32 depositIdSlotValue = factsRegistry.accountStorageSlotValues(
            remoteContract,
            blockNumber,
            depositIdSlot
        );
        bytes32 userSlotValue = factsRegistry.accountStorageSlotValues(
            remoteContract,
            blockNumber,
            userSlot
        );
        bytes32 tokenSlotValue = factsRegistry.accountStorageSlotValues(
            remoteContract,
            blockNumber,
            tokenSlot
        );
        bytes32 amountSlotValue = factsRegistry.accountStorageSlotValues(
            remoteContract,
            blockNumber,
            amountSlot
        );
        // bytes32 timestampSlotValue = factsRegistry.accountStorageSlotValues(
        //     remoteContract,
        //     blockNumber,
        //     timestampSlot
        // );

        // Ensure the verified values match the expected order values
        require(
            uint256(depositIdSlotValue) == depositId,
            "Mismatched depositId"
        );
        require(
            address(uint160(uint256(userSlotValue))) == msg.sender,
            "Mismatched user"
        );
        require(
            address(uint160(uint256(tokenSlotValue))) ==
                deposits[depositId].token,
            "Mismatched token"
        );
        require(uint256(amountSlotValue) == amount, "Mismatched amount");
        // Additional check for timestamp if needed
        // require(uint256(timestampSlotValue) == expectedTimestamp, "Mismatched timestamp");

        Deposit storage deposit = deposits[depositId];
        require(deposit.amount >= amount, "Insufficient deposit amount");

        deposit.amount -= amount;
        if (deposit.amount == 0) {
            delete deposits[depositId];
        }

        require(
            IERC20(deposit.token).transfer(msg.sender, amount),
            "Transfer failed"
        );

        emit ClaimedWithProof(msg.sender, depositId, amount);
    }

    function getDepositDetails(
        uint256 depositId
    )
        external
        view
        returns (address user, address token, uint256 amount, uint256 timestamp)
    {
        Deposit storage deposit = deposits[depositId];
        return (deposit.user, deposit.token, deposit.amount, deposit.timestamp);
    }

    function getFulfillmentOrder(
        uint256 orderId
    )
        external
        view
        returns (
            uint256 depositId,
            address user,
            address token,
            uint256 amount,
            uint256 timestamp
        )
    {
        FulfillmentOrder storage order = fulfillmentOrders[orderId];
        return (
            order.depositId,
            order.user,
            order.token,
            order.amount,
            order.timestamp
        );
    }
}
