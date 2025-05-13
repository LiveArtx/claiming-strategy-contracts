// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {ContractUnderTest} from "./ContractUnderTest.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract VestingStrategy_Initialize_Test is ContractUnderTest {
    function setUp() public override {
        super.setUp();
    }

    function test_should_set_vesting_token_correctly() public view {
        assertEq(
            address(vestingStrategy.vestingToken()),
            address(mockERC20Token)
        );
    }
    
    function test_should_set_owner_correctly() public view {
        assertEq(vestingStrategy.owner(), deployer);
    }

    function test_should_revert_if_already_initialized() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vestingStrategy.initialize(address(mockERC20Token));
    }

}
