//
//  SimpleMDBParser.swift
//  CheckbookApp
//
//  Simple MDB parser using mdbtools_c library
//  Works on iOS by calling mdbtools C functions directly
//

import Foundation

/// Simple MDB parser that uses mdbtools library directly via bridging header
/// This works on iOS and doesn't require command-line tools
struct SimpleMDBParser {
    let filePath: String
    
    enum ParseError: Error {
        case cannotOpenFile
        case tableNotFound(String)
        case readError(String)
        case columnReadError
    }
    
    /// Read all rows from a table
    func readTable(_ tableName: String) throws -> [[String: String]] {
        // Open the MDB file
        guard let mdb = mdb_open(filePath, MDB_NOFLAGS) else {
            throw ParseError.cannotOpenFile
        }
        defer { mdb_close(mdb) }
        
        // Read catalog to find table
        guard let catalog = mdb_read_catalog(mdb, Int32(MDB_TABLE)) else {
            throw ParseError.readError("Failed to read catalog")
        }
        
        // Find the table in the catalog
        var tablePtr: UnsafeMutablePointer<MdbTableDef>? = nil
        let catalogCount = Int(catalog.pointee.len)
        
        for i in 0..<catalogCount {
            // Access array element using the pdata pointer
            let entryPtr = catalog.pointee.pdata[i]?.assumingMemoryBound(to: MdbCatalogEntry.self)
            
            if let entry = entryPtr {
                // object_name is a fixed-size array, use withUnsafeBytes or tuple access
                let objName = withUnsafeBytes(of: entry.pointee.object_name) { buffer in
                    String(cString: buffer.baseAddress!.assumingMemoryBound(to: CChar.self))
                }
                
                if objName == tableName {
                    tablePtr = mdb_read_table(entry)
                    break
                }
            }
        }
        
        guard let table = tablePtr else {
            throw ParseError.tableNotFound(tableName)
        }
        defer { mdb_free_tabledef(table) }
        
        // Read columns
        guard let columns = mdb_read_columns(table) else {
            throw ParseError.columnReadError
        }
        
        // Get column names and info
        var columnNames: [String] = []
        let numCols = Int(table.pointee.num_cols)
        
        for i in 0..<numCols {
            // Access column from GPtrArray
            if let colPtr = columns.pointee.pdata[i]?.assumingMemoryBound(to: MdbColumn.self) {
                let name = withUnsafeBytes(of: colPtr.pointee.name) { buffer in
                    String(cString: buffer.baseAddress!.assumingMemoryBound(to: CChar.self))
                }
                columnNames.append(name)
            }
        }
        
        // Bind columns for reading - need to keep buffers alive
        var boundCols: [[CChar]] = Array(repeating: [CChar](repeating: 0, count: 256), count: numCols)
        
        for i in 0..<numCols {
            _ = mdb_bind_column(table, Int32(i + 1), &boundCols[i], nil)
        }
        
        // Rewind to start of table
        _ = mdb_rewind_table(table)
        
        // Read all rows
        var rows: [[String: String]] = []
        while mdb_fetch_row(table) != 0 {
            var row: [String: String] = [:]
            for (index, colName) in columnNames.enumerated() {
                let value = String(cString: boundCols[index])
                row[colName] = value.isEmpty ? "" : value
            }
            rows.append(row)
        }
        
        return rows
    }
    
    /// Read accounts from ACCT table
    func readAccounts() throws -> [(id: Int, name: String, balance: Decimal)] {
        let rows = try readTable("ACCT")
        
        var accounts: [(id: Int, name: String, balance: Decimal)] = []
        
        for row in rows {
            guard let hacctStr = row["hacct"],
                  let hacct = Int(hacctStr),
                  let szFull = row["szFull"],
                  !szFull.isEmpty else {
                continue
            }
            
            let balance: Decimal
            if let amtOpenStr = row["amtOpen"],
               let amt = Decimal(string: amtOpenStr) {
                balance = amt
            } else {
                balance = 0
            }
            
            accounts.append((id: hacct, name: szFull, balance: balance))
        }
        
        return accounts
    }
    
    /// Read transactions from TRN table
    func readTransactions(forAccount accountId: Int? = nil) throws -> [(id: Int, accountId: Int, date: Date, amount: Decimal)] {
        let rows = try readTable("TRN")
        
        var transactions: [(id: Int, accountId: Int, date: Date, amount: Decimal)] = []
        
        for row in rows {
            guard let htrnStr = row["htrn"],
                  let htrn = Int(htrnStr),
                  let hacctStr = row["hacct"],
                  let hacct = Int(hacctStr) else {
                continue
            }
            
            // Filter by account if specified
            if let accountId = accountId, hacct != accountId {
                continue
            }
            
            // Parse amount
            let amount: Decimal
            if let amtStr = row["amt"],
               let amt = Decimal(string: amtStr) {
                amount = amt
            } else {
                amount = 0
            }
            
            // Parse date (dt field is OLE date or date string)
            let date: Date
            if let dtStr = row["dt"], !dtStr.isEmpty {
                // Try parsing as date string "MM/DD/YY HH:MM:SS"
                let formatter = DateFormatter()
                formatter.dateFormat = "MM/dd/yy HH:mm:ss"
                date = formatter.date(from: dtStr) ?? Date()
            } else {
                date = Date()
            }
            
            transactions.append((id: htrn, accountId: hacct, date: date, amount: amount))
        }
        
        return transactions
    }
}

