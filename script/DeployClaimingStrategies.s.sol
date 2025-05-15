// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {VestingStrategy} from "src/VestingStrategy.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

// FOLLOW README INSTRUCTIONS

// DOCUMENTATION
// https://docs.openzeppelin.com/upgrades-plugins/1.x/api-foundry-upgrades#Upgrades-Upgrades-deployTransparentProxy-string-address-bytes-
// https://docs.openzeppelin.com/upgrades-plugins/1.x/api-core#define-reference-contracts



contract VestingStrategyDeployScript is Script {
    address vestingToken = 0x0000000000000000000000000000000000000000;

    error TransactionFailed(string message);

    function setUp() public {}

    function deployProxy(uint256 privateKey) internal returns (VestingStrategy) {
        address derivedAddress = vm.addr(privateKey);
        address initialOwner = derivedAddress;

        Options memory opts;
        opts.unsafeAllow = "external-library-linking";

        address proxy = Upgrades.deployTransparentProxy(
            "VestingStrategy.sol:VestingStrategy",
            initialOwner,
            abi.encodeCall(
                VestingStrategy.initialize,
                (vestingToken)
            ),
            opts
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