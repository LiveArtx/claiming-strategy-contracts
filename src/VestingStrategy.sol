// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {FixedPointMathLib} from "src/libraries/FixedPointMathLib.sol";

/// @title VestingStrategy
/// @notice Manages multiple vesting strategies with merkle proof-based claims
/// @dev This contract needs to be approved to spend tokens on behalf of the token holder
///      (the account that holds the tokens to be vested). The token holder should:
///      1. Transfer tokens to this contract, OR
///      2. Approve this contract to spend tokens using token.approve(address(this), amount)
///
/// @dev Vesting Schedule Example:
///      For a strategy with:
///      - 20% cliff unlock (cliffPercentage = 2000)
///      - 7-day cliff (cliffDuration = 7 days)
///      - 6-month vesting (vestingDuration = 180 days)
///      - Total allocation = 1000 tokens
///
///      The schedule would be:
///      1. Day 0-7: 200 tokens (20%) available during cliff
///      2. Day 8-180: 800 tokens vest linearly
///         - Daily rate = 800 / 173 days ≈ 4.6 tokens per day
///         - Formula: (remainingAmount * daysSinceCliff) / (vestingDuration - cliffDuration)
///      3. Day 180+: All tokens available
contract VestingStrategy is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using FixedPointMathLib for uint256;

    /// @notice Basis points denominator (100%)
    uint256 private constant BASIS_POINTS = 10000;

    // Struct to hold vesting strategy parameters
    struct Strategy {
        uint256 id; // Unique identifier for the strategy
        uint256 cliffDuration; // in seconds
        uint256 cliffPercentage; // in basis points (percentage available during cliff)
        uint256 vestingDuration; // in seconds
        uint256 expiryDate; // in seconds
        uint256 startTime; // When vesting starts for this strategy (in seconds)
        bytes32 merkleRoot; // Merkle root for the strategy
        bool isActive; // Whether the strategy is active
        bool claimWithDelay; // Whether tokens can only be claimed at vesting end
    }

    struct UserVesting {
        uint256 strategyId; // The strategy the user is participating in (0 if none)
        uint256 claimedAmount; // Total amount claimed by the user
        uint256 lastClaimTime; // Timestamp of last claim
        bool cliffClaimed; // Whether the user has claimed their cliff amount
        uint256 delayedAmount; // Amount of tokens currently locked for delayed claim
        uint256 delayStartTime; // When the delayed claim started (0 if not delayed)
        bool isDelayedClaim; // Whether the user has a delayed claim active
    }

    // Token being vested
    IERC20 public _vestingToken;

    // Mapping of strategy ID to Strategy
    mapping(uint256 => Strategy) private _strategies;

    // Mapping of user address to their vesting information
    mapping(address => UserVesting) private _userVestingInfo;

    // Counter for strategy IDs
    uint256 private _nextStrategyId;

    // Token Approver
    address private _tokenApprover;

    // Events
    event StrategyCreated(
        uint256 indexed strategyId,
        uint256 cliffDuration,
        uint256 cliffPercentage,
        uint256 vestingDuration,
        uint256 expiryDate,
        bytes32 merkleRoot,
        uint256 startTime,
        bool claimWithDelay
    );
    event StrategyUpdated(uint256 indexed strategyId, bool isActive);
    event TokensClaimed(
        address indexed user,
        uint256 indexed strategyId,
        uint256 amount,
        bool isInitialClaim,
        uint256 timestamp
    );
    event DebugVestingCalculation(
        uint256 elapsed,
        uint256 vestingElapsed,
        uint256 vested,
        uint256 claimed,
        uint256 claimable
    );

    // Errors
    error InvalidMerkleProof();
    error StrategyNotFound();
    error StrategyInactive();
    error InvalidStrategy();
    error NoTokensToClaim();
    error ClaimNotAllowed();
    error InvalidAmount();
    error InvalidUnlockPercentages();
    error UserAlreadyInStrategy();
    error DelayedClaimAlreadyActive();
    error DelayedClaimNotActive();
    error DelayedClaimLockNotExpired();

    function initialize(address vestingToken_, address tokenApprover_) external initializer {
        _vestingToken = IERC20(vestingToken_);
        _tokenApprover = tokenApprover_;
        __Ownable_init(_msgSender());
        __ReentrancyGuard_init();
        _nextStrategyId = 1;
    }

    /**
     * @notice Creates a new vesting strategy
     * @param cliffDuration The duration of the cliff period in seconds
     * @param cliffPercentage The percentage of tokens available during the cliff period
     * @param vestingDuration The total duration of the vesting period in seconds
     * @param expiryDate The timestamp when the vesting period ends
     * @param merkleRoot The merkle root for the strategy
     * @param claimWithDelay Whether to enable delayed claims
     */
    function createStrategy(
        uint256 cliffDuration,
        uint256 cliffPercentage,
        uint256 vestingDuration,
        uint256 expiryDate,
        bytes32 merkleRoot,
        bool claimWithDelay
    ) external onlyOwner {
        if (cliffPercentage > BASIS_POINTS) revert InvalidUnlockPercentages();
        if (expiryDate <= block.timestamp) revert InvalidStrategy();

        uint256 strategyId = _nextStrategyId;
        _nextStrategyId++;
        uint256 startTime = block.timestamp;

        _strategies[strategyId] = Strategy({
            id: strategyId,
            cliffDuration: cliffDuration,
            cliffPercentage: cliffPercentage,
            vestingDuration: vestingDuration,
            expiryDate: expiryDate,
            isActive: true,
            merkleRoot: merkleRoot,
            startTime: startTime,
            claimWithDelay: claimWithDelay
        });

        emit StrategyCreated(
            strategyId,
            cliffDuration,
            cliffPercentage,
            vestingDuration,
            expiryDate,
            merkleRoot,
            startTime,
            claimWithDelay
        );
    }

    /**
     * @notice Claims tokens based on merkle proof and vesting schedule
     * @param strategyId ID of the strategy
     * @param totalAllocation Total amount of tokens allocated
     * @param merkleProof Merkle proof for the user's allocation
     * @dev This function will:
     *      1. Verify the merkle proof
     *      2. Calculate claimable amount based on vesting schedule
     *      3. Either:
     *         a. Transfer tokens immediately (if claimWithDelay is false)
     *         b. Lock tokens until vesting period ends (if claimWithDelay is true)
     *      Note: The contract must have sufficient token balance or allowance
     *      Note: Users can only participate in one strategy at a time
     */
    function claim(
        uint256 strategyId,
        uint256 totalAllocation,
        bytes32[] calldata merkleProof
    ) external nonReentrant {
        // Fail fast on cheap checks first
        if (totalAllocation == 0) revert InvalidAmount();
        
        // Load strategy into memory to reduce storage reads
        Strategy memory strategy = _strategies[strategyId];
        if (strategy.id == 0) revert StrategyNotFound();
        if (!strategy.isActive) revert StrategyInactive();

        address user = _msgSender();
        uint256 currentTime = block.timestamp;

        // Get user's vesting info - keep in storage since we need to modify it
        UserVesting storage userInfo = _userVestingInfo[user];

        // Verify merkle proof early to fail fast if invalid
        bytes32 leaf = keccak256(abi.encodePacked(user, totalAllocation));
        if (!MerkleProof.verify(merkleProof, strategy.merkleRoot, leaf)) {
            revert InvalidMerkleProof();
        }

        // Check if user is already participating in a different strategy
        if (userInfo.strategyId != 0 && userInfo.strategyId != strategyId) {
            revert UserAlreadyInStrategy();
        }

        // Handle delayed claim release if user has a delayed claim
        if (userInfo.isDelayedClaim) {
            uint256 delayedAmount = userInfo.delayedAmount;
            
            // If we're past expiry, allow immediate release
            if (currentTime >= strategy.expiryDate) {
                // Batch storage writes for delayed claim reset
                userInfo.delayedAmount = 0;
                userInfo.delayStartTime = 0;
                userInfo.isDelayedClaim = false;

                // Transfer tokens from token contract
                _vestingToken.transferFrom(address(_tokenApprover), user, delayedAmount);

                emit TokensClaimed(user, strategyId, delayedAmount, false, currentTime);
                return;
            }

            // Otherwise, check if delay period has ended
            if (currentTime < userInfo.delayStartTime + strategy.vestingDuration && userInfo.claimedAmount == 0) {
                revert ClaimNotAllowed();
            }
            
            // Batch storage writes for delayed claim reset
            userInfo.delayedAmount = 0;
            userInfo.delayStartTime = 0;
            userInfo.isDelayedClaim = false;

            // Transfer tokens from token contract
            _vestingToken.transferFrom(address(_tokenApprover), user, delayedAmount);

            emit TokensClaimed(user, strategyId, delayedAmount, false, currentTime);
            return;
        }

        // For strategies with claimWithDelay, only allow claims at vesting end
        if (strategy.claimWithDelay) {
            // Check for existing delayed claim first
            if (userInfo.isDelayedClaim) {
                revert DelayedClaimAlreadyActive();
            }

            userInfo.delayedAmount = totalAllocation;
            userInfo.delayStartTime = currentTime;
            userInfo.isDelayedClaim = true;
            userInfo.claimedAmount = 0;
            userInfo.lastClaimTime = 0;
            userInfo.cliffClaimed = false;
            userInfo.strategyId = strategyId;
            
            return;
        }

        // Normal claim process for strategies without claimWithDelay
        // Check if enough time has passed since last claim (minimum 1 day)
        if (userInfo.lastClaimTime > 0 && currentTime < userInfo.lastClaimTime + 1 days) {
            revert NoTokensToClaim();
        }

        (uint256 claimable, bool isInitial) = _calculateClaimable(
            user,
            strategyId,
            totalAllocation
        );

        // Check if there are any tokens to claim
        if (claimable == 0) revert NoTokensToClaim();

        // Transfer tokens from token contract
        _vestingToken.transferFrom(address(_tokenApprover), user, claimable);

        userInfo.claimedAmount += claimable;
        userInfo.lastClaimTime = currentTime;
        if (isInitial) {
            userInfo.cliffClaimed = true;
        }
        if (userInfo.strategyId == 0) {
            userInfo.strategyId = strategyId;
        }

        emit TokensClaimed(user, strategyId, claimable, isInitial, currentTime);
    }

    /**
     * @notice Calculates the amount of tokens that can be claimed
     * @param user Address of the user
     * @param strategyId ID of the strategy
     * @param totalAllocation Total allocation for the user
     * @return claimable Amount that can be claimed
     * @return isInitial Whether this is the initial claim
     * @dev Calculation steps:
     *      1. For strategies with claimWithDelay:
     *         - Only returns claimable amount at vesting end
     *         - Returns full allocation if vesting period has ended
     *         - Returns 0 if vesting period hasn't ended
     *      2. For normal strategies:
     *         a. Cliff period: Available immediately if not claimed
     *            amount = (totalAllocation * cliffPercentage) / 10000
     *         b. Linear vesting: After cliff, remaining tokens vest linearly
     *            remaining = totalAllocation - cliffAmount
     *            dailyRate = remaining / (vestingDuration - cliffDuration)
     *            vested = dailyRate * daysSinceCliff
     */
    function _calculateClaimable(
        address user,
        uint256 strategyId,
        uint256 totalAllocation
    ) internal view returns (uint256 claimable, bool isInitial) {
        Strategy storage strategy = _strategies[strategyId];
        UserVesting storage userInfo = _userVestingInfo[user];
        uint256 currentTime = block.timestamp;

        // For strategies with claimWithDelay, only allow claims at vesting end
        if (strategy.claimWithDelay) {
            if (currentTime < strategy.startTime + strategy.vestingDuration) {
                return (0, false);
            }
            // At vesting end, return full allocation if not claimed
            if (userInfo.claimedAmount == 0) {
                return (totalAllocation, true);
            }
            return (0, false);
        }

        uint256 elapsed = currentTime - strategy.startTime;

        // If we're past the vesting period, return the full remaining amount
        if (elapsed >= strategy.vestingDuration) {
            if (userInfo.claimedAmount < totalAllocation) {
                return (totalAllocation - userInfo.claimedAmount, false);
            }
            return (0, false);
        }

        // Calculate total vested amount
        uint256 vested = 0;

        // Cliff percentage calculation
        if (!userInfo.cliffClaimed && elapsed <= strategy.cliffDuration) {
            vested += FixedPointMathLib.mulDivDown(
                totalAllocation,
                strategy.cliffPercentage,
                BASIS_POINTS
            );
            isInitial = true;
        }

        // Linear vesting calculation after cliff
        if (elapsed > strategy.cliffDuration) {
            // Calculate how much time has passed since cliff ended
            uint256 timeSinceCliff = elapsed - strategy.cliffDuration;
            // Calculate how much time is left in the vesting period after cliff
            uint256 vestingPeriodAfterCliff = strategy.vestingDuration - strategy.cliffDuration;

            // Calculate remaining amount after cliff (80% of total)
            uint256 remaining = FixedPointMathLib.mulDivDown(
                totalAllocation,
                BASIS_POINTS - strategy.cliffPercentage,
                BASIS_POINTS
            );

            // Calculate linear vesting amount based on time since cliff
            uint256 linearVested = FixedPointMathLib.mulDivDown(
                remaining,
                timeSinceCliff,
                vestingPeriodAfterCliff
            );

            // Add to total vested amount
            vested += linearVested;

            // If we're past the vesting period, ensure we can claim the full remaining amount
            if (elapsed >= strategy.vestingDuration) {
                uint256 totalVested = FixedPointMathLib.mulDivDown(
                    totalAllocation,
                    BASIS_POINTS,
                    BASIS_POINTS
                );
                if (totalVested > vested) {
                    vested = totalVested;
                }
            }
        }

        // Calculate claimable amount based on what's vested minus what's already claimed
        if (vested > userInfo.claimedAmount) {
            claimable = vested - userInfo.claimedAmount;
        }

        // If we're past expiry date, allow claiming remaining allocation
        if (
            currentTime > strategy.expiryDate &&
            totalAllocation > userInfo.claimedAmount
        ) {
            claimable = totalAllocation - userInfo.claimedAmount;
        }

        // If we're at or past the vesting period end, ensure we can claim the full remaining amount
        if (
            elapsed >= strategy.vestingDuration &&
            totalAllocation > userInfo.claimedAmount
        ) {
            claimable = totalAllocation - userInfo.claimedAmount;
        }

        return (claimable, isInitial);
    }

    /**
     * @notice Returns the amount of tokens that can be claimed by a user
     * @param user Address of the user
     * @param strategyId ID of the strategy
     * @param totalAllocation Total allocation for the user
     */
    function getClaimableAmount(
        address user,
        uint256 strategyId,
        uint256 totalAllocation
    ) external view returns (uint256) {
        (uint256 claimable, ) = _calculateClaimable(
            user,
            strategyId,
            totalAllocation
        );
        return claimable;
    }

    /**
     * @notice Updates the active status of a strategy
     * @param strategyId ID of the strategy to update
     * @param isActive New active status
     */
    function updateStrategyStatus(
        uint256 strategyId,
        bool isActive
    ) external onlyOwner {
        if (_strategies[strategyId].id == 0) revert StrategyNotFound();
        _strategies[strategyId].isActive = isActive;
        emit StrategyUpdated(strategyId, isActive);
    }

    /**
     * @notice Updates the merkle root for a strategy
     * @param strategyId ID of the strategy to update
     * @param newMerkleRoot New merkle root
     */
    function updateMerkleRoot(
        uint256 strategyId,
        bytes32 newMerkleRoot
    ) external onlyOwner {
        if (_strategies[strategyId].id == 0) revert StrategyNotFound();
        _strategies[strategyId].merkleRoot = newMerkleRoot;
    }

    /**
     * @notice Returns the strategy for a given ID
     * @param strategyId ID of the strategy to get
     * @return Strategy struct containing all strategy information
     */
    function getStrategy(
        uint256 strategyId
    ) external view returns (Strategy memory) {
        return _strategies[strategyId];
    }

    function getAllStrategies() external view returns (Strategy[] memory) {
        uint256 totalStrategies = _nextStrategyId;
        Strategy[] memory allStrategies = new Strategy[](totalStrategies);
        for (uint256 i = 0; i < totalStrategies; i++) {
            allStrategies[i] = _strategies[i];
        }
        return allStrategies;
    }

    /**
     * @notice Returns the vesting information for a given user
     * @param user Address of the user
     * @return UserVesting struct containing all user vesting information
     */
    function getUserVestingInfo(
        address user
    ) external view returns (UserVesting memory) {
        return _userVestingInfo[user];
    }

    /**
     * @notice Updates a user's vesting information (owner only)
     * @param user Address of the user to update
     * @param info New vesting information
     */
    function setUserVestingInfo(
        address user,
        UserVesting calldata info
    ) external onlyOwner {
        _userVestingInfo[user] = info;
    }

    /**
     * @notice Sets the token approver
     * @param tokenApprover_ Address of the token approver
     */
    function setTokenApprover(address tokenApprover_) external onlyOwner {
        _tokenApprover = tokenApprover_;
    }

    /**
     * @notice Sets the vesting token
     * @param vestingToken_ Address of the vesting token
     */
    function setVestingToken(address vestingToken_) external onlyOwner {
        _vestingToken = IERC20(vestingToken_);
    }
}
