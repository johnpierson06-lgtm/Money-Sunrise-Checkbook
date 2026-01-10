# 📱 Quick Reference: App Navigation Flow

## 🎬 Simple View Hierarchy

```
START → LoginView → FileSelectionView → AccountsView → TransactionsView → NewTransactionView
         (Step 1)      (Step 2)           (Step 3)        (Step 4)          (Step 5)
```

---

## 🔍 Detailed Navigation Map

```
@main CheckbookAppApp
│
└─→ LoginView
    │
    ├─ Uses: AuthManager
    │         └─ MSAL authentication
    │
    └─→ FileSelectionView (after login)
        │
        ├─ Uses: OneDrive API, AuthManager
        │         └─ Browse folders, select .mny file
        │
        └─→ AccountsView (after file selection)
            │
            ├─ Uses: MoneyFileService, MoneyFileParser
            │         ├─ Decrypt .mny file
            │         ├─ Parse ACCT table → accounts
            │         └─ Parse TRN table → calculate balances
            │
            └─→ TransactionsView (tap account)
                │
                ├─ Uses: MoneyFileParser
                │         ├─ Parse TRN (filtered by account)
                │         ├─ Parse CAT (categories)
                │         └─ Parse PAY (payees)
                │
                └─→ NewTransactionView (tap "Add Transaction")
                    │
                    └─ Form to add new transaction
                       └─ Save → Update DB (future)
```

---

## 📊 Data Flow: File → Display

```
1. OneDrive
   ↓ (download)
2. Local Storage: money.mny (encrypted)
   ↓ (decrypt)
3. Temp File: money-decrypted-[UUID].mdb (MSISAM database)
   ↓ (parse with mdbtools)
4. Database Tables:
   ├─ ACCT → MoneyAccount[] → UIAccount[]
   ├─ TRN → MoneyTransaction[]
   ├─ CAT → MoneyCategory[]
   └─ PAY → MoneyPayee[]
   ↓ (display)
5. UI Views:
   ├─ AccountsView shows UIAccount[]
   └─ TransactionsView shows MoneyTransaction[]
```

---

## 🏗️ Service Dependencies

```
Views → Services → Parsers → C Library

LoginView
  └─→ AuthManager (MSAL)

FileSelectionView
  ├─→ AuthManager (tokens)
  └─→ OneDriveFileManager (save file)

AccountsView
  ├─→ MoneyFileService
  │    └─→ MoneyFileParser
  │         └─→ SimpleMDBParser
  │              └─→ mdbtools C library
  └─→ PasswordStore (Keychain)

TransactionsView
  └─→ MoneyFileParser
       └─→ SimpleMDBParser
            └─→ mdbtools C library

NewTransactionView
  └─→ (Future: MoneyFileWriter)
```

---

## 🗂️ Files You Use vs Don't Use

### ✅ ACTIVE (In Navigation Flow):
- LoginView.swift
- FileSelectionView.swift
- AccountsView.swift
- TransactionsView.swift
- NewTransactionView.swift
- MoneyFileService.swift
- MoneyFileParser.swift
- SimpleMDBParser.swift
- AuthManager.swift
- MoneyModels.swift
- All mdbtools C files

### ❌ UNUSED (Can Delete):
- MainCheckbookView.swift (legacy, bypassed)
- MDBParser.swift (old broken parser)
- JetDatabaseReader.swift (old broken parser)
- MSISAMTableReader.swift (old broken parser)
- mdbtools-missing.c (if present)

---

## 🔑 Key Relationships

```
LoginView
  ├─ Creates: accessToken (via AuthManager)
  └─ Navigates to: FileSelectionView

FileSelectionView
  ├─ Uses: accessToken
  ├─ Downloads: money.mny file
  └─ Navigates to: AccountsView

AccountsView
  ├─ Loads: money.mny (from local storage)
  ├─ Decrypts to: money-decrypted-[UUID].mdb
  ├─ Parses: ACCT + TRN tables
  ├─ Creates: [UIAccount] with calculated balances
  └─ Navigates to: TransactionsView(account)

TransactionsView
  ├─ Receives: UIAccount (from AccountsView)
  ├─ Parses: TRN (filtered), CAT, PAY tables
  ├─ Creates: [MoneyTransaction]
  └─ Navigates to: NewTransactionView

NewTransactionView
  ├─ Receives: account, categories, payees
  └─ Creates: New transaction (future save)
```

---

See **APP_ARCHITECTURE_MAP.md** for complete details!
