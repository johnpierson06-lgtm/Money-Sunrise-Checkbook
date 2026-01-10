# MDBTools Integration Guide

## Overview

You now have **two approaches** to read data from Microsoft Money .mny files:

1. **CLI Approach (Recommended for Development)** - Uses `mdb-export` command-line tool
2. **Library Approach** - Links directly to libmdb.dylib

## Quick Start: CLI Approach (Easiest)

### Step 1: Install mdbtools via Homebrew

```bash
brew install mdbtools
```

### Step 2: Verify installation

```bash
which mdb-export
# Should output: /opt/homebrew/bin/mdb-export (Apple Silicon)
# or: /usr/local/bin/mdb-export (Intel Mac)

mdb-export --help
```

### Step 3: Update MDBToolsCLI.swift if needed

If your mdb-export is not at `/opt/homebrew/bin/mdb-export`, update the path in `MDBToolsCLI.swift`:

```swift
static let mdbExportPath = "/your/path/to/mdb-export"
```

### Step 4: Build and Run!

That's it! Your app will now:
1. Use MSAL to authenticate with OneDrive
2. Let you browse and select a .mny file
3. Download and decrypt the file
4. Use mdb-export to read the ACCT table
5. Display real account names and balances!

### How It Works

The app automatically detects if `mdb-export` is available and uses it:

```
MoneyFileService.readAccountSummaries()
  ↓
  Checks if MDBToolsCLI.isAvailable()
  ↓
  If YES: Use mdb-export CLI
  If NO: Try library approach (falls back to sample data)
```

## Advanced: Library Approach (For Production)

If you want to link directly to libmdb (no subprocess calls), follow these steps:

### Step 1: Install mdbtools

```bash
brew install mdbtools glib
```

### Step 2: Find library paths

```bash
brew list mdbtools | grep libmdb
brew --prefix glib
pkg-config --cflags --libs glib-2.0
```

Typical paths:
- **Library**: `/opt/homebrew/lib/libmdb.dylib`
- **Headers**: `/opt/homebrew/include`
- **GLib**: `/opt/homebrew/opt/glib/lib`

### Step 3: Configure Xcode Build Settings

1. Select your target → Build Settings
2. **Header Search Paths**: Add `/opt/homebrew/include`
3. **Library Search Paths**: Add `/opt/homebrew/lib`
4. **Other Linker Flags**: Add `-lmdb -lglib-2.0`
5. **Framework Search Paths**: Add `/opt/homebrew/opt/glib/lib` (if needed)

### Step 4: Remove Conflicting Files

In Xcode, remove these files from your target (or delete them):
- `mdbtools_stubs.c`
- `JetDatabaseReader.swift` (optional, not used with mdbtools)

### Step 5: Verify module.modulemap

Make sure your `module.modulemap` looks like this:

```
module mdbtools_c [system] {
  header "MoneyMDBHelpers.h"
  link "mdb"
  link "glib-2.0"
  export *
}
```

### Step 6: Build and Test

Build your project. If you get linker errors, double-check the paths in Step 2.

## Troubleshooting

### "mdb_open: undefined symbol"

- **Solution**: Library not linked properly
- Check: Other Linker Flags includes `-lmdb`
- Check: Library Search Paths includes mdbtools location

### "glib.h: file not found"

- **Solution**: Install glib and add its include path
```bash
brew install glib
```
- Add to Header Search Paths: `/opt/homebrew/include/glib-2.0`
- Also add: `/opt/homebrew/lib/glib-2.0/include`

### "Cannot find 'mdbtools_c' in scope"

- **Solution**: Make sure `MoneyMDBHelpers.c` is added to your target
- Check: module.modulemap is in the right location
- Verify: Import Search Paths includes the directory with module.modulemap

### CLI approach: "mdbtools not installed"

```bash
brew install mdbtools
# Then update the path in MDBToolsCLI.swift if needed
```

### CLI approach works but library doesn't

This is normal! The CLI approach is simpler. For development and testing, CLI is recommended.
For production (App Store distribution), you'll need the library approach or implement a pure Swift parser.

## Current Status

✅ **Working Now (with CLI approach)**:
- MSAL authentication
- OneDrive file browsing
- File download
- Decryption validation
- **Reading real ACCT data** (account names, balances)
- Displaying accounts in UI

⚠️ **Partially Implemented**:
- Transaction reading (TRN table) - code exists but needs testing

❌ **Not Yet Implemented**:
- Balance calculation (opening balance + sum of transactions)
- Favorite account flagging
- Transaction categories (CAT table)
- Transaction entry

## Next Steps

1. **Test your app** - Run it and verify you see real account data
2. **Implement transaction reading** - Already coded in `MoneyMDB+CLI.swift`
3. **Calculate current balances** - Sum transactions to get current balance
4. **Add transaction view** - Show transactions for each account

## Files Reference

### CLI Approach (Recommended):
- `MDBToolsCLI.swift` - Command-line interface to mdb-export
- `MoneyMDB+CLI.swift` - CLI-based reading methods
- `MoneyFileService 2.swift` - Automatically uses CLI if available

### Library Approach:
- `MoneyMDBHelpers.h` - C wrapper functions
- `MoneyMDBHelpers.c` - C wrapper implementation
- `MoneyMDB.swift` - Swift interface with #if canImport(mdbtools_c)
- `module.modulemap` - Module definition

### Support Files:
- `mdbtools.h` - mdbtools library header
- `mdbsql.h` - SQL interface header
- `mdbfakeglib.h` - GLib compatibility

## Questions?

If you see:
- ✅ "DECRYPTION SUCCESSFUL" in console → Decryption is working!
- ✅ "Read N accounts from ACCT table" → mdbtools is working!
- ✅ Real account names in UI → Everything is working!

If you see:
- ⚠️ "Returning sample data" → mdbtools not properly configured (try CLI approach)
- ❌ Linker errors → Library not linked (use CLI approach or fix build settings)
