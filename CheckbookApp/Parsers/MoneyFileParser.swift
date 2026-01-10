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
    
    /// Parse transactions from the TRN table
    /// Column mapping:
    /// - htrn: unique transaction identifier (Int)
    /// - hacct: account ID (Int)
    /// - dtrans: transaction date
    /// - amt: transaction amount (Decimal, can be positive or negative)
    /// - hpay: payee ID (Int, optional)
    /// - hcat: category ID (Int, optional)
    /// - szMemo: memo text (String, optional)
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
            
            // Extract dtrans (transaction date)
            let date = parseDate(row["dtrans"])
            
            // Extract hpay (payee ID, optional)
            let payeeId: Int? = {
                guard let hpayStr = row["hpay"],
                      !hpayStr.isEmpty else { return nil }
                return Int(hpayStr)
            }()
            
            // Extract hcat (category ID, optional)
            let categoryId: Int? = {
                guard let hcatStr = row["hcat"],
                      !hcatStr.isEmpty else { return nil }
                return Int(hcatStr)
            }()
            
            // Extract szMemo (memo, optional)
            let memo = row["szMemo"]
            
            transactions.append(MoneyTransaction(
                id: htrn,
                accountId: hacct,
                date: date,
                amount: amount,
                payeeId: payeeId,
                categoryId: categoryId,
                memo: memo
            ))
        }
        
        return transactions
    }
    
    // MARK: - Category Parsing
    
    /// Parse categories from the CAT table
    /// Column mapping:
    /// - hcat: unique category identifier (Int)
    /// - szName: category name (String)
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
            
            // Extract szName (category name)
            let szName = row["szName"] ?? ""
            guard !szName.isEmpty else { continue }
            
            categories.append(MoneyCategory(
                id: hcat,
                name: szName
            ))
        }
        
        return categories
    }
    
    // MARK: - Payee Parsing
    
    /// Parse payees from the PAY table
    /// Column mapping:
    /// - hpay: unique payee identifier (Int)
    /// - szName: payee name (String)
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
            
            // Extract szName (payee name)
            let szName = row["szName"] ?? ""
            guard !szName.isEmpty else { continue }
            
            payees.append(MoneyPayee(
                id: hpay,
                name: szName
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
        
        // Try various date formats
        let formatters: [DateFormatter] = [
            // Standard format with time
            {
                let f = DateFormatter()
                f.dateFormat = "MM/dd/yyyy HH:mm:ss"
                return f
            }(),
            // Short format
            {
                let f = DateFormatter()
                f.dateFormat = "MM/dd/yy HH:mm:ss"
                return f
            }(),
            // Date only
            {
                let f = DateFormatter()
                f.dateFormat = "MM/dd/yyyy"
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
                return date
            }
        }
        
        // If all else fails, try parsing as OLE automation date
        if let oleDate = Double(dateString) {
            return oleAutomationDateToDate(oleDate)
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
