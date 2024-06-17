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
            address userAddr,
            address tokenAddress,
            uint256 amount,
            uint256 timestamp
        ) = multiTokenDeposit.getDepositDetails(0);
        assertEq(userAddr, user);
        assertEq(tokenAddress, address(token));
        assertEq(amount, 100 * 10 ** 18);
    }

    function testWithdraw() public {
        vm.startPrank(user);
        token.approve(address(multiTokenDeposit), 100 * 10 ** 18);
        multiTokenDeposit.deposit(address(token), 100 * 10 ** 18);

        vm.warp(block.timestamp + 10 minutes);
        multiTokenDeposit.withdraw(0);

        vm.stopPrank();

        uint256 userBalance = token.balances(user);
        assertEq(userBalance, 1000 * 10 ** 18);
    }

    function testCreateFulfillmentOrder() public {
        vm.startPrank(user);
        token.approve(address(multiTokenDeposit), 100 * 10 ** 18);
        multiTokenDeposit.deposit(address(token), 100 * 10 ** 18);
        multiTokenDeposit.createFulfillmentOrder(0, 50 * 10 ** 18);
        vm.stopPrank();

        (
            uint256 depositId,
            address userAddr,
            address tokenAddress,
            uint256 amount,
            uint256 timestamp
        ) = multiTokenDeposit.getFulfillmentOrder(0);
        assertEq(depositId, 0);
        assertEq(userAddr, user);
        assertEq(tokenAddress, address(token));
        assertEq(amount, 50 * 10 ** 18);
    }

    function testClaimWithProof() public {
        vm.startPrank(user);
        token.approve(address(multiTokenDeposit), 100 * 10 ** 18);
        multiTokenDeposit.deposit(address(token), 100 * 10 ** 18);

        vm.warp(block.timestamp + 10 minutes);
        bytes memory proof = ""; // Mock proof, replace with actual proof in real scenarios
        multiTokenDeposit.claimWithProof(0, 100 * 10 ** 18, proof);

        vm.stopPrank();

        uint256 userBalance = token.balances(user);
        assertEq(userBalance, 1000 * 10 ** 18);
    }
}
