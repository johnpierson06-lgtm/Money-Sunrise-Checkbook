//
//  SyncService.swift
//  CheckbookApp
//
//  Service for syncing local transactions to Money file using mdb-tools
//

import Foundation

/// Service for syncing local database to Money file
class SyncService {
    static let shared = SyncService()
    
    enum SyncError: Error, LocalizedError {
        case noUnsyncedData
        case decryptionFailed(String)
        case writeFailed(String)
        case uploadFailed(String)
        case cleanupFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .noUnsyncedData: return "No unsynced data found"
            case .decryptionFailed(let msg): return "Decryption failed: \(msg)"
            case .writeFailed(let msg): return "Write failed: \(msg)"
            case .uploadFailed(let msg): return "Upload failed: \(msg)"
            case .cleanupFailed(let msg): return "Cleanup failed: \(msg)"
            }
        }
    }
    
    private init() {}
    
    /// Sync all unsynced transactions and payees to Money file
    /// 
    /// CRITICAL ARCHITECTURE - Encryption Incompatibility:
    /// 
    /// Money .mny files use MSISAM RC4 encryption:
    /// - Complex: SHA1/MD5(password) + salt derivation + RC4
    /// - Implemented in MoneyDecryptorBridge
    /// 
    /// mdb-tools uses simple RC4 encryption:
    /// - Simple: RC4(db_key ^ page_number)
    /// - Implemented in write.c line 90-94
    /// 
    /// These are INCOMPATIBLE! mdb-tools cannot read MSISAM-encrypted pages.
    /// 
    /// Solution - HYBRID Mode:
    /// 1. Read metadata from DECRYPTED .mdb (mdb-tools can read this)
    /// 2. Pack row data using mdb_pack_row() (mdb-tools function)
    /// 3. Write packed data MANUALLY to .mny file (pages 15+, unencrypted)
    /// 4. Leave pages 1-14 UNTOUCHED (MSISAM encrypted)
    /// 5. Upload .mny - Money Desktop compatible!
    /// 
    /// Page Structure:
    /// - Page 0: Header (never encrypted)
    /// - Pages 1-14: System catalog (MSISAM encrypted)
    /// - Pages 15+: Data pages (NOT encrypted in MSISAM!)
    func syncToMoneyFile() async throws {
        #if DEBUG
        print("═══════════════════════════════════════════════════════════════")
        print("[SyncService] SYNC TO MONEY FILE - HYBRID MODE")
        print("[SyncService] .mny uses MSISAM encryption (incompatible with mdb-tools)")
        print("═══════════════════════════════════════════════════════════════")
        #endif
        
        // Step 1: Get unsynced data
        let transactions = try LocalDatabaseManager.shared.getUnsyncedTransactions()
        let payees = try LocalDatabaseManager.shared.getUnsyncedPayees()
        
        #if DEBUG
        print("[SyncService] Found \(transactions.count) unsynced transactions")
        print("[SyncService] Found \(payees.count) unsynced payees")
        #endif
        
        guard !transactions.isEmpty || !payees.isEmpty else {
            throw SyncError.noUnsyncedData
        }
        
        // Step 2: Get .mny file path
        #if DEBUG
        print("[SyncService] Getting .mny file...")
        #endif
        
        let mnyURL = try MoneyFileService.ensureLocalFile()
        
        #if DEBUG
        print("[SyncService] .mny: \(mnyURL.path)")
        #endif
        
        // Step 3: Get decrypted .mdb for metadata
        #if DEBUG
        print("[SyncService] Decrypting .mny for metadata...")
        #endif
        
        let password = try PasswordStore.shared.load()
        let mdbPath = try MoneyDecryptorBridge.decryptToTempFile(fromFile: mnyURL.path, password: password)
        
        #if DEBUG
        print("[SyncService] .mdb: \(mdbPath)")
        #endif
        
        // Step 4: Get max transaction and payee IDs from Money file
        #if DEBUG
        print("[SyncService] Reading max IDs from Money file...")
        #endif
        
        let parser = try MoneyFileParser(filePath: mdbPath)
        let maxTransactionId = try parser.getMaxTransactionId()
        let maxPayeeId = try parser.getMaxPayeeId()
        
        #if DEBUG
        print("[SyncService] Max existing transaction ID: \(maxTransactionId)")
        print("[SyncService] Max existing payee ID: \(maxPayeeId)")
        print("[SyncService] New transactions will start from: \(maxTransactionId + 1)")
        print("[SyncService] New payees will start from: \(maxPayeeId + 1)")
        #endif
        
        // Reassign payee IDs sequentially AND create a mapping
        var nextPayeeId = maxPayeeId + 1
        var payeesWithNewIds: [(payee: LocalPayee, newId: Int)] = []
        var payeeIdMapping: [Int: Int] = [:]  // oldId -> newId
        
        for payee in payees {
            #if DEBUG
            print("[SyncService] Reassigning payee ID: \(payee.hpay) → \(nextPayeeId)")
            #endif
            
            payeesWithNewIds.append((payee, nextPayeeId))
            payeeIdMapping[payee.hpay] = nextPayeeId  // Save mapping
            nextPayeeId += 1
        }
        
        // Reassign transaction IDs sequentially
        var nextId = maxTransactionId + 1
        var transactionsWithNewIds: [(transaction: LocalTransaction, newId: Int)] = []
        
        for transaction in transactions {
            #if DEBUG
            print("[SyncService] Reassigning transaction ID: \(transaction.htrn) → \(nextId)")
            
            // Check if this transaction references a payee that was just created
            if let oldPayeeId = transaction.lHpay, let newPayeeId = payeeIdMapping[oldPayeeId] {
                print("[SyncService]   → Remapping payee ID: \(oldPayeeId) → \(newPayeeId)")
            }
            #endif
            
            transactionsWithNewIds.append((transaction, nextId))
            nextId += 1
        }
        
        // Step 5: Make .mny writable
        // Step 5: Make .mny writable
        try makeWritable(mnyURL.path)
        
        #if DEBUG
        print("[SyncService] Made .mny writable")
        #endif
        
        // Step 6: Open in HYBRID mode
        // - Read metadata from decrypted .mdb
        // - Write data manually to .mny (pages 15+, unencrypted)
        #if DEBUG
        print("[SyncService] Opening in HYBRID mode...")
        #endif
        
        let writer = try MDBToolsWriter(
            mdbFilePath: mdbPath,        // Read metadata from decrypted .mdb
            mnyFilePath: mnyURL.path     // Write data manually to .mny
        )
        
        // Insert payees first (transactions may reference them) with reassigned sequential IDs
        for (originalPayee, newId) in payeesWithNewIds {
            #if DEBUG
            print("[SyncService] Inserting payee: \(originalPayee.szFull) (ID: \(newId), was \(originalPayee.hpay))")
            #endif
            
            // CRITICAL: Set dtLast to the transaction date if this payee is used in a transaction
            // Find the earliest transaction date that uses this payee
            var payeeLastUsedDate: String?
            for transaction in transactions {
                if transaction.lHpay == originalPayee.hpay {
                    // Found a transaction using this payee
                    payeeLastUsedDate = transaction.dt
                    #if DEBUG
                    print("[SyncService]   → Payee last used on: \(transaction.dt)")
                    #endif
                    break
                }
            }
            
            // Create a new payee with the sequential ID and updated dtLast
            let payeeWithNewId = LocalPayee(
                hpay: newId,  // Use sequential ID from file
                hpayParent: originalPayee.hpayParent,
                haddr: originalPayee.haddr,
                mComment: originalPayee.mComment,
                fHidden: originalPayee.fHidden,
                szAls: originalPayee.szAls,
                szFull: originalPayee.szFull,
                mAcctNum: originalPayee.mAcctNum,
                mBankId: originalPayee.mBankId,
                mBranchId: originalPayee.mBranchId,
                mUserAcctAtPay: originalPayee.mUserAcctAtPay,
                mIntlChkSum: originalPayee.mIntlChkSum,
                mCompanyName: originalPayee.mCompanyName,
                mContact: originalPayee.mContact,
                haddrBill: originalPayee.haddrBill,
                haddrShip: originalPayee.haddrShip,
                mCellPhone: originalPayee.mCellPhone,
                mPager: originalPayee.mPager,
                mWebPage: originalPayee.mWebPage,
                terms: originalPayee.terms,
                mPmtType: originalPayee.mPmtType,
                mCCNum: originalPayee.mCCNum,
                dtCCExp: originalPayee.dtCCExp,
                dDiscount: originalPayee.dDiscount,
                dRateTax: originalPayee.dRateTax,
                fVendor: originalPayee.fVendor,
                fCust: originalPayee.fCust,
                dtLastModified: originalPayee.dtLastModified,
                lContactData: originalPayee.lContactData,
                shippref: originalPayee.shippref,
                fNoRecurringBill: originalPayee.fNoRecurringBill,
                dtSerial: originalPayee.dtSerial,
                grfcontt: originalPayee.grfcontt,
                fAutofillMemo: originalPayee.fAutofillMemo,
                dtLast: payeeLastUsedDate,  // ⚠️ CRITICAL: Use transaction date, not current date!
                sguid: originalPayee.sguid,
                fUpdated: originalPayee.fUpdated,
                fGlobal: originalPayee.fGlobal,
                fLocal: originalPayee.fLocal
            )
            
            try writer.insertPayee(payeeWithNewId)
        }
        
        // Insert transactions with reassigned sequential IDs
        for (originalTransaction, newId) in transactionsWithNewIds {
            #if DEBUG
            print("[SyncService] Inserting transaction: ID=\(newId) (was \(originalTransaction.htrn)), Amount=\(originalTransaction.amt)")
            #endif
            
            // CRITICAL: Remap payee ID if this transaction references a newly created payee
            let remappedPayeeId: Int?
            if let oldPayeeId = originalTransaction.lHpay {
                if let newPayeeId = payeeIdMapping[oldPayeeId] {
                    #if DEBUG
                    print("[SyncService]   → Using remapped payee ID: \(oldPayeeId) → \(newPayeeId)")
                    #endif
                    remappedPayeeId = newPayeeId
                } else {
                    // Payee already existed in Money file, use original ID
                    remappedPayeeId = oldPayeeId
                }
            } else {
                // No payee
                remappedPayeeId = nil
            }
            
            // Create a new transaction with the sequential ID and remapped payee ID
            let transactionWithNewId = LocalTransaction(
                htrn: newId,  // Use sequential ID
                hacct: originalTransaction.hacct,
                hacctLink: originalTransaction.hacctLink,
                dt: originalTransaction.dt,
                dtSent: originalTransaction.dtSent,
                dtCleared: originalTransaction.dtCleared,
                dtPost: originalTransaction.dtPost,
                cs: originalTransaction.cs,
                hsec: originalTransaction.hsec,
                amt: originalTransaction.amt,
                szId: originalTransaction.szId,
                hcat: originalTransaction.hcat,
                frq: originalTransaction.frq,
                fDefPmt: originalTransaction.fDefPmt,
                mMemo: originalTransaction.mMemo,
                oltt: originalTransaction.oltt,
                grfEntryMethods: originalTransaction.grfEntryMethods,
                ps: originalTransaction.ps,
                amtVat: originalTransaction.amtVat,
                grftt: originalTransaction.grftt,
                act: originalTransaction.act,
                cFrqInst: originalTransaction.cFrqInst,
                fPrint: originalTransaction.fPrint,
                mFiStmtId: originalTransaction.mFiStmtId,
                olst: originalTransaction.olst,
                fDebtPlan: originalTransaction.fDebtPlan,
                grfstem: originalTransaction.grfstem,
                cpmtsRemaining: originalTransaction.cpmtsRemaining,
                instt: originalTransaction.instt,
                htrnSrc: originalTransaction.htrnSrc,
                payt: originalTransaction.payt,
                grftf: originalTransaction.grftf,
                lHtxsrc: originalTransaction.lHtxsrc,
                lHcrncUser: originalTransaction.lHcrncUser,
                amtUser: originalTransaction.amtUser,
                amtVATUser: originalTransaction.amtVATUser,
                tef: originalTransaction.tef,
                fRefund: originalTransaction.fRefund,
                fReimburse: originalTransaction.fReimburse,
                dtSerial: originalTransaction.dtSerial,
                fUpdated: originalTransaction.fUpdated,
                fCCPmt: originalTransaction.fCCPmt,
                fDefBillAmt: originalTransaction.fDefBillAmt,
                fDefBillDate: originalTransaction.fDefBillDate,
                lHclsKak: originalTransaction.lHclsKak,
                lHcls1: originalTransaction.lHcls1,
                lHcls2: originalTransaction.lHcls2,
                dtCloseOffYear: originalTransaction.dtCloseOffYear,
                dtOldRel: originalTransaction.dtOldRel,
                hbillHead: originalTransaction.hbillHead,
                iinst: originalTransaction.iinst,
                amtBase: originalTransaction.amtBase,
                rt: originalTransaction.rt,
                amtPreRec: originalTransaction.amtPreRec,
                amtPreRecUser: originalTransaction.amtPreRecUser,
                hstmtRel: originalTransaction.hstmtRel,
                dRateToBase: originalTransaction.dRateToBase,
                lHpay: remappedPayeeId,  // ⚠️ CRITICAL: Use remapped payee ID!
                sguid: originalTransaction.sguid,
                szAggTrnId: originalTransaction.szAggTrnId,
                rgbDigest: originalTransaction.rgbDigest
            )
            
            try writer.insertTransaction(transactionWithNewId)
        }
        
        try writer.save()
        
        #if DEBUG
        print("[SyncService] ✅ Wrote \(transactionsWithNewIds.count) transactions, \(payeesWithNewIds.count) payees")
        print("[SyncService] ℹ️  Transaction IDs: \(maxTransactionId + 1) to \(maxTransactionId + transactionsWithNewIds.count)")
        print("[SyncService] ℹ️  Payee IDs: \(maxPayeeId + 1) to \(maxPayeeId + payeesWithNewIds.count)")
        print("[SyncService] ℹ️  Pages 1-14 UNTOUCHED (MSISAM encrypted)")
        print("[SyncService] ℹ️  Pages 15+ WRITTEN (plain text)")
        #endif
        
        // Step 7: Upload modified .mny
        // Step 7: Upload modified .mny
        #if DEBUG
        print("[SyncService] Uploading .mny to OneDrive...")
        #endif
        
        try await uploadToOneDrive(mnyURL, asDecryptedMDB: false)
        
        #if DEBUG
        print("[SyncService] ✅ Uploaded")
        #endif
        
        // Step 8: Mark synced
        try LocalDatabaseManager.shared.markRecordsAsSynced()
        
        #if DEBUG
        print("[SyncService] ✅ Marked records as synced")
        print("═══════════════════════════════════════════════════════════════")
        print("[SyncService] SYNC COMPLETE!")
        print("[SyncService] Synced \(transactionsWithNewIds.count) transactions, \(payeesWithNewIds.count) payees")
        print("[SyncService] Transaction IDs: \(maxTransactionId + 1) to \(maxTransactionId + transactionsWithNewIds.count)")
        print("[SyncService] Payee IDs: \(maxPayeeId + 1) to \(maxPayeeId + payeesWithNewIds.count)")
        print("═══════════════════════════════════════════════════════════════")
        #endif
    }
    
    /// Make file writable
    private func makeWritable(_ path: String) throws {
        let fileManager = FileManager.default
        var attributes = try fileManager.attributesOfItem(atPath: path)
        
        // Set permissions to read/write for owner
        var permissions = (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0o644
        permissions |= 0o600  // rw-------
        
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: permissions)], ofItemAtPath: path)
        
        #if DEBUG
        print("[SyncService] Set file permissions to \(String(format: "0o%o", permissions))")
        #endif
    }
    
    /// Upload file to OneDrive with timestamp
    private func uploadToOneDrive(_ fileURL: URL, asDecryptedMDB: Bool = false) async throws {
        let timestamp = DateFormatter.yyyyMMddHHmmss.string(from: Date())
        
        // Upload as .mdb with timestamp to avoid overwriting original
        let uploadFileName = asDecryptedMDB 
            ? "Money_Test_\(timestamp).mdb"  // Upload as .mdb (unencrypted)
            : "Money_Test_\(timestamp).mny"  // Upload as .mny (encrypted)
        
        #if DEBUG
        print("[SyncService] Uploading as: \(uploadFileName)")
        if asDecryptedMDB {
            print("[SyncService] ℹ️  Uploading DECRYPTED .mdb file")
            print("[SyncService] ℹ️  Money Desktop will re-encrypt on next save")
        }
        #endif
        
        // Get parent folder ID from saved file info
        guard let parentFolderId = OneDriveFileManager.shared.getSavedParentFolderId() else {
            throw SyncError.uploadFailed("No parent folder ID saved")
        }
        
        // Get access token
        let token = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            AuthManager.shared.acquireTokenSilent(scopes: ["Files.ReadWrite"]) { token, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let token = token else {
                    continuation.resume(throwing: SyncError.uploadFailed("No access token"))
                    return
                }
                
                continuation.resume(returning: token)
            }
        }
        
        // Upload file
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            OneDriveAPI.uploadFile(
                accessToken: token,
                fileURL: fileURL,
                fileName: uploadFileName,
                parentFolderId: parentFolderId
            ) { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
        
        #if DEBUG
        print("[SyncService] ✅ Upload complete: \(uploadFileName)")
        #endif
    }
}


