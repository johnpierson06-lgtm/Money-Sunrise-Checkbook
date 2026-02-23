//
//  MoneyFileParser.swift
//  CheckbookApp
//
//  Parser for Microsoft Money database files using mdbtools
//  This works natively on iOS without requiring command-line tools
//

import Foundation

#if canImport(mdbtools_c)

/// Parser for Microsoft Money database files
/// Uses mdbtools_c library to read ACCT, TRN, CAT, and PAY tables
struct MoneyFileParser {
    let filePath: String
    private let parser: SimpleMDBParser
    
    init(filePath: String) {
        self.filePath = filePath
        self.parser = SimpleMDBParser(filePath: filePath)
    }
    
    enum ParseError: Error {
        case invalidData(String)
        case tableReadError(Error)
    }
    
    // MARK: - Account Parsing
    
    /// Parse accounts from the ACCT table
    /// Column mapping:
    /// - hacct: unique account identifier (Int)
    /// - szFull: full account name (String)
    /// - amtOpen: opening balance (Decimal)
    /// - fFavorite: is favorite account (Bool)
    func parseAccounts() throws -> [MoneyAccount] {
        do {
            let rows = try parser.readTable("ACCT")
            return parseAccountRows(rows)
        } catch {
            throw ParseError.tableReadError(error)
        }
    }
    
    private func parseAccountRows(_ rows: [[String: String]]) -> [MoneyAccount] {
        var accounts: [MoneyAccount] = []
        
        for row in rows {
            // Extract hacct (account ID)
            guard let hacctStr = row["hacct"],
                  let hacct = Int(hacctStr) else {
                continue
            }
            
            // Extract szFull (account name)
            let szFull = row["szFull"] ?? ""
            guard !szFull.isEmpty else { continue }
            
            // Extract amtOpen (opening balance)
            let balance: Decimal
            if let amtOpenStr = row["amtOpen"],
               !amtOpenStr.isEmpty,
               let amt = Decimal(string: amtOpenStr) {
                balance = amt
            } else {
                balance = 0
            }
            
            accounts.append(MoneyAccount(
                id: hacct,
                name: szFull,
                beginningBalance: balance
            ))
        }
        
        return accounts
    }
    
    // MARK: - Transaction Parsing
    
    /// Get the maximum transaction ID from the TRN table
    /// This is used to generate sequential IDs for new transactions
    func getMaxTransactionId() throws -> Int {
        do {
            // Read all transactions and find the max ID
            let rows = try parser.readTable("TRN")
            
            var maxId = 0
            for row in rows {
                if let htrnStr = row["htrn"],
                   let htrn = Int(htrnStr) {
                    maxId = max(maxId, htrn)
                }
            }
            
            #if DEBUG
            print("[MoneyFileParser] Max transaction ID: \(maxId)")
            #endif
            
            return maxId
        } catch {
            throw ParseError.tableReadError(error)
        }
    }
    
    /// Get the maximum payee ID from the PAY table
    /// This is used to generate sequential IDs for new payees
    func getMaxPayeeId() throws -> Int {
        do {
            // Read all payees and find the max ID
            let rows = try parser.readTable("PAY")
            
            var maxId = 0
            for row in rows {
                if let hpayStr = row["hpay"],
                   let hpay = Int(hpayStr) {
                    maxId = max(maxId, hpay)
                }
            }
            
            #if DEBUG
            print("[MoneyFileParser] Max payee ID: \(maxId)")
            #endif
            
            return maxId
        } catch {
            throw ParseError.tableReadError(error)
        }
    }
    
    /// Parse transactions from the TRN table
    /// Column mapping:
    /// - htrn: unique transaction identifier (Int)
    /// - hacct: account ID (Int)
    /// - dt: transaction date
    /// - amt: transaction amount (Decimal, can be positive or negative)
    /// - lHpay: payee ID (Int, optional)
    /// - hcat: category ID (Int, optional)
    /// - mMemo: memo text (String, optional)
    /// - frq: frequency (-1 = posted, 3 = recurring schedule)
    /// - grftt: transaction type flags (bit 6 = split detail)
    /// - iinst: instance number for recurring transactions
    func parseTransactions(forAccount accountId: Int? = nil) throws -> [MoneyTransaction] {
        do {
            let rows = try parser.readTable("TRN")
            return parseTransactionRows(rows, filterAccountId: accountId)
        } catch {
            throw ParseError.tableReadError(error)
        }
    }
    
    private func parseTransactionRows(_ rows: [[String: String]], filterAccountId: Int?) -> [MoneyTransaction] {
        var transactions: [MoneyTransaction] = []
        
        for row in rows {
            // Extract htrn (transaction ID)
            guard let htrnStr = row["htrn"],
                  let htrn = Int(htrnStr) else {
                continue
            }
            
            // Extract hacct (account ID)
            guard let hacctStr = row["hacct"],
                  let hacct = Int(hacctStr) else {
                continue
            }
            
            // Filter by account if specified
            if let filterAccountId = filterAccountId,
               hacct != filterAccountId {
                continue
            }
            
            // Extract amt (transaction amount)
            let amount: Decimal
            if let amtStr = row["amt"],
               !amtStr.isEmpty,
               let amt = Decimal(string: amtStr) {
                amount = amt
            } else {
                amount = 0
            }
            
            // Extract dt (transaction date)
            let date = parseDate(row["dt"])
            
            // Extract lHpay (payee ID, optional) - note: this is column 58 in schema
            let payeeId: Int? = {
                guard let lHpayStr = row["lHpay"],
                      !lHpayStr.isEmpty else { return nil }
                return Int(lHpayStr)
            }()
            
            // Extract hcat (category ID, optional)
            let categoryId: Int? = {
                guard let hcatStr = row["hcat"],
                      !hcatStr.isEmpty else { return nil }
                return Int(hcatStr)
            }()
            
            // Extract mMemo (memo, optional)
            // Memo fields can contain corrupted data or special encoding - sanitize it
            let memo: String? = {
                guard let mMemo = row["mMemo"],
                      !mMemo.isEmpty else { return nil }
                
                // Filter out corrupted/invalid UTF-8 sequences
                // If the string contains only "?" characters, it's corrupted - return nil
                let questionMarkCount = mMemo.filter { $0 == "?" }.count
                if questionMarkCount > 3 && questionMarkCount == mMemo.count {
                    return nil // All question marks = corrupted
                }
                
                // Replace any invalid characters with empty string
                let cleaned = mMemo.filter { char in
                    char.unicodeScalars.allSatisfy { scalar in
                        // Keep printable ASCII and common Unicode
                        (scalar.value >= 32 && scalar.value < 127) || // Printable ASCII
                        (scalar.value >= 128 && scalar.value < 55296) || // Common Unicode
                        (scalar.value >= 57344 && scalar.value < 65536) // More Unicode
                    }
                }
                
                return cleaned.isEmpty ? nil : cleaned
            }()
            
            // Extract frq (frequency)
            let frequency: Int = {
                guard let frqStr = row["frq"],
                      !frqStr.isEmpty,
                      let frq = Int(frqStr) else { return -1 }
                return frq
            }()
            
            // Extract grftt (transaction type flags)
            let transactionTypeFlags: Int = {
                guard let grfttStr = row["grftt"],
                      !grfttStr.isEmpty,
                      let grftt = Int(grfttStr) else { return 0 }
                return grftt
            }()
            
            // Extract iinst (instance number for recurring transactions)
            // Note: -1 means "not set" in Money database, treat it as nil
            let instanceNumber: Int? = {
                guard let iinstStr = row["iinst"],
                      !iinstStr.isEmpty,
                      let iinst = Int(iinstStr),
                      iinst >= 0 else { return nil }  // -1 or negative = nil
                return iinst
            }()
            
            #if DEBUG
            // Log filtering for account 2 to debug balance calculation
            if hacct == 2 && frequency == -1 {
                let shouldCount = transactionTypeFlags < 64 || instanceNumber != nil
                print("[MoneyFileParser] htrn=\(htrn) amt=\(amount) frq=\(frequency) grftt=\(transactionTypeFlags) iinst=\(instanceNumber?.description ?? "nil") shouldCount=\(shouldCount)")
            }
            #endif
            
            transactions.append(MoneyTransaction(
                id: htrn,
                accountId: hacct,
                date: date,
                amount: amount,
                payeeId: payeeId,
                categoryId: categoryId,
                memo: memo,
                frequency: frequency,
                transactionTypeFlags: transactionTypeFlags,
                instanceNumber: instanceNumber
            ))
        }
        
        return transactions
    }
    
    // MARK: - Category Parsing
    
    /// Parse categories from the CAT table
    /// Column mapping:
    /// - hcat: unique category identifier (Int)
    /// - szFull: full category name (String)
    /// - hcatParent: parent category ID (Int, optional)
    /// - nLevel: hierarchy level (Int)
    func parseCategories() throws -> [MoneyCategory] {
        do {
            let rows = try parser.readTable("CAT")
            return parseCategoryRows(rows)
        } catch {
            throw ParseError.tableReadError(error)
        }
    }
    
    private func parseCategoryRows(_ rows: [[String: String]]) -> [MoneyCategory] {
        var categories: [MoneyCategory] = []
        
        for row in rows {
            // Extract hcat (category ID)
            guard let hcatStr = row["hcat"],
                  let hcat = Int(hcatStr) else {
                continue
            }
            
            // Extract szFull (category name)
            let szFull = row["szFull"] ?? ""
            guard !szFull.isEmpty else { continue }
            
            // Extract hcatParent (parent category ID, optional)
            let parentId: Int? = {
                guard let parentStr = row["hcatParent"],
                      !parentStr.isEmpty,
                      let parent = Int(parentStr),
                      parent >= 0 else { return nil }
                return parent
            }()
            
            // Extract nLevel (hierarchy level)
            let level: Int = {
                guard let levelStr = row["nLevel"],
                      let lvl = Int(levelStr) else { return 0 }
                return lvl
            }()
            
            categories.append(MoneyCategory(
                id: hcat,
                name: szFull,
                parentId: parentId,
                level: level
            ))
        }
        
        return categories
    }
    
    // MARK: - Payee Parsing
    
    /// Parse payees from the PAY table
    /// Column mapping:
    /// - hpay: unique payee identifier (Int)
    /// - szFull: full payee name (String)
    func parsePayees() throws -> [MoneyPayee] {
        do {
            let rows = try parser.readTable("PAY")
            return parsePayeeRows(rows)
        } catch {
            throw ParseError.tableReadError(error)
        }
    }
    
    private func parsePayeeRows(_ rows: [[String: String]]) -> [MoneyPayee] {
        var payees: [MoneyPayee] = []
        
        for row in rows {
            // Extract hpay (payee ID)
            guard let hpayStr = row["hpay"],
                  let hpay = Int(hpayStr) else {
                continue
            }
            
            // Extract szFull (payee name)
            let szFull = row["szFull"] ?? ""
            guard !szFull.isEmpty else { continue }
            
            payees.append(MoneyPayee(
                id: hpay,
                name: szFull
            ))
        }
        
        return payees
    }
    
    // MARK: - Calculate Account Balance
    
    /// Calculate the current balance for an account
    /// Balance = beginningBalance + sum(all transactions)
    func calculateBalance(for account: MoneyAccount, transactions: [MoneyTransaction]) -> Decimal {
        let transactionTotal = transactions
            .filter { $0.accountId == account.id }
            .map { $0.amount }
            .reduce(0, +)
        
        return account.beginningBalance + transactionTotal
    }
    
    // MARK: - Helper Methods
    
    private func parseDate(_ dateString: String?) -> Date {
        guard let dateString = dateString, !dateString.isEmpty else {
            return Date()
        }
        
        // Try parsing as OLE automation date first (most common in Money files)
        if let oleDate = Double(dateString) {
            return oleAutomationDateToDate(oleDate)
        }
        
        // Try various date formats
        let formatters: [DateFormatter] = [
            // Standard format with time (4-digit year)
            {
                let f = DateFormatter()
                f.dateFormat = "MM/dd/yyyy HH:mm:ss"
                return f
            }(),
            // Short format with time (2-digit year)
            {
                let f = DateFormatter()
                f.dateFormat = "MM/dd/yy HH:mm:ss"
                return f
            }(),
            // Date only (4-digit year)
            {
                let f = DateFormatter()
                f.dateFormat = "MM/dd/yyyy"
                return f
            }(),
            // Date only (2-digit year)
            {
                let f = DateFormatter()
                f.dateFormat = "MM/dd/yy"
                return f
            }(),
            // ISO 8601
            {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                return f
            }()
        ]
        
        for formatter in formatters {
            if let date = formatter.date(from: dateString) {
                // Fix 2-digit year issue: if year is < 100, add 2000
                let calendar = Calendar.current
                let year = calendar.component(.year, from: date)
                if year < 100 {
                    var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
                    components.year = 2000 + year
                    return calendar.date(from: components) ?? date
                }
                return date
            }
        }
        
        return Date()
    }
    
    /// Convert OLE Automation date (used by Microsoft Money) to Swift Date
    /// OLE Automation date is days since December 30, 1899
    private func oleAutomationDateToDate(_ oleDate: Double) -> Date {
        // OLE Automation date epoch: December 30, 1899
        let oleEpoch = DateComponents(year: 1899, month: 12, day: 30)
        guard let baseDate = Calendar.current.date(from: oleEpoch) else {
            return Date()
        }
        
        // Add the number of days (oleDate) to the base date
        let seconds = oleDate * 24 * 60 * 60
        return baseDate.addingTimeInterval(seconds)
    }
}

#else

// Fallback when mdbtools_c is not available
struct MoneyFileParser {
    let filePath: String
    
    enum ParseError: Error {
        case notAvailable
    }
    
    func parseAccounts() throws -> [MoneyAccount] {
        throw ParseError.notAvailable
    }
    
    func parseTransactions(forAccount accountId: Int? = nil) throws -> [MoneyTransaction] {
        throw ParseError.notAvailable
    }
    
    func parseCategories() throws -> [MoneyCategory] {
        throw ParseError.notAvailable
    }
    
    func parsePayees() throws -> [MoneyPayee] {
        throw ParseError.notAvailable
    }
    
    func calculateBalance(for account: MoneyAccount, transactions: [MoneyTransaction]) -> Decimal {
        return 0
    }
}

#endif
