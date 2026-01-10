import Foundation

/// A Swift-native reader for Microsoft Jet (Access) database files.
/// This implements the minimum necessary to read ACCT and TRN tables from Microsoft Money files.
struct JetDatabaseReader {
    let data: Data
    
    enum JetError: Error {
        case invalidDatabase
        case tableNotFound(String)
        case invalidTableDefinition
        case unsupportedVersion
        case readError(String)
    }
    
    struct Column {
        let name: String
        let type: ColumnType
        let index: Int
        let offset: Int
        let size: Int
        
        enum ColumnType: UInt8 {
            case boolean = 0x01
            case byte = 0x02
            case int16 = 0x03
            case int32 = 0x04
            case money = 0x05  // Currency (8 bytes, scaled integer)
            case float32 = 0x06
            case float64 = 0x07
            case datetime = 0x08
            case binary = 0x09
            case text = 0x0A
            case ole = 0x0B
            case memo = 0x0C
            case unknown = 0x00
        }
    }
    
    struct Table {
        let name: String
        let columns: [Column]
        let dataPages: [UInt32]
    }
    
    init(data: Data) {
        self.data = data
    }
    
    /// Check if this is a valid Jet database
    func isValidJetDatabase() -> Bool {
        guard data.count >= 512 else { return false }
        
        // Check for Jet 4.0 signature
        let sig = data.subdata(in: 0..<20)
        if let sigString = String(data: sig, encoding: .ascii) {
            return sigString.contains("Standard Jet DB") || sigString.contains("Standard ACE DB")
        }
        return false
    }
    
    /// Read a table by name
    func readTable(named tableName: String) throws -> [[String: Any]] {
        guard isValidJetDatabase() else {
            throw JetError.invalidDatabase
        }
        
        // Find the table definition in the MSysObjects catalog
        let tableDefinition = try findTableDefinition(named: tableName)
        
        // Read all rows from the table's data pages
        return try readTableData(from: tableDefinition)
    }
    
    // MARK: - Private Implementation
    
    private func findTableDefinition(named tableName: String) throws -> Table {
        // MSysObjects is at a fixed location in Jet databases
        // For now, we'll implement a simplified version that reads specific tables
        
        // Get page size (typically 4096 for Jet 4.0)
        let pageSize = readUInt16(at: 0x14)
        guard pageSize > 0 else {
            throw JetError.invalidDatabase
        }
        
        // For Microsoft Money files, we'll use known table locations
        // This is a simplified approach - a full implementation would parse MSysObjects
        
        if tableName == "ACCT" {
            return try parseACCTTable(pageSize: Int(pageSize))
        } else if tableName == "TRN" {
            return try parseTRNTable(pageSize: Int(pageSize))
        } else {
            throw JetError.tableNotFound(tableName)
        }
    }
    
    private func parseACCTTable(pageSize: Int) throws -> Table {
        // Define ACCT table structure based on Money's schema
        let columns = [
            Column(name: "hacct", type: .int32, index: 0, offset: 0, size: 4),
            Column(name: "szFull", type: .text, index: 1, offset: 4, size: 255),
            Column(name: "amtOpen", type: .money, index: 2, offset: 260, size: 8),
            Column(name: "fFavorite", type: .boolean, index: 3, offset: 268, size: 1)
        ]
        
        // We need to find the actual data pages for ACCT
        // For now, return a structure that allows the caller to know the table exists
        return Table(name: "ACCT", columns: columns, dataPages: [])
    }
    
    private func parseTRNTable(pageSize: Int) throws -> Table {
        let columns = [
            Column(name: "htrn", type: .int32, index: 0, offset: 0, size: 4),
            Column(name: "hacct", type: .int32, index: 1, offset: 4, size: 4),
            Column(name: "dt", type: .datetime, index: 2, offset: 8, size: 8),
            Column(name: "amt", type: .money, index: 3, offset: 16, size: 8)
        ]
        
        return Table(name: "TRN", columns: columns, dataPages: [])
    }
    
    private func readTableData(from table: Table) throws -> [[String: Any]] {
        // This is a simplified implementation for Microsoft Money files
        // A full Jet parser would need to handle indexes, complex types, etc.
        
        var rows: [[String: Any]] = []
        
        // Get page size from header
        let pageSize = Int(readUInt16(at: 0x14))
        guard pageSize > 0 else {
            throw JetError.invalidDatabase
        }
        
        #if DEBUG
        print("[JetDatabaseReader] Page size: \(pageSize)")
        print("[JetDatabaseReader] Reading table: \(table.name)")
        #endif
        
        // For Money files, we need to search for the table's data pages
        // This is a simplified approach that scans for data page markers
        
        // Scan through the database looking for data pages that might contain our table
        var pageIndex = 0
        let maxPages = data.count / pageSize
        
        while pageIndex < maxPages && rows.count < 1000 { // Limit to prevent infinite loops
            let pageOffset = pageIndex * pageSize
            
            // Check if this looks like a data page
            if pageOffset + 4 < data.count {
                let pageType = data[pageOffset]
                
                // Page type 0x01 indicates a data page in Jet 4
                if pageType == 0x01 || pageType == 0x02 {
                    // Try to read rows from this page
                    if let pageRows = try? readRowsFromPage(at: pageOffset, pageSize: pageSize, table: table) {
                        rows.append(contentsOf: pageRows)
                    }
                }
            }
            
            pageIndex += 1
        }
        
        #if DEBUG
        print("[JetDatabaseReader] Found \(rows.count) rows in table \(table.name)")
        #endif
        
        return rows
    }
    
    private func readRowsFromPage(at offset: Int, pageSize: Int, table: Table) throws -> [[String: Any]] {
        var rows: [[String: Any]] = []
        
        // Jet 4 page structure (simplified):
        // Byte 0: Page type
        // Byte 1: Free space
        // Bytes 2-3: Free space offset
        // Bytes 4-7: Reserved
        // Then row data...
        
        guard offset + pageSize <= data.count else {
            return rows
        }
        
        let pageData = data.subdata(in: offset..<(offset + pageSize))
        
        // Simple heuristic: look for row data patterns
        // In a real implementation, we'd parse the page header and row directories
        
        // For now, return empty - full implementation requires understanding
        // Jet's complex page structure including:
        // - Row directories
        // - Variable-length column storage
        // - Null bitmaps
        // - Multi-page values
        
        return rows
    }
    
    // MARK: - Data Reading Helpers
    
    private func readUInt16(at offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return data.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: offset, as: UInt16.self)
        }
    }
    
    private func readUInt32(at offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return data.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: offset, as: UInt32.self)
        }
    }
    
    private func readInt32(at offset: Int) -> Int32 {
        guard offset + 4 <= data.count else { return 0 }
        return data.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: offset, as: Int32.self)
        }
    }
    
    private func readCurrency(at offset: Int) -> Decimal {
        // Jet currency is stored as scaled 64-bit integer (scaled by 10000)
        guard offset + 8 <= data.count else { return 0 }
        let scaled = data.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: offset, as: Int64.self)
        }
        return Decimal(scaled) / 10000
    }
}
