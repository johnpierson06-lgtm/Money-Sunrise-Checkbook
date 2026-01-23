# CheckbookApp

An iOS application for managing Microsoft Money files with OneDrive integration.

## 🎯 Features

- ✅ **MSAL Authentication** - Secure OAuth2 login to Microsoft/OneDrive
- ✅ **OneDrive Integration** - Browse folders and select Money files
- ✅ **File Decryption** - Decrypt Microsoft Money Plus Sunset Edition files
- ✅ **Database Parsing** - Read MSISAM database format using mdbtools
- ✅ **Account Management** - View accounts, balances, and transactions
- ✅ **Native iOS** - Works on iPhone and iPad (iOS 16.0+)

## 🏗️ Architecture

### Components

```
CheckbookApp/
├── Authentication/
│   └── AuthManager.swift          # MSAL authentication
├── Services/
│   ├── MoneyFileService.swift     # File operations & parsing
│   └── MoneyDecryptor.swift       # Decryption logic
├── Models/
│   └── MoneyModels.swift          # Account, Transaction, Category, Payee
├── Parsers/
│   ├── SimpleMDBParser.swift      # Low-level mdbtools wrapper
│   └── MoneyFileParser.swift      # High-level Money file parser
└── MDBTools/
    ├── C Source Files/            # mdbtools library (compiled for iOS)
    ├── mdbfakeglib.c/h            # Minimal GLib implementation
    └── MoneyMDBHelpers.c/h        # C helper functions
```

### Data Flow

1. **Authenticate** → MSAL OAuth2 to OneDrive
2. **Select File** → Browse OneDrive folders
3. **Download** → Save .mny file locally
4. **Decrypt** → Convert encrypted file to MSISAM database
5. **Parse** → Use mdbtools to read database tables
6. **Display** → Show accounts, balances, transactions

## 🛠️ Technical Details

### Database Format

Microsoft Money files use **MSISAM** (Microsoft Indexed Sequential Access Method) database format:
- **ACCT** table - Accounts (hacct, szFull, amtOpen, fFavorite)
- **TRN** table - Transactions (htrn, hacct, dtrans, amt, hpay, hcat)
- **CAT** table - Categories (hcat, szName)
- **PAY** table - Payees (hpay, szName)

### MDBTools Integration

The app uses a **custom iOS build of mdbtools**:
- Compiled C library for MSISAM database access
- Minimal GLib implementation (mdbfakeglib)
- Swift bridging for C/Swift interop
- Supports UTF-16LE text encoding

### Key Technologies

- **Swift** - Primary language
- **SwiftUI** - UI framework
- **MSAL** - Microsoft Authentication Library
- **mdbtools** - Database parsing (C library)
- **CommonCrypto** - Decryption

## 📋 Requirements

- **Xcode** 14.0+
- **iOS** 16.0+
- **Swift** 5.7+
- **Swift Package Manager** dependencies:
  - MSAL (Microsoft Authentication Library)
  - BigInt (for decryption)

## 🚀 Setup

### 1. Clone Repository

```bash
git clone <your-repo-url>
cd CheckbookApp
```

### 2. Install Dependencies

Open `CheckbookApp.xcodeproj` in Xcode. Swift Package Manager will automatically resolve dependencies:
- MSAL
- BigInt

### 3. Configure MSAL

Update `AuthManager.swift` with your Azure AD app registration:
- Client ID
- Redirect URI
- Authority

### 4. Build & Run

1. Select a simulator or device
2. Press Cmd+B to build
3. Press Cmd+R to run

## 📦 Project Structure

### Swift Files

- `SimpleMDBParser.swift` - mdbtools wrapper for reading database tables
- `MoneyFileParser.swift` - Money-specific parser with field mapping
- `MoneyFileService.swift` - Main service for file operations
- `MoneyModels.swift` - Data models (MoneyAccount, MoneyTransaction, etc.)
- `AuthManager.swift` - MSAL authentication
- `ContentView.swift` - Main UI entry point

### C Files (mdbtools)

**Core Library:**
- `backend.c` - Database backend support
- `catalog.c` - Table catalog reading
- `data.c` - Data reading/conversion
- `file.c` - File I/O operations
- `index.c` - Index management
- `like.c` - Pattern matching
- `map.c` - Page mapping
- `money.c` - Money data type handling
- `props.c` - Property management
- `sargs.c` - Search arguments
- `table.c` - Table operations
- `write.c` - Write operations (future use)
- `worktable.c` - Temporary tables

**Support Files:**
- `mdbfakeglib.c` - Minimal GLib implementation for iOS
- `MoneyMDBHelpers.c` - Additional helper functions (mdb_debug, mdb_unicode2ascii, mdbi_rc4, etc.)

### Headers

- `mdbtools.h` - Main mdbtools API
- `mdbfakeglib.h` - GLib type definitions
- `mdbsql.h` - SQL support
- `mdbprivate.h` - Internal definitions
- `MoneyMDBHelpers.h` - Helper function declarations
- `CheckbookApp-Bridging-Header.h` - Exposes C to Swift

## 🐛 Known Issues

- **Write Support** - Not yet implemented (read-only currently)
- **Unicode** - Complex Unicode characters may show as '?' (UTF-16LE to UTF-8 conversion)
- **Database Encryption** - RC4 password-protected databases have basic support

## 🔄 Future Enhancements

- [ ] Transaction editing
- [ ] Database write support
- [ ] Re-encryption and OneDrive upload
- [ ] Offline caching
- [ ] Advanced filtering and search
- [ ] Charts and reports
- [ ] Multiple currency support
- [ ] Backup/restore

## 📝 Development Notes

### Memory Management

- C library uses manual memory management
- Swift wrappers handle bridging carefully
- `g_ptr_array_free` modified to prevent double-free crashes
- Always clean build when modifying C files

### Debugging

- Enable `MDB_DEBUG` in mdbtools.h for verbose logging
- Check Console.app for detailed mdbtools output
- Use Instruments for memory leak detection

### Testing

- Test with real Money files (various versions)
- Verify decryption with known-good files
- Check balance calculations against Microsoft Money

## 📄 License

[Your License Here]

## 🙏 Acknowledgments

- **mdbtools** - Brian Bruns and contributors
- **MSAL** - Microsoft Identity team
- **Microsoft Money** - For the file format documentation (reverse engineered)

## 📞 Support

For issues, questions, or contributions, please open an issue on GitHub.

---

**Version:** 1.0.0  
**Last Updated:** January 2026  
**Author:** [Your Name]
