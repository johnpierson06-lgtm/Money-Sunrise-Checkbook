# 📱 CheckbookApp - Complete View & Data Flow Hierarchy

## 🎯 App Entry Point & Navigation Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                        @main CheckbookAppApp                         │
│                     (CheckbookAppApp.swift)                          │
│                                                                       │
│  WindowGroup {                                                       │
│    NavigationStack {                                                 │
│      LoginView() ← STARTING POINT                                   │
│    }                                                                 │
│  }                                                                   │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                          1. LoginView                                │
│                        (LoginView.swift)                             │
├─────────────────────────────────────────────────────────────────────┤
│ State:                                                               │
│  • isSignedIn: Bool                                                  │
│  • errorMessage: String?                                             │
│  • presenterVC: UIViewController?                                    │
│                                                                       │
│ Dependencies:                                                        │
│  → AuthManager.shared.signIn()                                       │
│  → AuthManager.shared.acquireTokenSilent()                           │
│  → ViewControllerResolver (helper)                                   │
│                                                                       │
│ Actions:                                                             │
│  • "Sign in with Microsoft" button → MSAL OAuth                     │
│  • onAppear: Try silent token acquisition                           │
│                                                                       │
│ Navigation:                                                          │
│  If authenticated → NavigationLink to FileSelectionView             │
└───────────────────────────────┬─────────────────────────────────────┘
                                │ (when isSignedIn = true)
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      2. FileSelectionView                            │
│                   (FileSelectionView.swift)                          │
├─────────────────────────────────────────────────────────────────────┤
│ State:                                                               │
│  • items: [OneDriveModels.Item]                                      │
│  • path: [OneDriveModels.Item]                                       │
│  • breadcrumbs: [OneDriveModels.Item]                               │
│  • currentFolderId: String?                                          │
│  • accessToken: String?                                              │
│  • errorMessage: String?                                             │
│  • isLoading: Bool                                                   │
│  • navigateToAccounts: Bool                                          │
│                                                                       │
│ Dependencies:                                                        │
│  → OneDriveModels.Item                                               │
│  → AuthManager.shared.acquireTokenSilent()                           │
│  → OneDrive API (list folder contents)                              │
│  → OneDriveFileManager.shared.saveFile()                            │
│                                                                       │
│ UI Elements:                                                         │
│  • List of folders (navigable)                                      │
│  • List of .mny files with "Select" button                          │
│  • Breadcrumb navigation in title                                   │
│  • "Change account" button (signs out)                              │
│                                                                       │
│ Actions:                                                             │
│  • Click folder → Load children                                     │
│  • Click .mny file "Select" → Download & save file                  │
│  • "Change account" → Sign out & return to login                    │
│                                                                       │
│ Navigation:                                                          │
│  After file selection → NavigationLink to AccountsView              │
└───────────────────────────────┬─────────────────────────────────────┘
                                │ (after selecting .mny file)
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        3. AccountsView                               │
│                      (AccountsView.swift)                            │
├─────────────────────────────────────────────────────────────────────┤
│ State:                                                               │
│  • accounts: [UIAccount]                                             │
│  • isLoading: Bool                                                   │
│  • errorMessage: String?                                             │
│  • showPasswordPrompt: Bool                                          │
│  • tempPassword: String                                              │
│                                                                       │
│ Dependencies:                                                        │
│  → MoneyFileService.decryptFile()                                    │
│  → MoneyFileService.readAccountSummaries()                           │
│  → PasswordStore.shared                                              │
│  → OneDriveFileManager.shared.localURLForSavedFile()                │
│                                                                       │
│ Data Models:                                                         │
│  → UIAccount { id, name, openingBalance, currentBalance }           │
│                                                                       │
│ UI Elements:                                                         │
│  • List of accounts with current balances                           │
│  • "Refresh" button                                                  │
│  • Password prompt alert (if needed)                                │
│                                                                       │
│ Actions:                                                             │
│  • onAppear: Load & decrypt Money file                              │
│  • loadAccounts(): Parse ACCT + TRN tables                          │
│  • refreshAccounts(): Reload data                                   │
│  • Tap account → Navigate to TransactionsView                       │
│                                                                       │
│ Navigation:                                                          │
│  Tap account → NavigationLink to TransactionsView(account)          │
└───────────────────────────────┬─────────────────────────────────────┘
                                │ (tap specific account)
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      4. TransactionsView                             │
│                   (TransactionsView.swift)                           │
├─────────────────────────────────────────────────────────────────────┤
│ Input:                                                               │
│  • account: UIAccount (passed from AccountsView)                    │
│                                                                       │
│ State:                                                               │
│  • transactions: [MoneyTransaction]                                  │
│  • isLoading: Bool                                                   │
│  • errorMessage: String?                                             │
│  • showNewTransaction: Bool                                          │
│                                                                       │
│ Dependencies:                                                        │
│  → MoneyFileService.decryptFile()                                    │
│  → MoneyFileParser.parseTransactions(forAccount:)                    │
│  → MoneyFileParser.parseCategories()                                 │
│  → MoneyFileParser.parsePayees()                                     │
│                                                                       │
│ UI Elements:                                                         │
│  • List of transactions for the account                             │
│  • Each transaction shows: date, payee, category, amount            │
│  • "Add Transaction" button                                         │
│                                                                       │
│ Actions:                                                             │
│  • onAppear: Load transactions for this account                     │
│  • "Add Transaction" → Show NewTransactionView                      │
│                                                                       │
│ Navigation:                                                          │
│  "Add Transaction" → Sheet with NewTransactionView                  │
└───────────────────────────────┬─────────────────────────────────────┘
                                │ (tap "Add Transaction")
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                   5. NewTransactionView                              │
│                 (NewTransactionView.swift)                           │
├─────────────────────────────────────────────────────────────────────┤
│ Input:                                                               │
│  • account: UIAccount                                                │
│  • categories: [MoneyCategory]                                       │
│  • payees: [MoneyPayee]                                              │
│                                                                       │
│ State:                                                               │
│  • date: Date                                                        │
│  • amount: Decimal                                                   │
│  • selectedPayee: MoneyPayee?                                        │
│  • selectedCategory: MoneyCategory?                                  │
│  • memo: String                                                      │
│                                                                       │
│ UI Elements:                                                         │
│  • Date picker                                                       │
│  • Amount text field                                                 │
│  • Payee picker                                                      │
│  • Category picker                                                   │
│  • Memo text field                                                   │
│  • "Save" / "Cancel" buttons                                         │
│                                                                       │
│ Actions:                                                             │
│  • "Save" → Create transaction, write to DB (future)                │
│  • "Cancel" → Dismiss sheet                                          │
└─────────────────────────────────────────────────────────────────────┘


## 🔄 Alternative/Legacy Views (Not Currently Used)

┌─────────────────────────────────────────────────────────────────────┐
│                     MainCheckbookView                                │
│                  (MainCheckbookView.swift)                           │
├─────────────────────────────────────────────────────────────────────┤
│ NOTE: This view exists but is NOT in the current navigation flow    │
│       It was part of an earlier implementation                       │
│                                                                       │
│ Input:                                                               │
│  • accessToken: String                                               │
│  • fileRef: OneDriveModels.FileRef                                   │
│                                                                       │
│ Similar to AccountsView but with different data loading pattern     │
└─────────────────────────────────────────────────────────────────────┘

```

---

## 📊 Data Services & Models Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        SERVICE LAYER                                 │
└─────────────────────────────────────────────────────────────────────┘

AuthManager (AuthManager.swift)
├─ signIn() → MSAL authentication
├─ acquireTokenSilent() → Get cached token
├─ signOut() → Clear tokens
└─ Used by: LoginView, FileSelectionView

MoneyFileService (MoneyFileService.swift)
├─ download() → Download file from OneDrive
├─ decryptFile() → Decrypt Money file
├─ readAccountSummaries() → Parse ACCT + TRN tables
├─ ensureLocalFile() → Get local file URL
└─ Used by: AccountsView, TransactionsView

MoneyFileParser (MoneyFileParser.swift)
├─ parseAccounts() → Read ACCT table
├─ parseTransactions() → Read TRN table
├─ parseCategories() → Read CAT table
├─ parsePayees() → Read PAY table
├─ calculateBalance() → Sum transactions
└─ Uses: SimpleMDBParser (mdbtools wrapper)

SimpleMDBParser (SimpleMDBParser.swift)
├─ readTable() → Low-level mdbtools access
├─ readAccounts() → Read ACCT rows
├─ readTransactions() → Read TRN rows
└─ Uses: mdbtools C library (backend.c, catalog.c, data.c, etc.)

OneDriveFileManager (OneDriveFileManager.swift)
├─ saveFile() → Save downloaded file locally
├─ localURLForSavedFile() → Get saved file path
└─ Used by: FileSelectionView, AccountsView

PasswordStore (PasswordStore.swift)
├─ save() → Store password in Keychain
├─ load() → Retrieve password
└─ Used by: AccountsView, MoneyFileService

MoneyDecryptorBridge (MoneyDecryptorBridge.swift)
├─ decryptToTempFile() → Decrypt .mny to .mdb
└─ Used by: MoneyFileService

```

---

## 🗃️ Data Models

```
┌─────────────────────────────────────────────────────────────────────┐
│                         DATA MODELS                                  │
└─────────────────────────────────────────────────────────────────────┘

MoneyAccount (MoneyModels.swift)
├─ id: Int (hacct from ACCT table)
├─ name: String (szFull from ACCT table)
├─ beginningBalance: Decimal (amtOpen from ACCT table)
└─ Used by: MoneyFileParser, AccountsView

MoneyTransaction (MoneyModels.swift)
├─ id: Int (htrn from TRN table)
├─ accountId: Int (hacct from TRN table)
├─ date: Date (dtrans from TRN table)
├─ amount: Decimal (amt from TRN table)
├─ payeeId: Int? (hpay from TRN table)
├─ categoryId: Int? (hcat from TRN table)
├─ memo: String? (szMemo from TRN table)
└─ Used by: MoneyFileParser, TransactionsView

MoneyCategory (MoneyModels.swift)
├─ id: Int (hcat from CAT table)
├─ name: String (szName from CAT table)
└─ Used by: MoneyFileParser, TransactionsView, NewTransactionView

MoneyPayee (MoneyModels.swift)
├─ id: Int (hpay from PAY table)
├─ name: String (szName from PAY table)
└─ Used by: MoneyFileParser, TransactionsView, NewTransactionView

UIAccount (AccountsView.swift)
├─ id: Int
├─ name: String
├─ openingBalance: Decimal
├─ currentBalance: Decimal (calculated: opening + Σ transactions)
└─ Used by: AccountsView, TransactionsView (UI layer model)

OneDriveModels.Item (OneDrive APIs)
├─ id: String
├─ name: String
├─ isFolder: Bool
└─ Used by: FileSelectionView

OneDriveModels.FileRef (OneDrive APIs)
├─ id: String
├─ name: String
├─ parentId: String
└─ Used by: FileSelectionView, MainCheckbookView

```

---

## 🗂️ Database Tables → Models Mapping

```
Microsoft Money Database Tables (MSISAM format)
│
├─ ACCT Table (Accounts)
│  ├─ hacct (Int) → MoneyAccount.id
│  ├─ szFull (String) → MoneyAccount.name
│  ├─ amtOpen (Decimal) → MoneyAccount.beginningBalance
│  └─ fFavorite (Bool) → (not currently used)
│
├─ TRN Table (Transactions)
│  ├─ htrn (Int) → MoneyTransaction.id
│  ├─ hacct (Int) → MoneyTransaction.accountId
│  ├─ dtrans (Date) → MoneyTransaction.date
│  ├─ amt (Decimal) → MoneyTransaction.amount
│  ├─ hpay (Int?) → MoneyTransaction.payeeId
│  ├─ hcat (Int?) → MoneyTransaction.categoryId
│  └─ szMemo (String?) → MoneyTransaction.memo
│
├─ CAT Table (Categories)
│  ├─ hcat (Int) → MoneyCategory.id
│  └─ szName (String) → MoneyCategory.name
│
└─ PAY Table (Payees)
   ├─ hpay (Int) → MoneyPayee.id
   └─ szName (String) → MoneyPayee.name
```

---

## 🔄 Complete User Journey Flow

```
1. App Launch
   ↓
2. LoginView appears
   ├─ Try silent authentication (onAppear)
   │  ├─ Success → Auto-navigate to FileSelectionView
   │  └─ Fail → Show "Sign in with Microsoft" button
   └─ User taps "Sign in with Microsoft"
      ↓
3. MSAL OAuth Flow
   ├─ Browser/WebView appears
   ├─ User enters Microsoft credentials
   ├─ Consent to Files.Read, Files.ReadWrite scopes
   └─ Token received and cached
      ↓
4. FileSelectionView appears
   ├─ Load OneDrive root folder
   ├─ User navigates folders
   └─ User taps "Select" on a .mny file
      ├─ Download file from OneDrive
      ├─ Save locally
      └─ Navigate to AccountsView
         ↓
5. AccountsView appears
   ├─ Load local .mny file
   ├─ Decrypt file → .mdb
   ├─ Parse ACCT table → Get accounts
   ├─ Parse TRN table → Get all transactions
   ├─ Calculate current balance for each account
   └─ Display list of accounts
      ├─ User taps an account
      ↓
6. TransactionsView appears
   ├─ Load transactions for selected account
   ├─ Load categories and payees
   ├─ Display transaction list
   └─ User taps "Add Transaction"
      ↓
7. NewTransactionView appears (sheet)
   ├─ User enters transaction details
   ├─ Taps "Save"
   ├─ Write to database (future implementation)
   ├─ Re-encrypt and upload (future implementation)
   └─ Dismiss and refresh TransactionsView
```

---

## 🔐 Authentication & File Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Authentication Flow                              │
└─────────────────────────────────────────────────────────────────────┘

LoginView
  ↓
AuthManager.signIn(scopes: ["Files.Read", "Files.ReadWrite"])
  ↓
MSAL Library (Microsoft Authentication)
  ↓
Browser/WebView OAuth Flow
  ↓
Access Token stored in AuthManager
  ↓
Navigate to FileSelectionView

┌─────────────────────────────────────────────────────────────────────┐
│                        File Flow                                     │
└─────────────────────────────────────────────────────────────────────┘

FileSelectionView
  ↓
Select .mny file
  ↓
Download via OneDrive API
  ↓
OneDriveFileManager.saveFile() → /Documents/money.mny
  ↓
AccountsView loads file
  ↓
MoneyDecryptorBridge.decryptToTempFile()
  ├─ Read encrypted .mny
  ├─ Decrypt pages
  └─ Write /tmp/money-decrypted-[UUID].mdb
     ↓
SimpleMDBParser.readTable("ACCT")
  ↓
mdbtools C library
  ├─ mdb_open()
  ├─ mdb_read_catalog()
  ├─ mdb_read_table()
  ├─ mdb_read_columns()
  └─ mdb_fetch_row()
     ↓
Return [[String: String]] rows
  ↓
MoneyFileParser.parseAccounts()
  ↓
Convert to [MoneyAccount]
  ↓
Display in AccountsView
```

---

## 📁 File & Folder Structure Summary

```
CheckbookApp/
│
├── App Entry
│   └── CheckbookAppApp.swift (@main)
│
├── Views (UI Layer)
│   ├── LoginView.swift ......................... Step 1: Authentication
│   ├── FileSelectionView.swift ................. Step 2: Choose .mny file
│   ├── AccountsView.swift ...................... Step 3: List accounts
│   ├── TransactionsView.swift .................. Step 4: Show transactions
│   ├── NewTransactionView.swift ................ Step 5: Add transaction
│   └── MainCheckbookView.swift ................. (Legacy - not used)
│
├── Services (Business Logic)
│   ├── AuthManager.swift ....................... MSAL authentication
│   ├── MoneyFileService.swift .................. File operations
│   ├── OneDriveFileManager.swift ............... Local file storage
│   ├── PasswordStore.swift ..................... Keychain storage
│   └── MoneyDecryptorBridge.swift .............. Decryption
│
├── Parsers (Data Layer)
│   ├── MoneyFileParser.swift ................... High-level parser
│   ├── SimpleMDBParser.swift ................... mdbtools wrapper
│   ├── MDBParser.swift ......................... ❌ DELETE (unused)
│   ├── JetDatabaseReader.swift ................. ❌ DELETE (unused)
│   └── MSISAMTableReader.swift ................. ❌ DELETE (unused)
│
├── Models (Data Structures)
│   └── MoneyModels.swift ....................... MoneyAccount, MoneyTransaction,
│                                                   MoneyCategory, MoneyPayee
│
└── MDBTools (C Library)
    ├── C Source Files .......................... backend.c, catalog.c, data.c, etc.
    ├── mdbfakeglib.c ........................... Minimal GLib
    ├── MoneyMDBHelpers.c ....................... Helper functions
    └── Headers ................................. mdbtools.h, mdbfakeglib.h, etc.
```

---

This map shows every view, service, model, and data flow in your CheckbookApp!

