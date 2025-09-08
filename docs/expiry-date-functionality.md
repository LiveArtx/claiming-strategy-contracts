# Expiry Date Functionality

## Overview

The `expiryDate` parameter in VestingStrategy serves as an **enrollment deadline** for new users while providing **bonus benefits** to existing users. It is **NOT** a restriction on existing users' ability to claim their tokens - they can always claim according to their vesting schedule, with additional benefits after expiry.

## Key Principle

**Expiry Date = Enrollment Deadline + Bonus Benefits**

- **For New Users**: Absolute deadline to enter the strategy
- **For Existing Users**: Bonus feature that provides accelerated claiming, never a restriction

## Core Concepts

### 1. What is ExpiryDate?

The `expiryDate` is a timestamp (in seconds) that defines when a strategy stops accepting new participants:

```solidity
struct Strategy {
    // ... other fields
    uint256 expiryDate; // in seconds - enrollment deadline
}
```

**Critical Understanding**: 
- ✅ **Enrollment deadline** for new users
- ✅ **Bonus feature** for existing users  
- ❌ **NOT a restriction** on existing users

### 2. Expiry vs Vesting Duration

These serve completely different purposes:

- **Vesting Duration**: How long tokens take to vest (defines payout schedule)
- **Expiry Date**: When new enrollment stops (access control + bonus benefits)

```solidity
// Example: Strategy created on Jan 1st
createStrategy(
    startTime: Jan 1st,
    vestingDuration: 180 days,      // Tokens vest over 6 months
    expiryDate: Jan 1st + 365 days  // New users can join for 1 year
);
```

**Timeline**:
- **Jan 1 - Dec 31**: New users can join, existing users vest normally
- **Jan 1+ (next year)**: No new users, existing users get bonus benefits

## Strategy Creation Validation

When creating a strategy, validations ensure logical expiry dates:

```solidity
if (expiryDate <= block.timestamp) revert InvalidStrategy();        // Must be future
if (startTime >= expiryDate) revert InvalidStrategy();             // Start before expiry
if (startTime + vestingDuration > expiryDate) revert InvalidStrategy(); // Vesting fits within expiry
```

### Valid Configuration Examples

```solidity
// ✅ VALID: Expiry after vesting completes
startTime: Jan 1st
vestingDuration: 180 days (until July 1st)
expiryDate: Dec 31st (well after vesting ends)

// ✅ VALID: Expiry exactly when vesting completes  
startTime: Jan 1st
vestingDuration: 180 days (until July 1st)
expiryDate: July 1st (same as vesting end)

// ❌ INVALID: Expiry before vesting completes
startTime: Jan 1st
vestingDuration: 180 days (until July 1st)
expiryDate: April 1st (before vesting ends)
```

## User Access Control

### New Users (Never Claimed)

**Before Expiry**: ✅ Can enter strategy
```solidity
// Normal validation - user can join
if (userInfo.strategyId == 0 && block.timestamp < strategy.expiryDate) {
    // Allow user to claim and join strategy
}
```

**After Expiry**: ❌ Cannot enter strategy
```solidity
// Block new users from expired strategies
if (userInfo.strategyId == 0 && block.timestamp >= strategy.expiryDate) {
    revert StrategyExpired();
}
```

### Existing Users (Already Claimed)

**Always**: ✅ Can claim according to vesting schedule
```solidity
// Existing users bypass expiry check entirely
if (userInfo.strategyId != 0) {
    // User can always claim based on vesting rules
    // Expiry date does not restrict them
}
```

**After Expiry**: ✅ Get bonus benefits (accelerated claiming)
```solidity
// Bonus: immediate access to all remaining tokens
if (currentTime > strategy.expiryDate && totalWithReward > userInfo.claimedAmount) {
    claimable = totalWithReward - userInfo.claimedAmount;
}
```

## Bonus Benefits After Expiry

### 1. Normal Vesting Strategies

**Standard Behavior**: Users claim as tokens vest over time

**Bonus After Expiry**: Can claim all remaining tokens immediately
```solidity
// If past expiry, allow claiming full remaining allocation
if (currentTime > strategy.expiryDate && totalWithReward > userInfo.claimedAmount) {
    claimable = totalWithReward - userInfo.claimedAmount;
}
```

**Example**:
```
Strategy: 6-month linear vesting, expires after 1 year
- Month 2: User claims 33% (normal vesting)
- Month 8: User has 67% remaining
- Year 1+: User can claim all 67% immediately (bonus)
```

### 2. Delayed Claim Strategies

**Standard Behavior**: Must wait for full vesting period to claim

**Bonus After Expiry**: Can claim immediately without waiting
```solidity
// If past expiry, allow immediate delayed claim release
if (currentTime >= strategy.expiryDate) {
    return (userInfo.delayedAmount - userInfo.claimedAmount, false);
}
```

**Example**:
```
Strategy: 1-year delayed vesting, expires after 6 months
- Month 3: User sets up delayed claim
- Month 6: Strategy expires
- Month 6+: User can claim immediately (bonus, don't wait until month 12)
```

## Practical Examples

### Example 1: Long Enrollment Period

```solidity
createStrategy(
    startTime: block.timestamp,
    cliffDuration: 30 days,
    cliffPercentage: 2000,        // 20% cliff
    vestingDuration: 180 days,    // 6-month vesting
    expiryDate: block.timestamp + 730 days, // 2-year enrollment
    claimWithDelay: false
);
```

**Timeline**:
- **Months 0-24**: New users can join, existing users vest normally
- **Month 6+**: Vesting complete for users who joined early
- **Month 24+**: No new users, existing users get immediate claiming bonus

### Example 2: Short Enrollment Window

```solidity
createStrategy(
    startTime: block.timestamp,
    cliffDuration: 0,
    cliffPercentage: 0,
    vestingDuration: 60 days,     // 2-month vesting
    expiryDate: block.timestamp + 90 days, // 3-month enrollment
    claimWithDelay: true
);
```

**Timeline**:
- **Months 0-3**: New users can join and set up delayed claims
- **Month 2**: Vesting completes (for delayed claims, users can claim after vesting duration)
- **Month 3+**: No new users, existing users continue normal vesting rules

## Best Practices

### 1. Setting Expiry Dates

**For Long-term Strategies**:
```solidity
expiryDate: startTime + vestingDuration + 365 days  // 1 year buffer
```

**For Limited Campaigns**:
```solidity
// Assuming vestingDuration = 21 days
expiryDate: startTime + vestingDuration + 30 days  // Short enrollment + vesting buffer
```

### 2. Communication Strategy

**Pre-Launch**:
- Clearly communicate enrollment deadlines
- Explain bonus benefits for existing users
- Set expectations about post-expiry behavior

**Near Expiry**:
- Remind potential users of deadline
- Reassure existing users they're protected
- Explain upcoming bonus benefits

**Post-Expiry**:
- Inform existing users about accelerated claiming
- Confirm no new enrollments accepted

### 3. Monitoring & Analytics

```solidity
// Helper functions for monitoring
function isStrategyExpired(uint256 strategyId) external view returns (bool) {
    return block.timestamp >= _strategies[strategyId].expiryDate;
}

function timeUntilExpiry(uint256 strategyId) external view returns (uint256) {
    uint256 expiry = _strategies[strategyId].expiryDate;
    return block.timestamp >= expiry ? 0 : expiry - block.timestamp;
}
```

## Common Scenarios

### Scenario 1: User Joins Late, Strategy Expires

**Problem**: User wants to join but strategy just expired
**Solution**: User cannot join (enrollment deadline passed)

### Scenario 2: User Forgets to Claim After Vesting

**Problem**: User has delayed claim but forgets to claim after vesting ends
**Solution**: If strategy has expired, user gets immediate claiming bonus


## Integration Considerations

### 1. With Rewards

Expiry bonuses apply to total allocation including rewards:

```solidity
uint256 totalWithReward = totalAllocation + rewardAmount;
// After expiry, can claim full totalWithReward immediately
if (currentTime > strategy.expiryDate) {
    claimable = totalWithReward - userInfo.claimedAmount;
}
```

### 2. With Multiple Strategies

Each strategy has independent expiry dates:

```solidity
// Strategy A: Short enrollment, long benefits
createStrategy(..., expiryDate: block.timestamp + 30 days);

// Strategy B: Long enrollment, different terms
createStrategy(..., expiryDate: block.timestamp + 365 days);
```

Users can participate in ONLY ONE strategy.


## Conclusion

The `expiryDate` functionality provides sophisticated lifecycle management that balances access control with user protection:

**Remember**: Expiry is **never a restriction** for existing users. It's an **enrollment deadline** that transforms into **bonus benefits** for those already participating in the strategy.