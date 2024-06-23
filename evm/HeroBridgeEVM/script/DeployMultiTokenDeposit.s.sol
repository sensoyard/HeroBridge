// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {MultiTokenDeposit} from "../src/MultiTokenDeposit.sol";
import {IFactsRegistry} from "../src/interfaces/IFactsRegistry.sol";

contract DeployMultiTokenDeposit is Script {
    function run() external {
        //uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address factsRegistryAddress = 0x8Bf5d96bE3B1722114192293F7f25C575B2C70e5;
        address remoteContractAddress = address(0);

        //  vm.startBroadcast(deployerPrivateKey);

        MultiTokenDeposit multiTokenDeposit = new MultiTokenDeposit(
            factsRegistryAddress,
            remoteContractAddress
        );

        console.log(
            "MultiTokenDeposit deployed at:",
            address(multiTokenDeposit)
        );

        vm.stopBroadcast();
    }
}
