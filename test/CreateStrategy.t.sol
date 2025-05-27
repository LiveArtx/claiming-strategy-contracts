// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ContractUnderTest} from "./ContractUnderTest.sol";
import {VestingStrategy} from "../src/VestingStrategy.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract VestingStrategy_CreateStrategy_Test is ContractUnderTest {
    // Strategy parameters for testing
    uint256 constant CLIFF_DURATION = 7 days;
    uint256 constant CLIFF_PERCENTAGE = 2000; // 20%
    uint256 constant VESTING_DURATION = 180 days;
    uint256 constant EXPIRY_DATE = 365 days;
    bytes32 constant MERKLE_ROOT = bytes32(uint256(1));
    bool constant CLAIM_WITH_DELAY = false;

    function setUp() public override {
        super.setUp();
    }

    function test_should_create_strategy_with_valid_parameters() public {
        vm.startPrank(deployer);
        
        // Create strategy
        vestingStrategy.createStrategy(
            block.timestamp, // startTime
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            VESTING_DURATION,
            block.timestamp + EXPIRY_DATE,
            MERKLE_ROOT,
            CLAIM_WITH_DELAY,
            0 // No reward
        );

        // Verify strategy was created (first strategy has ID 1)
        VestingStrategy.Strategy memory strategy = vestingStrategy.getStrategy(1);
        
        assertEq(strategy.id, 1);
        assertEq(strategy.cliffDuration, CLIFF_DURATION);
        assertEq(strategy.cliffPercentage, CLIFF_PERCENTAGE);
        assertEq(strategy.vestingDuration, VESTING_DURATION);
        assertEq(strategy.merkleRoot, MERKLE_ROOT);
        assertTrue(strategy.isActive);
        assertEq(strategy.claimWithDelay, CLAIM_WITH_DELAY);
        assertEq(strategy.startTime, block.timestamp);
        assertEq(strategy.expiryDate, block.timestamp + EXPIRY_DATE);
        assertEq(strategy.rewardPercentage, 0);
    }

    function test_should_revert_if_not_owner() public {
        vm.startPrank(user1);
        
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user1));
        vestingStrategy.createStrategy(
            block.timestamp, // startTime
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            VESTING_DURATION,
            block.timestamp + EXPIRY_DATE,
            MERKLE_ROOT,
            CLAIM_WITH_DELAY,
            0 // No reward
        );
    }

    function test_should_revert_if_cliff_percentage_exceeds_100_percent() public {
        vm.startPrank(deployer);
        
        vm.expectRevert(VestingStrategy.InvalidUnlockPercentages.selector);
        vestingStrategy.createStrategy(
            block.timestamp, // startTime
            CLIFF_DURATION,
            10001, // 100.01%
            VESTING_DURATION,
            block.timestamp + EXPIRY_DATE,
            MERKLE_ROOT,
            CLAIM_WITH_DELAY,
            0 // No reward
        );
    }

    function test_should_revert_if_expiry_date_is_in_past() public {
        vm.startPrank(deployer);
        
        vm.expectRevert(VestingStrategy.InvalidStrategy.selector);
        vestingStrategy.createStrategy(
            block.timestamp, // startTime
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            VESTING_DURATION,
            block.timestamp - 1, // Past timestamp
            MERKLE_ROOT,
            CLAIM_WITH_DELAY,
            0 // No reward
        );
    }

    function test_should_create_multiple_strategies_with_incrementing_ids() public {
        vm.startPrank(deployer);
        
        // Create first strategy
        vestingStrategy.createStrategy(
            block.timestamp, // startTime
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            VESTING_DURATION,
            block.timestamp + EXPIRY_DATE,
            MERKLE_ROOT,
            CLAIM_WITH_DELAY,
            0 // No reward
        );

        // Create second strategy
        vestingStrategy.createStrategy(
            block.timestamp, // startTime
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            VESTING_DURATION,
            block.timestamp + EXPIRY_DATE,
            bytes32(uint256(2)), // Different merkle root
            CLAIM_WITH_DELAY,
            0 // No reward
        );

        // Verify IDs are incrementing
        VestingStrategy.Strategy memory strategy1 = vestingStrategy.getStrategy(1);
        VestingStrategy.Strategy memory strategy2 = vestingStrategy.getStrategy(2);
        assertEq(strategy2.id, strategy1.id + 1);
    }

    function test_should_emit_strategy_created_event() public {
        vm.startPrank(deployer);
        
        vm.expectEmit(true, false, false, true);
        emit VestingStrategy.StrategyCreated(
            1, // First strategy ID
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            VESTING_DURATION,
            block.timestamp + EXPIRY_DATE,
            MERKLE_ROOT,
            block.timestamp,
            CLAIM_WITH_DELAY,
            0 // No reward
        );

        vestingStrategy.createStrategy(
            block.timestamp, // startTime
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            VESTING_DURATION,
            block.timestamp + EXPIRY_DATE,
            MERKLE_ROOT,
            CLAIM_WITH_DELAY,
            0 // No reward
        );
    }

    function test_should_create_strategy_with_reward_tiers() public {
        vm.startPrank(deployer);
        
        // Create strategy with 50% reward (8 month claim)
        vestingStrategy.createStrategy(
            block.timestamp,
            0, // No cliff
            0, // No cliff percentage
            8 * 30 days, // 8 months vesting
            block.timestamp + EXPIRY_DATE,
            MERKLE_ROOT,
            true, // Enable delayed claims
            5000 // 50% reward
        );

        VestingStrategy.Strategy memory strategy = vestingStrategy.getStrategy(1);
        assertEq(strategy.rewardPercentage, 5000);
        assertTrue(strategy.claimWithDelay);
        assertEq(strategy.vestingDuration, 8 * 30 days);

        // Create strategy with 70% reward (10 month claim)
        vestingStrategy.createStrategy(
            block.timestamp,
            0,
            0,
            10 * 30 days, // 10 months vesting
            block.timestamp + EXPIRY_DATE,
            MERKLE_ROOT,
            true,
            7000 // 70% reward
        );

        strategy = vestingStrategy.getStrategy(2);
        assertEq(strategy.rewardPercentage, 7000);
        assertTrue(strategy.claimWithDelay);
        assertEq(strategy.vestingDuration, 10 * 30 days);

        // Create strategy with 120% reward (12 month claim)
        vestingStrategy.createStrategy(
            block.timestamp,
            0,
            0,
            12 * 30 days, // 12 months vesting
            block.timestamp + EXPIRY_DATE,
            MERKLE_ROOT,
            true,
            12000 // 120% reward
        );

        strategy = vestingStrategy.getStrategy(3);
        assertEq(strategy.rewardPercentage, 12000);
        assertTrue(strategy.claimWithDelay);
        assertEq(strategy.vestingDuration, 12 * 30 days);
    }

    function test_should_revert_when_reward_percentage_exceeds_max() public {
        vm.startPrank(deployer);
        
        vm.expectRevert(VestingStrategy.InvalidStrategy.selector);
        vestingStrategy.createStrategy(
            block.timestamp,
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            VESTING_DURATION,
            block.timestamp + EXPIRY_DATE,
            MERKLE_ROOT,
            CLAIM_WITH_DELAY,
            20001 // Exceeds max 200% (20000)
        );
    }

    function test_should_create_strategy_with_delayed_claims() public {
        vm.startPrank(deployer);
        
        vestingStrategy.createStrategy(
            block.timestamp, // startTime
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            VESTING_DURATION,
            block.timestamp + EXPIRY_DATE,
            MERKLE_ROOT,
            true, // Enable delayed claims
            0 // No reward
        );

        VestingStrategy.Strategy memory strategy = vestingStrategy.getStrategy(1);
        assertTrue(strategy.claimWithDelay);
        assertTrue(strategy.isActive);
        assertEq(strategy.rewardPercentage, 0);
    }

    function test_should_create_strategy_with_zero_cliff() public {
        vm.startPrank(deployer);
        
        vestingStrategy.createStrategy(
            block.timestamp, // startTime
            0, // No cliff
            0, // No cliff percentage
            VESTING_DURATION,
            block.timestamp + EXPIRY_DATE,
            MERKLE_ROOT,
            CLAIM_WITH_DELAY,
            0 // No reward
        );

        VestingStrategy.Strategy memory strategy = vestingStrategy.getStrategy(1);
        assertEq(strategy.cliffDuration, 0, "Cliff duration should be 0");
        assertEq(strategy.cliffPercentage, 0, "Cliff percentage should be 0");
        assertEq(strategy.vestingDuration, VESTING_DURATION, "Vesting duration should remain unchanged");
        assertEq(strategy.rewardPercentage, 0, "Reward percentage should be 0");
    }

    function test_should_allow_owner_to_update_user_vesting_info() public {
        vm.startPrank(deployer);
        
        // Create a strategy first
        vestingStrategy.createStrategy(
            block.timestamp, // startTime
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            VESTING_DURATION,
            block.timestamp + EXPIRY_DATE,
            MERKLE_ROOT,
            CLAIM_WITH_DELAY,
            0 // No reward
        );

        // Create new vesting info
        VestingStrategy.UserVesting memory newInfo = VestingStrategy.UserVesting({
            strategyId: 1,
            claimedAmount: 100,
            lastClaimTime: block.timestamp,
            cliffClaimed: true,
            delayedAmount: 0,
            delayStartTime: 0,
            isDelayedClaim: false
        });

        // Update user's vesting info
        vestingStrategy.setUserVestingInfo(user1, newInfo);

        // Verify the update
        VestingStrategy.UserVesting memory updatedInfo = vestingStrategy.getUserVestingInfo(user1);
        assertEq(updatedInfo.strategyId, newInfo.strategyId);
        assertEq(updatedInfo.claimedAmount, newInfo.claimedAmount);
        assertEq(updatedInfo.lastClaimTime, newInfo.lastClaimTime);
        assertTrue(updatedInfo.cliffClaimed);
        assertEq(updatedInfo.delayedAmount, newInfo.delayedAmount);
        assertEq(updatedInfo.delayStartTime, newInfo.delayStartTime);
        assertFalse(updatedInfo.isDelayedClaim);
    }

    function test_should_revert_if_non_owner_updates_user_vesting_info() public {
        vm.startPrank(user1);
        
        VestingStrategy.UserVesting memory newInfo = VestingStrategy.UserVesting({
            strategyId: 1,
            claimedAmount: 100,
            lastClaimTime: block.timestamp,
            cliffClaimed: true,
            delayedAmount: 0,
            delayStartTime: 0,
            isDelayedClaim: false
        });

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user1));
        vestingStrategy.setUserVestingInfo(user2, newInfo);
    }
} 