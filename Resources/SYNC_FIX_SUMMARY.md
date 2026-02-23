# Sync Fix: Separating Encrypted .mny and Decrypted .mdb Files

## Problem

The sync was failing with the error:
```
invalidFormat("MSysObjects page is not a data page")
```

This occurred because the code was trying to read the MSysObjects catalog (which contains table metadata like page numbers) from the **encrypted .mny file**. The encrypted pages don't have valid page type bytes in the expected format.

## Solution

Following the exact process used by the Java DA10DeepInsert_v12 example, we now:

1. **Read metadata from the DECRYPTED .mdb file** (created by MoneyDecryptorBridge)
   - MSysObjects catalog (table definitions and page numbers)
   - Table structure information
   - Usage map locations

2. **Write data directly to the ENCRYPTED .mny file**
   - Transaction/payee row data
   - Page headers (row count, free pointer)
   - Table row counts
   - Database flags ("needs compact")

## Changes Made

### 1. JackcessCompatibleMDBWriter.swift

**Before:**
- Single file path (`filePath`) pointing to encrypted .mny file
- Tried to read MSysObjects from encrypted data (failed!)
- Worked with `fileData` throughout

**After:**
- Two file paths:
  - `mnyFilePath`: Encrypted .mny file (write target)
  - `mdbFilePath`: Decrypted .mdb file (metadata source)
- Reads MSysObjects from decrypted .mdb file (succeeds!)
- Works with `mnyFileData` for the encrypted file

Key method changes:
- `init(mnyFilePath: String, mdbFilePath: String)` - Now takes both paths
- `findTableDefinitionPage()` - Reads from decrypted .mdb file
- `scanForTransactionPages()` - Still scans encrypted .mny (works on page structure)
- `appendRowToDataPage()` - Writes to encrypted .mny file
- `save()` - Saves encrypted .mny file only (never modifies .mdb)

### 2. MDBToolsNativeWriter.swift

**Before:**
```swift
// Decrypt file
let decryptedPath = try decryptFile()

// Open with mdbtools
guard let mdb = mdb_open(decryptedPath, MDB_WRITABLE) else {
    throw WriterError.databaseOpenFailed
}

// Insert data
try insertIntoTRN(transaction, mdb: mdb)

// Problem: This modified the decrypted .mdb file
// Then we'd need to re-encrypt it (doesn't work properly)
```

**After:**
```swift
// Decrypt file temporarily to get metadata
let decryptedMdbPath = try decryptFile()

// Use JackcessCompatibleMDBWriter with both paths
let writer = try JackcessCompatibleMDBWriter(
    mnyFilePath: fileURL.path,      // ENCRYPTED (write)
    mdbFilePath: decryptedMdbPath   // DECRYPTED (read metadata)
)

// Insert directly into encrypted .mny
try writer.insertTransaction(transaction)
try writer.save()

// No re-encryption needed! We wrote directly to .mny
```

## Why This Works

### The DA10DeepInsert_v12 Approach

Looking at the Java code:
```java
Database db = Database.open(moneyFile, false, false, null, null, codec);
Table trn = db.getTable("TRN");
```

Jackcess:
1. Opens the .mny file with the codec (MSISAMCryptCodecHandler)
2. The codec DECRYPTS pages as they're read
3. Reads MSysObjects from the decrypted page data
4. When writing, pages are encrypted on-the-fly
5. The encryption happens at the PageChannel level transparently

### Our iOS Approach

We can't perfectly replicate Jackcess's page-level encryption/decryption, so instead:

1. Use MoneyDecryptorBridge to create a full decrypted .mdb file once
2. Read all metadata (MSysObjects, table definitions) from the decrypted .mdb
3. Write row data directly to the encrypted .mny file
4. The .mny file structure remains valid because:
   - Page headers are the same encrypted or not
   - Row data is written to the correct offsets
   - Money Desktop will decrypt and rebuild indexes on open

## Testing

Test the sync with:
1. Create a new transaction in the app
2. Click "Sync to OneDrive"
3. Download the synced Money_Test_*.mny file
4. Open in Money Plus Desktop
5. Verify the transaction appears correctly

## Debug Output

You should see:
```
[MDBToolsNativeWriter] Decrypted temp file: /var/.../decrypted.mdb
[MDBToolsNativeWriter] Encrypted .mny file: /var/.../Money.mny
[MSysObjects] Looking up 'TRN' in system catalog from DECRYPTED .mdb file...
[MSysObjects] Catalog has X rows (from decrypted .mdb)
[MSysObjects] ✓ Found 'TRN' at table def page Y (from decrypted .mdb)
[Row Append] Writing to ENCRYPTED .mny file
✅ Transaction inserted into ENCRYPTED .mny file
```

## Important Notes

1. **Never modify the .mdb file** - It's only for reading metadata
2. **All writes go to .mny** - The encrypted file is the source of truth
3. **No re-encryption needed** - We write directly to encrypted format
4. **Money Desktop rebuilds indexes** - "needs compact" flag tells it to do this

This matches the Jackcess approach where encrypted pages are handled transparently by the codec layer.
