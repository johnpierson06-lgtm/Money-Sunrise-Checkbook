# Account Balance Calculation Fix

## Problem
Account balances were being calculated incorrectly, showing different values than Microsoft Money itself. The issue was discovered when comparing the app's calculated balance against the actual Money application.

## Root Cause Analysis

Through extensive testing with mdbtools and SQL queries against the Money database, we discovered that Microsoft Money uses **specific filtering rules** when calculating account balances that we weren't implementing.

### The TRN (Transaction) Table Structure

Microsoft Money's transaction table has several fields that control whether a transaction should be counted in balance calculations:

| Field | Type | Purpose |
|-------|------|---------|
| `frq` | Int | Frequency: `-1` = posted transaction, `3` = recurring schedule template |
| `grftt` | Int | Transaction type flags (bitfield), bit 6 (value 64) = split transaction detail |
| `iinst` | Int | Instance number for posted recurring transactions |

### Transaction Types in Money Files

1. **Regular Posted Transactions** (`frq=-1`, `grftt<64`, `iinst=empty`)
   - Standard one-time transactions entered by the user
   - ✅ Should be counted in balance

2. **Transfer Transactions** (`frq=-1`, `grftt=2 or 6`, `iinst=empty`)
   - Transfers between accounts
   - ✅ Should be counted in balance

3. **Recurring Schedule Templates** (`frq=3`, `grftt=0-63`, `iinst=empty`)
   - Future scheduled transactions that haven't been posted yet
   - ❌ Should NOT be counted in balance

4. **Posted Recurring Instances** (`frq=-1`, `iinst!=empty`)
   - Instances of recurring schedules that have been confirmed/posted
   - ✅ Should be counted in balance (even if `grftt>=64`)

5. **Split Transaction Details** (`frq=-1`, `grftt>=64`, `iinst=empty`)
   - Internal accounting entries for split transactions
   - The parent transaction already contains the full amount
   - ❌ Should NOT be counted in balance

## The Solution

### Filtering Logic

Only count transactions where:
```
(frq == -1) AND (grftt < 64 OR iinst != nil)
```

This translates to:
- Transaction must be posted (`frq == -1`)
- AND either:
  - It's not a split detail (`grftt < 64`), OR
  - It's a posted recurring instance (`iinst` has a value)

### Implementation

**1. Updated `MoneyTransaction` model** with new fields:
```swift
public struct MoneyTransaction {
    // ... existing fields ...
    public let frequency: Int           // frq
    public let transactionTypeFlags: Int // grftt
    public let instanceNumber: Int?     // iinst
    
    public var shouldCountInBalance: Bool {
        guard frequency == -1 else { return false }
        if transactionTypeFlags >= 64 {
            return instanceNumber != nil
        }
        return true
    }
}
```

**2. Updated `MoneyFileParser`** to parse these fields from the TRN table.

**3. Updated balance calculation** in `MoneyFileService`:
```swift
for transaction in transactions {
    guard transaction.shouldCountInBalance else { continue }
    accountBalances[transaction.accountId]! += transaction.amount
}
```

## Verification

Tested with actual Money file:
- **Account**: Canvas - Personal Checking (ID=2)
- **Starting Balance**: $1,534.43
- **Expected Balance** (from Money): $699.64
- **Calculated Balance** (with fix): $699.64 ✅

### Test Results

**Before fix:**
- Counted 203 total transactions
- Balance was incorrect due to including split details and future scheduled transactions

**After fix:**
- Counted 49 transactions (matching Money's display)
- Balance calculation: 1534.43 + (-834.79) = 699.64 ✅

## Database Query for Testing

To verify the logic in mdbtools:
```bash
mdb-export file.mdb TRN | awk -F',' \
  'BEGIN {sum=0; count=0} \
   $2=="ACCOUNT_ID" && $13=="-1" && ($20 < 64 || $50!="") \
   {sum+=$10; count++} \
   END {print "Count: "count; print "Sum: "sum}'
```

## References

- TRN table schema in Microsoft Money database
- Field mappings documented in `MoneyFileParser.swift`
- Balance calculation in `MoneyFileService.swift`
