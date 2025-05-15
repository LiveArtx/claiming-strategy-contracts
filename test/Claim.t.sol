// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ContractUnderTest} from "./ContractUnderTest.sol";
import {VestingStrategy} from "src/VestingStrategy.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {FixedPointMathLib} from "src/libraries/FixedPointMathLib.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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

    function test_should_claim_initial_cliff_amount_and_update_vesting_info() public {
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

    function test_should_claim_linear_vesting_amounts_daily_after_cliff() public {
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

    function test_should_vest_correctly_daily_over_entire_vesting_period_after_cliff() public {
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

    function test_should_vest_correctly_in_10_day_intervals_over_entire_period()
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

    function test_should_claim_remaining_amount_at_vesting_period_end() public {
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

    function test_should_handle_claims_at_cliff_end_and_vesting_end_boundaries() public {
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

    function test_should_revert_when_attempting_to_claim_again_within_24h_during_cliff() public {
        (bytes32 merkleRoot, bytes32[] memory merkleProof) = _claimerDetails();

        vm.startPrank(deployer);
        mockERC20Token.approve(address(vestingStrategy), CLAIM_AMOUNT);
        vestingStrategy.updateMerkleRoot(strategyId, merkleRoot);
        vm.stopPrank();

        // Get strategy for calculations
        VestingStrategy.Strategy memory strategy = vestingStrategy.getStrategy(strategyId);

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

    function test_should_transfer_tokens_from_token_contract_to_user() public {
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

    function test_should_revert_when_token_contract_has_insufficient_allowance() public {
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

    function test_should_revert_when_merkle_proof_is_invalid() public {
        (bytes32 merkleRoot, bytes32[] memory merkleProof) = _claimerDetails();

        vm.startPrank(deployer);
        mockERC20Token.approve(address(vestingStrategy), CLAIM_AMOUNT);
        vestingStrategy.updateMerkleRoot(strategyId, merkleRoot);
        vm.stopPrank();

        vm.startPrank(claimer1);

        // Modify the merkle proof to make it invalid
        merkleProof[0] = bytes32(uint256(2)); // Change first proof element

        vm.expectRevert(VestingStrategy.InvalidMerkleProof.selector);
        vestingStrategy.claim(strategyId, CLAIM_AMOUNT, merkleProof);
    }

    function test_should_revert_when_user_attempts_to_join_different_strategy() public {
        // Create a second strategy
        vm.startPrank(deployer);
        vestingStrategy.createStrategy(
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            VESTING_DURATION,
            block.timestamp + EXPIRY_DATE,
            bytes32(uint256(2)), // Different merkle root
            CLAIM_WITH_DELAY
        );
        uint256 strategyId2 = 2;

        // Setup first strategy
        (bytes32 merkleRoot1, bytes32[] memory merkleProof1) = _claimerDetails();
        mockERC20Token.approve(address(vestingStrategy), CLAIM_AMOUNT * 2);
        vestingStrategy.updateMerkleRoot(strategyId, merkleRoot1);
        vestingStrategy.updateMerkleRoot(strategyId2, merkleRoot1);
        vm.stopPrank();

        vm.startPrank(claimer1);

        // Claim from first strategy
        vestingStrategy.claim(strategyId, CLAIM_AMOUNT, merkleProof1);

        // Attempt to claim from second strategy
        vm.expectRevert(VestingStrategy.UserAlreadyInStrategy.selector);
        vestingStrategy.claim(strategyId2, CLAIM_AMOUNT, merkleProof1);
    }

    function test_should_handle_complete_delayed_claim_lifecycle() public {
        // Create a strategy with claimWithDelay
        vm.startPrank(deployer);
        vestingStrategy.createStrategy(
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            VESTING_DURATION,
            block.timestamp + EXPIRY_DATE,
            MERKLE_ROOT,
            true // Enable claimWithDelay
        );
        uint256 delayedStrategyId = 2;

        (bytes32 merkleRoot, bytes32[] memory merkleProof) = _claimerDetails();
        // Approve vesting contract to spend tokens from token contract
        vm.startPrank(address(mockERC20Token));
        mockERC20Token.approve(address(vestingStrategy), type(uint256).max);
        mockERC20Token.mint(address(mockERC20Token), CLAIM_AMOUNT);
        vm.stopPrank();

        vm.startPrank(deployer);
        vestingStrategy.updateMerkleRoot(delayedStrategyId, merkleRoot);
        vm.stopPrank();

        vm.startPrank(claimer1);

        // Get strategy for timing calculations
        VestingStrategy.Strategy memory strategy = vestingStrategy.getStrategy(delayedStrategyId);

        // Move past vesting period
        vm.warp(strategy.startTime + strategy.vestingDuration + 1);

        // Initial claim should set up delayed claim
        vestingStrategy.claim(delayedStrategyId, CLAIM_AMOUNT, merkleProof);

        // Verify delayed claim setup
        VestingStrategy.UserVesting memory userInfo = vestingStrategy.getUserVestingInfo(claimer1);
        assertTrue(userInfo.isDelayedClaim, "Should have delayed claim set up");
        assertEq(userInfo.delayedAmount, CLAIM_AMOUNT, "Should have full amount delayed");

        // Attempt to release before delay period ends
        vm.expectRevert(VestingStrategy.ClaimNotAllowed.selector);
        vestingStrategy.claim(delayedStrategyId, CLAIM_AMOUNT, merkleProof);

        // Move past delay period
        vm.warp(userInfo.delayStartTime + strategy.vestingDuration + 1);

        // Release delayed claim
        vestingStrategy.claim(delayedStrategyId, CLAIM_AMOUNT, merkleProof);

        // Verify tokens were released
        assertEq(mockERC20Token.balanceOf(claimer1), CLAIM_AMOUNT, "Should receive full amount");
        userInfo = vestingStrategy.getUserVestingInfo(claimer1);
        assertFalse(userInfo.isDelayedClaim, "Delayed claim should be cleared");
        assertEq(userInfo.delayedAmount, 0, "Delayed amount should be cleared");
    }

    function test_should_revert_when_attempting_to_claim_again_within_24h_during_vesting() public {
        (bytes32 merkleRoot, bytes32[] memory merkleProof) = _claimerDetails();

        vm.startPrank(deployer);
        mockERC20Token.approve(address(vestingStrategy), CLAIM_AMOUNT);
        vestingStrategy.updateMerkleRoot(strategyId, merkleRoot);
        vm.stopPrank();

        vm.startPrank(claimer1);

        // Get strategy for timing calculations
        VestingStrategy.Strategy memory strategy = vestingStrategy.getStrategy(strategyId);

        // Move past cliff period
        vm.warp(strategy.startTime + strategy.cliffDuration + 1);

        // First claim
        vestingStrategy.claim(strategyId, CLAIM_AMOUNT, merkleProof);

        // Attempt to claim again before 24 hours
        vm.warp(block.timestamp + 23 hours);
        vm.expectRevert(VestingStrategy.NoTokensToClaim.selector);
        vestingStrategy.claim(strategyId, CLAIM_AMOUNT, merkleProof);
    }

    function test_should_handle_delayed_claims_with_expiry_date() public {
        // Create a strategy with delayed claims and short expiry
        vm.startPrank(deployer);
        // Set expiry to be after vesting duration but not too far
        uint256 shortExpiry = block.timestamp + VESTING_DURATION + 30 days; // Ensure expiry is after vesting
        vestingStrategy.createStrategy(
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            VESTING_DURATION, // 180 days vesting
            shortExpiry,
            MERKLE_ROOT,
            true // Enable delayed claims
        );
        uint256 delayedExpiryStrategyId = 2;

        (bytes32 merkleRoot, bytes32[] memory merkleProof) = _claimerDetails();
        vm.startPrank(address(mockERC20Token));
        mockERC20Token.approve(address(vestingStrategy), type(uint256).max);
        mockERC20Token.mint(address(mockERC20Token), CLAIM_AMOUNT);
        vm.stopPrank();

        vm.startPrank(deployer);
        vestingStrategy.updateMerkleRoot(delayedExpiryStrategyId, merkleRoot);
        vm.stopPrank();

        vm.startPrank(claimer1);

        // Get strategy for timing calculations
        VestingStrategy.Strategy memory strategy = vestingStrategy.getStrategy(delayedExpiryStrategyId);

        // Move past vesting period but before expiry
        vm.warp(strategy.startTime + strategy.vestingDuration + 1);
        assertTrue(block.timestamp < strategy.expiryDate, "Should be before expiry date");

        // Initial claim should set up delayed claim
        vestingStrategy.claim(delayedExpiryStrategyId, CLAIM_AMOUNT, merkleProof);

        // Verify delayed claim setup
        VestingStrategy.UserVesting memory userInfo = vestingStrategy.getUserVestingInfo(claimer1);
        assertTrue(userInfo.isDelayedClaim, "Should have delayed claim set up");
        assertEq(userInfo.delayedAmount, CLAIM_AMOUNT, "Should have full amount delayed");

        // Move past expiry date
        vm.warp(strategy.expiryDate + 1);
        assertTrue(block.timestamp > strategy.expiryDate, "Should be past expiry date");

        // Should be able to release delayed claim after expiry
        vestingStrategy.claim(delayedExpiryStrategyId, CLAIM_AMOUNT, merkleProof);

        // Verify tokens were released
        assertEq(mockERC20Token.balanceOf(claimer1), CLAIM_AMOUNT, "Should receive full amount after expiry");
        userInfo = vestingStrategy.getUserVestingInfo(claimer1);
        assertFalse(userInfo.isDelayedClaim, "Delayed claim should be cleared");
        assertEq(userInfo.delayedAmount, 0, "Delayed amount should be cleared");

        // Reset state for second test case
        vm.stopPrank();
        vm.startPrank(deployer);
        // Reset user's vesting info
        VestingStrategy.UserVesting memory emptyInfo = VestingStrategy.UserVesting({
            strategyId: 0,
            claimedAmount: 0,
            lastClaimTime: 0,
            cliffClaimed: false,
            delayedAmount: 0,
            delayStartTime: 0,
            isDelayedClaim: false
        });
        vestingStrategy.setUserVestingInfo(claimer1, emptyInfo);
        
        // Use a new expiry date that's in the future relative to current time
        uint256 newExpiry = block.timestamp + VESTING_DURATION + 30 days;
        vestingStrategy.createStrategy(
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            VESTING_DURATION,
            newExpiry,
            MERKLE_ROOT,
            true
        );
        uint256 delayedExpiryStrategyId2 = 3;
        vestingStrategy.updateMerkleRoot(delayedExpiryStrategyId2, merkleRoot);
        vm.stopPrank();

        vm.startPrank(claimer1);

        // Get strategy for timing calculations
        strategy = vestingStrategy.getStrategy(delayedExpiryStrategyId2);

        // Move to before expiry but after vesting start
        vm.warp(strategy.startTime + 1);
        assertTrue(block.timestamp < strategy.expiryDate, "Should be before expiry date");

        // Should be able to set up delayed claim before expiry
        vestingStrategy.claim(delayedExpiryStrategyId2, CLAIM_AMOUNT, merkleProof);

        // Verify delayed claim setup
        userInfo = vestingStrategy.getUserVestingInfo(claimer1);
        assertTrue(userInfo.isDelayedClaim, "Should have delayed claim set up");
        assertEq(userInfo.delayedAmount, CLAIM_AMOUNT, "Should have full amount delayed");

        // Move past expiry date
        vm.warp(strategy.expiryDate + 1);
        assertTrue(block.timestamp > strategy.expiryDate, "Should be past expiry date");

        // Should be able to release delayed claim after expiry
        vestingStrategy.claim(delayedExpiryStrategyId2, CLAIM_AMOUNT, merkleProof);

        // Verify tokens were released
        assertEq(mockERC20Token.balanceOf(claimer1), CLAIM_AMOUNT * 2, "Should receive full amount after expiry");
        userInfo = vestingStrategy.getUserVestingInfo(claimer1);
        assertFalse(userInfo.isDelayedClaim, "Delayed claim should be cleared");
        assertEq(userInfo.delayedAmount, 0, "Delayed amount should be cleared");
    }
}
