// Deploy Mock ERC20
// Ex: forge script script/DeployMockERC20.s.sol:MockERC20DeployScript --rpc-url base-sepolia --private-key $PK --broadcast

pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {MockERC20Token} from "src/mock/ERC20Mock.sol";


contract MockERC20DeployScript is Script {
    function run() public {
        
        vm.startBroadcast();
        new MockERC20Token();
        vm.stopBroadcast();
    }
}
