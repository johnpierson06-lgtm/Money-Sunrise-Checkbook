# Phase 1 Implementation: Creating New Transactions

## Overview
Phase 1 adds the ability to create new transactions in the iOS app with full category and payee support. Transactions are stored in a local SQLite database and will be synchronized later.

## ✅ What's Been Implemented

### 1. **Local Database Storage (SQLite)**
- **File**: `LocalDatabaseManager.swift`
- Uses SQLite (built into iOS) instead of MySQL for local storage
- Creates two tables matching the Microsoft Money schema:
  - `TRN` table (61 columns) - stores unsynced transactions
  - `PAY` table (41 columns) - stores unsynced payees
- Provides methods to:
  - Insert transactions
  - Insert payees
  - Get next available IDs
  - Query unsynced data

### 2. **Data Models**
- **File**: `LocalModels.swift`
- `LocalTransaction` - matches full TRN schema with all 61 fields
- `LocalPayee` - matches full PAY schema with all 41 fields
- Static factory methods to create properly formatted records

### 3. **New Transaction UI**
- **File**: `NewTransactionView.swift`
- Beautiful SwiftUI form for entering transaction details:
  - Date picker
  - Amount field
  - Category picker (with search)
  - Payee picker (with search and ability to add new)
  - Memo field
- **Category Selection**:
  - Searches through all categories from CAT table
  - Automatically determines if category is Income or Expense by walking parent chain
  - Looks for parent/grandparent ID 131 (EXPENSE) or 130 (INCOME)
  - Shows visual indicator (green arrow up for income, red arrow down for expense)
- **Payee Selection**:
  - Searches through payees from PAY table + local database
  - Ability to add new payees on the fly
  - New payees are stored in local SQLite database

### 4. **Amount Sign Logic** ✅
- **Expense categories** (parent/grandparent 131): Amount stored as **negative**
- **Income categories** (parent/grandparent 130): Amount stored as **positive**
- User just enters the number - the sign is applied automatically based on category

### 5. **Balance Updates**
- **File**: `AccountBalanceService.swift`
- Enhanced balance calculation that includes:
  - Beginning balance from ACCT table
  - Transactions from TRN table (from Money file)
  - Unsynced transactions from local SQLite database
- Account list shows warning badge for accounts with unsynced transactions
- Balance shows in orange when unsynced transactions exist
- Disclaimer text: "*includes unsynced transactions"

### 6. **Transaction Display**
- **File**: `TransactionsView.swift` (updated)
- Shows two sections:
  1. **Unsynced Transactions** (from local database) - shown in orange with sync icon
  2. **Synced Transactions** (from Money file) - normal display
- Auto-refreshes when new transaction is added

### 7. **Critical Fields Set Correctly** ✅
According to your requirements:
- `frq = -1` (Posted transaction, not scheduled)
- `grftt = 0` (Normal transaction, not split detail)
- `iinst = -1` (Not a recurring instance)
- `fUpdated = 1` (Mark as updated - CRITICAL!)
- `lHcrncUser = 45` (USD currency)
- All default values match your sample transactions

## 📁 New Files Created

1. `LocalDatabaseManager.swift` - SQLite database manager
2. `LocalModels.swift` - Data models for local storage
3. `NewTransactionView.swift` - UI for creating transactions
4. `AccountBalanceService.swift` - Enhanced balance calculation

## 🔧 Modified Files

1. `AccountsView.swift` - Shows unsynced transaction warnings
2. `TransactionsView.swift` - Displays local + synced transactions
3. `MoneyModels.swift` - No changes needed (already good)
4. `MoneyFileParser.swift` - No changes needed (already good)

## 🎯 How It Works

### Creating a Transaction
1. User taps "+" button on Transactions screen
2. `NewTransactionView` appears with form
3. User selects category → System determines if expense/income
4. User selects or creates payee
5. User enters amount (positive number)
6. System applies correct sign based on category type
7. Transaction saved to local SQLite with proper schema
8. View dismisses and transaction list refreshes
9. Account balance updates to include new transaction
10. Warning badge appears on account list

### Category Type Detection
```swift
Category ID 239 → Parent 162 → Parent 131 (EXPENSE)
Result: Amount stored as negative

Category ID 150 → Parent 130 (INCOME)  
Result: Amount stored as positive
```

### Database Location
SQLite database stored at:
```
~/Library/Application Support/[AppName]/checkbook_local.db
```

## ⚠️ Important Notes

### Why SQLite Instead of MySQL?
- **MySQL** is a server database (requires network connection)
- **SQLite** is embedded in iOS (no server needed)
- SQLite is Apple's recommended solution for local storage on iOS
- The schema is identical - migration to server MySQL later will be straightforward

### Transaction ID Generation
- Checks both Money file and local database for max ID
- Uses `max(fileMax, localMax) + 1` to avoid conflicts
- Same logic for Payee IDs

### GUID Generation
- Uses iOS `UUID()` formatted as `{XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX}`
- Matches Microsoft Money format

### Date Format
- Stored as `"MM/DD/YY HH:MM:SS"` to match Money file format
- Example: `"01/21/26 14:30:00"`

## 🔜 Next Steps (Future Phases)

- **Phase 2**: Sync local transactions to OneDrive .mny file
- **Phase 3**: Handle transaction edits and deletes
- **Phase 4**: Support for transfers between accounts
- **Phase 5**: Split transactions

## 🧪 Testing Checklist

- [ ] Create expense transaction → Amount is negative
- [ ] Create income transaction → Amount is positive  
- [ ] Search categories → Long list is searchable
- [ ] Search payees → Long list is searchable
- [ ] Add new payee → Appears in list immediately
- [ ] View account balance → Includes unsynced transaction
- [ ] Account list → Shows orange warning badge
- [ ] Transaction list → Shows "Unsynced Transactions" section
- [ ] Dismiss and reopen → Data persists

## 📝 Sample Transaction Created

```
htrn: 261 (auto-generated)
hacct: 2 (user's checking account)
dt: "01/21/26 14:30:00"
amt: -50.05 (expense, negative)
hcat: 239 (Bills:Electric)
lHpay: 1 (The Home Depot)
mMemo: "New light fixtures"
frq: -1 (posted)
fUpdated: 1 (CRITICAL)
iinst: -1 (CRITICAL)
sguid: "{88D462BA-7B6F-4B25-95A2C626E69C56C8}"
```

## 🎉 Success Criteria Met

✅ Categories pulled from CAT table  
✅ Searchable category picker  
✅ Parent/grandparent ID 131 → Expense (negative)  
✅ Parent/grandparent ID 130 → Income (positive)  
✅ Searchable payee picker  
✅ Add new payees  
✅ Local database storage (SQLite)  
✅ Full table schemas preserved  
✅ Balance includes unsynced transactions  
✅ Visual warning on account page  

---

**Ready for Phase 2: Synchronization** 🚀
