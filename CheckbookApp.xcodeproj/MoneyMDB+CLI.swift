import Foundation

/// Alternative implementation using mdb-export CLI tool
/// This is simpler than linking the C library and works well for development/testing
extension MoneyMDB {
    
    /// Reads accounts using mdb-export command-line tool
    static func readAccountsUsingCLI(fromFile path: String, password: String?) throws -> [Account] {
        // Decrypt to temp MDB
        let decryptedPath = try MoneyDecryptorBridge.decryptToTempFile(fromFile: path, password: password)
        
        #if DEBUG
        print("[MoneyMDB-CLI] Decrypted file path: \(decryptedPath)")
        print("[MoneyMDB-CLI] Checking if mdb-export is available...")
        print("[MoneyMDB-CLI] mdb-export available: \(MDBToolsCLI.isAvailable())")
        #endif
        
        // Use mdb-export to read ACCT table
        let rows = try MDBToolsCLI.readTable(mdbPath: decryptedPath, tableName: "ACCT")
        
        #if DEBUG
        print("[MoneyMDB-CLI] ✅ Read \(rows.count) rows from ACCT table")
        if let firstRow = rows.first {
            print("[MoneyMDB-CLI] Sample row columns: \(firstRow.keys.joined(separator: ", "))")
        }
        #endif
        
        // Parse rows into Account objects
        var accounts: [Account] = []
        
        for row in rows {
            guard let hacctStr = row["hacct"],
                  let accountId = Int(hacctStr),
                  let accountName = row["szFull"] else {
                #if DEBUG
                print("[MoneyMDB-CLI] ⚠️ Skipping row with missing required fields")
                #endif
                continue
            }
            
            // Parse amtOpen (opening balance)
            let balance: Decimal
            if let amtOpenStr = row["amtOpen"], !amtOpenStr.isEmpty {
                balance = Decimal(string: amtOpenStr) ?? 0
            } else {
                balance = 0
            }
            
            let account = Account(id: accountId, name: accountName, beginningBalance: balance)
            accounts.append(account)
            
            #if DEBUG
            print("[MoneyMDB-CLI]   Account: ID=\(accountId), Name=\(accountName), Balance=\(balance)")
            #endif
        }
        
        #if DEBUG
        print("[MoneyMDB-CLI] ✅ Successfully parsed \(accounts.count) accounts")
        #endif
        
        return accounts
    }
    
    /// Reads transactions using mdb-export command-line tool
    static func readTransactionsUsingCLI(fromFile path: String, password: String?, accountId: Int) throws -> [Transaction] {
        let decryptedPath = try MoneyDecryptorBridge.decryptToTempFile(fromFile: path, password: password)
        
        let rows = try MDBToolsCLI.readTable(mdbPath: decryptedPath, tableName: "TRN")
        
        #if DEBUG
        print("[MoneyMDB-CLI] Read \(rows.count) rows from TRN table")
        #endif
        
        var transactions: [Transaction] = []
        
        for row in rows {
            // Filter by account ID
            guard let hacctStr = row["hacct"],
                  let acctId = Int(hacctStr),
                  acctId == accountId else {
                continue
            }
            
            guard let htrnStr = row["htrn"],
                  let transactionId = Int(htrnStr) else {
                continue
            }
            
            // Parse amount
            let amount: Decimal
            if let amtStr = row["amt"], !amtStr.isEmpty {
                amount = Decimal(string: amtStr) ?? 0
            } else {
                amount = 0
            }
            
            // Parse date (Jet dates are stored as double - days since 1899-12-30)
            let date: Date
            if let dtStr = row["dt"], !dtStr.isEmpty, let dtDouble = Double(dtStr) {
                // Convert Jet date to Swift Date
                // Jet epoch is 1899-12-30, we need days since then
                let jetEpoch = Date(timeIntervalSince1970: -2209161600) // 1899-12-30 00:00:00 UTC
                date = jetEpoch.addingTimeInterval(dtDouble * 86400) // 86400 seconds per day
            } else {
                date = Date()
            }
            
            let transaction = Transaction(id: transactionId, accountId: acctId, date: date, amount: amount)
            transactions.append(transaction)
        }
        
        #if DEBUG
        print("[MoneyMDB-CLI] ✅ Found \(transactions.count) transactions for account \(accountId)")
        #endif
        
        return transactions
    }
}
