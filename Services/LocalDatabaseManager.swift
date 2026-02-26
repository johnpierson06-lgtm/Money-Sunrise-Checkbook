//
//  LocalDatabaseManager.swift
//  CheckbookApp
//
//  Local SQLite database for storing unsynced transactions and payees
//

import Foundation
import SQLite3

/// Manager for local SQLite database storing unsynced transactions and payees
class LocalDatabaseManager {
    static let shared = LocalDatabaseManager()
    
    private var db: OpaquePointer?
    private let dbPath: String
    
    enum DatabaseError: Error, LocalizedError {
        case openFailed(String)
        case executeFailed(String)
        case prepareFailed(String)
        case bindFailed(String)
        case queryFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .openFailed(let msg): return "Failed to open database: \(msg)"
            case .executeFailed(let msg): return "Failed to execute: \(msg)"
            case .prepareFailed(let msg): return "Failed to prepare: \(msg)"
            case .bindFailed(let msg): return "Failed to bind: \(msg)"
            case .queryFailed(let msg): return "Failed to query: \(msg)"
            }
        }
    }
    
    private init() {
        // Store database in app's documents directory
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dbURL = documentsPath.appendingPathComponent("checkbook_local.db")
        dbPath = dbURL.path
        
        #if DEBUG
        print("[LocalDatabaseManager] Database path: \(dbPath)")
        #endif
        
        // Open/create database
        do {
            try openDatabase()
            try createTables()
        } catch {
            print("[LocalDatabaseManager] ❌ Failed to initialize: \(error)")
        }
    }
    
    deinit {
        closeDatabase()
    }
    
    // MARK: - Database Operations
    
    private func openDatabase() throws {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.openFailed(errmsg)
        }
        
        #if DEBUG
        print("[LocalDatabaseManager] ✅ Database opened successfully")
        #endif
    }
    
    private func closeDatabase() {
        if let db = db {
            sqlite3_close(db)
            self.db = nil
        }
    }
    
    private func createTables() throws {
        // Check if we need to migrate from old schema
        let checkSql = "SELECT sql FROM sqlite_master WHERE type='table' AND name='TRN'"
        var statement: OpaquePointer?
        var needsMigration = false
        
        if sqlite3_prepare_v2(db, checkSql, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                if let sqlPtr = sqlite3_column_text(statement, 0) {
                    let existingSql = String(cString: sqlPtr)
                    // Check if old schema (htrn as PRIMARY KEY)
                    if existingSql.contains("htrn INTEGER PRIMARY KEY") {
                        needsMigration = true
                    }
                }
            }
            sqlite3_finalize(statement)
        }
        
        if needsMigration {
            #if DEBUG
            print("[LocalDatabaseManager] ⚠️  Old schema detected - migrating data...")
            #endif
            
            // Rename old table
            try execute("ALTER TABLE TRN RENAME TO TRN_old")
            try execute("ALTER TABLE PAY RENAME TO PAY_old")
            
            // Create new tables
            try createNewTables()
            
            // Copy data
            try execute("""
                INSERT INTO TRN (htrn, hacct, hacctLink, dt, dtSent, dtCleared, dtPost, cs, hsec, amt,
                                szId, hcat, frq, fDefPmt, mMemo, oltt, grfEntryMethods, ps, amtVat, grftt,
                                act, cFrqInst, fPrint, mFiStmtId, olst, fDebtPlan, grfstem, cpmtsRemaining,
                                instt, htrnSrc, payt, grftf, lHtxsrc, lHcrncUser, amtUser, amtVATUser,
                                tef, fRefund, fReimburse, dtSerial, fUpdated, fCCPmt, fDefBillAmt, fDefBillDate,
                                lHclsKak, lHcls1, lHcls2, dtCloseOffYear, dtOldRel, hbillHead, iinst, amtBase,
                                rt, amtPreRec, amtPreRecUser, hstmtRel, dRateToBase, lHpay, sguid, szAggTrnId,
                                rgbDigest, is_synced)
                SELECT htrn, hacct, hacctLink, dt, dtSent, dtCleared, dtPost, cs, hsec, amt,
                       szId, hcat, frq, fDefPmt, mMemo, oltt, grfEntryMethods, ps, amtVat, grftt,
                       act, cFrqInst, fPrint, mFiStmtId, olst, fDebtPlan, grfstem, cpmtsRemaining,
                       instt, htrnSrc, payt, grftf, lHtxsrc, lHcrncUser, amtUser, amtVATUser,
                       tef, fRefund, fReimburse, dtSerial, fUpdated, fCCPmt, fDefBillAmt, fDefBillDate,
                       lHclsKak, lHcls1, lHcls2, dtCloseOffYear, dtOldRel, hbillHead, iinst, amtBase,
                       rt, amtPreRec, amtPreRecUser, hstmtRel, dRateToBase, lHpay, sguid, szAggTrnId,
                       rgbDigest, is_synced
                FROM TRN_old
            """)
            
            try execute("""
                INSERT INTO PAY SELECT * FROM PAY_old
            """)
            
            // Drop old tables
            try execute("DROP TABLE TRN_old")
            try execute("DROP TABLE PAY_old")
            
            #if DEBUG
            print("[LocalDatabaseManager] ✅ Migration complete")
            #endif
        } else {
            // No migration needed, just create tables if they don't exist
            try createNewTables()
        }
    }
    
    private func createNewTables() throws {
        // Create TRN table with all 61 columns
        // local_id is auto-incrementing for local storage only
        // htrn will be assigned during sync from Money file
        let createTrnTable = """
        CREATE TABLE IF NOT EXISTS TRN (
            local_id INTEGER PRIMARY KEY AUTOINCREMENT,
            htrn INTEGER,
            hacct INTEGER,
            hacctLink TEXT,
            dt TEXT,
            dtSent TEXT,
            dtCleared TEXT,
            dtPost TEXT,
            cs INTEGER,
            hsec TEXT,
            amt REAL,
            szId TEXT,
            hcat INTEGER,
            frq INTEGER,
            fDefPmt INTEGER,
            mMemo TEXT,
            oltt INTEGER,
            grfEntryMethods INTEGER,
            ps INTEGER,
            amtVat REAL,
            grftt INTEGER,
            act INTEGER,
            cFrqInst TEXT,
            fPrint INTEGER,
            mFiStmtId TEXT,
            olst INTEGER,
            fDebtPlan INTEGER,
            grfstem INTEGER,
            cpmtsRemaining INTEGER,
            instt INTEGER,
            htrnSrc TEXT,
            payt INTEGER,
            grftf INTEGER,
            lHtxsrc INTEGER,
            lHcrncUser INTEGER,
            amtUser REAL,
            amtVATUser REAL,
            tef INTEGER,
            fRefund INTEGER,
            fReimburse INTEGER,
            dtSerial TEXT,
            fUpdated INTEGER,
            fCCPmt INTEGER,
            fDefBillAmt INTEGER,
            fDefBillDate INTEGER,
            lHclsKak INTEGER,
            lHcls1 INTEGER,
            lHcls2 INTEGER,
            dtCloseOffYear TEXT,
            dtOldRel TEXT,
            hbillHead TEXT,
            iinst INTEGER,
            amtBase TEXT,
            rt INTEGER,
            amtPreRec TEXT,
            amtPreRecUser TEXT,
            hstmtRel TEXT,
            dRateToBase TEXT,
            lHpay INTEGER,
            sguid TEXT,
            szAggTrnId TEXT,
            rgbDigest TEXT,
            is_synced INTEGER DEFAULT 0
        )
        """
        
        // Create PAY table with all columns
        let createPayTable = """
        CREATE TABLE IF NOT EXISTS PAY (
            hpay INTEGER PRIMARY KEY,
            hpayParent INTEGER,
            haddr INTEGER,
            mComment TEXT,
            fHidden INTEGER NOT NULL DEFAULT 0,
            szAls TEXT,
            szFull TEXT,
            mAcctNum TEXT,
            mBankId TEXT,
            mBranchId TEXT,
            mUserAcctAtPay TEXT,
            mIntlChkSum TEXT,
            mCompanyName TEXT,
            mContact TEXT,
            haddrBill INTEGER,
            haddrShip INTEGER,
            mCellPhone TEXT,
            mPager TEXT,
            mWebPage TEXT,
            terms INTEGER,
            mPmtType TEXT,
            mCCNum TEXT,
            dtCCExp TEXT,
            dDiscount REAL,
            dRateTax REAL,
            fVendor INTEGER NOT NULL DEFAULT 0,
            fCust INTEGER NOT NULL DEFAULT 0,
            rgbEntryId BLOB,
            dtLastModified TEXT,
            lContactData INTEGER,
            shippref INTEGER,
            fNoRecurringBill INTEGER NOT NULL DEFAULT 0,
            dtSerial TEXT,
            grfcontt INTEGER,
            fAutofillMemo INTEGER NOT NULL DEFAULT 0,
            dtLast TEXT,
            rgbMemos BLOB,
            sguid TEXT,
            fUpdated INTEGER NOT NULL DEFAULT 1,
            fGlobal INTEGER NOT NULL DEFAULT 0,
            fLocal INTEGER NOT NULL DEFAULT 1,
            is_synced INTEGER DEFAULT 0
        )
        """
        
        try execute(createTrnTable)
        try execute(createPayTable)
        
        #if DEBUG
        print("[LocalDatabaseManager] ✅ Tables created successfully")
        #endif
    }
    
    private func execute(_ sql: String) throws {
        var errmsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errmsg) != SQLITE_OK {
            let error = String(cString: errmsg!)
            sqlite3_free(errmsg)
            throw DatabaseError.executeFailed(error)
        }
    }
    
    // MARK: - Transaction Operations
    
    /// Insert a new transaction into local database
    func insertTransaction(_ transaction: LocalTransaction) throws {
        let sql = """
        INSERT INTO TRN (
            htrn, hacct, hacctLink, dt, dtSent, dtCleared, dtPost, cs, hsec, amt,
            szId, hcat, frq, fDefPmt, mMemo, oltt, grfEntryMethods, ps, amtVat, grftt,
            act, cFrqInst, fPrint, mFiStmtId, olst, fDebtPlan, grfstem, cpmtsRemaining,
            instt, htrnSrc, payt, grftf, lHtxsrc, lHcrncUser, amtUser, amtVATUser,
            tef, fRefund, fReimburse, dtSerial, fUpdated, fCCPmt, fDefBillAmt, fDefBillDate,
            lHclsKak, lHcls1, lHcls2, dtCloseOffYear, dtOldRel, hbillHead, iinst, amtBase,
            rt, amtPreRec, amtPreRecUser, hstmtRel, dRateToBase, lHpay, sguid, szAggTrnId,
            rgbDigest, is_synced
        ) VALUES (
            ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
            ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
            ?, ?, ?, ?, ?, ?, ?, ?,
            ?, ?, ?, ?, ?, ?, ?, ?,
            ?, ?, ?, ?, ?, ?, ?, ?,
            ?, ?, ?, ?, ?, ?, ?, ?,
            ?, ?, ?, ?, ?, ?, ?, ?,
            ?, 0
        )
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let errmsg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.prepareFailed(errmsg)
        }
        
        defer { sqlite3_finalize(statement) }
        
        // Bind all 61 values
        sqlite3_bind_int(statement, 1, Int32(transaction.htrn))
        sqlite3_bind_int(statement, 2, Int32(transaction.hacct))
        bindTextOrNull(statement, 3, transaction.hacctLink)
        bindText(statement, 4, transaction.dt)
        bindText(statement, 5, transaction.dtSent)
        bindText(statement, 6, transaction.dtCleared)
        bindText(statement, 7, transaction.dtPost)
        sqlite3_bind_int(statement, 8, Int32(transaction.cs))
        bindTextOrNull(statement, 9, transaction.hsec)
        sqlite3_bind_double(statement, 10, NSDecimalNumber(decimal: transaction.amt).doubleValue)
        bindTextOrNull(statement, 11, transaction.szId)
        bindIntOrNull(statement, 12, transaction.hcat)
        sqlite3_bind_int(statement, 13, Int32(transaction.frq))
        sqlite3_bind_int(statement, 14, Int32(transaction.fDefPmt))
        bindTextOrNull(statement, 15, transaction.mMemo)
        sqlite3_bind_int(statement, 16, Int32(transaction.oltt))
        sqlite3_bind_int(statement, 17, Int32(transaction.grfEntryMethods))
        sqlite3_bind_int(statement, 18, Int32(transaction.ps))
        sqlite3_bind_double(statement, 19, transaction.amtVat)
        sqlite3_bind_int(statement, 20, Int32(transaction.grftt))
        sqlite3_bind_int(statement, 21, Int32(transaction.act))
        bindTextOrNull(statement, 22, transaction.cFrqInst)
        sqlite3_bind_int(statement, 23, Int32(transaction.fPrint))
        bindTextOrNull(statement, 24, transaction.mFiStmtId)
        sqlite3_bind_int(statement, 25, Int32(transaction.olst))
        sqlite3_bind_int(statement, 26, Int32(transaction.fDebtPlan))
        sqlite3_bind_int(statement, 27, Int32(transaction.grfstem))
        sqlite3_bind_int(statement, 28, Int32(transaction.cpmtsRemaining))
        sqlite3_bind_int(statement, 29, Int32(transaction.instt))
        bindTextOrNull(statement, 30, transaction.htrnSrc)
        sqlite3_bind_int(statement, 31, Int32(transaction.payt))
        sqlite3_bind_int(statement, 32, Int32(transaction.grftf))
        sqlite3_bind_int(statement, 33, Int32(transaction.lHtxsrc))
        sqlite3_bind_int(statement, 34, Int32(transaction.lHcrncUser))
        sqlite3_bind_double(statement, 35, NSDecimalNumber(decimal: transaction.amtUser).doubleValue)
        sqlite3_bind_double(statement, 36, transaction.amtVATUser)
        sqlite3_bind_int(statement, 37, Int32(transaction.tef))
        sqlite3_bind_int(statement, 38, Int32(transaction.fRefund))
        sqlite3_bind_int(statement, 39, Int32(transaction.fReimburse))
        bindText(statement, 40, transaction.dtSerial)
        sqlite3_bind_int(statement, 41, Int32(transaction.fUpdated))
        sqlite3_bind_int(statement, 42, Int32(transaction.fCCPmt))
        sqlite3_bind_int(statement, 43, Int32(transaction.fDefBillAmt))
        sqlite3_bind_int(statement, 44, Int32(transaction.fDefBillDate))
        sqlite3_bind_int(statement, 45, Int32(transaction.lHclsKak))
        sqlite3_bind_int(statement, 46, Int32(transaction.lHcls1))
        sqlite3_bind_int(statement, 47, Int32(transaction.lHcls2))
        bindText(statement, 48, transaction.dtCloseOffYear)
        bindText(statement, 49, transaction.dtOldRel)
        bindTextOrNull(statement, 50, transaction.hbillHead)
        sqlite3_bind_int(statement, 51, Int32(transaction.iinst))
        bindTextOrNull(statement, 52, transaction.amtBase)
        sqlite3_bind_int(statement, 53, Int32(transaction.rt))
        bindTextOrNull(statement, 54, transaction.amtPreRec)
        bindTextOrNull(statement, 55, transaction.amtPreRecUser)
        bindTextOrNull(statement, 56, transaction.hstmtRel)
        bindTextOrNull(statement, 57, transaction.dRateToBase)
        bindIntOrNull(statement, 58, transaction.lHpay)
        bindText(statement, 59, transaction.sguid)
        bindTextOrNull(statement, 60, transaction.szAggTrnId)
        bindTextOrNull(statement, 61, transaction.rgbDigest)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let errmsg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.executeFailed(errmsg)
        }
        
        #if DEBUG
        print("[LocalDatabaseManager] ✅ Inserted transaction htrn=\(transaction.htrn)")
        #endif
    }
    
    /// Get all unsynced transactions
    func getUnsyncedTransactions() throws -> [LocalTransaction] {
        let sql = """
        SELECT htrn, hacct, hacctLink, dt, dtSent, dtCleared, dtPost, cs, hsec, amt,
               szId, hcat, frq, fDefPmt, mMemo, oltt, grfEntryMethods, ps, amtVat, grftt,
               act, cFrqInst, fPrint, mFiStmtId, olst, fDebtPlan, grfstem, cpmtsRemaining,
               instt, htrnSrc, payt, grftf, lHtxsrc, lHcrncUser, amtUser, amtVATUser,
               tef, fRefund, fReimburse, dtSerial, fUpdated, fCCPmt, fDefBillAmt, fDefBillDate,
               lHclsKak, lHcls1, lHcls2, dtCloseOffYear, dtOldRel, hbillHead, iinst, amtBase,
               rt, amtPreRec, amtPreRecUser, hstmtRel, dRateToBase, lHpay, sguid, szAggTrnId,
               rgbDigest
        FROM TRN
        WHERE is_synced = 0
        """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let errmsg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.prepareFailed(errmsg)
        }
        
        defer { sqlite3_finalize(statement) }
        
        var transactions: [LocalTransaction] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let htrn = Int(sqlite3_column_int(statement, 0))
            let hacct = Int(sqlite3_column_int(statement, 1))
            let dt = columnString(statement, 3) ?? ""
            let amt = Decimal(sqlite3_column_double(statement, 9))
            let hcat = columnIntOrNil(statement, 11)
            let mMemo = columnString(statement, 14)
            let lHpay = columnIntOrNil(statement, 57)
            
            #if DEBUG
            print("🔍 [SQLite READ] Row:")
            print("   htrn: \(htrn)")
            print("   hacct: \(hacct)")
            print("   dt: '\(dt)'")
            print("   amt: \(amt)")
            print("   hcat: \(hcat?.description ?? "nil")")
            print("   mMemo: '\(mMemo ?? "nil")'")
            print("   lHpay: \(lHpay?.description ?? "nil")")
            #endif
            
            let transaction = LocalTransaction(
                htrn: htrn,
                hacct: hacct,
                hacctLink: columnString(statement, 2),
                dt: dt,
                dtSent: columnString(statement, 4) ?? "",
                dtCleared: columnString(statement, 5) ?? "",
                dtPost: columnString(statement, 6) ?? "",
                cs: Int(sqlite3_column_int(statement, 7)),
                hsec: columnString(statement, 8),
                amt: amt,
                szId: columnString(statement, 10),
                hcat: hcat,
                frq: Int(sqlite3_column_int(statement, 12)),
                fDefPmt: Int(sqlite3_column_int(statement, 13)),
                mMemo: mMemo,
                oltt: Int(sqlite3_column_int(statement, 15)),
                grfEntryMethods: Int(sqlite3_column_int(statement, 16)),
                ps: Int(sqlite3_column_int(statement, 17)),
                amtVat: sqlite3_column_double(statement, 18),
                grftt: Int(sqlite3_column_int(statement, 19)),
                act: Int(sqlite3_column_int(statement, 20)),
                cFrqInst: columnString(statement, 21),
                fPrint: Int(sqlite3_column_int(statement, 22)),
                mFiStmtId: columnString(statement, 23),
                olst: Int(sqlite3_column_int(statement, 24)),
                fDebtPlan: Int(sqlite3_column_int(statement, 25)),
                grfstem: Int(sqlite3_column_int(statement, 26)),
                cpmtsRemaining: Int(sqlite3_column_int(statement, 27)),
                instt: Int(sqlite3_column_int(statement, 28)),
                htrnSrc: columnString(statement, 29),
                payt: Int(sqlite3_column_int(statement, 30)),
                grftf: Int(sqlite3_column_int(statement, 31)),
                lHtxsrc: Int(sqlite3_column_int(statement, 32)),
                lHcrncUser: Int(sqlite3_column_int(statement, 33)),
                amtUser: Decimal(sqlite3_column_double(statement, 34)),
                amtVATUser: sqlite3_column_double(statement, 35),
                tef: Int(sqlite3_column_int(statement, 36)),
                fRefund: Int(sqlite3_column_int(statement, 37)),
                fReimburse: Int(sqlite3_column_int(statement, 38)),
                dtSerial: columnString(statement, 39) ?? "",
                fUpdated: Int(sqlite3_column_int(statement, 40)),
                fCCPmt: Int(sqlite3_column_int(statement, 41)),
                fDefBillAmt: Int(sqlite3_column_int(statement, 42)),
                fDefBillDate: Int(sqlite3_column_int(statement, 43)),
                lHclsKak: Int(sqlite3_column_int(statement, 44)),
                lHcls1: Int(sqlite3_column_int(statement, 45)),
                lHcls2: Int(sqlite3_column_int(statement, 46)),
                dtCloseOffYear: columnString(statement, 47) ?? "",
                dtOldRel: columnString(statement, 48) ?? "",
                hbillHead: columnString(statement, 49),
                iinst: Int(sqlite3_column_int(statement, 50)),
                amtBase: columnString(statement, 51),
                rt: Int(sqlite3_column_int(statement, 52)),
                amtPreRec: columnString(statement, 53),
                amtPreRecUser: columnString(statement, 54),
                hstmtRel: columnString(statement, 55),
                dRateToBase: columnString(statement, 56),
                lHpay: lHpay,
                sguid: columnString(statement, 58) ?? "",
                szAggTrnId: columnString(statement, 59),
                rgbDigest: columnString(statement, 60)
            )
            
            transactions.append(transaction)
        }
        
        #if DEBUG
        print("[LocalDatabaseManager] ✅ Retrieved \(transactions.count) unsynced transactions")
        #endif
        
        return transactions
    }
    
    // MARK: - Payee Operations
    
    /// Insert a new payee into local database
    func insertPayee(_ payee: LocalPayee) throws {
        #if DEBUG
        print("[LocalDatabaseManager] insertPayee called:")
        print("  hpay: \(payee.hpay)")
        print("  szFull: '\(payee.szFull)'")
        print("  szFull.isEmpty: \(payee.szFull.isEmpty)")
        print("  szFull.count: \(payee.szFull.count)")
        #endif
        
        let sql = """
        INSERT INTO PAY (
            hpay, hpayParent, haddr, mComment, fHidden, szAls, szFull, mAcctNum,
            mBankId, mBranchId, mUserAcctAtPay, mIntlChkSum, mCompanyName, mContact,
            haddrBill, haddrShip, mCellPhone, mPager, mWebPage, terms, mPmtType,
            mCCNum, dtCCExp, dDiscount, dRateTax, fVendor, fCust, rgbEntryId,
            dtLastModified, lContactData, shippref, fNoRecurringBill, dtSerial,
            grfcontt, fAutofillMemo, dtLast, rgbMemos, sguid, fUpdated, fGlobal,
            fLocal, is_synced
        ) VALUES (
            ?, ?, ?, ?, ?, ?, ?, ?,
            ?, ?, ?, ?, ?, ?,
            ?, ?, ?, ?, ?, ?, ?,
            ?, ?, ?, ?, ?, ?, ?,
            ?, ?, ?, ?, ?,
            ?, ?, ?, ?, ?, ?, ?,
            ?, 0
        )
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let errmsg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.prepareFailed(errmsg)
        }
        
        defer { sqlite3_finalize(statement) }
        
        // Bind all values
        sqlite3_bind_int(statement, 1, Int32(payee.hpay))
        bindIntOrNull(statement, 2, payee.hpayParent)
        bindIntOrNull(statement, 3, payee.haddr)
        bindTextOrNull(statement, 4, payee.mComment)
        sqlite3_bind_int(statement, 5, payee.fHidden ? 1 : 0)
        bindTextOrNull(statement, 6, payee.szAls)
        
        #if DEBUG
        print("[LocalDatabaseManager] About to bind szFull at parameter 7: '\(payee.szFull)'")
        #endif
        
        bindText(statement, 7, payee.szFull)
        
        #if DEBUG
        print("[LocalDatabaseManager] szFull bound successfully")
        #endif
        
        bindTextOrNull(statement, 8, payee.mAcctNum)
        bindTextOrNull(statement, 9, payee.mBankId)
        bindTextOrNull(statement, 10, payee.mBranchId)
        bindTextOrNull(statement, 11, payee.mUserAcctAtPay)
        bindTextOrNull(statement, 12, payee.mIntlChkSum)
        bindTextOrNull(statement, 13, payee.mCompanyName)
        bindTextOrNull(statement, 14, payee.mContact)
        bindIntOrNull(statement, 15, payee.haddrBill)
        bindIntOrNull(statement, 16, payee.haddrShip)
        bindTextOrNull(statement, 17, payee.mCellPhone)
        bindTextOrNull(statement, 18, payee.mPager)
        bindTextOrNull(statement, 19, payee.mWebPage)
        sqlite3_bind_int(statement, 20, Int32(payee.terms))
        bindTextOrNull(statement, 21, payee.mPmtType)
        bindTextOrNull(statement, 22, payee.mCCNum)
        bindTextOrNull(statement, 23, payee.dtCCExp)
        sqlite3_bind_double(statement, 24, payee.dDiscount)
        sqlite3_bind_double(statement, 25, payee.dRateTax)
        sqlite3_bind_int(statement, 26, payee.fVendor ? 1 : 0)
        sqlite3_bind_int(statement, 27, payee.fCust ? 1 : 0)
        // rgbEntryId (BLOB) - skip for now
        sqlite3_bind_null(statement, 28)
        bindText(statement, 29, payee.dtLastModified)
        sqlite3_bind_int(statement, 30, Int32(payee.lContactData))
        sqlite3_bind_int(statement, 31, Int32(payee.shippref))
        sqlite3_bind_int(statement, 32, payee.fNoRecurringBill ? 1 : 0)
        bindText(statement, 33, payee.dtSerial)
        sqlite3_bind_int(statement, 34, Int32(payee.grfcontt))
        sqlite3_bind_int(statement, 35, payee.fAutofillMemo ? 1 : 0)
        bindTextOrNull(statement, 36, payee.dtLast)
        // rgbMemos (BLOB) - skip for now
        sqlite3_bind_null(statement, 37)
        bindText(statement, 38, payee.sguid)
        sqlite3_bind_int(statement, 39, payee.fUpdated ? 1 : 0)
        sqlite3_bind_int(statement, 40, payee.fGlobal ? 1 : 0)
        sqlite3_bind_int(statement, 41, payee.fLocal ? 1 : 0)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let errmsg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.executeFailed(errmsg)
        }
        
        #if DEBUG
        print("[LocalDatabaseManager] ✅ Inserted payee hpay=\(payee.hpay), name=\(payee.szFull)")
        #endif
    }
    
    /// Get the next available payee ID
    func getNextPayeeId() throws -> Int {
        // Check local database
        let localMaxSql = "SELECT MAX(hpay) FROM PAY"
        var statement: OpaquePointer?
        
        var localMax = 0
        if sqlite3_prepare_v2(db, localMaxSql, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                localMax = Int(sqlite3_column_int(statement, 0))
            }
            sqlite3_finalize(statement)
        }
        
        // Also check the Money file for max ID
        var fileMax = 0
        do {
            let url = try MoneyFileService.ensureLocalFile()
            let password = (try? PasswordStore.shared.load()) ?? ""
            let decryptedPath = try MoneyDecryptorBridge.decryptToTempFile(fromFile: url.path, password: password)
            let parser = MoneyFileParser(filePath: decryptedPath)
            let payees = try parser.parsePayees()
            fileMax = payees.map { $0.id }.max() ?? 0
        } catch {
            #if DEBUG
            print("[LocalDatabaseManager] Could not read Money file max payee ID: \(error)")
            #endif
        }
        
        let nextId = max(localMax, fileMax) + 1
        
        #if DEBUG
        print("[LocalDatabaseManager] Next payee ID: \(nextId) (local max: \(localMax), file max: \(fileMax))")
        #endif
        
        return nextId
    }
    
    // MARK: - Helper Methods
    
    private func bindTextOrNull(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value = value, !value.isEmpty {
            sqlite3_bind_text(statement, index, value, -1, nil)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }
    
    private func bindIntOrNull(_ statement: OpaquePointer?, _ index: Int32, _ value: Int?) {
        if let value = value {
            sqlite3_bind_int(statement, index, Int32(value))
        } else {
            sqlite3_bind_null(statement, index)
        }
    }
    
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
            let hpay = Int(sqlite3_column_int(statement, 0))
            let szFull = columnString(statement, 6) ?? ""
            let dtLastModified = columnString(statement, 27) ?? ""
            let dtSerial = columnString(statement, 31) ?? ""
            let sguid = columnString(statement, 35) ?? ""
            
            #if DEBUG
            print("[getUnsyncedPayees] Reading payee from SQLite:")
            print("  hpay: \(hpay)")
            print("  szFull (col 6): '\(szFull)'")
            print("  dtLastModified (col 27): '\(dtLastModified)'")
            print("  dtSerial (col 31): '\(dtSerial)'")
            print("  sguid (col 35): '\(sguid)'")
            #endif
            
            let payee = LocalPayee(
                hpay: hpay,
                hpayParent: columnIntOrNil(statement, 1),
                haddr: columnIntOrNil(statement, 2),
                mComment: columnString(statement, 3),
                fHidden: sqlite3_column_int(statement, 4) != 0,
                szAls: columnString(statement, 5),
                szFull: szFull,
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
                dtLastModified: dtLastModified,
                lContactData: Int(sqlite3_column_int(statement, 28)),
                shippref: Int(sqlite3_column_int(statement, 29)),
                fNoRecurringBill: sqlite3_column_int(statement, 30) != 0,
                dtSerial: dtSerial,
                grfcontt: Int(sqlite3_column_int(statement, 32)),
                fAutofillMemo: sqlite3_column_int(statement, 33) != 0,
                dtLast: columnString(statement, 34),
                sguid: sguid,
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
    
    /// Clear all synced records from local database
    func clearSyncedRecords() throws {
        // Delete synced transactions
        let deleteTrnSql = "DELETE FROM TRN WHERE is_synced = 1"
        try execute(deleteTrnSql)
        
        // Delete synced payees
        let deletePaySql = "DELETE FROM PAY WHERE is_synced = 1"
        try execute(deletePaySql)
        
        #if DEBUG
        print("[LocalDatabaseManager] ✅ Cleared synced records from local database")
        #endif
    }
    
    /// Clear ALL payee records (for testing/debugging)
    func clearAllPayees() throws {
        let sql = "DELETE FROM PAY"
        try execute(sql)
        
        #if DEBUG
        print("[LocalDatabaseManager] ✅ Cleared ALL payee records from local database")
        #endif
    }
    
    /// Mark records as synced
    func markRecordsAsSynced() throws {
        // Mark all transactions as synced
        let updateTrnSql = "UPDATE TRN SET is_synced = 1 WHERE is_synced = 0"
        try execute(updateTrnSql)
        
        // Mark all payees as synced
        let updatePaySql = "UPDATE PAY SET is_synced = 1 WHERE is_synced = 0"
        try execute(updatePaySql)
        
        #if DEBUG
        print("[LocalDatabaseManager] ✅ Marked all records as synced")
        #endif
    }
    
    // MARK: - Helper Methods for Reading Columns
    
    private func columnString(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: cString)
    }
    
    // MARK: - Helper Methods for Binding Values
    
    private func bindText(_ statement: OpaquePointer?, _ index: Int32, _ value: String) {
        value.withCString { cString in
            // SQLITE_TRANSIENT = -1 (tells SQLite to make its own copy)
            sqlite3_bind_text(statement, index, cString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
    }
    
    private func columnIntOrNil(_ statement: OpaquePointer?, _ index: Int32) -> Int? {
        if sqlite3_column_type(statement, index) == SQLITE_NULL {
            return nil
        }
        return Int(sqlite3_column_int(statement, index))
    }
}
