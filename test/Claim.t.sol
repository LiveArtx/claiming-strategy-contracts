// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ContractUnderTest} from "./ContractUnderTest.sol";
import {VestingStrategy} from "src/VestingStrategy.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {FixedPointMathLib} from "src/libraries/FixedPointMathLib.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import "forge-std/console.sol";


contract VestingStrategy_Claim_Test is ContractUnderTest {
    // Strategy parameters for testing
    uint256 constant CLIFF_DURATION = 7 days;
    uint256 constant CLIFF_PERCENTAGE = 2000; // 20%
    uint256 constant VESTING_DURATION = 180 days;
    uint256 constant EXPIRY_DATE = 365 days;
    bytes32 constant MERKLE_ROOT = bytes32(uint256(1));
    bool constant CLAIM_WITH_DELAY = false;
    uint256 private strategyId; // Add this to track the strategy ID

    function setUp() public override {
        super.setUp();

        // Create a strategy
        vm.startPrank(deployer);
        vestingStrategy.createStrategy(
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            VESTING_DURATION,
            block.timestamp + EXPIRY_DATE,
            MERKLE_ROOT,
            CLAIM_WITH_DELAY
        );
        // Strategy ID will be 1 since we initialize _nextStrategyId to 1
        strategyId = 1;
        // Mint tokens to token contract and approve vesting contract
        mockERC20Token.mint(address(mockERC20Token), CLAIM_AMOUNT);
        vm.startPrank(address(mockERC20Token));
        mockERC20Token.approve(address(vestingStrategy), type(uint256).max); // Approve max amount
        vm.stopPrank();
        vm.stopPrank();
    }

    function test_should_claim_cliff_amount() public {
        (bytes32 merkleRoot, bytes32[] memory merkleProof) = _claimerDetails();

        vm.startPrank(deployer);
        mockERC20Token.approve(address(vestingStrategy), CLAIM_AMOUNT);
        vestingStrategy.updateMerkleRoot(strategyId, merkleRoot);
        vm.stopPrank();

        vm.startPrank(claimer1);

        // Calculate expected cliff amount (20% of allocation)
        uint256 expectedCliffAmount = (CLAIM_AMOUNT * CLIFF_PERCENTAGE) / 10000;

        // Claim tokens
        vestingStrategy.claim(strategyId, CLAIM_AMOUNT, merkleProof);

        // Verify token balance
        assertEq(
            mockERC20Token.balanceOf(claimer1),
            expectedCliffAmount,
            "User should receive cliff amount"
        );

        // Verify vesting info
        VestingStrategy.UserVesting memory userInfo = vestingStrategy
            .getUserVestingInfo(claimer1);
        assertEq(
            userInfo.claimedAmount,
            expectedCliffAmount,
            "Claimed amount should be updated"
        );
        assertTrue(userInfo.cliffClaimed, "Cliff should be marked as claimed");
        assertEq(userInfo.strategyId, strategyId, "Strategy ID should be set");
        assertEq(
            userInfo.cliffClaimed,
            true,
            "Cliff should be marked as claimed"
        );
    }

    function test_should_claim_linear_vesting_after_cliff() public {
        (bytes32 merkleRoot, bytes32[] memory merkleProof) = _claimerDetails();

        vm.startPrank(deployer);
        mockERC20Token.approve(address(vestingStrategy), CLAIM_AMOUNT);
        vestingStrategy.updateMerkleRoot(strategyId, merkleRoot);
        vm.stopPrank();

        vm.startPrank(claimer1);

        // First claim the cliff amount
        uint256 cliffAmount = (CLAIM_AMOUNT * CLIFF_PERCENTAGE) / 10000; // 20% of total
        vestingStrategy.claim(strategyId, CLAIM_AMOUNT, merkleProof);
        assertEq(
            mockERC20Token.balanceOf(claimer1),
            cliffAmount,
            "User should receive cliff amount"
        );

        // Move past cliff period
        uint256 timeAfterCliff = block.timestamp + CLIFF_DURATION;
        vm.warp(timeAfterCliff);

        // Track total claimed amount
        uint256 totalClaimed = cliffAmount;
        uint256 lastClaimTime = block.timestamp;
        uint256 SECONDS_PER_DAY = 1 days;

        // Test claims for 7 days after cliff
        for (uint256 day = 1; day <= 7; day++) {
            // Move forward one day
            vm.warp(lastClaimTime + SECONDS_PER_DAY);

            // Get claimable amount for this day
            uint256 newClaimable = vestingStrategy.getClaimableAmount(
                claimer1,
                strategyId,
                CLAIM_AMOUNT
            );

            // Skip if nothing new to claim
            if (newClaimable == 0) continue;

            // Claim and verify
            uint256 preClaimBalance = mockERC20Token.balanceOf(claimer1);
            vestingStrategy.claim(strategyId, CLAIM_AMOUNT, merkleProof);
            uint256 postClaimBalance = mockERC20Token.balanceOf(claimer1);

            // Verify the claim amount
            assertEq(
                postClaimBalance - preClaimBalance,
                newClaimable,
                "Claim amount should match claimable amount"
            );
            totalClaimed += newClaimable;

            // Update last claim time
            lastClaimTime = block.timestamp;
        }

        // Verify vesting info
        VestingStrategy.UserVesting memory userInfo = vestingStrategy
            .getUserVestingInfo(claimer1);
        assertEq(
            userInfo.claimedAmount,
            totalClaimed,
            "Claimed amount should be updated"
        );
        assertTrue(userInfo.cliffClaimed, "Cliff should be marked as claimed");
    }

    function test_should_vest_correctly_over_entire_period_after_cliff_claimed() public {
        (bytes32 merkleRoot, bytes32[] memory merkleProof) = _claimerDetails();

        vm.startPrank(deployer);
        mockERC20Token.approve(address(vestingStrategy), CLAIM_AMOUNT);
        vestingStrategy.updateMerkleRoot(strategyId, merkleRoot);
        vm.stopPrank();

        vm.startPrank(claimer1);

        // Get strategy for calculations
        VestingStrategy.Strategy memory strategy = vestingStrategy.getStrategy(strategyId);

        // First claim the cliff amount
        uint256 cliffAmount = (CLAIM_AMOUNT * CLIFF_PERCENTAGE) / 10000; // 20% of total
        vestingStrategy.claim(strategyId, CLAIM_AMOUNT, merkleProof);
        assertEq(
            mockERC20Token.balanceOf(claimer1),
            cliffAmount,
            "User should receive cliff amount"
        );

        // Track total claimed amount
        uint256 totalClaimed = cliffAmount;
        uint256 lastClaimTime = block.timestamp;
        uint256 SECONDS_PER_DAY = 1 days;

        // Move past cliff period
        vm.warp(strategy.startTime + strategy.cliffDuration + 1);
        lastClaimTime = block.timestamp;

        // Calculate total days in vesting period after cliff
        uint256 vestingDaysAfterCliff = (strategy.vestingDuration - strategy.cliffDuration) / SECONDS_PER_DAY;

        // Test claims for each day after cliff
        for (uint256 day = 1; day <= vestingDaysAfterCliff; day++) {
            // Move forward one day
            vm.warp(lastClaimTime + SECONDS_PER_DAY);

            // Get claimable amount for this day
            uint256 newClaimable = vestingStrategy.getClaimableAmount(
                claimer1,
                strategyId,
                CLAIM_AMOUNT
            );

            // Skip if nothing new to claim
            if (newClaimable == 0) continue;

            // Claim and verify
            uint256 preClaimBalance = mockERC20Token.balanceOf(claimer1);
            vestingStrategy.claim(strategyId, CLAIM_AMOUNT, merkleProof);
            uint256 postClaimBalance = mockERC20Token.balanceOf(claimer1);

            // Verify the claim amount
            assertEq(
                postClaimBalance - preClaimBalance,
                newClaimable,
                "Claim amount should match claimable amount"
            );
            totalClaimed += newClaimable;

            // Update last claim time
            lastClaimTime = block.timestamp;

            // Debug log
            console.log("Day", day);
            console.log("New claimable", newClaimable);
            console.log("Total claimed", totalClaimed);
            console.log("Time", block.timestamp);
            console.log("Time since start", block.timestamp - strategy.startTime);
            console.log("Time since cliff", block.timestamp - (strategy.startTime + strategy.cliffDuration));
        }

        // Move to end of vesting period
        vm.warp(strategy.startTime + strategy.vestingDuration + 1);

        // Get final claimable amount
        uint256 finalClaimable = vestingStrategy.getClaimableAmount(
            claimer1,
            strategyId,
            CLAIM_AMOUNT
        );

        if (finalClaimable > 0) {
            // Claim final amount
            uint256 preClaimBalance = mockERC20Token.balanceOf(claimer1);
            vestingStrategy.claim(strategyId, CLAIM_AMOUNT, merkleProof);
            uint256 postClaimBalance = mockERC20Token.balanceOf(claimer1);
            totalClaimed += (postClaimBalance - preClaimBalance);
        }

        // Verify final amounts
        assertApproxEqAbs(
            totalClaimed,
            CLAIM_AMOUNT,
            vestingDaysAfterCliff, // Total accumulated rounding error allowance
            "Final claimed amount should equal allocated amount"
        );

        // Verify vesting info
        VestingStrategy.UserVesting memory userInfo = vestingStrategy.getUserVestingInfo(claimer1);
        assertEq(
            userInfo.claimedAmount,
            totalClaimed,
            "Claimed amount should be updated"
        );
        assertTrue(userInfo.cliffClaimed, "Cliff should be marked as claimed");
    }

    function test_should_vest_correctly_every_10_days_over_entire_period()
        public
    {
        (bytes32 merkleRoot, bytes32[] memory merkleProof) = _claimerDetails();

        vm.startPrank(deployer);
        mockERC20Token.approve(address(vestingStrategy), CLAIM_AMOUNT);
        vestingStrategy.updateMerkleRoot(strategyId, merkleRoot);
        vm.stopPrank();

        vm.startPrank(claimer1);

        // First claim the cliff amount
        uint256 cliffAmount = (CLAIM_AMOUNT * CLIFF_PERCENTAGE) / 10000; // 20% of total
        vestingStrategy.claim(strategyId, CLAIM_AMOUNT, merkleProof);
        assertEq(
            mockERC20Token.balanceOf(claimer1),
            cliffAmount,
            "User should receive cliff amount"
        );

        // Get strategy for calculations
        VestingStrategy.Strategy memory strategy = vestingStrategy.getStrategy(
            strategyId
        );

        uint256 totalClaimed = cliffAmount;
        uint256 lastClaimTime = block.timestamp;
        uint256 SECONDS_PER_DAY = 1 days;
        uint256 totalDays = strategy.vestingDuration / SECONDS_PER_DAY;
        uint256 increment = 10;

        // Skip cliff period
        vm.warp(block.timestamp + strategy.cliffDuration);
        lastClaimTime = block.timestamp;

        // Calculate how many 10-day periods we need to cover the full vesting period
        uint256 periods = (totalDays + increment - 1) / increment;  // Ceiling division

        for (uint256 i = 0; i < periods; i++) {
            // Calculate the actual increment for this period
            uint256 currentIncrement = (i == periods - 1) ? (totalDays - (i * increment)) : increment;
            
            // Warp forward by the current increment
            vm.warp(lastClaimTime + (currentIncrement * SECONDS_PER_DAY));
            lastClaimTime = block.timestamp;

            uint256 newClaimable = vestingStrategy.getClaimableAmount(
                claimer1,
                strategyId,
                CLAIM_AMOUNT
            );

            if (newClaimable > 0) {
                uint256 preClaimBalance = mockERC20Token.balanceOf(claimer1);
                vestingStrategy.claim(strategyId, CLAIM_AMOUNT, merkleProof);
                uint256 postClaimBalance = mockERC20Token.balanceOf(claimer1);

                assertEq(
                    postClaimBalance - preClaimBalance,
                    newClaimable,
                    "Claim amount should match claimable amount"
                );
                totalClaimed += newClaimable;
            }
        }

        // Verify final amounts
        assertApproxEqAbs(
            totalClaimed,
            CLAIM_AMOUNT,
            totalDays / 10, // Total accumulated rounding error allowance
            "Final claimed amount should equal allocated amount"
        );

        // Verify vesting info
        VestingStrategy.UserVesting memory userInfo = vestingStrategy
            .getUserVestingInfo(claimer1);
        assertEq(
            userInfo.claimedAmount,
            totalClaimed,
            "Claimed amount should be updated"
        );
        assertTrue(userInfo.cliffClaimed, "Cliff should be marked as claimed");
    }

    function test_should_claim_total_amount_after_vesting_period_ends() public {
        (bytes32 merkleRoot, bytes32[] memory merkleProof) = _claimerDetails();

        vm.startPrank(deployer);
        mockERC20Token.approve(address(vestingStrategy), CLAIM_AMOUNT);
        vestingStrategy.updateMerkleRoot(strategyId, merkleRoot);
        vm.stopPrank();

        vm.startPrank(claimer1);

        // First claim the cliff amount
        uint256 cliffAmount = (CLAIM_AMOUNT * CLIFF_PERCENTAGE) / 10000; // 20% of total
        vestingStrategy.claim(strategyId, CLAIM_AMOUNT, merkleProof);
        assertEq(
            mockERC20Token.balanceOf(claimer1),
            cliffAmount,
            "User should receive cliff amount"
        );

        // Get strategy for calculations
        VestingStrategy.Strategy memory strategy = vestingStrategy.getStrategy(
            strategyId
        );

        // Move to after vesting period ends
        vm.warp(strategy.startTime + strategy.vestingDuration + 1 days);

        // After vesting period ends, user should be able to claim the full remaining amount
        uint256 remainingAmount = CLAIM_AMOUNT - cliffAmount; // 80% of total

        // Get claimable amount before claiming
        uint256 finalClaimable = vestingStrategy.getClaimableAmount(
            claimer1,
            strategyId,
            CLAIM_AMOUNT
        );
        assertEq(
            finalClaimable,
            remainingAmount,
            "Should be able to claim full remaining amount after vesting period"
        );

        // Claim remaining amount
        vestingStrategy.claim(strategyId, CLAIM_AMOUNT, merkleProof);

        // Verify final amounts
        assertEq(
            mockERC20Token.balanceOf(claimer1),
            CLAIM_AMOUNT,
            "User should receive full allocation"
        );

        // Verify vesting info
        VestingStrategy.UserVesting memory userInfo = vestingStrategy
            .getUserVestingInfo(claimer1);
        assertEq(
            userInfo.claimedAmount,
            CLAIM_AMOUNT,
            "Claimed amount should be full allocation"
        );
        assertTrue(userInfo.cliffClaimed, "Cliff should be marked as claimed");
    }

    function test_should_handle_claims_near_vesting_boundaries() public {
        (bytes32 merkleRoot, bytes32[] memory merkleProof) = _claimerDetails();

        vm.startPrank(deployer);
        mockERC20Token.approve(address(vestingStrategy), CLAIM_AMOUNT);
        vestingStrategy.updateMerkleRoot(strategyId, merkleRoot);
        vm.stopPrank();

        vm.startPrank(claimer1);

        // Get strategy for calculations
        VestingStrategy.Strategy memory strategy = vestingStrategy.getStrategy(
            strategyId
        );

        // Test claim exactly at cliff end
        vm.warp(strategy.startTime + strategy.cliffDuration);
        uint256 cliffEndAmount = vestingStrategy.getClaimableAmount(
            claimer1,
            strategyId,
            CLAIM_AMOUNT
        );
        vestingStrategy.claim(strategyId, CLAIM_AMOUNT, merkleProof);
        assertEq(
            mockERC20Token.balanceOf(claimer1),
            cliffEndAmount,
            "User should receive cliff amount at cliff end"
        );
        uint256 totalClaimed = cliffEndAmount;

        // Test claim one second before vesting ends
        vm.warp(strategy.startTime + strategy.vestingDuration - 1);
        uint256 nearEndAmount = vestingStrategy.getClaimableAmount(
            claimer1,
            strategyId,
            CLAIM_AMOUNT
        );
        vestingStrategy.claim(strategyId, CLAIM_AMOUNT, merkleProof);
        totalClaimed += nearEndAmount;

        // Verify vesting info
        VestingStrategy.UserVesting memory userInfo = vestingStrategy
            .getUserVestingInfo(claimer1);
        assertEq(
            userInfo.claimedAmount,
            totalClaimed,
            "Claimed amount should be updated"
        );
        assertTrue(userInfo.cliffClaimed, "Cliff should be marked as claimed");
    }

    function test_should_revert_when_attempting_to_claim_multiple_times_per_day()
        public
    {
        (bytes32 merkleRoot, bytes32[] memory merkleProof) = _claimerDetails();

        vm.startPrank(deployer);
        mockERC20Token.approve(address(vestingStrategy), CLAIM_AMOUNT);
        vestingStrategy.updateMerkleRoot(strategyId, merkleRoot);
        vm.stopPrank();

        // Get strategy for calculations
        VestingStrategy.Strategy memory strategy = vestingStrategy.getStrategy(
            strategyId
        );

        // Warp to 10 minutes after strategy start
        vm.warp(strategy.startTime + 10 minutes);

        vm.startPrank(claimer1);

        // First claim at cliff
        vestingStrategy.claim(strategyId, CLAIM_AMOUNT, merkleProof);

        // Warp to 10 minutes after first claim
        vm.warp(strategy.startTime + 10 minutes);

        // Attempt to claim again immediately
        vm.expectRevert(VestingStrategy.NoTokensToClaim.selector);
        vestingStrategy.claim(strategyId, CLAIM_AMOUNT, merkleProof);
    }

    function test_should_update_claimedAmount_after_claim() public {
        (bytes32 merkleRoot, bytes32[] memory merkleProof) = _claimerDetails();

        vm.startPrank(deployer);
        mockERC20Token.approve(address(vestingStrategy), CLAIM_AMOUNT);
        vestingStrategy.updateMerkleRoot(strategyId, merkleRoot);
        vm.stopPrank();

        vm.startPrank(claimer1);

        // Get expected claim amount
        uint256 expectedClaimAmount = vestingStrategy.getClaimableAmount(
            claimer1,
            strategyId,
            CLAIM_AMOUNT
        );

        // Claim tokens
        vestingStrategy.claim(strategyId, CLAIM_AMOUNT, merkleProof);

        // Verify claimed amount is updated
        VestingStrategy.UserVesting memory userInfo = vestingStrategy
            .getUserVestingInfo(claimer1);
        assertEq(
            userInfo.claimedAmount,
            expectedClaimAmount,
            "Claimed amount should be updated"
        );
    }

    function test_should_emit_TokensClaimed_event() public {
        (bytes32 merkleRoot, bytes32[] memory merkleProof) = _claimerDetails();

        vm.startPrank(deployer);
        mockERC20Token.approve(address(vestingStrategy), CLAIM_AMOUNT);
        vestingStrategy.updateMerkleRoot(strategyId, merkleRoot);
        vm.stopPrank();

        vm.startPrank(claimer1);

        // Get expected claim amount
        uint256 expectedClaimAmount = vestingStrategy.getClaimableAmount(
            claimer1,
            strategyId,
            CLAIM_AMOUNT
        );

        // Expect the TokensClaimed event
        vm.expectEmit(true, true, false, true);
        emit VestingStrategy.TokensClaimed(
            claimer1,
            strategyId,
            expectedClaimAmount,
            true, // isInitial
            block.timestamp
        );

        // Claim tokens
        vestingStrategy.claim(strategyId, CLAIM_AMOUNT, merkleProof);
    }

    function test_should_revert_when_user_already_in_different_strategy() public {
        // Create second strategy with different parameters
        vm.startPrank(deployer);
        vestingStrategy.createStrategy(
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            VESTING_DURATION,
            block.timestamp + EXPIRY_DATE,
            bytes32(uint256(2)), // Different merkle root
            CLAIM_WITH_DELAY
        );
        uint256 secondStrategyId = 2; // Second strategy ID will be 2
        vm.stopPrank();

        // Get merkle proofs for both strategies
        (bytes32 merkleRoot1, bytes32[] memory merkleProof1) = _claimerDetails();
        (bytes32 merkleRoot2, bytes32[] memory merkleProof2) = _claimerDetails();

        // Set merkle roots for both strategies
        vm.startPrank(deployer);
        vestingStrategy.updateMerkleRoot(strategyId, merkleRoot1);
        vestingStrategy.updateMerkleRoot(secondStrategyId, merkleRoot2);
        vm.stopPrank();

        vm.startPrank(claimer1);

        // First claim in strategy 1
        vestingStrategy.claim(strategyId, CLAIM_AMOUNT, merkleProof1);

        // Verify user is in strategy 1
        VestingStrategy.UserVesting memory userInfo = vestingStrategy.getUserVestingInfo(claimer1);
        assertEq(userInfo.strategyId, strategyId, "User should be in strategy 1");

        // Try to claim in strategy 2 - should revert
        vm.expectRevert(VestingStrategy.UserAlreadyInStrategy.selector);
        vestingStrategy.claim(secondStrategyId, CLAIM_AMOUNT, merkleProof2);

        // Verify user is still in strategy 1
        userInfo = vestingStrategy.getUserVestingInfo(claimer1);
        assertEq(userInfo.strategyId, strategyId, "User should still be in strategy 1");
    }

    function test_should_revert_when_merkle_proof_is_invalid() public {
        // Get valid merkle proof for the strategy
        (bytes32 merkleRoot, bytes32[] memory validProof) = _claimerDetails();

        // Set the merkle root for the strategy
        vm.startPrank(deployer);
        vestingStrategy.updateMerkleRoot(strategyId, merkleRoot);
        vm.stopPrank();

        vm.startPrank(claimer1);

        // Create an invalid proof by modifying the first element
        bytes32[] memory invalidProof = new bytes32[](validProof.length);
        for (uint256 i = 0; i < validProof.length; i++) {
            invalidProof[i] = validProof[i];
        }
        // Modify the first element to make it invalid
        invalidProof[0] = bytes32(uint256(999));

        // Try to claim with invalid proof - should revert
        vm.expectRevert(VestingStrategy.InvalidMerkleProof.selector);
        vestingStrategy.claim(strategyId, CLAIM_AMOUNT, invalidProof);

        // Verify user has not been assigned to any strategy
        VestingStrategy.UserVesting memory userInfo = vestingStrategy.getUserVestingInfo(claimer1);
        assertEq(userInfo.strategyId, 0, "User should not be assigned to any strategy");
        assertEq(userInfo.claimedAmount, 0, "User should not have claimed any tokens");

        // Verify claim works with valid proof
        vestingStrategy.claim(strategyId, CLAIM_AMOUNT, validProof);

        // Verify user is now in the strategy
        userInfo = vestingStrategy.getUserVestingInfo(claimer1);
        assertEq(userInfo.strategyId, strategyId, "User should be assigned to strategy");
        assertTrue(userInfo.claimedAmount > 0, "User should have claimed tokens");
    }

    function test_should_handle_delayed_claim_release() public {
        // Create strategy with delayed claims enabled
        vm.startPrank(deployer);
        vestingStrategy.createStrategy(
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            VESTING_DURATION,
            block.timestamp + EXPIRY_DATE,
            bytes32(uint256(2)), // Different merkle root
            true // Enable delayed claims
        );
        uint256 delayedStrategyId = 2;

        // Mint tokens to token contract and approve vesting contract
        mockERC20Token.mint(address(mockERC20Token), CLAIM_AMOUNT);
        vm.startPrank(address(mockERC20Token));
        mockERC20Token.approve(address(vestingStrategy), type(uint256).max);
        vm.stopPrank();
        vm.stopPrank();

        // Get merkle proof for the delayed strategy
        (bytes32 merkleRoot, bytes32[] memory merkleProof) = _claimerDetails();

        // Set merkle root for the delayed strategy
        vm.startPrank(deployer);
        vestingStrategy.updateMerkleRoot(delayedStrategyId, merkleRoot);
        vm.stopPrank();

        vm.startPrank(claimer1);

        // Get strategy for timing calculations
        VestingStrategy.Strategy memory strategy = vestingStrategy.getStrategy(delayedStrategyId);

        // Try to claim before vesting period ends - should revert
        vm.expectRevert(VestingStrategy.ClaimNotAllowed.selector);
        vestingStrategy.claim(delayedStrategyId, CLAIM_AMOUNT, merkleProof);

        // Move to vesting period end
        vm.warp(strategy.startTime + strategy.vestingDuration);

        // First claim should set up delayed claim
        vestingStrategy.claim(delayedStrategyId, CLAIM_AMOUNT, merkleProof);

        // Verify delayed claim state
        VestingStrategy.UserVesting memory userInfo = vestingStrategy.getUserVestingInfo(claimer1);
        assertTrue(userInfo.isDelayedClaim, "Should be marked as delayed claim");
        assertEq(userInfo.delayedAmount, CLAIM_AMOUNT, "Delayed amount should be set");
        assertEq(userInfo.delayStartTime, block.timestamp, "Delay start time should be set");
        assertEq(userInfo.claimedAmount, CLAIM_AMOUNT, "Claimed amount should be updated");

        // Try to release before vesting duration has elapsed - should revert
        vm.expectRevert(VestingStrategy.ClaimNotAllowed.selector);
        vestingStrategy.claim(delayedStrategyId, CLAIM_AMOUNT, merkleProof);

        // Move past vesting duration
        vm.warp(userInfo.delayStartTime + strategy.vestingDuration + 1);

        // Record initial balances
        uint256 initialTokenContractBalance = mockERC20Token.balanceOf(address(mockERC20Token));
        uint256 initialUserBalance = mockERC20Token.balanceOf(claimer1);

        // Release delayed claim
        vestingStrategy.claim(delayedStrategyId, CLAIM_AMOUNT, merkleProof);

        // Verify final balances
        uint256 finalTokenContractBalance = mockERC20Token.balanceOf(address(mockERC20Token));
        uint256 finalUserBalance = mockERC20Token.balanceOf(claimer1);

        // Verify token contract transferred exactly the delayed amount
        assertEq(
            initialTokenContractBalance - finalTokenContractBalance,
            CLAIM_AMOUNT,
            "Token contract should transfer exactly the delayed amount"
        );

        // Verify user received exactly the delayed amount
        assertEq(
            finalUserBalance - initialUserBalance,
            CLAIM_AMOUNT,
            "User should receive exactly the delayed amount"
        );

        // Verify delayed claim state is cleared
        userInfo = vestingStrategy.getUserVestingInfo(claimer1);
        assertFalse(userInfo.isDelayedClaim, "Should not be marked as delayed claim");
        assertEq(userInfo.delayedAmount, 0, "Delayed amount should be cleared");
        assertEq(userInfo.delayStartTime, 0, "Delay start time should be cleared");
        assertEq(userInfo.claimedAmount, CLAIM_AMOUNT, "Claimed amount should remain unchanged");
    }

    function test_should_emit_tokens_released_event_and_transfer_tokens() public {
        // Create strategy with delayed claims enabled
        vm.startPrank(deployer);
        vestingStrategy.createStrategy(
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            VESTING_DURATION,
            block.timestamp + EXPIRY_DATE,
            bytes32(uint256(2)), // Different merkle root
            true // Enable delayed claims
        );
        uint256 delayedStrategyId = 2;

        // Mint tokens to token contract and approve vesting contract
        mockERC20Token.mint(address(mockERC20Token), CLAIM_AMOUNT);
        vm.startPrank(address(mockERC20Token));
        mockERC20Token.approve(address(vestingStrategy), type(uint256).max);
        vm.stopPrank();
        vm.stopPrank();

        // Get merkle proof for the delayed strategy
        (bytes32 merkleRoot, bytes32[] memory merkleProof) = _claimerDetails();

        // Set merkle root for the delayed strategy
        vm.startPrank(deployer);
        vestingStrategy.updateMerkleRoot(delayedStrategyId, merkleRoot);
        vm.stopPrank();

        vm.startPrank(claimer1);

        // Get strategy for timing calculations
        VestingStrategy.Strategy memory strategy = vestingStrategy.getStrategy(delayedStrategyId);

        // Move to vesting period end and make initial claim
        vm.warp(strategy.startTime + strategy.vestingDuration);
        vestingStrategy.claim(delayedStrategyId, CLAIM_AMOUNT, merkleProof);

        // Get user info to calculate release time
        VestingStrategy.UserVesting memory userInfo = vestingStrategy.getUserVestingInfo(claimer1);
        
        // Move past vesting duration
        vm.warp(userInfo.delayStartTime + strategy.vestingDuration + 1);

        // Record initial balances
        uint256 initialTokenContractBalance = mockERC20Token.balanceOf(address(mockERC20Token));
        uint256 initialUserBalance = mockERC20Token.balanceOf(claimer1);

        // Expect TokensReleased event
        vm.expectEmit(true, true, false, true);
        emit VestingStrategy.TokensReleased(
            claimer1,
            delayedStrategyId,
            CLAIM_AMOUNT,
            block.timestamp
        );

        // Release delayed claim
        vestingStrategy.claim(delayedStrategyId, CLAIM_AMOUNT, merkleProof);

        // Verify final balances
        uint256 finalTokenContractBalance = mockERC20Token.balanceOf(address(mockERC20Token));
        uint256 finalUserBalance = mockERC20Token.balanceOf(claimer1);

        // Verify token contract transferred exactly the delayed amount
        assertEq(
            initialTokenContractBalance - finalTokenContractBalance,
            CLAIM_AMOUNT,
            "Token contract should transfer exactly the delayed amount"
        );

        // Verify user received exactly the delayed amount
        assertEq(
            finalUserBalance - initialUserBalance,
            CLAIM_AMOUNT,
            "User should receive exactly the delayed amount"
        );

        // Verify delayed claim state is cleared
        userInfo = vestingStrategy.getUserVestingInfo(claimer1);
        assertFalse(userInfo.isDelayedClaim, "Should not be marked as delayed claim");
        assertEq(userInfo.delayedAmount, 0, "Delayed amount should be cleared");
        assertEq(userInfo.delayStartTime, 0, "Delay start time should be cleared");
        assertEq(userInfo.claimedAmount, CLAIM_AMOUNT, "Claimed amount should remain unchanged");
    }

    function test_should_revert_when_attempting_delayed_claim_before_vesting_duration() public {
        // Create strategy with delayed claims enabled
        vm.startPrank(deployer);
        vestingStrategy.createStrategy(
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            VESTING_DURATION,
            block.timestamp + EXPIRY_DATE,
            bytes32(uint256(2)), // Different merkle root
            true // Enable delayed claims
        );
        uint256 delayedStrategyId = 2;

        // Mint tokens to token contract and approve vesting contract
        mockERC20Token.mint(address(mockERC20Token), CLAIM_AMOUNT);
        vm.startPrank(address(mockERC20Token));
        mockERC20Token.approve(address(vestingStrategy), type(uint256).max);
        vm.stopPrank();
        vm.stopPrank();

        // Get merkle proof for the delayed strategy
        (bytes32 merkleRoot, bytes32[] memory merkleProof) = _claimerDetails();

        // Set merkle root for the delayed strategy
        vm.startPrank(deployer);
        vestingStrategy.updateMerkleRoot(delayedStrategyId, merkleRoot);
        vm.stopPrank();

        vm.startPrank(claimer1);

        // Get strategy for timing calculations
        VestingStrategy.Strategy memory strategy = vestingStrategy.getStrategy(delayedStrategyId);

        // Move to vesting period end and make initial claim
        vm.warp(strategy.startTime + strategy.vestingDuration);
        vestingStrategy.claim(delayedStrategyId, CLAIM_AMOUNT, merkleProof);

        // Get user info to calculate release time
        VestingStrategy.UserVesting memory userInfo = vestingStrategy.getUserVestingInfo(claimer1);
        
        // Verify delayed claim is set up
        assertTrue(userInfo.isDelayedClaim, "Should be marked as delayed claim");
        assertEq(userInfo.delayedAmount, CLAIM_AMOUNT, "Delayed amount should be set");
        assertEq(userInfo.delayStartTime, block.timestamp, "Delay start time should be set");

        // Try to release immediately - should revert
        vm.expectRevert(VestingStrategy.ClaimNotAllowed.selector);
        vestingStrategy.claim(delayedStrategyId, CLAIM_AMOUNT, merkleProof);

        // Try to release at various points before vesting duration has elapsed
        uint256[] memory testTimes = new uint256[](3);
        testTimes[0] = userInfo.delayStartTime + 1 days;                    // 1 day after
        testTimes[1] = userInfo.delayStartTime + (strategy.vestingDuration / 2);  // Half way
        testTimes[2] = userInfo.delayStartTime + strategy.vestingDuration - 1;    // 1 second before

        for (uint256 i = 0; i < testTimes.length; i++) {
            vm.warp(testTimes[i]);
            vm.expectRevert(VestingStrategy.ClaimNotAllowed.selector);
            vestingStrategy.claim(delayedStrategyId, CLAIM_AMOUNT, merkleProof);

            // Verify delayed claim state is unchanged
            userInfo = vestingStrategy.getUserVestingInfo(claimer1);
            assertTrue(userInfo.isDelayedClaim, "Should still be marked as delayed claim");
            assertEq(userInfo.delayedAmount, CLAIM_AMOUNT, "Delayed amount should remain unchanged");
            assertEq(userInfo.delayStartTime, strategy.startTime + strategy.vestingDuration, "Delay start time should remain unchanged");
        }

        // Test claim at exactly vesting duration - should succeed
        vm.warp(userInfo.delayStartTime + strategy.vestingDuration);
        uint256 preBalance = mockERC20Token.balanceOf(claimer1);
        vestingStrategy.claim(delayedStrategyId, CLAIM_AMOUNT, merkleProof);
        uint256 postBalance = mockERC20Token.balanceOf(claimer1);

        // Verify tokens were transferred
        assertEq(
            postBalance - preBalance,
            CLAIM_AMOUNT,
            "Should receive full delayed amount at exactly vesting duration"
        );

        // Verify delayed claim state is cleared
        userInfo = vestingStrategy.getUserVestingInfo(claimer1);
        assertFalse(userInfo.isDelayedClaim, "Should not be marked as delayed claim");
        assertEq(userInfo.delayedAmount, 0, "Delayed amount should be cleared");
        assertEq(userInfo.delayStartTime, 0, "Delay start time should be cleared");
    }

    // function test_should_revert_when_claiming_multiple_times_within_same_day() public {
    //     (bytes32 merkleRoot, bytes32[] memory merkleProof) = _claimerDetails();

    //     vm.startPrank(deployer);
    //     mockERC20Token.approve(address(vestingStrategy), CLAIM_AMOUNT);
    //     vestingStrategy.updateMerkleRoot(strategyId, merkleRoot);
    //     vm.stopPrank();

    //     vm.startPrank(claimer1);

    //     // Get strategy for timing calculations
    //     VestingStrategy.Strategy memory strategy = vestingStrategy.getStrategy(strategyId);

    //     // Move past cliff period
    //     vm.warp(strategy.startTime + strategy.cliffDuration + 1 days);

    //     // First claim should succeed
    //     vestingStrategy.claim(strategyId, CLAIM_AMOUNT, merkleProof);
    //     uint256 firstClaimTime = block.timestamp;

    //     // Try to claim again immediately - should revert
    //     vm.expectRevert(VestingStrategy.NoTokensToClaim.selector);
    //     vestingStrategy.claim(strategyId, CLAIM_AMOUNT, merkleProof);

    //     // Try to claim after 12 hours - should still revert
    //     vm.warp(firstClaimTime + 12 hours);
    //     vm.expectRevert(VestingStrategy.NoTokensToClaim.selector);
    //     vestingStrategy.claim(strategyId, CLAIM_AMOUNT, merkleProof);

    //     // Try to claim after 23 hours - should still revert
    //     vm.warp(firstClaimTime + 23 hours);
    //     vm.expectRevert(VestingStrategy.NoTokensToClaim.selector);
    //     vestingStrategy.claim(strategyId, CLAIM_AMOUNT, merkleProof);

    //     // Try to claim after 23 hours and 59 minutes - should still revert
    //     vm.warp(firstClaimTime + 23 hours + 59 minutes);
    //     vm.expectRevert(VestingStrategy.NoTokensToClaim.selector);
    //     vestingStrategy.claim(strategyId, CLAIM_AMOUNT, merkleProof);

    //     // Try to claim at 23 hours and 59 minutes and 59 seconds - should still revert
    //     vm.warp(firstClaimTime + 23 hours + 59 minutes + 59 seconds);
    //     vm.expectRevert(VestingStrategy.NoTokensToClaim.selector);
    //     vestingStrategy.claim(strategyId, CLAIM_AMOUNT, merkleProof);

    //     // Move past 24 hours
    //     vm.warp(firstClaimTime + 1 days + 1);

    //     // Now claim should succeed
    //     uint256 preBalance = mockERC20Token.balanceOf(claimer1);
    //     vestingStrategy.claim(strategyId, CLAIM_AMOUNT, merkleProof);
    //     uint256 postBalance = mockERC20Token.balanceOf(claimer1);

    //     // Verify tokens were claimed
    //     assertTrue(postBalance > preBalance, "Should be able to claim after 24 hours");

    //     // Verify last claim time was updated
    //     VestingStrategy.UserVesting memory userInfo = vestingStrategy.getUserVestingInfo(claimer1);
    //     assertEq(userInfo.lastClaimTime, block.timestamp, "Last claim time should be updated");
    // }

    function test_should_transfer_tokens_directly_from_token_contract() public {
        (bytes32 merkleRoot, bytes32[] memory merkleProof) = _claimerDetails();

        vm.startPrank(deployer);
        vestingStrategy.updateMerkleRoot(strategyId, merkleRoot);
        vm.stopPrank();

        vm.startPrank(claimer1);

        // Get strategy for timing calculations
        VestingStrategy.Strategy memory strategy = vestingStrategy.getStrategy(strategyId);

        // Move past cliff period
        vm.warp(strategy.startTime + strategy.cliffDuration + 1 days);

        // Record initial balances
        uint256 initialTokenContractBalance = mockERC20Token.balanceOf(address(mockERC20Token));
        uint256 initialUserBalance = mockERC20Token.balanceOf(claimer1);

        // Calculate expected claimable amount
        uint256 expectedClaimable = vestingStrategy.getClaimableAmount(
            claimer1,
            strategyId,
            CLAIM_AMOUNT
        );

        // Claim tokens
        vestingStrategy.claim(strategyId, CLAIM_AMOUNT, merkleProof);

        // Verify final balances
        uint256 finalTokenContractBalance = mockERC20Token.balanceOf(address(mockERC20Token));
        uint256 finalUserBalance = mockERC20Token.balanceOf(claimer1);

        // Verify token contract transferred exactly the claimable amount
        assertEq(
            initialTokenContractBalance - finalTokenContractBalance,
            expectedClaimable,
            "Token contract should transfer exactly the claimable amount"
        );

        // Verify user received exactly the claimable amount
        assertEq(
            finalUserBalance - initialUserBalance,
            expectedClaimable,
            "User should receive exactly the claimable amount"
        );

        // Verify token contract has approved the vesting contract
        assertEq(
            mockERC20Token.allowance(address(mockERC20Token), address(vestingStrategy)),
            type(uint256).max,
            "Token contract should have max approval for vesting contract"
        );
    }

    function test_should_revert_when_token_contract_has_insufficient_approval() public {
        (bytes32 merkleRoot, bytes32[] memory merkleProof) = _claimerDetails();

        vm.startPrank(deployer);
        vestingStrategy.updateMerkleRoot(strategyId, merkleRoot);
        vm.stopPrank();

        // Clear token contract's max approval and set insufficient approval
        vm.startPrank(address(mockERC20Token));
      
        // Then approve a very small amount (1% of CLAIM_AMOUNT)
        mockERC20Token.approve(address(vestingStrategy), CLAIM_AMOUNT / 100); // Only approve 1% of what's needed
        vm.stopPrank();

        vm.startPrank(claimer1);

        // Get strategy for timing calculations
        VestingStrategy.Strategy memory strategy = vestingStrategy.getStrategy(strategyId);

        // Move past cliff period
        vm.warp(strategy.startTime + strategy.vestingDuration + 1 days);

        // Calculate expected claimable amount
        uint256 expectedClaimable = vestingStrategy.getClaimableAmount(
            claimer1,
            strategyId,
            CLAIM_AMOUNT
        );

        // Verify approval is insufficient
        uint256 approval = mockERC20Token.allowance(address(mockERC20Token), address(vestingStrategy));
        assertTrue(approval < expectedClaimable, "Approval should be insufficient");

        // Claim should revert due to insufficient approval
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(vestingStrategy), approval, expectedClaimable));
        vestingStrategy.claim(strategyId, CLAIM_AMOUNT, merkleProof);

        // Verify no tokens were transferred
        assertEq(
            mockERC20Token.balanceOf(claimer1),
            0,
            "User should not receive any tokens"
        );

        // Verify vesting info is unchanged
        VestingStrategy.UserVesting memory userInfo = vestingStrategy.getUserVestingInfo(claimer1);
        assertEq(userInfo.claimedAmount, 0, "Claimed amount should not be updated");
        assertEq(userInfo.lastClaimTime, 0, "Last claim time should not be updated");
    }
}
