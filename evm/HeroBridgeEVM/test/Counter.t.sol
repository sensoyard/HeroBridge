// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/MultiTokenDeposit.sol";

contract ERC20Mock is IERC20 {
    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowances;

    function transfer(
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
        balances[recipient] += amount;
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        require(balances[sender] >= amount, "Insufficient balance");
        require(allowances[sender][msg.sender] >= amount, "Allowance exceeded");
        balances[sender] -= amount;
        balances[recipient] += amount;
        allowances[sender][msg.sender] -= amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowances[msg.sender][spender] = amount;
        return true;
    }

    function mint(address account, uint256 amount) external {
        balances[account] += amount;
    }
}

contract MultiTokenDepositTest is Test {
    MultiTokenDeposit public multiTokenDeposit;
    ERC20Mock public token;

    address user = address(1);

    function setUp() public {
        multiTokenDeposit = new MultiTokenDeposit();
        token = new ERC20Mock();

        token.mint(user, 1000 * 10 ** 18);
    }

    function testDeposit() public {
        vm.startPrank(user);
        token.approve(address(multiTokenDeposit), 100 * 10 ** 18);
        multiTokenDeposit.deposit(address(token), 100 * 10 ** 18);
        vm.stopPrank();

        (
            address tokenAddress,
            uint256 amount,
            uint256 timestamp,
            uint256 nonce
        ) = multiTokenDeposit.getDepositDetails(user);
        assertEq(tokenAddress, address(token));
        assertEq(amount, 100 * 10 ** 18);
        assertEq(nonce, 0);
    }

    function testWithdraw() public {
        vm.startPrank(user);
        token.approve(address(multiTokenDeposit), 100 * 10 ** 18);
        multiTokenDeposit.deposit(address(token), 100 * 10 ** 18);

        vm.warp(block.timestamp + 10 minutes);
        multiTokenDeposit.withdraw();

        vm.stopPrank();

        uint256 userBalance = token.balances(user);
        assertEq(userBalance, 1000 * 10 ** 18);
    }

    function testDepositAndWithdraw() public {
        vm.startPrank(user);
        token.approve(address(multiTokenDeposit), 100 * 10 ** 18);
        multiTokenDeposit.deposit(address(token), 100 * 10 ** 18);

        vm.warp(block.timestamp + 10 minutes);
        multiTokenDeposit.withdraw();

        vm.stopPrank();

        uint256 userBalance = token.balances(user);
        assertEq(userBalance, 1000 * 10 ** 18);
    }

    function testCannotWithdrawBefore10Minutes() public {
        vm.startPrank(user);
        token.approve(address(multiTokenDeposit), 100 * 10 ** 18);
        multiTokenDeposit.deposit(address(token), 100 * 10 ** 18);

        vm.expectRevert("Withdrawal not allowed yet");
        multiTokenDeposit.withdraw();

        vm.stopPrank();
    }

    function testStorageSlot() public {
        vm.startPrank(user);
        token.approve(address(multiTokenDeposit), 100 * 10 ** 18);
        multiTokenDeposit.deposit(address(token), 100 * 10 ** 18);
        vm.stopPrank();

        // Calculate the storage slot for the `deposits` mapping
        bytes32 userSlot = keccak256(abi.encode(user, uint256(0))); // keccak256(user address, slot of deposits mapping)

        // Load the storage values at the calculated slots
        bytes32 tokenSlot = vm.load(address(multiTokenDeposit), userSlot);
        bytes32 amountSlot = vm.load(
            address(multiTokenDeposit),
            bytes32(uint256(userSlot) + 1)
        );
        bytes32 timestampSlot = vm.load(
            address(multiTokenDeposit),
            bytes32(uint256(userSlot) + 2)
        );
        bytes32 nonceSlot = vm.load(
            address(multiTokenDeposit),
            bytes32(uint256(userSlot) + 3)
        );

        // Convert storage values to the correct types and assert
        address tokenAddress = address(uint160(uint256(tokenSlot)));
        uint256 amount = uint256(amountSlot);
        uint256 timestamp = uint256(timestampSlot);
        uint256 nonce = uint256(nonceSlot);

        assertEq(tokenAddress, address(token));
        assertEq(amount, 100 * 10 ** 18);
        assertEq(nonce, 0);
    }
}
