# VestingStrategy Smart Contract

A flexible and secure smart contract for managing multiple vesting strategies with merkle-proof-based allowlisting. This contract allows for the creation of multiple vesting strategies, each with its own unique configuration and allowlist.

## Features

### Multiple Vesting Strategies
- Each strategy has unique parameters (cliff, vesting duration, etc.)
- Users can participate in multiple strategies
- Each strategy has its own merkle-root-based allowlist

### Strategy Parameters
Each vesting strategy includes:
- **Initial Unlock Percentage**: Percentage of tokens unlocked immediately upon allocation (in basis points)
- **Cliff Duration**: Initial period before additional tokens can be claimed
- **Cliff Percentage**: Additional percentage of tokens unlocked at cliff (in basis points)
- **Vesting Duration**: Total period over which remaining tokens are unlocked
- **Expiry Date**: Date after which no more claims are allowed
- **Merkle Root**: Root of the merkle tree for strategy allowlist

### Basis Points System
The contract uses basis points (bps) for percentage calculations:
- 1 basis point = 0.01%
- 100 basis points = 1%
- 10000 basis points = 100%

Examples:
```solidity
// Common percentage values in basis points:
1000  = 10%   // Initial unlock
0     = 0%    // No cliff unlock
9000  = 90%   // Linear vesting amount
10000 = 100%  // Total allocation
```

### Security Features
- Merkle proof verification for allocation claims
- Reentrancy protection
- Owner-only administrative functions
- Custom error handling for gas efficiency
- Immutable token address

## Contract Architecture

### Key Components

1. **Strategy Management**
   ```solidity
   struct Strategy {
       uint256 id;
       uint256 initialUnlockPercentage; // in basis points (1% = 100)
       uint256 cliffDuration;
       uint256 cliffPercentage;         // in basis points
       uint256 vestingDuration;
       uint256 expiryDate;
       uint256 startTime;
       bytes32 merkleRoot;
       bool isActive;
   }
   ```

### Main Functions

1. **Strategy Creation**
   ```solidity
   function createStrategy(
       uint256 initialUnlockPercentage,  // in basis points (e.g., 1000 for 10%)
       uint256 cliffDuration,            // in seconds
       uint256 cliffPercentage,          // in basis points
       uint256 vestingDuration,          // in seconds
       uint256 expiryDate,               // Unix timestamp
       bytes32 merkleRoot
   ) external onlyOwner
   ```

2. **Token Claiming**
   ```solidity
   function claim(
       uint256 strategyId,
       uint256 totalAllocation,
       bytes32[] calldata merkleProof
   ) external nonReentrant
   ```

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
    initialUnlockPercentage: 1000,  // 10% in basis points
    cliffDuration: 7 days,          // 7 days in seconds
    cliffPercentage: 0,             // 0% in basis points
    vestingDuration: 180 days,      // 180 days in seconds
    expiryDate: [future timestamp],
    merkleRoot: [merkle root]
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

### 4. Admin Functions
- Update strategy status: `updateStrategyStatus(strategyId, isActive)`
- Update merkle root: `updateMerkleRoot(strategyId, newMerkleRoot)`

### Example Scenario: 10% Initial Unlock with 6-Month Linear Vesting

Here's a detailed example of implementing a vesting schedule with:
- 10% initial unlock (1000 basis points)
- 7-day cliff
- 90% daily unlock over 6 months (180 days)

#### Strategy Parameters
```solidity
// For a total allocation of 1000 tokens:
initialUnlockPercentage = 1000;  // 10% in basis points
cliffDuration = 7 days;          // 7-day cliff
cliffPercentage = 0;            // 0% in basis points
vestingDuration = 180 days;      // 6-month vesting
```

#### Vesting Schedule Timeline
1. **Day 0 (Initial Unlock)**
   - 100 tokens (10%) available immediately
   - Users can claim this amount right away
   - Calculation: `(1000 * 1000) / 10000 = 100 tokens`

2. **Day 1-7 (Cliff Period)**
   - No additional tokens unlock
   - Total available remains at 100 tokens

3. **Day 8-180 (Linear Vesting)**
   - Remaining 900 tokens vest linearly
   - Daily rate = 900 / 173 days ≈ 5.2 tokens per day
   - Formula: `(remainingAmount * daysSinceCliff) / (vestingDuration - cliffDuration)`
   - Example daily unlocks:
     - Day 8: ~105.2 tokens total (100 + 5.2)
     - Day 9: ~110.4 tokens total (100 + 10.4)
     - Day 30: ~220 tokens total (100 + 120)
     - Day 180: All 1000 tokens available

4. **Day 180+ (Vesting Complete)**
   - All tokens fully vested
   - Total available: 1000 tokens

#### Implementation
```solidity
// Create the strategy
vestingStrategy.createStrategy(
    initialUnlockPercentage: 1000,  // 10% in basis points
    cliffDuration: 7 days,
    cliffPercentage: 0,            // 0% in basis points
    vestingDuration: 180 days,     // 6 months
    expiryDate: [future date],
    merkleRoot: [your merkle root]
);

// Users can claim their allocation using merkle proof
vestingStrategy.claim(
    strategyId: [strategy id],
    totalAllocation: 1000,         // Total tokens allocated
    merkleProof: [proof]
);
```

#### Key Points
- Initial 10% is available immediately upon claiming
- No additional tokens unlock during the 7-day cliff
- After cliff, tokens vest linearly over the remaining period
- All calculations use precise fixed-point math to prevent rounding errors
- Users can claim their available tokens at any time
- The contract tracks claimed amounts to prevent double-claiming

## Vesting Calculation

The contract implements a three-phase vesting schedule:

1. **Initial Unlock Phase**
   - A percentage of tokens is immediately available upon allocation
   - This amount can be claimed right away
   - Initial unlock percentage is specified in basis points (1% = 100)
   - Example: `(totalAllocation * initialUnlockPercentage) / BASIS_POINTS`

2. **Cliff Phase**
   - No additional tokens are claimable until the cliff period
   - At cliff, an additional percentage of tokens becomes available
   - Cliff percentage is specified in basis points (1% = 100)
   - Example: `(totalAllocation * cliffPercentage) / BASIS_POINTS`

3. **Linear Vesting Phase**
   - Remaining tokens vest linearly over the vesting duration
   - Vesting starts after the cliff period
   - Remaining amount = `totalAllocation - initialUnlock - cliffAmount`
   - Formula: `vestedAmount = initialUnlockAmount + cliffAmount + (remainingAmount * vestingTime) / vestingDuration`

## Security Considerations

1. **Access Control**
   - Only owner can create/update strategies
   - Users can only claim their own allocations
   - Merkle proofs prevent unauthorized claims

2. **Reentrancy Protection**
   - All external functions that transfer tokens are protected
   - Uses OpenZeppelin's ReentrancyGuard

3. **Input Validation**
   - Cliff percentage cannot exceed 100%
   - Expiry date must be in the future
   - Amounts must be greater than zero

## Events

The contract emits events for important actions:
- `StrategyCreated`: When a new strategy is created
- `StrategyUpdated`: When a strategy's status is updated
- `AllocationClaimed`: When a user claims their allocation
- `TokensClaimed`: When a user claims vested tokens

## Error Handling

Custom errors are used for gas efficiency:
- `InvalidMerkleProof`: Invalid merkle proof provided
- `StrategyNotFound`: Strategy ID doesn't exist
- `StrategyInactive`: Strategy is not active
- `AlreadyClaimed`: User has already claimed their allocation
- `NoTokensToClaim`: No tokens available to claim
- `ClaimNotAllowed`: Claim not allowed (e.g., before cliff or after expiry)

## Testing

To test the contract:
1. Deploy the contract with a test token
2. Create a strategy with test parameters
3. Generate merkle proofs for test users
4. Test allocation claiming and token vesting
5. Verify all security measures

## License

MIT License
