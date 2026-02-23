//
//  LocalModels.swift
//  CheckbookApp
//
//  Data models for local database storage (unsynced transactions and payees)
//

import Foundation

// MARK: - Local Transaction Model

/// Represents a transaction stored in local SQLite database
/// Matches the full TRN schema from Microsoft Money
struct LocalTransaction {
    let htrn: Int                      // Column 1: Transaction ID
    let hacct: Int                     // Column 2: Account ID
    let hacctLink: String?             // Column 3: Linked account (for transfers)
    let dt: String                     // Column 4: Transaction date "MM/DD/YY HH:MM:SS"
    let dtSent: String                 // Column 5: Sent date
    let dtCleared: String              // Column 6: Cleared date
    let dtPost: String                 // Column 7: Post date
    let cs: Int                        // Column 8: Cleared status
    let hsec: String?                  // Column 9: Security ID
    let amt: Decimal                   // Column 10: Amount
    let szId: String?                  // Column 11: Check number
    let hcat: Int?                     // Column 12: Category ID
    let frq: Int                       // Column 13: Frequency (-1 = posted)
    let fDefPmt: Int                   // Column 14: Default payment
    let mMemo: String?                 // Column 15: Memo
    let oltt: Int                      // Column 16: Online transaction type
    let grfEntryMethods: Int           // Column 17: Entry method flags
    let ps: Int                        // Column 18: Posting status
    let amtVat: Double                 // Column 19: VAT amount
    let grftt: Int                     // Column 20: Transaction type flags
    let act: Int                       // Column 21: Account type
    let cFrqInst: String?              // Column 22: Frequency instance
    let fPrint: Int                    // Column 23: Print flag
    let mFiStmtId: String?             // Column 24: Statement ID
    let olst: Int                      // Column 25: Online statement
    let fDebtPlan: Int                 // Column 26: Debt plan flag
    let grfstem: Int                   // Column 27: Statement flags
    let cpmtsRemaining: Int            // Column 28: Payments remaining
    let instt: Int                     // Column 29: Installment type
    let htrnSrc: String?               // Column 30: Source transaction
    let payt: Int                      // Column 31: Payment type
    let grftf: Int                     // Column 32: Transfer flags
    let lHtxsrc: Int                   // Column 33: Tax source
    let lHcrncUser: Int                // Column 34: Currency (45 = USD)
    let amtUser: Decimal               // Column 35: Amount in user currency
    let amtVATUser: Double             // Column 36: VAT in user currency
    let tef: Int                       // Column 37: Transfer flag
    let fRefund: Int                   // Column 38: Refund flag
    let fReimburse: Int                // Column 39: Reimburse flag
    let dtSerial: String               // Column 40: Serial datetime
    let fUpdated: Int                  // Column 41: Updated flag (CRITICAL - must be 1)
    let fCCPmt: Int                    // Column 42: Credit card payment
    let fDefBillAmt: Int               // Column 43: Default bill amount
    let fDefBillDate: Int              // Column 44: Default bill date
    let lHclsKak: Int                  // Column 45: Classification
    let lHcls1: Int                    // Column 46: Classification 1
    let lHcls2: Int                    // Column 47: Classification 2
    let dtCloseOffYear: String         // Column 48: Close off year date
    let dtOldRel: String               // Column 49: Old release date
    let hbillHead: String?             // Column 50: Bill header
    let iinst: Int                     // Column 51: Instance number (CRITICAL - must be -1)
    let amtBase: String?               // Column 52: Base amount
    let rt: Int                        // Column 53: Rate
    let amtPreRec: String?             // Column 54: Pre-reconcile amount
    let amtPreRecUser: String?         // Column 55: Pre-reconcile user amount
    let hstmtRel: String?              // Column 56: Statement relation
    let dRateToBase: String?           // Column 57: Rate to base
    let lHpay: Int?                    // Column 58: Payee ID
    let sguid: String                  // Column 59: GUID
    let szAggTrnId: String?            // Column 60: Aggregation ID
    let rgbDigest: String?             // Column 61: Digest
    
    /// Create a new transaction from user input
    static func createNew(
        id: Int,
        accountId: Int,
        date: Date,
        amount: Decimal,
        categoryId: Int?,
        payeeId: Int?,
        memo: String?,
        isTransfer: Bool = false
    ) -> LocalTransaction {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM/dd/yy HH:mm:ss"
        dateFormatter.timeZone = TimeZone(identifier: "America/Denver") ?? TimeZone.current
        
        // Strip time from transaction date (Money expects 00:00:00)
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "America/Denver") ?? TimeZone.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let dateAtMidnight = calendar.date(from: dateComponents) ?? date
        let dateString = dateFormatter.string(from: dateAtMidnight)
        
        #if DEBUG
        print("[LocalTransaction] Creating transaction with date:")
        print("  Input date: \(date)")
        print("  Date at midnight: \(dateAtMidnight)")
        print("  Formatted string: '\(dateString)'")
        #endif
        
        // Current date/time for dtSerial (when transaction was entered)
        let currentDateTime = dateFormatter.string(from: Date())
        
        #if DEBUG
        print("  Current date/time: '\(currentDateTime)'")
        #endif
        
        // NULL_DATE must match real Money data
        // From actual .mny file analysis: 2958524.2916666665
        // This is Mon Feb 28 00:00:00 MST 10000 (7:00:00 UTC)
        // 
        // CRITICAL: Use a marker string that allocOleDate will detect
        // Format doesn't matter since allocOleDate checks for "10000" and converts directly
        let nullDate = "NULL_10000"  // Will be detected and converted to 2958524.2916666665
        
        #if DEBUG
        print("  NULL date marker: '\(nullDate)'")
        #endif
        
        // Generate GUID
        let guid = "{\(UUID().uuidString)}"
        
        return LocalTransaction(
            htrn: id,
            hacct: accountId,
            hacctLink: nil,
            dt: dateString,
            dtSent: nullDate,
            dtCleared: nullDate,
            dtPost: nullDate,
            cs: 0,
            hsec: nil,
            amt: amount,
            szId: nil,
            hcat: categoryId,
            frq: -1,  // Posted transaction
            fDefPmt: 0,
            mMemo: memo,
            oltt: -1,
            grfEntryMethods: 1,
            ps: 0,
            amtVat: 0.0,
            grftt: isTransfer ? 2 : 0,
            act: -1,  // CRITICAL: Must be -1 for regular transactions
            cFrqInst: nil,
            fPrint: 0,
            mFiStmtId: nil,
            olst: -1,
            fDebtPlan: 0,
            grfstem: 0,
            cpmtsRemaining: -1,
            instt: -1,
            htrnSrc: nil,
            payt: -1,
            grftf: 0,
            lHtxsrc: -1,
            lHcrncUser: 45,  // USD
            amtUser: amount,
            amtVATUser: 0.0,
            tef: -1,
            fRefund: 0,
            fReimburse: 0,
            dtSerial: currentDateTime,
            fUpdated: 1,  // CRITICAL
            fCCPmt: 0,
            fDefBillAmt: 0,
            fDefBillDate: 0,
            lHclsKak: -1,
            lHcls1: -1,
            lHcls2: -1,
            dtCloseOffYear: nullDate,
            dtOldRel: nullDate,
            hbillHead: nil,
            iinst: -1,  // CRITICAL
            amtBase: nil,
            rt: -1,
            amtPreRec: nil,
            amtPreRecUser: nil,
            hstmtRel: nil,
            dRateToBase: nil,
            lHpay: payeeId,
            sguid: guid,
            szAggTrnId: nil,
            rgbDigest: nil
        )
    }
}

// MARK: - Local Payee Model

/// Represents a payee stored in local SQLite database
/// Matches the full PAY schema from Microsoft Money
struct LocalPayee {
    let hpay: Int
    let hpayParent: Int?
    let haddr: Int?
    let mComment: String?
    let fHidden: Bool
    let szAls: String?
    let szFull: String
    let mAcctNum: String?
    let mBankId: String?
    let mBranchId: String?
    let mUserAcctAtPay: String?
    let mIntlChkSum: String?
    let mCompanyName: String?
    let mContact: String?
    let haddrBill: Int?
    let haddrShip: Int?
    let mCellPhone: String?
    let mPager: String?
    let mWebPage: String?
    let terms: Int
    let mPmtType: String?
    let mCCNum: String?
    let dtCCExp: String?
    let dDiscount: Double
    let dRateTax: Double
    let fVendor: Bool
    let fCust: Bool
    let dtLastModified: String
    let lContactData: Int
    let shippref: Int
    let fNoRecurringBill: Bool
    let dtSerial: String
    let grfcontt: Int
    let fAutofillMemo: Bool
    let dtLast: String?
    let sguid: String
    let fUpdated: Bool
    let fGlobal: Bool
    let fLocal: Bool
    
    /// Create a new payee from user input
    static func createNew(id: Int, name: String) -> LocalPayee {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM/dd/yy HH:mm:ss"
        dateFormatter.timeZone = TimeZone(identifier: "America/Denver") ?? TimeZone.current
        let currentDateTime = dateFormatter.string(from: Date())
        
        // NULL_DATE must match real Money data - use marker that allocOleDate will detect
        let nullDate = "NULL_10000"  // Will be converted to 2958524.0 (minus 7hrs to compensate for timezone)
        
        // Generate GUID
        let guid = "{\(UUID().uuidString.uppercased())}"
        
        #if DEBUG
        print("[LocalPayee.createNew] Creating payee:")
        print("  id: \(id)")
        print("  name: '\(name)'")
        print("  currentDateTime: '\(currentDateTime)'")
        print("  guid: '\(guid)'")
        #endif
        
        return LocalPayee(
            hpay: id,
            hpayParent: nil,
            haddr: nil,
            mComment: nil,
            fHidden: false,
            szAls: nil,
            szFull: name,
            mAcctNum: nil,
            mBankId: nil,
            mBranchId: nil,
            mUserAcctAtPay: nil,
            mIntlChkSum: nil,
            mCompanyName: nil,
            mContact: nil,
            haddrBill: nil,
            haddrShip: nil,
            mCellPhone: nil,
            mPager: nil,
            mWebPage: nil,
            terms: -1,
            mPmtType: nil,
            mCCNum: nil,
            dtCCExp: nullDate,
            dDiscount: 0.0,
            dRateTax: 0.0,
            fVendor: false,
            fCust: false,
            dtLastModified: currentDateTime,
            lContactData: -1,
            shippref: -1,
            fNoRecurringBill: false,
            dtSerial: currentDateTime,
            grfcontt: -1,
            fAutofillMemo: false,
            dtLast: nil,
            sguid: guid,
            fUpdated: true,
            fGlobal: false,
            fLocal: true
        )
    }
}
