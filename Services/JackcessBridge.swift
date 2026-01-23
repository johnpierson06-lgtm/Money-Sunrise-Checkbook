//
//  JackcessBridge.swift
//  CheckbookApp
//
//  Bridge to insert records into Money files using Jackcess-style approach
//  This recreates the Java Jackcess method used by money_insert.py
//

import Foundation

/// Bridge for inserting records into Microsoft Money files
/// Uses a Jackcess-compatible approach to maintain database integrity
enum JackcessBridge {
    
    // MARK: - Errors
    
    enum JackcessError: Error, LocalizedError {
        case fileNotFound
        case insertFailed(String)
        case decryptionFailed(String)
        case encryptionFailed(String)
        case javaRuntimeNotFound
        case jackcessJarNotFound
        
        var errorDescription: String? {
            switch self {
            case .fileNotFound:
                return "Money file not found"
            case .insertFailed(let msg):
                return "Insert failed: \(msg)"
            case .decryptionFailed(let msg):
                return "Decryption failed: \(msg)"
            case .encryptionFailed(let msg):
                return "Encryption failed: \(msg)"
            case .javaRuntimeNotFound:
                return "Java runtime not found - required for Jackcess operations"
            case .jackcessJarNotFound:
                return "Jackcess JAR file not found in Resources"
            }
        }
    }
    
    // MARK: - Insert Payee
    
    /// Insert a payee into the Money file
    /// This uses the Jackcess approach to properly maintain indexes
    static func insertPayee(_ payee: LocalPayee, into fileURL: URL, password: String) throws {
        #if DEBUG
        print("[JackcessBridge] Inserting payee: \(payee.szFull) (id: \(payee.hpay))")
        #endif
        
        // Since we can't use Java/Jackcess directly on iOS, we need to use
        // Swift-native approach with mdbtools to insert records
        
        // For now, we'll use a direct database insertion approach
        // This mimics what Jackcess does but in pure Swift
        try insertPayeeNative(payee, into: fileURL, password: password)
    }
    
    // MARK: - Insert Transaction
    
    /// Insert a transaction into the Money file
    /// This uses the Jackcess approach to properly maintain indexes and balances
    static func insertTransaction(_ transaction: LocalTransaction, into fileURL: URL, password: String) throws {
        #if DEBUG
        print("[JackcessBridge] Inserting transaction: #\(transaction.htrn) for account \(transaction.hacct)")
        #endif
        
        // Use Swift-native approach
        try insertTransactionNative(transaction, into: fileURL, password: password)
    }
    
    // MARK: - Native Implementation (Swift-based)
    
    /// Native Swift implementation of payee insertion
    /// This opens the .mny file directly and inserts using our Swift tools
    private static func insertPayeeNative(_ payee: LocalPayee, into fileURL: URL, password: String) throws {
        // The approach based on money_insert.py:
        // 1. Work directly with the .mny file (encrypted MDB)
        // 2. Use MDBToolsNativeWriter to insert into PAY and XPAY tables
        // 3. The .mny file is already encrypted, so we insert directly
        
        #if DEBUG
        print("[JackcessBridge] Inserting payee \(payee.hpay): \(payee.szFull)")
        print("[JackcessBridge] File: \(fileURL.path)")
        #endif
        
        // Use MDBToolsNativeWriter to insert
        let writer = MDBToolsNativeWriter(fileURL: fileURL, password: password)
        
        // Insert into PAY table
        try writer.insertPayee(payee)
        
        #if DEBUG
        print("[JackcessBridge] ✅ Successfully inserted payee \(payee.hpay)")
        #endif
    }
    
    /// Native Swift implementation of transaction insertion
    /// This opens the .mny file directly and inserts using our Swift tools
    private static func insertTransactionNative(_ transaction: LocalTransaction, into fileURL: URL, password: String) throws {
        // Same approach as payee insertion
        // Based on money_insert.py transaction insertion logic
        
        #if DEBUG
        print("[JackcessBridge] Inserting transaction \(transaction.htrn) for account \(transaction.hacct)")
        print("[JackcessBridge] Amount: \(transaction.amt)")
        print("[JackcessBridge] File: \(fileURL.path)")
        #endif
        
        // Use MDBToolsNativeWriter to insert
        let writer = MDBToolsNativeWriter(fileURL: fileURL, password: password)
        
        // Insert into TRN table
        try writer.insertTransaction(transaction)
        
        #if DEBUG
        print("[JackcessBridge] ✅ Successfully inserted transaction \(transaction.htrn)")
        #endif
    }
}

// MARK: - Extensions for LocalDatabaseManager

extension LocalDatabaseManager {
    
    /// Get all unsynced payees
    func getUnsyncedPayees() throws -> [LocalPayee] {
        let sql = """
        SELECT hpay, hpayParent, haddr, mComment, fHidden, szAls, szFull, mAcctNum,
               mBankId, mBranchId, mUserAcctAtPay, mIntlChkSum, mCompanyName, mContact,
               haddrBill, haddrShip, mCellPhone, mPager, mWebPage, terms, mPmtType,
               mCCNum, dtCCExp, dDiscount, dRateTax, fVendor, fCust,
               dtLastModified, lContactData, shippref, fNoRecurringBill, dtSerial,
               grfcontt, fAutofillMemo, dtLast, sguid, fUpdated, fGlobal, fLocal
        FROM PAY
        WHERE is_synced = 0
        """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let errmsg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.prepareFailed(errmsg)
        }
        
        defer { sqlite3_finalize(statement) }
        
        var payees: [LocalPayee] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let payee = LocalPayee(
                hpay: Int(sqlite3_column_int(statement, 0)),
                hpayParent: columnIntOrNil(statement, 1),
                haddr: columnIntOrNil(statement, 2),
                mComment: columnString(statement, 3),
                fHidden: sqlite3_column_int(statement, 4) != 0,
                szAls: columnString(statement, 5),
                szFull: columnString(statement, 6) ?? "",
                mAcctNum: columnString(statement, 7),
                mBankId: columnString(statement, 8),
                mBranchId: columnString(statement, 9),
                mUserAcctAtPay: columnString(statement, 10),
                mIntlChkSum: columnString(statement, 11),
                mCompanyName: columnString(statement, 12),
                mContact: columnString(statement, 13),
                haddrBill: columnIntOrNil(statement, 14),
                haddrShip: columnIntOrNil(statement, 15),
                mCellPhone: columnString(statement, 16),
                mPager: columnString(statement, 17),
                mWebPage: columnString(statement, 18),
                terms: Int(sqlite3_column_int(statement, 19)),
                mPmtType: columnString(statement, 20),
                mCCNum: columnString(statement, 21),
                dtCCExp: columnString(statement, 22),
                dDiscount: sqlite3_column_double(statement, 23),
                dRateTax: sqlite3_column_double(statement, 24),
                fVendor: sqlite3_column_int(statement, 25) != 0,
                fCust: sqlite3_column_int(statement, 26) != 0,
                dtLastModified: columnString(statement, 27) ?? "",
                lContactData: Int(sqlite3_column_int(statement, 28)),
                shippref: Int(sqlite3_column_int(statement, 29)),
                fNoRecurringBill: sqlite3_column_int(statement, 30) != 0,
                dtSerial: columnString(statement, 31) ?? "",
                grfcontt: Int(sqlite3_column_int(statement, 32)),
                fAutofillMemo: sqlite3_column_int(statement, 33) != 0,
                dtLast: columnString(statement, 34),
                sguid: columnString(statement, 35) ?? "",
                fUpdated: sqlite3_column_int(statement, 36) != 0,
                fGlobal: sqlite3_column_int(statement, 37) != 0,
                fLocal: sqlite3_column_int(statement, 38) != 0
            )
            
            payees.append(payee)
        }
        
        #if DEBUG
        print("[LocalDatabaseManager] ✅ Retrieved \(payees.count) unsynced payees")
        #endif
        
        return payees
    }
    
    /// Clear all synced records (after successful sync)
    func clearSyncedRecords() throws {
        // Delete transactions
        let deleteTrnSql = "DELETE FROM TRN WHERE is_synced = 0"
        try execute(deleteTrnSql)
        
        // Delete payees
        let deletePaySql = "DELETE FROM PAY WHERE is_synced = 0"
        try execute(deletePaySql)
        
        #if DEBUG
        print("[LocalDatabaseManager] ✅ Cleared all synced records")
        #endif
    }
    
    /// Count unsynced transactions
    func countUnsyncedTransactions() throws -> Int {
        let sql = "SELECT COUNT(*) FROM TRN WHERE is_synced = 0"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let errmsg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.prepareFailed(errmsg)
        }
        
        defer { sqlite3_finalize(statement) }
        
        var count = 0
        if sqlite3_step(statement) == SQLITE_ROW {
            count = Int(sqlite3_column_int(statement, 0))
        }
        
        return count
    }
    
    /// Count unsynced payees
    func countUnsyncedPayees() throws -> Int {
        let sql = "SELECT COUNT(*) FROM PAY WHERE is_synced = 0"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let errmsg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.prepareFailed(errmsg)
        }
        
        defer { sqlite3_finalize(statement) }
        
        var count = 0
        if sqlite3_step(statement) == SQLITE_ROW {
            count = Int(sqlite3_column_int(statement, 0))
        }
        
        return count
    }
}
