// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
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
///      - 10% initial unlock (initialUnlockPercentage = 1000)
///      - 7-day cliff (cliffDuration = 7 days)
///      - 6-month vesting (vestingDuration = 180 days)
///      - Total allocation = 1000 tokens
///
///      The schedule would be:
///      1. Day 0: 100 tokens (10%) available immediately
///      2. Day 1-7: No additional tokens (cliff period)
///      3. Day 8-180: 900 tokens vest linearly
///         - Daily rate = 900 / 173 days ≈ 5.2 tokens per day
///         - Formula: (remainingAmount * daysSinceCliff) / (vestingDuration - cliffDuration)
///      4. Day 180+: All tokens available
contract VestingStrategy is Ownable, ReentrancyGuard {
    using FixedPointMathLib for uint256;

    /// @notice Basis points denominator (100%)
    uint256 private constant BASIS_POINTS = 10000;

    // Struct to hold vesting strategy parameters
    struct Strategy {
        uint256 id;
        uint256 initialUnlockPercentage; // in basis points (1% = 100)
        uint256 cliffDuration;
        uint256 cliffPercentage; // in basis points
        uint256 vestingDuration;
        uint256 expiryDate;
        uint256 startTime; // When vesting starts for this strategy
        bytes32 merkleRoot;
        bool isActive;
    }

    // Token being vested
    IERC20 public immutable vestingToken;

    // Mapping of strategy ID to Strategy
    mapping(uint256 => Strategy) public strategies;
    
    // Mapping of user address to their claimed amounts per strategy
    mapping(uint256 => mapping(address => uint256)) public claimedAmount;
    
    // Mapping to track if user has claimed initial amount per strategy
    mapping(uint256 => mapping(address => bool)) public initialClaimed;
    
    // Counter for strategy IDs
    uint256 private _nextStrategyId;
    
    // Events
    event StrategyCreated(
        uint256 indexed strategyId,
        uint256 initialUnlockPercentage,
        uint256 cliffDuration,
        uint256 cliffPercentage,
        uint256 vestingDuration,
        uint256 expiryDate,
        bytes32 merkleRoot,
        uint256 startTime
    );
    event StrategyUpdated(uint256 indexed strategyId, bool isActive);
    event TokensClaimed(
        address indexed user,
        uint256 indexed strategyId,
        uint256 amount,
        bool isInitialClaim
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

    constructor(address _vestingToken) Ownable(_msgSender()) {
        vestingToken = IERC20(_vestingToken);
    }

    /**
     * @notice Creates a new vesting strategy
     */
    function createStrategy(
        uint256 initialUnlockPercentage,
        uint256 cliffDuration,
        uint256 cliffPercentage,
        uint256 vestingDuration,
        uint256 expiryDate,
        bytes32 merkleRoot
    ) external onlyOwner {
        if (initialUnlockPercentage + cliffPercentage > BASIS_POINTS) revert InvalidUnlockPercentages();
        if (expiryDate <= block.timestamp) revert InvalidStrategy();
        
        uint256 strategyId = _nextStrategyId++;
        uint256 startTime = block.timestamp;
        
        strategies[strategyId] = Strategy({
            id: strategyId,
            initialUnlockPercentage: initialUnlockPercentage,
            cliffDuration: cliffDuration,
            cliffPercentage: cliffPercentage,
            vestingDuration: vestingDuration,
            expiryDate: expiryDate,
            isActive: true,
            merkleRoot: merkleRoot,
            startTime: startTime
        });

        emit StrategyCreated(
            strategyId,
            initialUnlockPercentage,
            cliffDuration,
            cliffPercentage,
            vestingDuration,
            expiryDate,
            merkleRoot,
            startTime
        );
    }

    /**
     * @notice Checks if the contract has sufficient token balance and allowance
     * @param strategyId ID of the strategy
     * @param totalAllocation Total allocation for the user
     * @return hasBalance Whether the contract has sufficient token balance
     * @return hasAllowance Whether the contract has sufficient token allowance
     */
    function checkTokenStatus(
        uint256 strategyId,
        uint256 totalAllocation
    ) external view returns (bool hasBalance, bool hasAllowance) {
        Strategy storage strategy = strategies[strategyId];
        if (strategy.id == 0) revert StrategyNotFound();

        // Check contract's token balance
        uint256 balance = vestingToken.balanceOf(address(this));
        hasBalance = balance >= totalAllocation;

        // Check token holder's allowance to this contract
        address tokenHolder = owner(); // Assuming owner is the token holder
        uint256 allowance = vestingToken.allowance(tokenHolder, address(this));
        hasAllowance = allowance >= totalAllocation;

        return (hasBalance, hasAllowance);
    }

    /**
     * @notice Claims tokens based on merkle proof and vesting schedule
     * @param strategyId ID of the strategy
     * @param totalAllocation Total amount of tokens allocated
     * @param merkleProof Merkle proof for the user's allocation
     * @dev This function will:
     *      1. Verify the merkle proof
     *      2. Calculate claimable amount based on vesting schedule
     *      3. Transfer tokens from the contract to the claimer
     *      Note: The contract must have sufficient token balance or allowance
     */
    function claim(
        uint256 strategyId,
        uint256 totalAllocation,
        bytes32[] calldata merkleProof
    ) external nonReentrant {
        if (strategies[strategyId].id == 0) revert StrategyNotFound();
        if (!strategies[strategyId].isActive) revert StrategyInactive();
        if (totalAllocation == 0) revert InvalidAmount();

        // Verify merkle proof
        bytes32 leaf = keccak256(abi.encodePacked(_msgSender(), totalAllocation));
        if (!MerkleProof.verify(merkleProof, strategies[strategyId].merkleRoot, leaf)) {
            revert InvalidMerkleProof();
        }

        (uint256 claimable, bool isInitial) = _calculateClaimable(_msgSender(), strategyId, totalAllocation);
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

        // Update claimed amounts
        claimedAmount[strategyId][_msgSender()] += claimable;
        if (isInitial) {
            initialClaimed[strategyId][_msgSender()] = true;
        }

        // Transfer tokens to claimer
        require(vestingToken.transfer(_msgSender(), claimable), "Transfer failed");

        emit TokensClaimed(_msgSender(), strategyId, claimable, isInitial);
    }

    /**
     * @notice Calculates the amount of tokens that can be claimed
     * @param user Address of the user
     * @param strategyId ID of the strategy
     * @param totalAllocation Total allocation for the user
     * @return claimable Amount that can be claimed
     * @return isInitial Whether this is the initial claim
     * @dev Calculation steps:
     *      1. Initial unlock: Available immediately if not claimed
     *         amount = (totalAllocation * initialUnlockPercentage) / 10000
     *      2. Cliff period: No additional tokens until cliffDuration
     *      3. Linear vesting: After cliff, remaining tokens vest linearly
     *         remaining = totalAllocation - initialUnlock - cliffAmount
     *         dailyRate = remaining / (vestingDuration - cliffDuration)
     *         vested = dailyRate * daysSinceCliff
     */
    function _calculateClaimable(
        address user,
        uint256 strategyId,
        uint256 totalAllocation
    ) internal view returns (uint256 claimable, bool isInitial) {
        Strategy storage strategy = strategies[strategyId];
        uint256 elapsed = block.timestamp - strategy.startTime;
        uint256 vested = 0;

        // Initial unlock calculation
        if (!initialClaimed[strategyId][user]) {
            // Use mulDivDown for precise percentage calculation
            vested += FixedPointMathLib.mulDivDown(
                totalAllocation,
                strategy.initialUnlockPercentage,
                BASIS_POINTS
            );
            isInitial = true;
        }

        // Linear vesting calculation after cliff
        if (elapsed > strategy.cliffDuration) {
            uint256 vestingElapsed = elapsed - strategy.cliffDuration;
            
            // Cap vesting at maximum duration
            if (vestingElapsed >= (strategy.vestingDuration - strategy.cliffDuration)) {
                vestingElapsed = strategy.vestingDuration - strategy.cliffDuration;
            }

            // Calculate remaining amount that vests linearly using mulDivDown
            uint256 remaining = FixedPointMathLib.mulDivDown(
                totalAllocation,
                BASIS_POINTS - strategy.initialUnlockPercentage - strategy.cliffPercentage,
                BASIS_POINTS
            );

            // Calculate linear vesting with precise division using mulDivDown
            uint256 linearVested = FixedPointMathLib.mulDivDown(
                remaining,
                vestingElapsed,
                strategy.vestingDuration - strategy.cliffDuration
            );

            // Ensure remaining amount at vesting end
            if (vestingElapsed >= strategy.vestingDuration - strategy.cliffDuration) {
                linearVested = remaining;
            }

            // Add cliff amount if not claimed, using mulDivDown
            if (!initialClaimed[strategyId][user]) {
                vested += FixedPointMathLib.mulDivDown(
                    totalAllocation,
                    strategy.cliffPercentage,
                    BASIS_POINTS
                );
            }

            vested += linearVested;
        }

        uint256 alreadyClaimed = claimedAmount[strategyId][user];

        // Calculate claimable amount
        if (vested > alreadyClaimed && block.timestamp <= strategy.expiryDate) {
            claimable = vested - alreadyClaimed;
        } else if (totalAllocation > alreadyClaimed && block.timestamp > strategy.expiryDate) {
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
        if (strategies[strategyId].id == 0) revert StrategyNotFound();
        strategies[strategyId].isActive = isActive;
        emit StrategyUpdated(strategyId, isActive);
    }

    /**
     * @notice Updates the merkle root for a strategy
     * @param strategyId ID of the strategy to update
     * @param newMerkleRoot New merkle root
     */
    function updateMerkleRoot(uint256 strategyId, bytes32 newMerkleRoot) external onlyOwner {
        if (strategies[strategyId].id == 0) revert StrategyNotFound();
        strategies[strategyId].merkleRoot = newMerkleRoot;
    }
}
