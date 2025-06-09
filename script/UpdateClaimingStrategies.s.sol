// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {VestingStrategy} from "src/VestingStrategy.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

// UPDATE SCRIPT FOR VESTING STRATEGY PROXY
// 
// This script upgrades an existing VestingStrategy proxy contract to a new implementation.
// 
// BEFORE RUNNING:
// 1. Update the proxyAddress variable below with your deployed proxy address
// 2. Ensure your new VestingStrategy implementation is compatible with the existing storage layout
// 3. Make sure you have the correct private key set in your environment variables
//
// USAGE:
// 1. Set your environment variables:
//    export RPC_URL="your_rpc_url"
//    export PK="your_private_key"
//
// 2. Update the proxyAddress variable in this script with your deployed proxy address
//
// 3. Run the script:
//    forge script script/UpdateClaimingStrategies.s.sol:VestingStrategyUpdateScript --rpc-url $RPC_URL --private-key $PK --broadcast
//
// 4. For simulation only (without broadcasting):
//    forge script script/UpdateClaimingStrategies.s.sol:VestingStrategyUpdateScript --rpc-url $RPC_URL --private-key $PK


// DOCUMENTATION
// https://docs.openzeppelin.com/upgrades-plugins/1.x/api-foundry-upgrades#Upgrades-Upgrades-upgradeProxy-address-string-bytes-
// https://docs.openzeppelin.com/upgrades-plugins/1.x/api-core#define-reference-contracts


contract VestingStrategyUpdateScript is Script {
    // Address of the existing proxy contract to upgrade
    // TODO: Replace with your actual deployed proxy address
    address proxyAddress = 0x07E4bBf6AB95cBa1B21F805D57697c226D47cC6c;

    error TransactionFailed(string message);

    function setUp() public {}

    function upgradeProxy() internal {
        // Upgrade the existing proxy with the new implementation
        Upgrades.upgradeProxy(
            proxyAddress,
            "VestingStrategy.sol:VestingStrategy",
            "" // No additional data needed for this upgrade
        );
    }

    function run() public {
        uint256 privateKey = vm.envUint("PK");
        
        // Validate that proxy address is set
        if (proxyAddress == address(0)) {
            revert("Proxy address not set. Please update the proxyAddress variable with your deployed proxy address.");
        }

        console.log("Starting proxy upgrade...");
        console.log("Proxy address:", proxyAddress);
        console.log("New implementation: VestingStrategy.sol:VestingStrategy");

        vm.startBroadcast(privateKey);
        upgradeProxy();
        vm.stopBroadcast();

        console.log("Proxy upgrade completed successfully!");
        console.log("Proxy address:", proxyAddress);
        console.log("Implementation has been updated to the latest version.");
    }
}