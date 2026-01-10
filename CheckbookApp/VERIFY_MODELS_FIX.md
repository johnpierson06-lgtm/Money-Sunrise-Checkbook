# Verify MoneyModels Fix

## Current Errors

You're seeing these errors:
1. ✗ Missing package product 'MSAL'
2. ✗ Missing package product 'BigInt'
3. ✗ Cannot find type 'MoneyAccount' in scope (line 242, 342)
4. ✗ UUID/BinaryInteger comparison error (line 84)
5. ✗ Value has no member 'memo' (line 114)

## Root Causes

### Package Errors (MSAL & BigInt)
- **Cause:** Swift Package Manager dependencies are missing or corrupted
- **Fix:** Re-add packages in Xcode

### MoneyAccount Not Found
- **Cause:** `MoneyModels.swift` is either:
  - Not in the Xcode project
  - Not in the CheckbookApp target
  - File on disk doesn't match project reference
- **Fix:** Verify file exists and is in target

### UUID/BinaryInteger Error
- **Cause:** Xcode build cache thinks IDs are UUIDs
- **Fix:** Clean build folder after fixing models

### 'memo' Not Found
- **Cause:** Compiler can't see MoneyTransaction definition
- **Fix:** Same as MoneyAccount fix

## Step-by-Step Fix

### Part 1: Fix Package Dependencies

#### Fix MSAL Package

1. Open Xcode
2. Go to **File → Add Package Dependencies...**
3. In the search box, enter:
   ```
   https://github.com/AzureAD/microsoft-authentication-library-for-objc
   ```
4. Click **"Add Package"**
5. Select **"MSAL"** product
6. Click **"Add Package"**

#### Fix BigInt Package

1. While still in Package Dependencies
2. Click the **"+"** button to add another package
3. In the search box, enter:
   ```
   https://github.com/attaswift/BigInt
   ```
4. Click **"Add Package"**
5. Select **"BigInt"** product
6. Click **"Add Package"**

If packages already exist but are broken:

1. Select your **project** in Project Navigator
2. Select **CheckbookApp target**
3. Go to **"Frameworks, Libraries, and Embedded Content"** section
4. Remove MSAL and BigInt if they show errors
5. Re-add them using steps above

### Part 2: Fix MoneyModels.swift

#### Option A: File Missing from Project

If you **DON'T** see `MoneyModels.swift` in Project Navigator:

1. In Finder, navigate to:
   ```
   /Users/johnpierson/Documents/CheckbookApp/CheckbookApp/
   ```

2. Check if `MoneyModels.swift` exists
   - If **YES**: Right-click the CheckbookApp folder in Xcode → "Add Files to CheckbookApp" → Select MoneyModels.swift
   - If **NO**: Create it (see instructions below)

3. Make sure **"Copy items if needed"** is UNCHECKED
4. Make sure **"CheckbookApp" target is CHECKED**
5. Click **"Add"**

#### Option B: File Exists but Not in Target

If you **DO** see `MoneyModels.swift` in Project Navigator:

1. Click on `MoneyModels.swift` in Project Navigator
2. Open **File Inspector** (View → Inspectors → Show File Inspector, or Option+Cmd+1)
3. Look for **"Target Membership"** section
4. Make sure **"CheckbookApp"** has a **CHECKMARK**
5. If not checked, check it now

#### Option C: Create MoneyModels.swift

If the file doesn't exist at all:

1. Right-click **"CheckbookApp"** folder in Project Navigator
2. Select **"New File..."**
3. Choose **"Swift File"**
4. Name it: **"MoneyModels.swift"**
5. Make sure **"CheckbookApp" target** is **CHECKED**
6. Click **"Create"**

7. Paste this complete code:

```swift
//
//  MoneyModels.swift
//  CheckbookApp
//
//  Data models for Microsoft Money file parsing
//

import Foundation

// MARK: - Account Model

public struct MoneyAccount: Identifiable, Hashable, Codable, Sendable {
    public let id: Int              // Maps to: hacct
    public let name: String          // Maps to: szFull
    public let beginningBalance: Decimal  // Maps to: amtOpen

    public init(id: Int, name: String, beginningBalance: Decimal) {
        self.id = id
        self.name = name
        self.beginningBalance = beginningBalance
    }
}

// MARK: - Transaction Model

public struct MoneyTransaction: Identifiable, Hashable, Codable, Sendable {
    public let id: Int          // Maps to: htrn
    public let accountId: Int   // Maps to: hacct
    public let date: Date       // Maps to: dtrans
    public let amount: Decimal  // Maps to: amt
    public let payeeId: Int?    // Maps to: hpay
    public let categoryId: Int? // Maps to: hcat
    public let memo: String?    // Maps to: szMemo

    public init(id: Int, accountId: Int, date: Date, amount: Decimal, payeeId: Int? = nil, categoryId: Int? = nil, memo: String? = nil) {
        self.id = id
        self.accountId = accountId
        self.date = date
        self.amount = amount
        self.payeeId = payeeId
        self.categoryId = categoryId
        self.memo = memo
    }
}

// MARK: - Category Model

public struct MoneyCategory: Identifiable, Hashable, Codable, Sendable {
    public let id: Int       // Maps to: hcat
    public let name: String  // Maps to: szName

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

// MARK: - Payee Model

public struct MoneyPayee: Identifiable, Hashable, Codable, Sendable {
    public let id: Int       // Maps to: hpay
    public let name: String  // Maps to: szName

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}
```

### Part 3: Clean Build

After fixing packages and models:

1. **Close Xcode completely** (Cmd+Q)
2. **Delete Derived Data:**
   - Open Terminal
   - Run: `rm -rf ~/Library/Developer/Xcode/DerivedData`
3. **Reopen Xcode**
4. **Clean Build Folder:**
   - Product → Hold Option → Clean Build Folder
5. **Build:**
   - Product → Build (Cmd+B)

## Verification Checklist

After following the steps, verify:

- [ ] MSAL package shows no errors in Project Navigator
- [ ] BigInt package shows no errors in Project Navigator  
- [ ] MoneyModels.swift appears in Project Navigator
- [ ] MoneyModels.swift has CheckbookApp target checked
- [ ] Build succeeds with no errors
- [ ] You can import models in other files

## Test Code

To verify models are working, try adding this to any view:

```swift
// Test that models are accessible
let testAccount = MoneyAccount(id: 1, name: "Test", beginningBalance: 100)
let testTransaction = MoneyTransaction(id: 1, accountId: 1, date: Date(), amount: 50)
print("Models work! Account: \(testAccount.name), Memo: \(testTransaction.memo ?? "none")")
```

If this compiles, your models are working!

## Common Issues

### Issue: "Duplicate symbols" error
**Solution:** You have MoneyModels defined in multiple places. Search entire project for `struct MoneyAccount` and remove duplicates.

### Issue: Still can't find MoneyAccount
**Solution:** The file might have the wrong encoding or invisible characters. Delete the file and recreate it.

### Issue: Packages keep showing as missing
**Solution:** 
1. Delete Package.resolved file in Finder
2. In Xcode: File → Packages → Reset Package Caches
3. File → Packages → Resolve Package Versions

### Issue: "Module 'MSAL' not found"
**Solution:** Make sure AuthManager.swift imports MSAL correctly:
```swift
import MSAL
```

## Expected Final State

After successful fix:

```
✓ MSAL package: Added and resolved
✓ BigInt package: Added and resolved
✓ MoneyModels.swift: In project and target
✓ MoneyAccount: Defined with id, name, beginningBalance
✓ MoneyTransaction: Defined with id, accountId, date, amount, memo, etc.
✓ All files compile without errors
✓ App runs successfully
```

## Still Having Issues?

If you still see errors after following ALL steps above:

1. Take a screenshot of:
   - The error panel (bottom of Xcode)
   - Project Navigator showing MoneyModels.swift
   - File Inspector for MoneyModels.swift

2. Check these files exist and are in target:
   - MoneyModels.swift ← MUST exist
   - MoneyFileService.swift
   - AccountsView.swift
   - TransactionsView.swift
   - NewTransactionView.swift

3. Verify you can see MSAL and BigInt under "Package Dependencies" in Project Navigator

4. Try creating a brand new Swift file to test:
   ```swift
   import Foundation
   
   // If this compiles, models are working
   let test = MoneyAccount(id: 1, name: "Test", beginningBalance: 0)
   ```

---

**Most likely issue:** MoneyModels.swift doesn't exist in your actual Xcode project, only in the code you've shared with me. Create it following Option C above.
