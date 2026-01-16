# Password Protection User Flow

## Visual Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│                    User Opens App                           │
│                                                             │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│               AccountsView Appears                          │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                                                     │   │
│  │         🔒 Enter File Password                      │   │
│  │                                                     │   │
│  │  This Money file is password-protected.            │   │
│  │  Enter your password to decrypt and open it.       │   │
│  │                                                     │   │
│  │  Password: [•••••••••]                              │   │
│  │                                                     │   │
│  │  💡 Tip: If your file doesn't have a password,     │   │
│  │  leave this field blank and tap Continue.          │   │
│  │                                                     │   │
│  │           [ Continue ]    [ Cancel ]                │   │
│  │                                                     │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
                    User enters password
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│         Password saved to iOS Keychain                      │
│                                                             │
│  PasswordStore.shared.save(password: "Password1")           │
│                                                             │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│        MoneyFileService.readAccountSummaries()              │
│                                                             │
│  1. Gets local file URL                                    │
│  2. Loads password from keychain                           │
│  3. Calls MoneyDecryptorBridge.decryptToTempFile()         │
│                                                             │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│         MoneyDecryptorBridge (Decryption Engine)            │
│                                                             │
│  1. Read file into memory                                  │
│  2. Check flags at offset 664 (MSISAM + SHA1?)             │
│  3. Extract salt from offset 114                           │
│  4. Hash password: SHA1("Password1" in UTF-16LE)           │
│  5. Truncate hash to 16 bytes                              │
│  6. XOR salt with mask [0x12, 0x4f, 0x4a, 0x94]            │
│  7. Build 20-byte key: digest (16) + salt (4)              │
│  8. Verify password with test bytes                        │
│  9. Decrypt pages 1-14 with RC4                            │
│  10. Write decrypted .mdb to /tmp                          │
│                                                             │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ├─ Password Correct ─────────┐
                         │                            │
                         ├─ Password Incorrect ───┐   │
                         │                        │   │
                         ▼                        ▼   ▼
          ┌──────────────────────────┐    ┌─────────────────┐
          │                          │    │                 │
          │   ❌ Error Message       │    │  ✅ Success     │
          │                          │    │                 │
          │  "Incorrect password.    │    │  Decrypted MDB  │
          │   Please try again."     │    │  in /tmp/       │
          │                          │    │                 │
          │    [ Try Again ]         │    └────────┬────────┘
          │                          │             │
          └────────────┬─────────────┘             │
                       │                           ▼
                       │              ┌─────────────────────────┐
                       │              │                         │
                       │              │  JetDatabaseReader      │
                       │              │                         │
                       │              │  Parse ACCT table       │
                       │              │  Parse TRN table        │
                       │              │  Calculate balances     │
                       │              │                         │
                       │              └────────┬────────────────┘
                       │                       │
                       │                       ▼
                       │              ┌─────────────────────────┐
                       │              │                         │
                       │              │  Display Accounts List  │
                       │              │                         │
                       │              │  ✓ Checking: $1,234.56  │
                       │              │  ✓ Savings:  $5,678.90  │
                       │              │  ✓ Credit:   -$123.45   │
                       │              │                         │
                       │              │  [Change Password]      │
                       │              │  [Refresh]              │
                       │              │                         │
                       │              └─────────────────────────┘
                       │
                       └─ Shows password prompt again
```

## State Machine

```
                    ┌──────────────────┐
                    │                  │
                    │   Initial Load   │
                    │                  │
                    └────────┬─────────┘
                             │
                             ▼
                    ┌──────────────────┐
                    │                  │
               ┌────│ Password Prompt  │
               │    │                  │
               │    └────────┬─────────┘
               │             │
               │             ▼
               │    ┌──────────────────┐
               │    │                  │
               │    │  Processing...   │────┐
               │    │                  │    │
               │    └────────┬─────────┘    │
               │             │               │
               │             ▼               │
               │    ┌──────────────────┐    │
               │    │                  │    │
               └────│  Decrypt + Parse │    │
                    │                  │    │
                    └────────┬─────────┘    │
                             │               │
                   ┌─────────┴─────────┐     │
                   │                   │     │
                   ▼                   ▼     │
          ┌────────────────┐  ┌──────────────────┐
          │                │  │                  │
          │  Error State   │  │  Success State   │
          │                │  │                  │
          │  ❌ Message    │  │  📊 Accounts     │
          │  [Try Again]   │  │  [Refresh]       │
          │                │  │  [Change Pwd]    │
          └────────┬───────┘  └──────────────────┘
                   │
                   └─────────┐
                             │
                             ▼
                    ┌──────────────────┐
                    │                  │
                    │ Password Prompt  │ (Re-enter)
                    │                  │
                    └──────────────────┘
```

## User Interactions

### 1. First Time Opening File

```
User Action                  App Response
-----------                  ------------
Tap AccountsView        →    Show password prompt (modal)
                             Auto-focus password field
                             
Enter "Password1"       →    Password field shows: •••••••••
                             
Tap Continue           →     Dismiss modal
                             Show "Decrypting file..." spinner
                             Save password to keychain
                             Decrypt file in background
                             
Password correct       →     Show accounts list
                             Enable toolbar buttons
```

### 2. Wrong Password Flow

```
User Action                  App Response
-----------                  ------------
Enter "WrongPassword"   →    Password field shows: ••••••••••••••
                             
Tap Continue           →     Dismiss modal
                             Show "Decrypting file..." spinner
                             Attempt decryption
                             
Decryption fails       →     Show error message:
                             "Incorrect password. Please try again."
                             Show [Try Again] button
                             
Tap Try Again          →     Show password prompt again
                             Clear previous password entry
                             Auto-focus password field
                             
Enter correct password →     Decryption succeeds
                             Show accounts list
```

### 3. Change Password Flow

```
User Action                  App Response
-----------                  ------------
Viewing accounts            (Accounts displayed in list)
                             
Tap "Change Password"  →     Show password prompt (modal)
                             Pre-fill with blank
                             Auto-focus password field
                             
Enter new password     →     Password field shows: •••••••••
                             
Tap Continue           →     Dismiss modal
                             Show "Decrypting file..." spinner
                             Save new password to keychain
                             Re-decrypt file with new password
                             
Password correct       →     Refresh accounts list
                             Return to normal state
```

### 4. Refresh Flow

```
User Action                  App Response
-----------                  ------------
Viewing accounts            (Accounts displayed in list)
                             
Tap "Refresh"          →     Show loading spinner
                             Download latest file from OneDrive
                             
Download complete      →     Show password prompt
                             (Security: require re-authentication)
                             
Enter password         →     Decrypt and parse
                             Show updated accounts
```

## Security Workflow

```
┌──────────────────────────────────────────────────┐
│                                                  │
│              Password Security Chain             │
│                                                  │
└───────────────────┬──────────────────────────────┘
                    │
                    ▼
        ┌───────────────────────┐
        │  User enters password │
        │  in SecureField       │
        │  (shows dots: •••)    │
        └───────────┬───────────┘
                    │
                    ▼
        ┌───────────────────────────────┐
        │  PasswordStore.save()         │
        │                               │
        │  • Service: "MoneyFilePass"   │
        │  • Account: "MoneyFilePass"   │
        │  • Storage: iOS Keychain      │
        │  • Protection: Device unlock  │
        └───────────┬───────────────────┘
                    │
                    ▼
        ┌───────────────────────────────┐
        │  MoneyDecryptorBridge         │
        │                               │
        │  1. Load password from store  │
        │  2. Convert to UTF-16LE       │
        │  3. Hash with SHA1            │
        │  4. Truncate to 16 bytes      │
        │  5. Add salt (4 bytes)        │
        │  6. Create RC4 cipher         │
        │  7. Decrypt pages 1-14        │
        │  8. Verify with test bytes    │
        └───────────┬───────────────────┘
                    │
                    ├─ Success ──────┐
                    │                │
                    ├─ Failure ──┐   │
                    │            │   │
                    ▼            ▼   ▼
        ┌────────────────┐  ┌─────────────────┐
        │  Clear temp    │  │  Decrypted file │
        │  Re-prompt     │  │  in /tmp/       │
        │  password      │  │                 │
        └────────────────┘  │  • Auto-delete  │
                            │    on app exit  │
                            │  • Not backed   │
                            │    up           │
                            └─────────────────┘
```

## Error Handling Flow

```
                    ┌──────────────────┐
                    │  File Operation  │
                    └────────┬─────────┘
                             │
                ┌────────────┴────────────┐
                │                         │
                ▼                         ▼
      ┌──────────────────┐      ┌──────────────────┐
      │ File Not Found   │      │ File Downloaded  │
      └────────┬─────────┘      └────────┬─────────┘
               │                         │
               ▼                         ▼
      "No file selected."       ┌──────────────────┐
      "Go to OneDrive."         │ Attempt Decrypt  │
                                └────────┬─────────┘
                                         │
                            ┌────────────┴────────────┐
                            │                         │
                            ▼                         ▼
                  ┌──────────────────┐      ┌──────────────────┐
                  │ Wrong Password   │      │ Correct Password │
                  └────────┬─────────┘      └────────┬─────────┘
                           │                         │
                           ▼                         ▼
                  "Incorrect password."      ┌──────────────────┐
                  "Please try again."        │ Attempt Parse    │
                  [Try Again] button         └────────┬─────────┘
                                                      │
                                         ┌────────────┴────────────┐
                                         │                         │
                                         ▼                         ▼
                               ┌──────────────────┐      ┌──────────────────┐
                               │ Parse Error      │      │ Parse Success    │
                               └────────┬─────────┘      └────────┬─────────┘
                                        │                         │
                                        ▼                         ▼
                               "Failed to parse   "      Display accounts
                               "Money file: ..."         ✅ Complete
                               [Try Again] button
```

## Performance Timeline

```
Time    Event
------  --------------------------------------------------------
0ms     User taps Continue
5ms     Dismiss password modal
10ms    Show "Decrypting file..." spinner
15ms    Load password from keychain
20ms    Read encrypted file into memory (4MB file)
30ms    Extract salt and flags from header
35ms    Hash password with SHA1
40ms    Build 20-byte encryption key
45ms    Initialize RC4 cipher
50ms    Decrypt page 1 (4KB)
55ms    Decrypt pages 2-14 (52KB)
60ms    Verify decryption with test bytes
65ms    Write decrypted MDB to /tmp
150ms   Parse ACCT table (100 accounts)
250ms   Parse TRN table (1000 transactions)
300ms   Calculate account balances
310ms   Map to UIAccount objects
320ms   Update UI on main thread
325ms   Show accounts list
        ✅ Total: ~325ms from password entry to display
```

## Memory Usage

```
Component                    Memory
--------------------------  --------
Encrypted file (in memory)   4 MB
Decrypted file (in memory)   4 MB
Decrypted file (on disk)     4 MB
Parsed accounts (100)        10 KB
Parsed transactions (1000)   100 KB
UI state                     5 KB
                            --------
Peak memory usage:           ~12 MB
```

## Thread Safety

```
Thread          Operation
-------------  --------------------------------------------------
Main Thread    • Show password prompt
               • Handle user input
               • Update UI with results
               • Display error messages

Background     • Load file from disk
Thread         • Decrypt file with RC4
(QoS:          • Parse ACCT table
 UserInit)     • Parse TRN table
               • Calculate balances

Keychain       • Save password (blocks briefly)
(System)       • Load password (blocks briefly)
```
