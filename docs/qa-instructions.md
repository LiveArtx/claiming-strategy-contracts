# QA Testing Instructions for VestingStrategy Contract

## Prerequisites

1. **Access**
   - Base Sepolia testnet ETH
   - MetaMask wallet
   - Contract deployment address
   - Owner and test user private keys
   - Token contract address

2. **Tools**
   - Merkle tree generator
   - BaseScan access

## Test Environment

1. **Contract Setup**
   - Verify contract on BaseScan
   - Confirm owner address
   - Verify token contract and approvals
   - A calculated merkle root based on the test data allocation amounts

2. **Token Setup**
   ```solidity
   // MockERC20Token requirements
   - Mint tokens to token contract: mockERC20Token.mint(address(mockERC20Token), totalAmount)
   - Approve vesting contract: mockERC20Token.approve(address(vestingStrategy), approvalAmount)
   - Verify token contract has sufficient balance for all test cases
   - Verify approval is setup with the correct amount
   ```

3. **Strategy Timing**
   ```solidity
   // Quick tests (1-5 minutes)
   cliffDuration: 60,            // 1 min (seconds)
   vestingDuration: 300,         // 5 min (seconds)
   expiryDate: block.timestamp + vestingDuration + 60  // 5 min + 1 min (seconds)

   // Medium tests (1-2 hours)
   cliffDuration: 3600,          // 1 hour (seconds)
   vestingDuration: 7200,        // 2 hours (seconds)
   expiryDate: block.timestamp + vestingDuration + 3600  // 2 hours + 1 hour (seconds)

   // Long tests (8-24 hours)
   cliffDuration: 28800,         // 8 hours (seconds) 
   vestingDuration: 43200,       // 12 hours (seconds)
   expiryDate: block.timestamp + vestingDuration + 43200  // 12 hours + 12 hours (seconds)
   ```

## Test Cases

### 1. Strategy Creation

#### 1.1 Valid Strategy
```solidity
createStrategy(
    cliffDuration: 60,          // 1 min (seconds)
    cliffPercentage: 2000,      // 20%
    vestingDuration: 300,       // 5 min (seconds)
    expiryDate: block.timestamp + 600,
    merkleRoot: [valid root],
    claimWithDelay: false
)
```
Verify: Transaction success, StrategyCreated event, strategy ID = 1

#### 1.2 Invalid Strategy
- Past expiry date: Reverts with `InvalidStrategy`
- Cliff > 100%: Reverts with `InvalidUnlockPercentages`

### 2. Normal Claims

#### 2.1 Cliff Claim
```solidity
claim(
    strategyId: 1,
    totalAllocation: 1000000000000000000000,  // 1000 tokens
    merkleProof: [valid proof]
)
```
Verify: 20% tokens received, cliffClaimed = true

#### 2.2 Post-Cliff Claim
- Wait 1 minute after cliff
- Claim again
Verify: Linear vesting amount received

#### 2.3 Post-Expiry Claim
- Wait for expiry (5 minutes)
- Claim remaining allocation
Verify: Full remaining amount received

### 3. Delayed Claims

#### 3.1 Setup Delayed Claim
```solidity
createStrategy(
    cliffDuration: 0,           // No cliff
    vestingDuration: 60,        // 1 min (seconds)
    expiryDate: block.timestamp + 300,  // 5 min (seconds)
    claimWithDelay: true
)
```
Verify: isDelayedClaim = true, delayedAmount set

#### 3.2 Early Release Attempt
- Try immediate claim
Verify: Reverts with `ClaimNotAllowed`

#### 3.3 Post-Vesting Release
- Wait 1 minute
- Claim again
Verify: Full allocation received, delayed claim reset

#### 3.4 Post-Expiry Release
```solidity
createStrategy(
    cliffDuration: 0,           // No cliff
    vestingDuration: 300,       // 5 min (seconds)
    expiryDate: block.timestamp + vestingDuration + 60,  // 5 min + 1 min (seconds)
    claimWithDelay: true
)
```
- Wait 1 minute
- Claim
Verify: Full allocation received immediately

### 4. Error Cases

#### 4.1 Invalid Merkle Proof
- Use modified proof
Verify: Reverts with `InvalidMerkleProof`

#### 4.2 Multiple Strategy Claims
- Create second strategy
- Try claiming as existing user
Verify: Reverts with `UserAlreadyInStrategy`

#### 4.3 Pre-Cliff Claim
- Try claiming before cliff
Verify: Reverts with `ClaimNotAllowed`

## Test Data

1. **Merkle Tree**
   - 3+ test users
   - Different allocation amounts
   - Save proofs and root

2. **Token Amounts**
   - Small: 1 token
   - Medium: 1000 tokens
   - Large: 1000000 tokens

## Common Test Scenarios

1. **Strategy Lifecycle**
   - Create → Update root → Update status
   - Verify all parameters

2. **User Journey**
   - Initial claim → Multiple claims → Final claim
   - Verify all amounts

3. **Edge Cases**
   - Claims at cliff/vesting/expiry boundaries
   - Multiple claims in same block
   - Max token amounts

## Notes

- Use testnet only
- Keep test tokens separate
- Document all transactions
- Verify events and state changes
- Monitor block timestamps
- Add buffer for network delays
- Track active strategies
