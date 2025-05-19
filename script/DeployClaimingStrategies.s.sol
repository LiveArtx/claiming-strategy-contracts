// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {VestingStrategy} from "src/VestingStrategy.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

// FOLLOW README INSTRUCTIONS

// DOCUMENTATION
// https://docs.openzeppelin.com/upgrades-plugins/1.x/api-foundry-upgrades#Upgrades-Upgrades-deployTransparentProxy-string-address-bytes-
// https://docs.openzeppelin.com/upgrades-plugins/1.x/api-core#define-reference-contracts


// ex: forge script script/DeployClaimingStrategies.s.sol:VestingStrategyDeployScript --rpc-url $RPC_URL --private-key $PK --broadcast 


contract VestingStrategyDeployScript is Script {
    address vestingToken = 0xcE1BeFb348B6D9C190aAe8C875925987c0e20EDD;

    error TransactionFailed(string message);

    function setUp() public {}

    function deployProxy(uint256 privateKey) internal returns (VestingStrategy) {
        address derivedAddress = vm.addr(privateKey);
        address initialOwner = derivedAddress;

        address proxy = Upgrades.deployTransparentProxy(
            "VestingStrategy.sol:VestingStrategy",
            initialOwner,
            abi.encodeCall(
                VestingStrategy.initialize,
                (vestingToken)
            )
        );

        return VestingStrategy(proxy);
    }

    function run() public {
        uint256 privateKey = vm.envUint("PK");
        vm.startBroadcast(privateKey);
        VestingStrategy vestingStrategy = deployProxy(privateKey);
        vm.stopBroadcast();

        console.log("Proxy deployed at:", address(vestingStrategy));
    }
}