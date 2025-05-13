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
        uint256 id;                      // Unique identifier for the strategy
        uint256 cliffDuration;           // in seconds
        uint256 cliffPercentage;         // in basis points (percentage available during cliff)
        uint256 vestingDuration;         // in seconds
        uint256 expiryDate;              // in seconds
        uint256 startTime;               // When vesting starts for this strategy (in seconds)
        bytes32 merkleRoot;              // Merkle root for the strategy
        bool isActive;                   // Whether the strategy is active
        bool claimWithDelay;             // Whether tokens can only be claimed at vesting end
    }

    struct UserVesting {
        uint256 strategyId;      // The strategy the user is participating in (0 if none)
        uint256 claimedAmount;   // Total amount claimed by the user
        uint256 lastClaimTime;   // Timestamp of last claim
        bool cliffClaimed;       // Whether the user has claimed their cliff amount
        uint256 delayedAmount;   // Amount of tokens currently locked for delayed claim
        uint256 delayStartTime;  // When the delayed claim started (0 if not delayed)
        bool isDelayedClaim;     // Whether the user has a delayed claim active
    }

    // Token being vested
    IERC20 public vestingToken;

    // Mapping of strategy ID to Strategy
    mapping(uint256 => Strategy) private _strategies;
    
    // Mapping of user address to their vesting information
    mapping(address => UserVesting) private _userVestingInfo;
    
    // Counter for strategy IDs
    uint256 private _nextStrategyId;
    
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
    event TokensReleased(
        address indexed user,
        uint256 indexed strategyId,
        uint256 amount,
        uint256 releaseTime
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

  

    function initialize(address _vestingToken) external initializer {
        vestingToken = IERC20(_vestingToken);
        __Ownable_init(_msgSender());
        __ReentrancyGuard_init();
    }

    /**
     * @notice Creates a new vesting strategy
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
        
        uint256 strategyId = _nextStrategyId++;
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
        if (_strategies[strategyId].id == 0) revert StrategyNotFound();
        if (!_strategies[strategyId].isActive) revert StrategyInactive();
        if (totalAllocation == 0) revert InvalidAmount();

        Strategy storage strategy = _strategies[strategyId];
        address user = _msgSender();
        uint256 currentTime = block.timestamp;
        
        // Get user's vesting info
        UserVesting storage userInfo = _userVestingInfo[user];
        
        // Check if user is already participating in a strategy
        if (userInfo.strategyId != 0 && userInfo.strategyId != strategyId) {
            revert UserAlreadyInStrategy();
        }

        // Verify merkle proof
        bytes32 leaf = keccak256(abi.encodePacked(user, totalAllocation));
        if (!MerkleProof.verify(merkleProof, strategy.merkleRoot, leaf)) {
            revert InvalidMerkleProof();
        }

        // Handle delayed claim release if user has a delayed claim
        if (userInfo.isDelayedClaim) {
            if (currentTime < userInfo.delayStartTime + strategy.vestingDuration) {
                revert ClaimNotAllowed();
            }

            uint256 delayedAmount = userInfo.delayedAmount;
            
            // Reset delayed claim state
            userInfo.delayedAmount = 0;
            userInfo.delayStartTime = 0;
            userInfo.isDelayedClaim = false;

            // Transfer delayed claim tokens to user
            require(vestingToken.transfer(user, delayedAmount), "Transfer failed");

            emit TokensReleased(user, strategyId, delayedAmount, currentTime);
            return;
        }

        // For strategies with claimWithDelay, only allow claims at vesting end
        if (strategy.claimWithDelay) {
            if (currentTime < strategy.startTime + strategy.vestingDuration) {
                revert ClaimNotAllowed();
            }
            // When claiming at vesting end, user gets their full allocation
            if (userInfo.claimedAmount > 0) revert ClaimNotAllowed();
            
            // Update user's delayed claim info
            userInfo.delayedAmount = totalAllocation;
            userInfo.delayStartTime = currentTime;
            userInfo.isDelayedClaim = true;
            userInfo.claimedAmount = totalAllocation;
            userInfo.lastClaimTime = currentTime;
            userInfo.cliffClaimed = true;

            emit TokensClaimed(user, strategyId, totalAllocation, true, currentTime);
            return;
        }

        // Normal claim process for strategies without claimWithDelay
        (uint256 claimable, bool isInitial) = _calculateClaimable(user, strategyId, totalAllocation);
        if (claimable == 0) revert NoTokensToClaim();

        // Check if contract has enough tokens
        uint256 balance = vestingToken.balanceOf(address(this));
        if (balance < claimable) {
            // If not enough balance, try to transfer from owner (token holder)
            require(
                vestingToken.transferFrom(owner(), address(this), claimable - balance),
                "TransferFrom failed"
            );
        }

        // Update user's vesting info
        userInfo.claimedAmount += claimable;
        userInfo.lastClaimTime = currentTime;
        if (isInitial) {
            userInfo.cliffClaimed = true;
        }

        // Set user's strategy if this is their first claim
        if (userInfo.strategyId == 0) {
            userInfo.strategyId = strategyId;
        }

        // Transfer tokens immediately
        require(vestingToken.transfer(user, claimable), "Transfer failed");

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
            uint256 vestingElapsed = elapsed - strategy.cliffDuration;
            
            if (vestingElapsed >= (strategy.vestingDuration - strategy.cliffDuration)) {
                vestingElapsed = strategy.vestingDuration - strategy.cliffDuration;
            }

            uint256 remaining = FixedPointMathLib.mulDivDown(
                totalAllocation,
                BASIS_POINTS - strategy.cliffPercentage,
                BASIS_POINTS
            );

            uint256 linearVested = FixedPointMathLib.mulDivDown(
                remaining,
                vestingElapsed,
                strategy.vestingDuration - strategy.cliffDuration
            );

            if (vestingElapsed >= strategy.vestingDuration - strategy.cliffDuration) {
                linearVested = remaining;
            }

            vested += linearVested;
        }

        uint256 alreadyClaimed = userInfo.claimedAmount;

        // Calculate claimable amount
        if (vested > alreadyClaimed && currentTime <= strategy.expiryDate) {
            claimable = vested - alreadyClaimed;
        } else if (totalAllocation > alreadyClaimed && currentTime > strategy.expiryDate) {
            claimable = totalAllocation - alreadyClaimed;
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
        (uint256 claimable, ) = _calculateClaimable(user, strategyId, totalAllocation);
        return claimable;
    }

    /**
     * @notice Updates the active status of a strategy
     * @param strategyId ID of the strategy to update
     * @param isActive New active status
     */
    function updateStrategyStatus(uint256 strategyId, bool isActive) external onlyOwner {
        if (_strategies[strategyId].id == 0) revert StrategyNotFound();
        _strategies[strategyId].isActive = isActive;
        emit StrategyUpdated(strategyId, isActive);
    }

    /**
     * @notice Updates the merkle root for a strategy
     * @param strategyId ID of the strategy to update
     * @param newMerkleRoot New merkle root
     */
    function updateMerkleRoot(uint256 strategyId, bytes32 newMerkleRoot) external onlyOwner {
        if (_strategies[strategyId].id == 0) revert StrategyNotFound();
        _strategies[strategyId].merkleRoot = newMerkleRoot;
    }

    /**
     * @notice Returns the strategy for a given ID
     * @param strategyId ID of the strategy to get
     * @return Strategy struct containing all strategy information
     */
    function getStrategy(uint256 strategyId) external view returns (Strategy memory) {
        return _strategies[strategyId];
    }

    /**
     * @notice Returns the vesting information for a given user
     * @param user Address of the user
     * @return UserVesting struct containing all user vesting information
     */
    function getUserVestingInfo(address user) external view returns (UserVesting memory) {
        return _userVestingInfo[user];
    }

    /**
     * @notice Updates a user's vesting information (owner only)
     * @param user Address of the user to update
     * @param info New vesting information
     */
    function setUserVestingInfo(address user, UserVesting calldata info) external onlyOwner {
        _userVestingInfo[user] = info;
    }
}
