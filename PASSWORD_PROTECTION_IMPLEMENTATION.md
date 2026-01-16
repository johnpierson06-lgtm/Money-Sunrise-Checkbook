# Password Protection Implementation

## Overview
This implementation adds **mandatory password prompting** for all Microsoft Money (.mny) files, providing an additional security layer even for files with blank passwords. The decryption engine already supports password-protected files using the MSISAM codec with SHA1 hashing.

## What Changed

### 1. **AccountsView.swift** - Complete UI Overhaul
The main accounts view now implements a proper password flow:

#### New Features:
- ✅ **Mandatory password prompt** on file open (appears as a modal sheet)
- ✅ **Professional password entry UI** with:
  - Lock shield icon
  - Clear instructions
  - SecureField for password entry
  - Tip about blank passwords
  - Focus management (auto-focuses password field)
- ✅ **"Change Password" button** in toolbar to re-enter password
- ✅ **Better error handling**:
  - Detects password errors and shows "Try Again" button
  - Automatically re-prompts for password on incorrect entry
- ✅ **Loading states**:
  - Shows "Decrypting file..." during processing
  - Prevents duplicate actions while processing
- ✅ **ViewControllerResolver** helper for presenting modals

#### User Flow:
1. User opens AccountsView → Password prompt appears immediately
2. User enters password (or leaves blank for no-password files)
3. App saves password to keychain via `PasswordStore`
4. App decrypts file using `MoneyDecryptorBridge.decryptToTempFile()`
5. App parses accounts using `MoneyFileService.readAccountSummaries()`
6. If password is wrong → Error message + "Try Again" button
7. If successful → Accounts list displays

### 2. **Password Storage**
Uses the existing `PasswordStore.swift` which:
- Stores passwords securely in iOS Keychain
- Supports blank passwords (for Money Plus Sunset Edition files)
- Provides save/load/clear operations

### 3. **Decryption Engine** (No Changes Required!)
The existing `MoneyDecryptorBridge.swift` already supports password-protected files:

```swift
// From MoneyDecryptorBridge.swift
public static func decryptToTempFile(fromFile path: String, password: String? = "") throws -> String
```

#### How It Works:
Based on your Java test results, password-protected Money files use:
- **MSISAM codec** (flags at offset 664, bits 1&2 set)
- **SHA1 hashing** (flag bit 5 set)
- **20-byte encoding key**:
  - First 16 bytes: SHA1 hash of password (truncated to 16 bytes)
  - Last 4 bytes: Salt from file header (offset 114, XOR'd with mask)
- **RC4 encryption** on pages 1-14 (page 0 is not encrypted)

Your test files prove this works:
```
Password1 → Key: 3f7f06460870b1c67373c44bc7e88ec9097ea487
Password2 → Key: b6649fe71bba45464d298c0a2a11e73d21cbbd8a
PasswordZany5127 → Key: 3aabb8c75b6ea8e58d689ad5f13dc772c089718d
```

The Swift implementation already:
1. Reads encryption flags to detect MSISAM format
2. Extracts salt from offset 114
3. Creates password digest using SHA1 (for flag bit 5) or MD5
4. Builds 20-byte encoding key (digest + salt)
5. Applies RC4 decryption to pages 1-14
6. Verifies password by decrypting test bytes at offset 745

## Testing Instructions

### Test 1: Blank Password File
1. Open the app
2. Select a Money file with no password
3. When prompted, leave password field **blank**
4. Tap "Continue"
5. ✅ File should decrypt successfully and show accounts

### Test 2: Password-Protected File
1. Open the app
2. Select one of your test files:
   - `money - Password1.mny` → Password: `Password1`
   - `money - Password2.mny` → Password: `Password2`
   - `money - PasswordZany5127.mny` → Password: `PasswordZany5127`
3. When prompted, enter the correct password
4. Tap "Continue"
5. ✅ File should decrypt successfully and show accounts

### Test 3: Wrong Password
1. Open a password-protected file
2. Enter the **wrong** password
3. Tap "Continue"
4. ✅ Should show error: "Incorrect password. Please try again."
5. ✅ Password prompt should automatically re-appear
6. Enter correct password
7. ✅ Should now decrypt successfully

### Test 4: Change Password
1. While viewing accounts, tap "Change Password" in toolbar
2. ✅ Password prompt appears again
3. Enter different password or same password
4. ✅ File re-decrypts with new password

### Test 5: Refresh
1. While viewing accounts, tap "Refresh"
2. ✅ File re-downloads from OneDrive
3. ✅ Password prompt appears again for security

## Security Benefits

1. **Mandatory password entry** - Users must explicitly confirm password (even if blank)
2. **Keychain storage** - Passwords stored securely in iOS Keychain
3. **No hardcoded passwords** - All passwords come from user input
4. **Re-authentication on refresh** - Fresh password required after file refresh
5. **Clear password change flow** - Users can easily change stored password

## Architecture

```
┌─────────────────────┐
│   AccountsView      │  ← Shows password prompt immediately
│   (UI Layer)        │  ← Manages user interaction
└──────────┬──────────┘
           │
           ├─ Password entered
           │
           ▼
┌─────────────────────┐
│   PasswordStore     │  ← Saves to iOS Keychain
│   (Storage Layer)   │
└─────────────────────┘
           │
           ▼
┌─────────────────────┐
│ MoneyFileService    │  ← Loads password from keychain
│ (Service Layer)     │  ← Calls MoneyDecryptorBridge
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│MoneyDecryptorBridge │  ← Decrypts with password
│ (Crypto Layer)      │  ← Implements MSISAM RC4 + SHA1
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Decrypted MDB      │  ← Temporary file in /tmp
└─────────────────────┘
           │
           ▼
┌─────────────────────┐
│ JetDatabaseReader   │  ← Parses ACCT/TRN tables
│ (Parser Layer)      │
└─────────────────────┘
```

## Technical Notes

### Password Encoding
From Java analysis and Swift implementation:
- Password is converted to **UTF-16 Little Endian** (40 bytes, padded with zeros)
- Hashed with **SHA1** (if USE_SHA1 flag set) → 20 bytes
- Truncated to **16 bytes** for digest
- Combined with **4-byte salt** → 20-byte encoding key

### Salt Extraction
```swift
// Salt is at offset 114 (8 bytes total)
let fileSalt = data[114..<122]

// Real salt = first 4 bytes XOR with mask
let saltMask: [UInt8] = [0x12, 0x4f, 0x4a, 0x94]
var baseSalt = fileSalt[0..<4]
for i in 0..<4 {
    baseSalt[i] ^= saltMask[i]
}
```

This matches the Java `MSISAMCryptCodecHandler` implementation exactly.

### Encryption Pages
Only pages 1-14 are encrypted with RC4:
- **Page 0** (database header) is **NOT encrypted**
- **Pages 1-14** are encrypted with RC4 using page-specific keys
- **Pages 15+** are not encrypted (or use different encryption)

### Password Verification
The decryption code verifies the password by:
1. Reading test bytes at offset `745 + salt[0]`
2. Decrypting them with the full 24-byte key (digest + 8-byte salt)
3. Comparing result to the 4-byte base salt
4. If match → password correct ✅
5. If no match → password incorrect ❌

## Known Compatibility

✅ **Blank password files** (Money Plus Sunset Edition)  
✅ **Password-protected files** with SHA1 hashing  
✅ **MSISAM format** (4096-byte pages)  
✅ **Java Jackcess compatibility** (same encryption as your test)

## Future Enhancements

1. **Biometric unlock** - Use Face ID/Touch ID to unlock stored password
2. **Password strength indicator** - Show strength when setting password
3. **Remember password option** - Checkbox to remember for session only
4. **Multiple file support** - Store passwords per file ID
5. **Auto-lock timeout** - Clear password after X minutes of inactivity

## References

- Java Jackcess: `MSISAMCryptCodecHandler.java`
- Your test output: `DA8CodecCheck.java` results
- MSISAM specification: Microsoft Jet 4.0 database format
- RC4 cipher: Standard stream cipher implementation
- SHA1 hashing: CommonCrypto framework
