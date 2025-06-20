// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ContractUnderTest} from "./ContractUnderTest.sol";
import {VestingStrategy} from "src/VestingStrategy.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {FixedPointMathLib} from "src/libraries/FixedPointMathLib.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Merkle} from "murky/src/Merkle.sol";
import "forge-std/console.sol";

using FixedPointMathLib for uint256;

// Test reentrancy protection by creating a malicious contract
contract MaliciousClaimer {
    VestingStrategy public vestingStrategy;
    uint256 public strategyId;
    uint256 public amount;
    bytes32[] public merkleProof;

    constructor(address _vestingStrategy, uint256 _strategyId, uint256 _amount, bytes32[] memory _merkleProof) {
        vestingStrategy = VestingStrategy(_vestingStrategy);
        strategyId = _strategyId;
        amount = _amount;
        merkleProof = _merkleProof;
    }

    function attack() external {
        vestingStrategy.claim(strategyId, amount, merkleProof);
    }

    // This will be called by the vesting contract during transfer
    function onERC20Received(address, uint256, bytes calldata) external returns (bytes4) {
        // Try to reenter
        vestingStrategy.claim(strategyId, amount, merkleProof);
        return this.onERC20Received.selector;
    }
}

contract VestingStrategy_Claim_Test is ContractUnderTest {
    // Strategy parameters for testing
    uint256 constant CLIFF_DURATION = 7 days;
    uint256 constant CLIFF_PERCENTAGE = 2000; // 20%
    uint256 constant VESTING_DURATION = 180 days;
    uint256 constant EXPIRY_DATE = 365 days;
    uint256 constant BASIS_POINTS = 10000; // 100%
    bytes32 constant MERKLE_ROOT = bytes32(uint256(1));
    bool constant CLAIM_WITH_DELAY = false;
    uint256 private strategyId; // Add this to track the strategy ID

    // Allowlist data
    struct AllowlistEntry {
        address account;
        uint256 amount; // Amount in wei
    }

    AllowlistEntry[] private allowlist;
    bytes32 private merkleRoot;
    mapping(address => bytes32[]) private merkleProofs;
    Merkle private merkle;

    // Add strategy variable at class level
    VestingStrategy.Strategy private strategy;

    function setUp() public override {
        super.setUp();
        
        // Initialize Murky
        merkle = new Merkle();
        
        // Create standard strategy (no reward)
        vm.startPrank(deployer);
        vestingStrategy.createStrategy(
            block.timestamp,
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            VESTING_DURATION,
            block.timestamp + EXPIRY_DATE,
            MERKLE_ROOT,
            CLAIM_WITH_DELAY,
            0 // No reward
        );
        strategyId = 1;

        // Initialize allowlist with amounts in wei
        allowlist = new AllowlistEntry[](32);
        allowlist[0] = AllowlistEntry(0xA3AE55a26F825778d4F1F5118d9FAfE94044cbcD, 500000 * 1e18);
        allowlist[1] = AllowlistEntry(0x90D81498270e6AeC61d47334f247004Dcb084592, 500000 * 1e18);
        allowlist[2] = AllowlistEntry(0x495D4E2b3C7028Aa592cD2f6781b008dA60c1a07, 100500 * 1e18);
        allowlist[3] = AllowlistEntry(0x6c4d2093eE854Ed4F437Af0841c3CCc1BA29C6a3, 500000 * 1e18);
        allowlist[4] = AllowlistEntry(0xb7DDD470426ddfF5D2c5e28e18B16CFF29AD1C53, 600000 * 1e18);
        allowlist[5] = AllowlistEntry(0x8dac4f0cee9b4Ffea9A2EAcC70aB1b0E3cE30501, 500000 * 1e18);
        allowlist[6] = AllowlistEntry(0xAbc997662A1A4D0599C5837A138cC239f25C28ae, 500000 * 1e18);
        allowlist[7] = AllowlistEntry(0xcb908079C11AA5b3b8c2Bae48ffF2a1af9eEb4de, 500000 * 1e18);
        allowlist[8] = AllowlistEntry(0xf90Ed810D103F583C53b5eBdaCA3eE631C108cf2, 500000 * 1e18);
        allowlist[9] = AllowlistEntry(0x50787A8689909EbBD8f17dbB83cBF264AA7c4821, 500000 * 1e18);
        allowlist[10] = AllowlistEntry(0x2787BA59d11E7524dE94F4Eda44C5b08A78803B0, 500000 * 1e18);
        allowlist[11] = AllowlistEntry(0x97DDc69e15E204Dd041304b06E90Fb0DCDdb27Ef, 500000 * 1e18);
        allowlist[12] = AllowlistEntry(0xb934814e6F6fc7f5Aa0ED69b78916e42F631A9A2, 500000 * 1e18);
        allowlist[13] = AllowlistEntry(0x00bF12BAAf90E4a989cD1F0753800fB025131564, 500000 * 1e18);
        allowlist[14] = AllowlistEntry(0x69B1528307B95A7DF7ac34C7b305a55B3f3Aa29b, 500000 * 1e18);
        allowlist[15] = AllowlistEntry(0xfF3046B569217A9D32b736E72Bca13250b3bD8b4, 500000 * 1e18);
        allowlist[16] = AllowlistEntry(0xB2B5C087F7e4d40BfA254D77B34451A52fcD7E35, 500000 * 1e18);
        allowlist[17] = AllowlistEntry(0x5890E7020Ef8b7D05A9d7EF4AAaE2C7a4277E0c0, 500000 * 1e18);
        allowlist[18] = AllowlistEntry(0xbcE61ff613e0DFCB3a5a30A36237Df9CB3872E6F, 500000 * 1e18);
        allowlist[19] = AllowlistEntry(claimer1, CLAIM_AMOUNT);
        allowlist[20] = AllowlistEntry(0x702E5a03B3d7625ae99f7067d157D06Ad224fa91, 500000 * 1e18);
        allowlist[21] = AllowlistEntry(0x1ed3a8768624ae6d7BfF537775F2EF5BDA846928, 500000 * 1e18);
        allowlist[22] = AllowlistEntry(0x7dB62c7FE2fEf297bBfa76e54C49C7Ce7870bCa6, 500000 * 1e18);
        allowlist[23] = AllowlistEntry(0xEDc2081b451c1aF0754F06fdDC7267773f4936D6, 500000 * 1e18);
        allowlist[24] = AllowlistEntry(0x5b6AcCE8B882493b2b7CA6acCF53745c4dF1e283, 500000 * 1e18);
        allowlist[25] = AllowlistEntry(0x03f48714E86be629a8A76d04178D438465912399, 500000 * 1e18);
        allowlist[26] = AllowlistEntry(0xaa862C6bd08B27361E0cd952F292Cd8acae246bb, 510000 * 1e18);
        allowlist[27] = AllowlistEntry(0xa040D46c4237f99fe05aa38035889A612C8417a7, 500000 * 1e18);
        allowlist[28] = AllowlistEntry(0x202ef3Abd8402C72D74f4354c54f9E72F4fB0049, 500000 * 1e18);
        allowlist[29] = AllowlistEntry(0x6234937A4b3db79CfA13A36d0a40b4E398e289b8, 500000 * 1e18);
        allowlist[30] = AllowlistEntry(0xCf17635F4d5F51841C98f04c1c54532D974E19A0, 500000 * 1e18);

        // Build merkle tree using Murky
        bytes32[] memory leaves = new bytes32[](allowlist.length);
        for (uint256 i = 0; i < allowlist.length; i++) {
            leaves[i] = keccak256(abi.encodePacked(allowlist[i].account, allowlist[i].amount));
        }
        merkleRoot = merkle.getRoot(leaves);

        // Generate proofs for each address using Murky
        for (uint256 i = 0; i < allowlist.length; i++) {
            console.log("");
            console.log(allowlist[i].account);
            bytes32[] memory proof = merkle.getProof(leaves, i);
            for (uint256 j = 0; j < proof.length; j++) {
                console.logBytes32(proof[j]);
            }
            console.log("");

            merkleProofs[allowlist[i].account] = proof;
        }

        // Mint tokens to token approver and approve vesting contract
        mockERC20Token.mint(tokenApprover, CLAIM_AMOUNT * 100); // Mint enough for all claims
        vm.startPrank(tokenApprover);
        mockERC20Token.approve(address(vestingStrategy), type(uint256).max);
        vm.stopPrank();
    }

    function _getClaimerDetails(address claimer) internal view returns (bytes32, bytes32[] memory) {
        // Remove unused variable warning by not creating the leaf variable
        return (merkleRoot, merkleProofs[claimer]);
    }

    // Override parent's _claimerDetails to use our own merkle tree
    function _claimerDetails() internal view returns (bytes32, bytes32[] memory) {
        return _getClaimerDetails(claimer1);
    }

    // Helper function to get allocation for an address
    function _getAllocation(address account) internal view returns (uint256) {
        for (uint256 i = 0; i < allowlist.length; i++) {
            if (allowlist[i].account == account) {
                return allowlist[i].amount;
            }
        }
        return 0;
    }

    function test_should_claim_initial_cliff_amount_and_update_vesting_info() public {
        (bytes32 root, bytes32[] memory merkleProof) = _claimerDetails();

        console.log("address", claimer1);
        console.log("allocation", _getAllocation(claimer1));
        console.logBytes32(root);
        console.log("Merkle proof length", merkleProof.length);
        for (uint256 i = 0; i < merkleProof.length; i++) {
            console.logBytes32(merkleProof[i]);
        }

        vm.startPrank(deployer);
        vestingStrategy.updateMerkleRoot(strategyId, root);
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
        (bytes32 root, bytes32[] memory merkleProof) = _claimerDetails();

        vm.startPrank(deployer);
        vestingStrategy.updateMerkleRoot(strategyId, root);
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
        (bytes32 root, bytes32[] memory merkleProof) = _claimerDetails();

        vm.startPrank(deployer);
        vestingStrategy.updateMerkleRoot(strategyId, root);
        vm.stopPrank();

        vm.startPrank(claimer1);

        // Get strategy for calculations - rename to avoid shadowing
        VestingStrategy.Strategy memory currentStrategy = vestingStrategy.getStrategy(strategyId);

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
        vm.warp(currentStrategy.startTime + currentStrategy.cliffDuration + 1);
        lastClaimTime = block.timestamp;

        // Calculate total days in vesting period after cliff
        uint256 vestingDaysAfterCliff = (currentStrategy.vestingDuration - currentStrategy.cliffDuration) / SECONDS_PER_DAY;

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
            console.log("Time since start", block.timestamp - currentStrategy.startTime);
            console.log("Time since cliff", block.timestamp - (currentStrategy.startTime + currentStrategy.cliffDuration));
        }

        // Move to end of vesting period
        vm.warp(currentStrategy.startTime + currentStrategy.vestingDuration + 1);

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
        (bytes32 root, bytes32[] memory merkleProof) = _claimerDetails();

        vm.startPrank(deployer);
        vestingStrategy.updateMerkleRoot(strategyId, root);
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
        VestingStrategy.Strategy memory currentStrategy = vestingStrategy.getStrategy(
            strategyId
        );

        uint256 totalClaimed = cliffAmount;
        uint256 lastClaimTime = block.timestamp;
        uint256 SECONDS_PER_DAY = 1 days;
        uint256 totalDays = currentStrategy.vestingDuration / SECONDS_PER_DAY;
        uint256 increment = 10;

        // Skip cliff period
        vm.warp(block.timestamp + currentStrategy.cliffDuration);
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
        (bytes32 root, bytes32[] memory merkleProof) = _claimerDetails();

        vm.startPrank(deployer);
        vestingStrategy.updateMerkleRoot(strategyId, root);
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
        VestingStrategy.Strategy memory currentStrategy = vestingStrategy.getStrategy(
            strategyId
        );

        // Move to after vesting period ends
        vm.warp(currentStrategy.startTime + currentStrategy.vestingDuration + 1 days);

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
        (bytes32 root, bytes32[] memory merkleProof) = _claimerDetails();

        vm.startPrank(deployer);
        vestingStrategy.updateMerkleRoot(strategyId, root);
        vm.stopPrank();

        vm.startPrank(claimer1);

        // Get strategy for calculations
        VestingStrategy.Strategy memory currentStrategy = vestingStrategy.getStrategy(
            strategyId
        );

        // Test claim exactly at cliff end
        vm.warp(currentStrategy.startTime + currentStrategy.cliffDuration);
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
        vm.warp(currentStrategy.startTime + currentStrategy.vestingDuration - 1);
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
        (bytes32 root, bytes32[] memory merkleProof) = _claimerDetails();

        vm.startPrank(deployer);
        vestingStrategy.updateMerkleRoot(strategyId, root);
        vm.stopPrank();

        // Get strategy for calculations
        VestingStrategy.Strategy memory currentStrategy = vestingStrategy.getStrategy(strategyId);

        // Warp to 10 minutes after strategy start
        vm.warp(currentStrategy.startTime + 10 minutes);

        vm.startPrank(claimer1);

        // First claim at cliff
        vestingStrategy.claim(strategyId, CLAIM_AMOUNT, merkleProof);

        // Warp to 10 minutes after first claim
        vm.warp(currentStrategy.startTime + 10 minutes);

        // Attempt to claim again immediately
        vm.expectRevert(VestingStrategy.NoTokensToClaim.selector);
        vestingStrategy.claim(strategyId, CLAIM_AMOUNT, merkleProof);
    }

    function test_should_transfer_tokens_from_token_contract_to_user() public {
        (bytes32 root, bytes32[] memory merkleProof) = _claimerDetails();

        vm.startPrank(deployer);
        vestingStrategy.updateMerkleRoot(strategyId, root);
        vm.stopPrank();

        vm.startPrank(claimer1);

        // Get strategy for timing calculations
        VestingStrategy.Strategy memory currentStrategy = vestingStrategy.getStrategy(strategyId);

        // Move past cliff period
        vm.warp(currentStrategy.startTime + currentStrategy.cliffDuration + 1 days);

        // Record initial balances
        uint256 initialTokenApproverBalance = mockERC20Token.balanceOf(tokenApprover);
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
        uint256 finalTokenApproverBalance = mockERC20Token.balanceOf(tokenApprover);
        uint256 finalUserBalance = mockERC20Token.balanceOf(claimer1);

        // Verify token approver transferred exactly the claimable amount
        assertEq(
            initialTokenApproverBalance - finalTokenApproverBalance,
            expectedClaimable,
            "Token approver should transfer exactly the claimable amount"
        );

        // Verify user received exactly the claimable amount
        assertEq(
            finalUserBalance - initialUserBalance,
            expectedClaimable,
            "User should receive exactly the claimable amount"
        );

        // Verify token approver has approved the vesting contract
        assertEq(
            mockERC20Token.allowance(tokenApprover, address(vestingStrategy)),
            type(uint256).max,
            "Token approver should have max approval for vesting contract"
        );
    }

    function test_should_revert_when_token_contract_has_insufficient_allowance() public {
        (bytes32 root, bytes32[] memory merkleProof) = _claimerDetails();

        vm.startPrank(deployer);
        vestingStrategy.updateMerkleRoot(strategyId, root);
        vm.stopPrank();

        // Clear token approver's max approval and set insufficient approval
        vm.startPrank(tokenApprover);
        mockERC20Token.approve(address(vestingStrategy), 0); // Clear approval
        mockERC20Token.approve(address(vestingStrategy), CLAIM_AMOUNT / 100); // Only approve 1% of what's needed
        vm.stopPrank();

        vm.startPrank(claimer1);

        // Get strategy for timing calculations
        VestingStrategy.Strategy memory currentStrategy = vestingStrategy.getStrategy(strategyId);

        // Move past cliff period
        vm.warp(currentStrategy.startTime + currentStrategy.vestingDuration + 1 days);

        // Calculate expected claimable amount
        uint256 expectedClaimable = vestingStrategy.getClaimableAmount(
            claimer1,
            strategyId,
            CLAIM_AMOUNT
        );

        // Verify approval is insufficient
        uint256 approval = mockERC20Token.allowance(tokenApprover, address(vestingStrategy));
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
        (bytes32 root, bytes32[] memory merkleProof) = _claimerDetails();

        vm.startPrank(deployer);
        vestingStrategy.updateMerkleRoot(strategyId, root);
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
            block.timestamp,
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            VESTING_DURATION,
            block.timestamp + EXPIRY_DATE,
            bytes32(uint256(2)), // Different merkle root
            CLAIM_WITH_DELAY,
            0 // No reward
        );
        uint256 strategyId2 = 2;

        // Setup first strategy
        (bytes32 root1, bytes32[] memory merkleProof1) = _claimerDetails();
        mockERC20Token.approve(address(vestingStrategy), CLAIM_AMOUNT * 2);
        vestingStrategy.updateMerkleRoot(strategyId, root1);
        vestingStrategy.updateMerkleRoot(strategyId2, root1);
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
            block.timestamp,
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            VESTING_DURATION,
            block.timestamp + EXPIRY_DATE,
            MERKLE_ROOT,
            true, // Enable claimWithDelay
            0 // No reward
        );
        uint256 delayedStrategyId = 2;

        // Create a second strategy to test UserAlreadyInStrategy
        vestingStrategy.createStrategy(
            block.timestamp,
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            VESTING_DURATION,
            block.timestamp + EXPIRY_DATE,
            bytes32(uint256(2)), // Different merkle root
            true, // Enable claimWithDelay
            0 // No reward
        );
        uint256 secondStrategyId = 3;

        (bytes32 root, bytes32[] memory merkleProof) = _claimerDetails();
        // Approve vesting contract to spend tokens from token contract
        vm.startPrank(tokenApprover);
        mockERC20Token.approve(address(vestingStrategy), type(uint256).max);
        mockERC20Token.mint(tokenApprover, CLAIM_AMOUNT * 2); // Mint enough for both strategies
        vm.stopPrank();

        vm.startPrank(deployer);
        vestingStrategy.updateMerkleRoot(delayedStrategyId, root);
        vestingStrategy.updateMerkleRoot(secondStrategyId, root);
        vm.stopPrank();

        vm.startPrank(claimer1);

        // Get strategy for timing calculations
        VestingStrategy.Strategy memory currentStrategy = vestingStrategy.getStrategy(delayedStrategyId);

        // Move past vesting period
        vm.warp(currentStrategy.startTime + currentStrategy.vestingDuration + 1);

        // Initial claim should set up delayed claim
        vestingStrategy.claim(delayedStrategyId, CLAIM_AMOUNT, merkleProof);

        // Verify delayed claim setup
        VestingStrategy.UserVesting memory userInfo = vestingStrategy.getUserVestingInfo(claimer1);
        assertTrue(userInfo.isDelayedClaim, "Should have delayed claim set up");
        assertEq(userInfo.delayedAmount, CLAIM_AMOUNT, "Should have full amount delayed");

        // Attempt to release before delay period ends
        vm.expectRevert(VestingStrategy.ClaimNotAllowed.selector);
        vestingStrategy.claim(delayedStrategyId, CLAIM_AMOUNT, merkleProof);

        // Try to set up a delayed claim in a different strategy - should revert with UserAlreadyInStrategy
        vm.expectRevert(VestingStrategy.UserAlreadyInStrategy.selector);
        vestingStrategy.claim(secondStrategyId, CLAIM_AMOUNT, merkleProof);

        // Move past delay period
        vm.warp(userInfo.delayStartTime + currentStrategy.vestingDuration + 1);

        // Release delayed claim
        vestingStrategy.claim(delayedStrategyId, CLAIM_AMOUNT, merkleProof);

        // Verify tokens were released but delayed claim state remains
        assertEq(mockERC20Token.balanceOf(claimer1), CLAIM_AMOUNT, "Should receive full amount");
        userInfo = vestingStrategy.getUserVestingInfo(claimer1);
        assertFalse(userInfo.isDelayedClaim, "Delayed claim state should be reset after claiming");
        assertEq(userInfo.delayedAmount, 0, "Delayed amount should be reset after claiming");
        assertEq(userInfo.delayStartTime, 0, "Delay start time should be reset after claiming");
        assertEq(userInfo.strategyId, delayedStrategyId, "Strategy ID should remain set");
        assertEq(userInfo.claimedAmount, CLAIM_AMOUNT, "Claimed amount should be updated");

        // Try to claim again after expiry - should revert since no tokens are claimable
        vm.expectRevert(VestingStrategy.NoTokensToClaim.selector);
        vestingStrategy.claim(delayedStrategyId, CLAIM_AMOUNT, merkleProof);

        // Verify user info remains unchanged
        userInfo = vestingStrategy.getUserVestingInfo(claimer1);
        assertFalse(userInfo.isDelayedClaim, "Delayed claim state should remain reset");
        assertEq(userInfo.delayedAmount, 0, "Delayed amount should remain reset");
        assertEq(userInfo.strategyId, delayedStrategyId, "Strategy ID should remain set");
        assertEq(userInfo.claimedAmount, CLAIM_AMOUNT, "Claimed amount should remain unchanged");
    }

    function test_should_handle_delayed_claims_with_expiry_date() public {
        // Create a strategy with delayed claims and short expiry
        vm.startPrank(deployer);
       
        uint256 startTime = block.timestamp;
        uint256 shortExpiry = startTime + VESTING_DURATION + 30 days;
        vestingStrategy.createStrategy(
            startTime,
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            VESTING_DURATION, // 180 days vesting
            shortExpiry,
            MERKLE_ROOT,
            true, // Enable delayed claims
            0 // No reward
        );
        uint256 delayedExpiryStrategyId = 2;

        // Create a second strategy to test UserAlreadyInStrategy
        vestingStrategy.createStrategy(
            startTime,
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            VESTING_DURATION,
            shortExpiry,
            bytes32(uint256(2)), // Different merkle root
            true, // Enable delayed claims
            0 // No reward
        );
        uint256 secondStrategyId = 3;

        (bytes32 root, bytes32[] memory merkleProof) = _claimerDetails();
        
        // Mint additional tokens to token approver for both strategies
        vm.startPrank(tokenApprover);
        mockERC20Token.mint(tokenApprover, CLAIM_AMOUNT * 2);
        vm.stopPrank();

        vm.startPrank(deployer);
        vestingStrategy.updateMerkleRoot(delayedExpiryStrategyId, root);
        vestingStrategy.updateMerkleRoot(secondStrategyId, root);
        vm.stopPrank();

        vm.startPrank(claimer1);

        // Get strategy for timing calculations
        VestingStrategy.Strategy memory currentStrategy = vestingStrategy.getStrategy(delayedExpiryStrategyId);

        // Move past vesting period but before expiry
        vm.warp(currentStrategy.startTime + currentStrategy.vestingDuration + 1);
        assertTrue(block.timestamp < currentStrategy.expiryDate, "Should be before expiry date");

        // Initial claim should set up delayed claim
        vestingStrategy.claim(delayedExpiryStrategyId, CLAIM_AMOUNT, merkleProof);

        // Verify delayed claim setup
        VestingStrategy.UserVesting memory userInfo = vestingStrategy.getUserVestingInfo(claimer1);
        assertTrue(userInfo.isDelayedClaim, "Should have delayed claim set up");
        assertEq(userInfo.delayedAmount, CLAIM_AMOUNT, "Should have full amount delayed");

        // Try to set up a delayed claim in a different strategy - should revert with UserAlreadyInStrategy
        vm.expectRevert(VestingStrategy.UserAlreadyInStrategy.selector);
        vestingStrategy.claim(secondStrategyId, CLAIM_AMOUNT, merkleProof);

        // Try to claim again before delay period ends - should revert with ClaimNotAllowed
        vm.expectRevert(VestingStrategy.ClaimNotAllowed.selector);
        vestingStrategy.claim(delayedExpiryStrategyId, CLAIM_AMOUNT, merkleProof);

        // Move past expiry date
        vm.warp(currentStrategy.expiryDate + 1);
        assertTrue(block.timestamp > currentStrategy.expiryDate, "Should be past expiry date");

        // Should be able to release delayed claim after expiry
        vestingStrategy.claim(delayedExpiryStrategyId, CLAIM_AMOUNT, merkleProof);

        // Verify tokens were released but delayed claim state remains
        assertEq(mockERC20Token.balanceOf(claimer1), CLAIM_AMOUNT, "Should receive full amount after expiry");
        userInfo = vestingStrategy.getUserVestingInfo(claimer1);
        assertFalse(userInfo.isDelayedClaim, "Delayed claim state should be reset after claiming");
        assertEq(userInfo.delayedAmount, 0, "Delayed amount should be reset after claiming");
        assertEq(userInfo.delayStartTime, 0, "Delay start time should be reset after claiming");
        assertEq(userInfo.strategyId, delayedExpiryStrategyId, "Strategy ID should remain set");
        assertEq(userInfo.claimedAmount, CLAIM_AMOUNT, "Claimed amount should be updated");

        // Try to claim again after expiry - should revert since no tokens are claimable
        vm.expectRevert(VestingStrategy.NoTokensToClaim.selector);
        vestingStrategy.claim(delayedExpiryStrategyId, CLAIM_AMOUNT, merkleProof);

        // Verify user info remains unchanged
        userInfo = vestingStrategy.getUserVestingInfo(claimer1);
        assertFalse(userInfo.isDelayedClaim, "Delayed claim state should remain reset");
        assertEq(userInfo.delayedAmount, 0, "Delayed amount should remain reset");
        assertEq(userInfo.strategyId, delayedExpiryStrategyId, "Strategy ID should remain set");
        assertEq(userInfo.claimedAmount, CLAIM_AMOUNT, "Claimed amount should remain unchanged");
    }

    function test_should_revert_when_start_time_is_after_expiry_date() public {
        vm.startPrank(deployer);
        uint256 futureStartTime = block.timestamp + 100 days;
        uint256 pastExpiryDate = block.timestamp + 50 days; // Expiry before start time

        vm.expectRevert(VestingStrategy.InvalidStrategy.selector);
        vestingStrategy.createStrategy(
            futureStartTime,
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            VESTING_DURATION,
            pastExpiryDate,
            MERKLE_ROOT,
            CLAIM_WITH_DELAY,
            0 // No reward
        );
        vm.stopPrank();
    }

    function test_should_revert_when_vesting_period_exceeds_expiry_date() public {
        vm.startPrank(deployer);
        uint256 startTime = block.timestamp;
        uint256 shortExpiryDate = startTime + 10 days; // Expiry too soon
        uint256 longVestingDuration = 20 days; // Vesting duration longer than time until expiry

        vm.expectRevert(VestingStrategy.InvalidStrategy.selector);
        vestingStrategy.createStrategy(
            startTime,
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            longVestingDuration,
            shortExpiryDate,
            MERKLE_ROOT,
            CLAIM_WITH_DELAY,
            0 // No reward
        );
        vm.stopPrank();
    }

    function test_should_create_strategy_with_future_start_time() public {
        vm.startPrank(deployer);
        // Create a first strategy to ensure we get ID 2 for our future strategy
        vestingStrategy.createStrategy(
            block.timestamp,
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            VESTING_DURATION,
            block.timestamp + EXPIRY_DATE,
            MERKLE_ROOT,
            CLAIM_WITH_DELAY,
            0 // No reward
        );

        uint256 futureStartTime = block.timestamp + 30 days;
        uint256 futureExpiryDate = futureStartTime + EXPIRY_DATE;

        vestingStrategy.createStrategy(
            futureStartTime,
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            VESTING_DURATION,
            futureExpiryDate,
            MERKLE_ROOT,
            CLAIM_WITH_DELAY,
            0 // No reward
        );
        uint256 futureStrategyId = 3; // This will be the third strategy (ID 3)

        // Verify strategy was created with correct start time
        VestingStrategy.Strategy memory currentStrategy = vestingStrategy.getStrategy(futureStrategyId);
        assertEq(currentStrategy.startTime, futureStartTime, "Strategy should have correct start time");

        // Verify no tokens can be claimed before start time
        vm.stopPrank();
        vm.startPrank(claimer1);
        // Remove unused variables - we don't need root and merkleProof for this test
        
        // Try to claim before start time
        vm.warp(futureStartTime - 1 days);
        uint256 claimableBeforeStart = vestingStrategy.getClaimableAmount(
            claimer1,
            futureStrategyId,
            CLAIM_AMOUNT
        );
        assertEq(claimableBeforeStart, 0, "Should not be able to claim before start time");

        // Verify can claim after start time
        vm.warp(futureStartTime + 1 days);
        uint256 claimableAfterStart = vestingStrategy.getClaimableAmount(
            claimer1,
            futureStrategyId,
            CLAIM_AMOUNT
        );
        assertTrue(claimableAfterStart > 0, "Should be able to claim after start time");
        vm.stopPrank();
    }

    function test_should_revert_when_claiming_inactive_strategy() public {
        (bytes32 root, bytes32[] memory merkleProof) = _claimerDetails();

        vm.startPrank(deployer);
        vestingStrategy.updateMerkleRoot(strategyId, root);
        vestingStrategy.updateStrategyStatus(strategyId, false);
        vm.stopPrank();

        vm.startPrank(claimer1);
        vm.expectRevert(VestingStrategy.StrategyInactive.selector);
        vestingStrategy.claim(strategyId, CLAIM_AMOUNT, merkleProof);
    }

    function test_should_revert_when_claiming_zero_amount() public {
        (bytes32 root, bytes32[] memory merkleProof) = _claimerDetails();

        vm.startPrank(deployer);
        vestingStrategy.updateMerkleRoot(strategyId, root);
        vm.stopPrank();

        vm.startPrank(claimer1);
        vm.expectRevert(VestingStrategy.InvalidAmount.selector);
        vestingStrategy.claim(strategyId, 0, merkleProof);
    }

    function test_should_revert_when_claiming_nonexistent_strategy() public {
        // Only get merkleProof since root is not used
        (, bytes32[] memory merkleProof) = _claimerDetails();

        vm.startPrank(claimer1);
        vm.expectRevert(VestingStrategy.StrategyNotFound.selector);
        vestingStrategy.claim(999, CLAIM_AMOUNT, merkleProof);
    }

    function test_should_handle_delayed_claim_at_exact_expiry_time() public {
        // Create a strategy with claimWithDelay
        vm.startPrank(deployer);
        uint256 startTime = block.timestamp;
        uint256 expiryTime = startTime + EXPIRY_DATE;
        vestingStrategy.createStrategy(
            startTime,
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            VESTING_DURATION,
            expiryTime,
            MERKLE_ROOT,
            true, // Enable claimWithDelay
            0 // No reward
        );
        uint256 delayedStrategyId = 2;

        (bytes32 root, bytes32[] memory merkleProof) = _claimerDetails();
        vm.startPrank(tokenApprover);
        mockERC20Token.mint(tokenApprover, CLAIM_AMOUNT);
        vm.stopPrank();

        vm.startPrank(deployer);
        vestingStrategy.updateMerkleRoot(delayedStrategyId, root);
        vm.stopPrank();

        vm.startPrank(claimer1);

        // Get strategy for timing calculations
        VestingStrategy.Strategy memory currentStrategy = vestingStrategy.getStrategy(delayedStrategyId);

        // Move to just before vesting period ends
        vm.warp(currentStrategy.startTime + currentStrategy.vestingDuration);

        // Initial claim should set up delayed claim
        vestingStrategy.claim(delayedStrategyId, CLAIM_AMOUNT, merkleProof);

        // Verify delayed claim setup
        VestingStrategy.UserVesting memory userInfo = vestingStrategy.getUserVestingInfo(claimer1);
        assertTrue(userInfo.isDelayedClaim, "Should have delayed claim set up");
        assertEq(userInfo.delayedAmount, CLAIM_AMOUNT, "Should have full amount delayed");

        // Move to exact expiry time
        vm.warp(expiryTime);

        // Should be able to claim at exact expiry time
        vestingStrategy.claim(delayedStrategyId, CLAIM_AMOUNT, merkleProof);

        // Verify tokens were released
        assertEq(mockERC20Token.balanceOf(claimer1), CLAIM_AMOUNT, "Should receive full amount at expiry");
        userInfo = vestingStrategy.getUserVestingInfo(claimer1);
        assertFalse(userInfo.isDelayedClaim, "Delayed claim state should be reset after claiming");
        assertEq(userInfo.delayedAmount, 0, "Delayed amount should be reset after claiming");
        assertEq(userInfo.delayStartTime, 0, "Delay start time should be reset after claiming");
        assertEq(userInfo.claimedAmount, CLAIM_AMOUNT, "Claimed amount should be updated");
    }

    function test_should_apply_reward_to_vesting_calculations() public {
        vm.startPrank(deployer);
        
        // Create strategy with 50% reward and standard vesting (10% cliff, 90% linear)
        vestingStrategy.createStrategy(
            block.timestamp,
            CLIFF_DURATION,
            1000, // 10% cliff
            VESTING_DURATION,
            block.timestamp + EXPIRY_DATE,
            MERKLE_ROOT,
            false, // No delayed claims
            5000 // 50% reward
        );
        uint256 rewardStrategyId = 2;

        (bytes32 root, bytes32[] memory merkleProof) = _claimerDetails();
        vm.startPrank(tokenApprover);
        // Mint enough tokens including reward
        mockERC20Token.mint(tokenApprover, CLAIM_AMOUNT + (CLAIM_AMOUNT * 5000 / 10000));
        vm.stopPrank();

        vm.startPrank(deployer);
        vestingStrategy.updateMerkleRoot(rewardStrategyId, root);
        vm.stopPrank();

        vm.startPrank(claimer1);

        // Calculate total amount with reward
        uint256 totalWithReward = CLAIM_AMOUNT + (CLAIM_AMOUNT * 5000 / 10000); // 150% of allocation
        
        // Calculate cliff amount (10% of total with reward)
        uint256 cliffAmount = FixedPointMathLib.mulDivDown(totalWithReward, 1000, BASIS_POINTS);
        
        // Claim at cliff
        vestingStrategy.claim(rewardStrategyId, CLAIM_AMOUNT, merkleProof);
        assertEq(mockERC20Token.balanceOf(claimer1), cliffAmount, "Should receive cliff amount including reward");

        // Move past cliff period
        VestingStrategy.Strategy memory currentStrategy = vestingStrategy.getStrategy(rewardStrategyId);
        vm.warp(currentStrategy.startTime + currentStrategy.cliffDuration + 1);

        // Calculate remaining amount after cliff (90% of total with reward) using the same method as the contract
        uint256 remainingAmount = FixedPointMathLib.mulDivDown(
            totalWithReward,
            BASIS_POINTS - currentStrategy.cliffPercentage,
            BASIS_POINTS
        );
        
        // Move to middle of vesting period
        uint256 halfVestingPeriod = (currentStrategy.vestingDuration - currentStrategy.cliffDuration) / 2;
        vm.warp(currentStrategy.startTime + currentStrategy.cliffDuration + halfVestingPeriod);
        
        // Claim again
        vestingStrategy.claim(rewardStrategyId, CLAIM_AMOUNT, merkleProof);
        
        // Calculate expected vested amount at this point:
        // 1. Cliff amount (10% of total with reward)
        // 2. Half of remaining amount (45% of total with reward)
        uint256 expectedVested = cliffAmount + (remainingAmount / 2);
        
        // Get actual balance
        uint256 actualBalance = mockERC20Token.balanceOf(claimer1);
        
        // Allow for small rounding errors (1% of remaining amount)
        uint256 maxDelta = remainingAmount / 100;
        assertApproxEqAbs(
            actualBalance,
            expectedVested,
            maxDelta,
            "Should receive correct vested amount including reward"
        );

        // Move to end of vesting period
        vm.warp(currentStrategy.startTime + currentStrategy.vestingDuration + 1);
        
        // Final claim
        vestingStrategy.claim(rewardStrategyId, CLAIM_AMOUNT, merkleProof);
        assertEq(mockERC20Token.balanceOf(claimer1), totalWithReward, "Should receive full amount including reward at vesting end");
    }

    function test_should_claim_with_50_percent_reward() public {
        vm.startPrank(deployer);
        
        // Create 8 month claim with 50% reward
        vestingStrategy.createStrategy(
            block.timestamp,
            0, // No cliff
            0, // No cliff percentage
            8 * 30 days, // 8 months vesting
            block.timestamp + EXPIRY_DATE,
            MERKLE_ROOT,
            false, // Disable delayed claims for immediate vesting
            5000 // 50% reward
        );
        uint256 localStrategyId = 2;

        // Setup merkle root and mint tokens
        (bytes32 root, bytes32[] memory merkleProof) = _claimerDetails();
        vm.startPrank(tokenApprover);
        // Mint enough tokens including reward
        mockERC20Token.mint(tokenApprover, CLAIM_AMOUNT + (CLAIM_AMOUNT * 5000 / 10000));
        vm.stopPrank();

        vm.startPrank(deployer);
        vestingStrategy.updateMerkleRoot(localStrategyId, root);
        vm.stopPrank();

        vm.startPrank(claimer1);
        VestingStrategy.Strategy memory currentStrategy = vestingStrategy.getStrategy(localStrategyId);
        
        // Calculate expected amount: base + 50% reward
        uint256 expectedAmount = CLAIM_AMOUNT + (CLAIM_AMOUNT * 5000 / 10000); // 150% of allocation
        
        // Move past vesting period
        vm.warp(currentStrategy.startTime + currentStrategy.vestingDuration + 1);
        
        // Check claimable amount before claiming
        uint256 claimableAmount = vestingStrategy.getClaimableAmount(claimer1, localStrategyId, CLAIM_AMOUNT);
        assertEq(claimableAmount, expectedAmount, "Claimable amount should match expected amount");
        
        // Claim should work immediately since delayed claims are disabled
        vestingStrategy.claim(localStrategyId, CLAIM_AMOUNT, merkleProof);
        assertEq(mockERC20Token.balanceOf(claimer1), expectedAmount, "Should receive 150% of allocation for 8 month claim");
        vm.stopPrank();
    }

    function test_should_claim_with_70_percent_reward() public {
        // Reset user's vesting info
        vm.startPrank(deployer);
        vestingStrategy.setUserVestingInfo(claimer1, VestingStrategy.UserVesting({
            strategyId: 0,
            claimedAmount: 0,
            lastClaimTime: 0,
            cliffClaimed: false,
            delayedAmount: 0,
            delayStartTime: 0,
            isDelayedClaim: false
        }));
        
        // Create 10 month claim with 70% reward
        vestingStrategy.createStrategy(
            block.timestamp,
            0,
            0,
            10 * 30 days, // 10 months vesting
            block.timestamp + EXPIRY_DATE,
            MERKLE_ROOT,
            false, // Disable delayed claims for immediate vesting
            7000 // 70% reward
        );
        uint256 localStrategyId = 2;

        // Setup merkle root and mint tokens
        (bytes32 currentRoot, bytes32[] memory merkleProof) = _claimerDetails();
        vm.startPrank(tokenApprover);
        // Mint enough tokens including reward
        mockERC20Token.mint(tokenApprover, CLAIM_AMOUNT + (CLAIM_AMOUNT * 7000 / 10000));
        vm.stopPrank();

        vm.startPrank(deployer);
        vestingStrategy.updateMerkleRoot(localStrategyId, currentRoot);
        vm.stopPrank();

        vm.startPrank(claimer1);
        VestingStrategy.Strategy memory currentStrategy = vestingStrategy.getStrategy(localStrategyId);
        
        uint256 expectedAmount = CLAIM_AMOUNT + (CLAIM_AMOUNT * 7000 / 10000); // 170% of allocation
        
        // Move past vesting period
        vm.warp(currentStrategy.startTime + currentStrategy.vestingDuration + 1);
        
        // Check claimable amount before claiming
        uint256 claimableAmount = vestingStrategy.getClaimableAmount(claimer1, localStrategyId, CLAIM_AMOUNT);
        assertEq(claimableAmount, expectedAmount, "Claimable amount should match expected amount");
        
        vestingStrategy.claim(localStrategyId, CLAIM_AMOUNT, merkleProof);
        assertEq(mockERC20Token.balanceOf(claimer1), expectedAmount, "Should receive 170% of allocation for 10 month claim");
        vm.stopPrank();
    }

    function test_should_claim_with_120_percent_reward() public {
        // Reset user's vesting info
        vm.startPrank(deployer);
        vestingStrategy.setUserVestingInfo(claimer1, VestingStrategy.UserVesting({
            strategyId: 0,
            claimedAmount: 0,
            lastClaimTime: 0,
            cliffClaimed: false,
            delayedAmount: 0,
            delayStartTime: 0,
            isDelayedClaim: false
        }));
        
        // Create 12 month claim with 120% reward
        vestingStrategy.createStrategy(
            block.timestamp,
            0,
            0,
            12 * 30 days, // 12 months vesting
            block.timestamp + EXPIRY_DATE,
            MERKLE_ROOT,
            false, // Disable delayed claims for immediate vesting
            12000 // 120% reward
        );
        uint256 localStrategyId = 2;

        // Setup merkle root and mint tokens
        (bytes32 currentRoot, bytes32[] memory merkleProof) = _claimerDetails();
        vm.startPrank(tokenApprover);
        // Mint enough tokens including reward
        mockERC20Token.mint(tokenApprover, CLAIM_AMOUNT + (CLAIM_AMOUNT * 12000 / 10000));
        vm.stopPrank();

        vm.startPrank(deployer);
        vestingStrategy.updateMerkleRoot(localStrategyId, currentRoot);
        vm.stopPrank();

        vm.startPrank(claimer1);
        VestingStrategy.Strategy memory currentStrategy = vestingStrategy.getStrategy(localStrategyId);
        
        uint256 expectedAmount = CLAIM_AMOUNT + (CLAIM_AMOUNT * 12000 / 10000); // 220% of allocation
        
        // Move past vesting period
        vm.warp(currentStrategy.startTime + currentStrategy.vestingDuration + 1);
        
        // Check claimable amount before claiming
        uint256 claimableAmount = vestingStrategy.getClaimableAmount(claimer1, localStrategyId, CLAIM_AMOUNT);
        assertEq(claimableAmount, expectedAmount, "Claimable amount should match expected amount");
        
        vestingStrategy.claim(localStrategyId, CLAIM_AMOUNT, merkleProof);
        assertEq(mockERC20Token.balanceOf(claimer1), expectedAmount, "Should receive 220% of allocation for 12 month claim");
        vm.stopPrank();
    }

    function test_should_claim_with_cliff() public {
        // Create strategy with cliff
        vm.startPrank(deployer);
        vestingStrategy.createStrategy(
            block.timestamp,
            60, // 1 min cliff
            2000, // 20% cliff
            300, // 5 min vesting
            block.timestamp + 600,
            MERKLE_ROOT,
            false, // No delayed claims
            5000 // 50% reward
        );
        uint256 strategy_id = 1;

        // Setup merkle root and mint tokens
        (bytes32 root, bytes32[] memory merkleProof) = _claimerDetails();
        vm.stopPrank();

        vm.startPrank(tokenApprover);
        // Mint enough tokens including reward
        mockERC20Token.mint(tokenApprover, CLAIM_AMOUNT + (CLAIM_AMOUNT * 5000 / 10000));
        vm.stopPrank();

        vm.startPrank(deployer);
        vestingStrategy.updateMerkleRoot(strategy_id, root);
        vm.stopPrank();

        vm.startPrank(claimer1);
        VestingStrategy.Strategy memory _strategy = vestingStrategy.getStrategy(strategy_id);
        
        // Calculate cliff amount (20% of total with reward)
        uint256 rewardAmount = FixedPointMathLib.mulDivDown(CLAIM_AMOUNT, _strategy.rewardPercentage, BASIS_POINTS);
        uint256 totalWithReward = CLAIM_AMOUNT + rewardAmount;
        uint256 cliffAmount = FixedPointMathLib.mulDivDown(totalWithReward, _strategy.cliffPercentage, BASIS_POINTS);
        
        // Check claimable amount before claiming
        uint256 claimableAmount = vestingStrategy.getClaimableAmount(claimer1, strategy_id, CLAIM_AMOUNT);
        assertEq(claimableAmount, cliffAmount, "Claimable amount should match cliff amount");
        
        vestingStrategy.claim(strategy_id, CLAIM_AMOUNT, merkleProof);
        assertEq(mockERC20Token.balanceOf(claimer1), cliffAmount, "Should receive cliff amount");
        vm.stopPrank();

        // Move past cliff period and wait 24 hours for cooldown
        vm.warp(_strategy.startTime + _strategy.cliffDuration + 1 days + 1);
        
        // Get the actual claimable amount from the contract
        uint256 actualClaimable = vestingStrategy.getClaimableAmount(claimer1, strategy_id, CLAIM_AMOUNT);
        
        vm.startPrank(claimer1);
        vestingStrategy.claim(strategy_id, CLAIM_AMOUNT, merkleProof);
        assertEq(mockERC20Token.balanceOf(claimer1), cliffAmount + actualClaimable, "Should receive cliff + linear vesting amount");
        vm.stopPrank();
    }

    function test_should_claim_with_delayed_claim() public {
        vm.startPrank(deployer);
        
        // Create strategy with delayed claims
        vestingStrategy.createStrategy(
            block.timestamp,
            0, // No cliff
            0, // No cliff percentage
            60, // 1 min vesting
            block.timestamp + 300,
            MERKLE_ROOT,
            true, // Enable delayed claims
            5000 // 50% reward
        );
        uint256 localStrategyId = 2;

        // Setup merkle root and mint tokens
        (bytes32 root, bytes32[] memory merkleProof) = _claimerDetails();
        vm.startPrank(tokenApprover);
        // Mint enough tokens including reward
        mockERC20Token.mint(tokenApprover, CLAIM_AMOUNT + (CLAIM_AMOUNT * 5000 / 10000));
        vm.stopPrank();

        vm.startPrank(deployer);
        vestingStrategy.updateMerkleRoot(localStrategyId, root);
        vm.stopPrank();

        vm.startPrank(claimer1);
        VestingStrategy.Strategy memory currentStrategy = vestingStrategy.getStrategy(localStrategyId);
        
        // Calculate total amount with reward
        uint256 rewardAmount = FixedPointMathLib.mulDivDown(CLAIM_AMOUNT, currentStrategy.rewardPercentage, BASIS_POINTS);
        uint256 totalWithReward = CLAIM_AMOUNT + rewardAmount;
        
        // Initial claim should set up delayed claim
        uint256 claimableAmount = vestingStrategy.getClaimableAmount(claimer1, localStrategyId, CLAIM_AMOUNT);
        assertEq(claimableAmount, 0, "No tokens should be claimable before vesting end");
        
        vestingStrategy.claim(localStrategyId, CLAIM_AMOUNT, merkleProof);
        
        // Move past vesting period
        vm.warp(currentStrategy.startTime + currentStrategy.vestingDuration + 1);
        
        // Check claimable amount before final claim
        claimableAmount = vestingStrategy.getClaimableAmount(claimer1, localStrategyId, CLAIM_AMOUNT);
        assertEq(claimableAmount, totalWithReward, "Full amount should be claimable after vesting end");
        
        vestingStrategy.claim(localStrategyId, CLAIM_AMOUNT, merkleProof);
        assertEq(mockERC20Token.balanceOf(claimer1), totalWithReward, "Should receive full amount with reward");
        vm.stopPrank();
    }

    function test_should_prevent_multiple_delayed_claims_after_release() public {
        // Create a strategy with claimWithDelay
        vm.startPrank(deployer);
        vestingStrategy.createStrategy(
            block.timestamp,
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            VESTING_DURATION,
            block.timestamp + EXPIRY_DATE,
            MERKLE_ROOT,
            true, // Enable claimWithDelay
            0 // No reward
        );
        uint256 delayedStrategyId = 2;

        (bytes32 root, bytes32[] memory merkleProof) = _claimerDetails();
        vm.startPrank(tokenApprover);
        mockERC20Token.mint(tokenApprover, CLAIM_AMOUNT);
        vm.stopPrank();

        vm.startPrank(deployer);
        vestingStrategy.updateMerkleRoot(delayedStrategyId, root);
        vm.stopPrank();

        vm.startPrank(claimer1);

        // Get strategy for timing calculations
        VestingStrategy.Strategy memory currentStrategy = vestingStrategy.getStrategy(delayedStrategyId);

        // Move past vesting period
        vm.warp(currentStrategy.startTime + currentStrategy.vestingDuration + 1);

        // Initial claim should set up delayed claim
        vestingStrategy.claim(delayedStrategyId, CLAIM_AMOUNT, merkleProof);

        // Verify delayed claim setup
        VestingStrategy.UserVesting memory userInfo = vestingStrategy.getUserVestingInfo(claimer1);
        assertTrue(userInfo.isDelayedClaim, "Should have delayed claim set up");
        assertEq(userInfo.delayedAmount, CLAIM_AMOUNT, "Should have full amount delayed");

        // Move past delay period
        vm.warp(userInfo.delayStartTime + currentStrategy.vestingDuration + 1);

        // Release delayed claim
        vestingStrategy.claim(delayedStrategyId, CLAIM_AMOUNT, merkleProof);

        // Verify tokens were released and delayed claim state is reset
        assertEq(mockERC20Token.balanceOf(claimer1), CLAIM_AMOUNT, "Should receive full amount");
        userInfo = vestingStrategy.getUserVestingInfo(claimer1);
        assertFalse(userInfo.isDelayedClaim, "Delayed claim state should be reset after claiming");
        assertEq(userInfo.delayedAmount, 0, "Delayed amount should be reset after claiming");
        assertEq(userInfo.claimedAmount, CLAIM_AMOUNT, "Claimed amount should be updated");

        // Try to claim again - should return 0 claimable amount and not set up new delayed claim
        uint256 claimableAmount = vestingStrategy.getClaimableAmount(claimer1, delayedStrategyId, CLAIM_AMOUNT);
        assertEq(claimableAmount, 0, "Should return 0 claimable amount after delayed claim is released");

        // Attempt to claim again - should revert with NoTokensToClaim
        vm.expectRevert(VestingStrategy.NoTokensToClaim.selector);
        vestingStrategy.claim(delayedStrategyId, CLAIM_AMOUNT, merkleProof);

        // Verify user info remains unchanged
        userInfo = vestingStrategy.getUserVestingInfo(claimer1);
        assertFalse(userInfo.isDelayedClaim, "Delayed claim state should remain reset");
        assertEq(userInfo.delayedAmount, 0, "Delayed amount should remain reset");
        assertEq(userInfo.strategyId, delayedStrategyId, "Strategy ID should remain set");
        assertEq(userInfo.claimedAmount, CLAIM_AMOUNT, "Claimed amount should remain unchanged");
    }

    // ========== EXPIRY DATE FUNCTIONALITY TESTS ==========

    function test_should_prevent_new_users_from_entering_expired_strategy() public {
        // Create a strategy with short expiry
        vm.startPrank(deployer);
        uint256 startTime = block.timestamp;
        uint256 shortExpiry = startTime + 30 days; // Short expiry
        
        vestingStrategy.createStrategy(
            startTime,
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            20 days, // Shorter vesting duration to fit within expiry
            shortExpiry,
            MERKLE_ROOT,
            CLAIM_WITH_DELAY,
            0 // No reward
        );
        uint256 expiredStrategyId = 2;

        (bytes32 root, bytes32[] memory merkleProof) = _claimerDetails();
        vestingStrategy.updateMerkleRoot(expiredStrategyId, root);
        vm.stopPrank();

        // Move past expiry date
        vm.warp(shortExpiry + 1 days);
        
        // Try to claim as a new user - should revert
        vm.startPrank(claimer1);
        vm.expectRevert(VestingStrategy.StrategyExpired.selector);
        vestingStrategy.claim(expiredStrategyId, CLAIM_AMOUNT, merkleProof);
        vm.stopPrank();
    }

    function test_should_allow_existing_users_to_claim_after_expiry() public {
        // Create a strategy with short expiry
        vm.startPrank(deployer);
        uint256 startTime = block.timestamp;
        uint256 shortExpiry = startTime + 30 days; // Short expiry
        
        vestingStrategy.createStrategy(
            startTime,
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            20 days, // Shorter vesting duration to fit within expiry
            shortExpiry,
            MERKLE_ROOT,
            CLAIM_WITH_DELAY,
            0 // No reward
        );
        uint256 expiredStrategyId = 2;

        (bytes32 root, bytes32[] memory merkleProof) = _claimerDetails();
        vestingStrategy.updateMerkleRoot(expiredStrategyId, root);
        vm.stopPrank();

        // First, claimer1 claims before expiry to become an existing user
        vm.startPrank(claimer1);
        vestingStrategy.claim(expiredStrategyId, CLAIM_AMOUNT, merkleProof);
        
        // Verify user is now participating in the strategy
        VestingStrategy.UserVesting memory userInfo = vestingStrategy.getUserVestingInfo(claimer1);
        assertEq(userInfo.strategyId, expiredStrategyId, "User should be participating in strategy");
        
        // Move past expiry date
        vm.warp(shortExpiry + 1 days);
        
        // Should be able to claim after expiry as an existing user
        // This should release the delayed claim
        vestingStrategy.claim(expiredStrategyId, CLAIM_AMOUNT, merkleProof);
        
        // Verify tokens were received
        assertEq(mockERC20Token.balanceOf(claimer1), CLAIM_AMOUNT, "Should receive full amount after expiry");
        vm.stopPrank();
    }

    function test_should_allow_existing_users_to_claim_full_allocation_after_expiry() public {
        // Create a strategy with short expiry and normal vesting (no delay)
        vm.startPrank(deployer);
        uint256 startTime = block.timestamp;
        uint256 shortExpiry = startTime + 30 days; // Short expiry
        
        vestingStrategy.createStrategy(
            startTime,
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            20 days, // Shorter vesting duration to fit within expiry
            shortExpiry,
            MERKLE_ROOT,
            false, // No claimWithDelay
            0 // No reward
        );
        uint256 expiredStrategyId = 2;

        (bytes32 root, bytes32[] memory merkleProof) = _claimerDetails();
        vestingStrategy.updateMerkleRoot(expiredStrategyId, root);
        vm.stopPrank();

        // First, claimer1 claims before expiry to become an existing user
        vm.startPrank(claimer1);
        vestingStrategy.claim(expiredStrategyId, CLAIM_AMOUNT, merkleProof);
        vm.stopPrank();
        
        // Move past expiry date
        vm.warp(shortExpiry + 1 days);
        
        // claimer1 should be able to claim after expiry
        vm.startPrank(claimer1);
        vestingStrategy.claim(expiredStrategyId, CLAIM_AMOUNT, merkleProof);
        assertEq(mockERC20Token.balanceOf(claimer1), CLAIM_AMOUNT, "Should receive full amount after expiry");
        vm.stopPrank();
    }

    function test_should_prevent_new_users_from_entering_expired_strategy_with_rewards() public {
        // Create a strategy with short expiry and rewards
        vm.startPrank(deployer);
        uint256 startTime = block.timestamp;
        uint256 shortExpiry = startTime + 30 days; // Short expiry
        
        vestingStrategy.createStrategy(
            startTime,
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            20 days, // Shorter vesting duration to fit within expiry
            shortExpiry,
            MERKLE_ROOT,
            CLAIM_WITH_DELAY,
            5000 // 50% reward
        );
        uint256 expiredStrategyId = 2;

        (bytes32 root, bytes32[] memory merkleProof) = _claimerDetails();
        vestingStrategy.updateMerkleRoot(expiredStrategyId, root);
        vm.stopPrank();

        // Move past expiry date
        vm.warp(shortExpiry + 1 days);
        
        // Try to claim as a new user - should revert
        vm.startPrank(claimer1);
        vm.expectRevert(VestingStrategy.StrategyExpired.selector);
        vestingStrategy.claim(expiredStrategyId, CLAIM_AMOUNT, merkleProof);
        vm.stopPrank();
    }

    function test_should_allow_existing_users_to_claim_rewards_after_expiry() public {
        // Create a strategy with short expiry and rewards
        vm.startPrank(deployer);
        uint256 startTime = block.timestamp;
        uint256 shortExpiry = startTime + 30 days; // Short expiry
        
        vestingStrategy.createStrategy(
            startTime,
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            20 days, // Shorter vesting duration to fit within expiry
            shortExpiry,
            MERKLE_ROOT,
            CLAIM_WITH_DELAY,
            5000 // 50% reward
        );
        uint256 expiredStrategyId = 2;

        (bytes32 root, bytes32[] memory merkleProof) = _claimerDetails();
        vestingStrategy.updateMerkleRoot(expiredStrategyId, root);
        vm.stopPrank();

        // First, claimer1 claims before expiry to become an existing user
        vm.startPrank(claimer1);
        vestingStrategy.claim(expiredStrategyId, CLAIM_AMOUNT, merkleProof);
        
        // Verify user is now participating in the strategy
        VestingStrategy.UserVesting memory userInfo = vestingStrategy.getUserVestingInfo(claimer1);
        assertEq(userInfo.strategyId, expiredStrategyId, "User should be participating in strategy");
        
        // Move past expiry date
        vm.warp(shortExpiry + 1 days);
        
        // Should be able to claim after expiry as an existing user
        vestingStrategy.claim(expiredStrategyId, CLAIM_AMOUNT, merkleProof);
        
        // Verify tokens were received (base + 50% reward)
        uint256 totalWithReward = CLAIM_AMOUNT + (CLAIM_AMOUNT * 5000) / 10000;
        assertEq(mockERC20Token.balanceOf(claimer1), totalWithReward, "Should receive full amount with reward after expiry");
        vm.stopPrank();
    }

    function test_should_allow_multiple_claims_after_expiry_for_existing_users() public {
        // Create a strategy with short expiry
        vm.startPrank(deployer);
        uint256 startTime = block.timestamp;
        uint256 shortExpiry = startTime + 30 days; // Short expiry
        
        vestingStrategy.createStrategy(
            startTime,
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            20 days, // Shorter vesting duration to fit within expiry
            shortExpiry,
            MERKLE_ROOT,
            false, // No claimWithDelay
            0 // No reward
        );
        uint256 expiredStrategyId = 2;

        (bytes32 root, bytes32[] memory merkleProof) = _claimerDetails();
        vestingStrategy.updateMerkleRoot(expiredStrategyId, root);
        vm.stopPrank();

        // First, claimer1 claims before expiry to become an existing user
        vm.startPrank(claimer1);
        vestingStrategy.claim(expiredStrategyId, CLAIM_AMOUNT, merkleProof);
        vm.stopPrank();
        
        // Move past expiry date
        vm.warp(shortExpiry + 1 days);
        
        // claimer1 should be able to claim after expiry
        vm.startPrank(claimer1);
        vestingStrategy.claim(expiredStrategyId, CLAIM_AMOUNT, merkleProof);
        assertEq(mockERC20Token.balanceOf(claimer1), CLAIM_AMOUNT, "Should receive full amount after expiry");
        vm.stopPrank();
        
        // claimer2 should not be able to claim after expiry
        vm.startPrank(claimer2);
        vm.expectRevert(VestingStrategy.StrategyExpired.selector);
        vestingStrategy.claim(expiredStrategyId, CLAIM_AMOUNT, merkleProof);
        vm.stopPrank();
    }

    function test_should_prevent_new_users_from_entering_expired_strategy_at_exact_expiry_time() public {
        // Create a strategy with short expiry
        vm.startPrank(deployer);
        uint256 startTime = block.timestamp;
        uint256 shortExpiry = startTime + 30 days; // Short expiry
        
        vestingStrategy.createStrategy(
            startTime,
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            20 days, // Shorter vesting duration to fit within expiry
            shortExpiry,
            MERKLE_ROOT,
            CLAIM_WITH_DELAY,
            0 // No reward
        );
        uint256 expiredStrategyId = 2;

        (bytes32 root, bytes32[] memory merkleProof) = _claimerDetails();
        vestingStrategy.updateMerkleRoot(expiredStrategyId, root);
        vm.stopPrank();

        // Move to exact expiry time
        vm.warp(shortExpiry);
        
        // Try to claim as a new user at exact expiry time - should revert
        vm.startPrank(claimer1);
        vm.expectRevert(VestingStrategy.StrategyExpired.selector);
        vestingStrategy.claim(expiredStrategyId, CLAIM_AMOUNT, merkleProof);
        vm.stopPrank();
    }

    function test_should_allow_existing_users_to_claim_at_exact_expiry_time() public {
        // Create a strategy with short expiry
        vm.startPrank(deployer);
        uint256 startTime = block.timestamp;
        uint256 shortExpiry = startTime + 30 days; // Short expiry
        
        vestingStrategy.createStrategy(
            startTime,
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            20 days, // Shorter vesting duration to fit within expiry
            shortExpiry,
            MERKLE_ROOT,
            CLAIM_WITH_DELAY,
            0 // No reward
        );
        uint256 expiredStrategyId = 2;

        (bytes32 root, bytes32[] memory merkleProof) = _claimerDetails();
        vestingStrategy.updateMerkleRoot(expiredStrategyId, root);
        vm.stopPrank();

        // First, claimer1 claims before expiry to become an existing user
        vm.startPrank(claimer1);
        vestingStrategy.claim(expiredStrategyId, CLAIM_AMOUNT, merkleProof);
        
        // Move to exact expiry time
        vm.warp(shortExpiry);
        
        // Should be able to claim at exact expiry time as an existing user
        vestingStrategy.claim(expiredStrategyId, CLAIM_AMOUNT, merkleProof);
        
        // Verify tokens were received
        assertEq(mockERC20Token.balanceOf(claimer1), CLAIM_AMOUNT, "Should receive full amount at exact expiry time");
        vm.stopPrank();
    }

    function test_should_prevent_new_users_from_entering_expired_strategy_with_different_user() public {
        // Create a strategy with short expiry
        vm.startPrank(deployer);
        uint256 startTime = block.timestamp;
        uint256 shortExpiry = startTime + 30 days; // Short expiry
        
        vestingStrategy.createStrategy(
            startTime,
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            20 days, // Shorter vesting duration to fit within expiry
            shortExpiry,
            MERKLE_ROOT,
            CLAIM_WITH_DELAY,
            0 // No reward
        );
        uint256 expiredStrategyId = 2;

        (bytes32 root, bytes32[] memory merkleProof) = _claimerDetails();
        vestingStrategy.updateMerkleRoot(expiredStrategyId, root);
        vm.stopPrank();

        // Move past expiry date
        vm.warp(shortExpiry + 1 days);
        
        // Try to claim as a different user (claimer2) - should revert
        vm.startPrank(claimer2);
        vm.expectRevert(VestingStrategy.StrategyExpired.selector);
        vestingStrategy.claim(expiredStrategyId, CLAIM_AMOUNT, merkleProof);
        vm.stopPrank();
    }

    function test_should_allow_existing_user_to_claim_while_preventing_new_users() public {
        // Create a strategy with short expiry
        vm.startPrank(deployer);
        uint256 startTime = block.timestamp;
        uint256 shortExpiry = startTime + 30 days; // Short expiry
        
        vestingStrategy.createStrategy(
            startTime,
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            20 days, // Shorter vesting duration to fit within expiry
            shortExpiry,
            MERKLE_ROOT,
            CLAIM_WITH_DELAY,
            0 // No reward
        );
        uint256 expiredStrategyId = 2;

        (bytes32 root, bytes32[] memory merkleProof) = _claimerDetails();
        vestingStrategy.updateMerkleRoot(expiredStrategyId, root);
        vm.stopPrank();

        // First, claimer1 claims before expiry to become an existing user
        vm.startPrank(claimer1);
        vestingStrategy.claim(expiredStrategyId, CLAIM_AMOUNT, merkleProof);
        vm.stopPrank();
        
        // Move past expiry date
        vm.warp(shortExpiry + 1 days);
        
        // claimer1 should be able to claim after expiry
        vm.startPrank(claimer1);
        vestingStrategy.claim(expiredStrategyId, CLAIM_AMOUNT, merkleProof);
        assertEq(mockERC20Token.balanceOf(claimer1), CLAIM_AMOUNT, "Should receive full amount after expiry");
        vm.stopPrank();
        
        // claimer2 should not be able to claim after expiry
        vm.startPrank(claimer2);
        vm.expectRevert(VestingStrategy.StrategyExpired.selector);
        vestingStrategy.claim(expiredStrategyId, CLAIM_AMOUNT, merkleProof);
        vm.stopPrank();
    }

    function test_should_handle_expiry_with_multiple_strategies() public {
        // Create two strategies with different expiry dates
        vm.startPrank(deployer);
        uint256 startTime = block.timestamp;
        
        // Strategy 1: Long expiry
        vestingStrategy.createStrategy(
            startTime,
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            VESTING_DURATION,
            startTime + 365 days, // Long expiry
            MERKLE_ROOT,
            CLAIM_WITH_DELAY,
            0 // No reward
        );
        uint256 longExpiryStrategyId = 2;
        
        // Strategy 2: Short expiry
        vestingStrategy.createStrategy(
            startTime,
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            20 days, // Shorter vesting duration to fit within expiry
            startTime + 30 days, // Short expiry
            MERKLE_ROOT,
            CLAIM_WITH_DELAY,
            0 // No reward
        );
        uint256 shortExpiryStrategyId = 3;

        (bytes32 root, bytes32[] memory merkleProof) = _claimerDetails();
        vestingStrategy.updateMerkleRoot(longExpiryStrategyId, root);
        vestingStrategy.updateMerkleRoot(shortExpiryStrategyId, root);
        vm.stopPrank();

        // Move past short expiry but before long expiry
        vm.warp(startTime + 60 days);
        
        // Should be able to claim from long expiry strategy
        vm.startPrank(claimer1);
        vestingStrategy.claim(longExpiryStrategyId, CLAIM_AMOUNT, merkleProof);
        vm.stopPrank();
        
        // Should not be able to claim from short expiry strategy as new user
        vm.startPrank(claimer2);
        vm.expectRevert(VestingStrategy.StrategyExpired.selector);
        vestingStrategy.claim(shortExpiryStrategyId, CLAIM_AMOUNT, merkleProof);
        vm.stopPrank();
    }

    function test_should_handle_expiry_with_getClaimableAmount() public {
        // Create a strategy with short expiry
        vm.startPrank(deployer);
        uint256 startTime = block.timestamp;
        uint256 shortExpiry = startTime + 30 days; // Short expiry
        
        vestingStrategy.createStrategy(
            startTime,
            CLIFF_DURATION,
            CLIFF_PERCENTAGE,
            20 days, // Shorter vesting duration to fit within expiry
            shortExpiry,
            MERKLE_ROOT,
            CLAIM_WITH_DELAY,
            0 // No reward
        );
        uint256 expiredStrategyId = 2;

        (bytes32 root, bytes32[] memory merkleProof) = _claimerDetails();
        vestingStrategy.updateMerkleRoot(expiredStrategyId, root);
        vm.stopPrank();

        // First, claimer1 claims BEFORE expiry to become an existing user
        vm.startPrank(claimer1);
        vestingStrategy.claim(expiredStrategyId, CLAIM_AMOUNT, merkleProof);
        vm.stopPrank();
        
        // Move past expiry date
        vm.warp(shortExpiry + 1 days);
        
        // getClaimableAmount should return 0 for new users on expired strategy
        uint256 claimableAmount = vestingStrategy.getClaimableAmount(claimer2, expiredStrategyId, CLAIM_AMOUNT);
        assertEq(claimableAmount, 0, "New users should not be able to claim from expired strategy");
        
        // But existing users should still be able to claim the remaining amount
        claimableAmount = vestingStrategy.getClaimableAmount(claimer1, expiredStrategyId, CLAIM_AMOUNT);
        uint256 expectedRemaining = CLAIM_AMOUNT - (CLAIM_AMOUNT * CLIFF_PERCENTAGE / 10000); // 80% of total
        assertEq(claimableAmount, expectedRemaining, "Existing users should be able to claim remaining amount after expiry");
    }

    function test_should_claim_cliff_amount_when_first_claiming_after_cliff_period() public {
        (bytes32 root, bytes32[] memory merkleProof) = _claimerDetails();

        vm.startPrank(deployer);
        vestingStrategy.updateMerkleRoot(strategyId, root);
        vm.stopPrank();

        vm.startPrank(claimer1);

        // Get strategy for calculations
        VestingStrategy.Strategy memory currentStrategy = vestingStrategy.getStrategy(strategyId);

        // Move past cliff period without claiming during cliff
        vm.warp(currentStrategy.startTime + currentStrategy.cliffDuration + 1 days);

        // Calculate expected amounts
        uint256 cliffAmount = (CLAIM_AMOUNT * CLIFF_PERCENTAGE) / 10000; // 20% of total
        uint256 timeSinceCliff = block.timestamp - (currentStrategy.startTime + currentStrategy.cliffDuration);
        uint256 vestingPeriodAfterCliff = currentStrategy.vestingDuration - currentStrategy.cliffDuration;
        uint256 remainingAfterCliff = CLAIM_AMOUNT - cliffAmount; // 80% of total
        
        // Calculate linear vesting amount for the time that has passed since cliff
        uint256 linearVested = (remainingAfterCliff * timeSinceCliff) / vestingPeriodAfterCliff;
        
        // Total expected claimable should be cliff amount + linear vesting amount
        uint256 expectedTotalClaimable = cliffAmount + linearVested;

        // Get claimable amount
        uint256 claimableAmount = vestingStrategy.getClaimableAmount(
            claimer1,
            strategyId,
            CLAIM_AMOUNT
        );

        // Verify claimable amount includes cliff + linear vesting
        assertEq(
            claimableAmount,
            expectedTotalClaimable,
            "Claimable amount should include cliff + linear vesting when claiming after cliff period"
        );

        // Claim the tokens
        uint256 preClaimBalance = mockERC20Token.balanceOf(claimer1);
        vestingStrategy.claim(strategyId, CLAIM_AMOUNT, merkleProof);
        uint256 postClaimBalance = mockERC20Token.balanceOf(claimer1);

        // Verify the claim amount
        assertEq(
            postClaimBalance - preClaimBalance,
            expectedTotalClaimable,
            "User should receive cliff + linear vesting amount when claiming after cliff period"
        );

        // Verify vesting info
        VestingStrategy.UserVesting memory userInfo = vestingStrategy.getUserVestingInfo(claimer1);
        assertEq(
            userInfo.claimedAmount,
            expectedTotalClaimable,
            "Claimed amount should be updated correctly"
        );
        assertTrue(userInfo.cliffClaimed, "Cliff should be marked as claimed after first claim");
        assertEq(
            userInfo.strategyId,
            strategyId,
            "User should be assigned to the strategy"
        );
    }

    function test_should_claim_only_cliff_amount_when_claiming_during_cliff_period() public {
        (bytes32 root, bytes32[] memory merkleProof) = _claimerDetails();

        vm.startPrank(deployer);
        vestingStrategy.updateMerkleRoot(strategyId, root);
        vm.stopPrank();

        vm.startPrank(claimer1);

        // Get strategy for calculations
        VestingStrategy.Strategy memory currentStrategy = vestingStrategy.getStrategy(strategyId);

        // Move to middle of cliff period
        vm.warp(currentStrategy.startTime + (currentStrategy.cliffDuration / 2));

        // Calculate expected cliff amount
        uint256 cliffAmount = (CLAIM_AMOUNT * CLIFF_PERCENTAGE) / 10000; // 20% of total

        // Get claimable amount
        uint256 claimableAmount = vestingStrategy.getClaimableAmount(
            claimer1,
            strategyId,
            CLAIM_AMOUNT
        );

        // Verify only cliff amount is claimable during cliff period
        assertEq(
            claimableAmount,
            cliffAmount,
            "Only cliff amount should be claimable during cliff period"
        );

        // Claim the tokens
        uint256 preClaimBalance = mockERC20Token.balanceOf(claimer1);
        vestingStrategy.claim(strategyId, CLAIM_AMOUNT, merkleProof);
        uint256 postClaimBalance = mockERC20Token.balanceOf(claimer1);

        // Verify the claim amount
        assertEq(
            postClaimBalance - preClaimBalance,
            cliffAmount,
            "User should receive only cliff amount during cliff period"
        );

        // Verify vesting info
        VestingStrategy.UserVesting memory userInfo = vestingStrategy.getUserVestingInfo(claimer1);
        assertEq(
            userInfo.claimedAmount,
            cliffAmount,
            "Claimed amount should be cliff amount only"
        );
        assertTrue(userInfo.cliffClaimed, "Cliff should be marked as claimed");
    }
}