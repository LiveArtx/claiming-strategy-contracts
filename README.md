# VestingStrategy Smart Contract

A flexible and secure smart contract for managing multiple vesting strategies with merkle-proof-based allowlisting. This contract allows for the creation of multiple vesting strategies, each with its own unique configuration and allowlist.

## Contract Architecture

### Core Data Structures

The contract uses two main structs to manage vesting strategies and user participation:

1. **Strategy Struct** - Defines the parameters for each vesting strategy:
```solidity
struct Strategy {
    uint256 id;                      // Unique identifier for the strategy
    uint256 initialUnlockPercentage; // in basis points (1% = 100)
    uint256 cliffDuration;           // in seconds
    uint256 cliffPercentage;         // in basis points
    uint256 vestingDuration;         // in seconds
    uint256 expiryDate;              // in seconds
    uint256 startTime;               // When vesting starts for this strategy
    bytes32 merkleRoot;              // Merkle root for the strategy
    bool isActive;                   // Whether the strategy is active
    bool claimWithDelay;             // Whether tokens can only be claimed at vesting end
}
```

2. **UserVesting Struct** - Tracks a user's participation in a single strategy:
```solidity
struct UserVesting {
    uint256 strategyId;      // The strategy the user is participating in (0 if none)
    uint256 claimedAmount;   // Total amount claimed by the user
    uint256 lastClaimTime;   // Timestamp of last claim
    bool initialClaimed;     // Whether the user has claimed their initial amount
    uint256 delayedAmount;   // Amount of tokens currently locked for delayed claim
    uint256 delayStartTime;  // When the delayed claim started (0 if not delayed)
    bool isDelayedClaim;     // Whether the user has a delayed claim active
}
```

### Storage Layout

```solidity
// Strategy management
mapping(uint256 => Strategy) public strategies;        // strategyId => Strategy

// User management
mapping(address => UserVesting) public userVestingInfo; // user => UserVesting

// Token
IERC20 public immutable vestingToken;                  // The token being vested
```

### Key Design Decisions

1. **Single Strategy Per User**
   - Users can only participate in one strategy at a time
   - This is enforced through the `strategyId` field in `UserVesting`
   - Attempting to claim from a different strategy will revert with `UserAlreadyInStrategy`

2. **Gas-Efficient Storage**
   - Uses a single mapping `userVestingInfo` instead of multiple mappings
   - All user-related data is packed into one struct
   - Reduces storage slots and gas costs for reads/writes

3. **Time-Based Parameters**
   - All duration parameters are in seconds
   - `cliffDuration`: Time before linear vesting begins
   - `vestingDuration`: Total time over which tokens vest
   - `expiryDate`: When the strategy expires
   - `startTime`: When the strategy becomes active

4. **Percentage-Based Parameters**
   - Uses basis points (bps) for percentage calculations
   - 1 basis point = 0.01%
   - 100 basis points = 1%
   - 10000 basis points = 100%

## Features

### Strategy Parameters
Each vesting strategy includes:
- **Cliff Duration**: Initial period before linear vesting begins (in seconds)
- **Cliff Percentage**: Percentage of tokens that can be claimed during the cliff period (in basis points)
  - Available during the cliff period
  - Example: 2000 basis points (20%) means 200 tokens can be claimed during cliff
  - After cliff ends, remaining tokens vest linearly
- **Vesting Duration**: Total period over which remaining tokens are unlocked (in seconds)
- **Expiry Date**: Date after which no more claims are allowed (Unix timestamp)
- **Merkle Root**: Root of the merkle tree for strategy allowlist
- **Claim With Delay**: Whether tokens can only be claimed at vesting end

Example token distribution for a 1000 token allocation:
```solidity
// Strategy with cliff unlock
cliffDuration: 90 days,         // 3-month cliff
cliffPercentage: 2000,          // 20% (200 tokens) available during cliff
// Remaining 80% (800 tokens) vests linearly after cliff

// Strategy with no cliff
cliffDuration: 0,               // No cliff period
cliffPercentage: 0,             // No cliff unlock
// 100% (1000 tokens) vests linearly from start
```

### Claiming Mechanism

The contract supports two claiming modes:

1. **Normal Claims** (when `claimWithDelay` is false):
   - Initial unlock available immediately
   - Linear vesting after cliff period
   - Users can claim as tokens vest
   - Multiple claims allowed

2. **Delayed Claims** (when `claimWithDelay` is true):
   - No tokens can be claimed until vesting period ends
   - Users can only claim their full allocation at the end
   - No partial claims or early unlocks allowed
   - Single claim at vesting end

#### Claim Process Flow
1. User calls `claim()` with:
   - Strategy ID
   - Total allocation
   - Merkle proof
2. Contract verifies:
   - Strategy exists and is active
   - User is authorized (merkle proof)
   - User hasn't claimed from another strategy
3. Contract calculates claimable amount:
   - For delayed claims: Full allocation at vesting end
   - For normal claims: Based on vesting schedule
4. If claimable amount > 0:
   - Updates user's claimed amount
   - Records claim timestamp
   - Transfers tokens to user
   - Emits appropriate events

### Events
The contract emits events for important actions:
- `StrategyCreated`: When a new strategy is created
- `StrategyUpdated`: When a strategy's status is updated
- `TokensClaimed`: When a user claims vested tokens
- `TokensDelayed`: When a claim is delayed until vesting end
- `TokensReleased`: When delayed claim tokens are released

## Usage Guide

### 1. Deploying the Contract
```solidity
// Deploy with the token address that will be vested
VestingStrategy vestingStrategy = new VestingStrategy(tokenAddress);
```

### 2. Creating a Strategy
1. Generate a merkle tree of allowed users and their allocations
2. Create a strategy with the merkle root:
```solidity
await vestingStrategy.createStrategy(
    cliffDuration: 7 days,          // 7 days in seconds
    cliffPercentage: 2000,          // 20% in basis points
    vestingDuration: 180 days,      // 180 days in seconds
    expiryDate: [future timestamp],
    merkleRoot: [merkle root],
    claimWithDelay: false          // Whether to enable delayed claims
);
```

### 3. User Claiming Process
Users claim their vested tokens using merkle proof:
```solidity
await vestingStrategy.claim(
    strategyId,
    totalAllocation,  // Total tokens allocated (e.g., 1000 tokens)
    merkleProof
);
```

### 4. Querying User Information
Get all vesting information for a user:
```solidity
UserVesting memory info = vestingStrategy.getUserVestingInfo(userAddress);
```

### 5. Admin Functions
All admin functions are restricted to the contract owner:

- Create new strategy: `createStrategy(
    cliffDuration,
    cliffPercentage,
    vestingDuration,
    expiryDate,
    merkleRoot,
    claimWithDelay
)`
- Update strategy status: `updateStrategyStatus(strategyId, isActive)`
- Update merkle root: `updateMerkleRoot(strategyId, newMerkleRoot)`

## Example Strategies

Here are some common strategy configurations:

### 1. Standard Vesting Strategy
A typical vesting schedule with cliff unlock and linear vesting:
```solidity
// Strategy parameters for 1000 tokens total allocation
await vestingStrategy.createStrategy(
    cliffDuration: 7 days,          // 7-day cliff
    cliffPercentage: 1000,          // 10% (100 tokens) available during cliff
    vestingDuration: 180 days,      // 6-month vesting
    expiryDate: [future timestamp],
    merkleRoot: [merkle root],
    claimWithDelay: false          // Normal vesting
);

// Vesting schedule:
// Day 0-7:  100 tokens (10%) available during cliff
// Day 8-180: 900 tokens vest linearly (~5.2 tokens per day)
// Day 180+: All tokens available
```

### 2. Delayed Claim Strategy
A strategy where tokens can only be claimed at the end of the vesting period:
```solidity
// Strategy parameters for 1000 tokens total allocation
await vestingStrategy.createStrategy(
    cliffDuration: 0,               // No cliff
    cliffPercentage: 0,             // No cliff unlock
    vestingDuration: 365 days,      // 1-year vesting
    expiryDate: [future timestamp],
    merkleRoot: [merkle root],
    claimWithDelay: true           // Enable delayed claims
);

// Vesting schedule:
// Day 0-364: No tokens can be claimed
// Day 365:   User can claim full 1000 tokens
```

### 3. Cliff-Heavy Strategy
A strategy with a significant cliff unlock:
```solidity
// Strategy parameters for 1000 tokens total allocation
await vestingStrategy.createStrategy(
    cliffDuration: 90 days,         // 3-month cliff
    cliffPercentage: 3000,          // 30% (300 tokens) available during cliff
    vestingDuration: 365 days,      // 1-year vesting
    expiryDate: [future timestamp],
    merkleRoot: [merkle root],
    claimWithDelay: false          // Normal vesting
);

// Vesting schedule:
// Day 0-90:  300 tokens (30%) available during cliff
// Day 91-365: 700 tokens vest linearly (~2.5 tokens per day)
// Day 365+: All tokens available
```

Each strategy can be customized by adjusting:
- Cliff duration and percentage
- Vesting duration
- Whether to use delayed claims
- Expiry date
- Merkle root (allowlist)

## Security Considerations

1. **Access Control**
   - Only owner can create/update strategies
   - Users can only claim their own allocations
   - Merkle proofs prevent unauthorized claims
   - Users can only participate in one strategy at a time

2. **Reentrancy Protection**
   - All external functions that transfer tokens are protected
   - Uses OpenZeppelin's ReentrancyGuard

3. **Input Validation**
   - Cliff percentage cannot exceed 100%
   - Expiry date must be in the future
   - Amounts must be greater than zero
   - Users cannot claim from multiple strategies

## Error Handling

Custom errors are used for gas efficiency:
- `InvalidMerkleProof`: Invalid merkle proof provided
- `StrategyNotFound`: Strategy ID doesn't exist
- `StrategyInactive`: Strategy is not active
- `NoTokensToClaim`: No tokens available to claim
- `ClaimNotAllowed`: Claim not allowed (e.g., before cliff or after expiry)
- `UserAlreadyInStrategy`: User is already participating in a different strategy
- `InvalidAmount`: Amount is zero or invalid
- `InvalidUnlockPercentages`: Initial unlock + cliff percentage exceeds 100%
- `DelayedClaimAlreadyActive`: User already has a delayed claim
- `DelayedClaimNotActive`: No delayed claim to release
- `DelayedClaimLockNotExpired`: Delayed claim period hasn't ended

## License

MIT License
