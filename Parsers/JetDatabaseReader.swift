import Foundation

/// A Swift-native reader for Microsoft Jet 4 (Access 2000) database files.
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
    
    init(data: Data) {
        self.data = data
    }
    
    /// Check if this is a valid Jet/MSISAM database
    func isValidJetDatabase() -> Bool {
        guard data.count >= 512 else { return false }
        
        let sig = data.subdata(in: 0..<20)
        if let sigString = String(data: sig, encoding: .ascii) {
            return sigString.contains("Standard Jet DB") || 
                   sigString.contains("Standard ACE DB") ||
                   sigString.contains("MSISAM")  // MSISAM is an older Jet format
        }
        return false
    }
    
    /// Read a table by name and return rows as dictionaries
    func readTable(named tableName: String) throws -> [[String: Any]] {
        guard isValidJetDatabase() else {
            throw JetError.invalidDatabase
        }
        
        // Determine if this is MSISAM or Jet
        let isMSISAM = String(data: data.prefix(20), encoding: .ascii)?.contains("MSISAM") ?? false
        
        // Get page size - MSISAM stores it differently than Jet
        let pageSize: Int
        if isMSISAM {
            // MSISAM databases typically use 4096-byte pages
            // The page size isn't stored at offset 0x14 in MSISAM format
            pageSize = 4096
            #if DEBUG
            print("[JetDatabaseReader] MSISAM detected, using default page size: \(pageSize)")
            print("[JetDatabaseReader] Using MSISAMTableReader for parsing...")
            #endif
            
            // Use specialized MSISAM reader
            let msReader = MSISAMTableReader(data: data, pageSize: pageSize)
            return try msReader.readTable(named: tableName)
        } else {
            // Jet 4.0 stores page size at offset 0x14 (2 bytes, little-endian)
            pageSize = Int(readUInt16(at: 0x14))
            #if DEBUG
            print("[JetDatabaseReader] Jet detected, page size from offset 0x14: \(pageSize)")
            #endif
        }
        
        guard pageSize == 4096 || pageSize == 2048 else {
            #if DEBUG
            print("[JetDatabaseReader] ❌ Unsupported page size: \(pageSize) (expected 4096 or 2048)")
            #endif
            throw JetError.unsupportedVersion
        }
        
        #if DEBUG
        print("[JetDatabaseReader] ✓ Using page size: \(pageSize)")
        #endif
        
        // Read system catalog to find the table
        let tableDefPage = try findTableDefinitionPage(tableName: tableName, pageSize: pageSize)
        
        // Parse table definition
        let tableDef = try parseTableDefinition(at: tableDefPage, pageSize: pageSize, tableName: tableName)
        
        // Read data from the table
        return try readTableData(tableDef: tableDef, pageSize: pageSize)
    }
    
    // MARK: - Table Definition Parsing
    
    private struct TableDefinition {
        let name: String
        let columns: [ColumnDefinition]
        let dataPagePointer: Int?
    }
    
    private struct ColumnDefinition {
        let name: String
        let type: UInt8
        let index: Int
        let fixedOffset: Int?
        let varLenOffset: Int?
        let size: Int
        let flags: UInt8
    }
    
    private func findTableDefinitionPage(tableName: String, pageSize: Int) throws -> Int {
        // MSysObjects is typically on page 2 (page 0 is database header, page 1 is system)
        // For Money files, we'll scan pages looking for our table name
        
        #if DEBUG
        print("[JetDatabaseReader] 🔍 Searching for table '\(tableName)'...")
        print("[JetDatabaseReader] Database size: \(data.count) bytes")
        print("[JetDatabaseReader] Total pages: \(data.count / pageSize)")
        #endif
        
        // Start at page 1 and scan for table definition pages
        var pagesScanned = 0
        var pageTypesFound: [UInt8: Int] = [:]
        var tableNamesFound: [String] = []
        
        for pageNum in 1..<min(500, data.count / pageSize) {
            let pageOffset = pageNum * pageSize
            guard pageOffset + pageSize <= data.count else { continue }
            
            pagesScanned += 1
            let pageType = data[pageOffset]
            pageTypesFound[pageType, default: 0] += 1
            
            // Page type 0x02 = Table definition page in Jet 4.0
            // MSISAM uses different page types but the structure is similar
            if pageType == 0x02 || pageType == 0x01 || pageType == 0x04 {
                // Check if this page contains our table name
                let pageData = data.subdata(in: pageOffset..<(pageOffset + pageSize))
                
                // Look for table name as ASCII
                if let nameRange = pageData.range(of: tableName.data(using: .ascii) ?? Data()) {
                    #if DEBUG
                    print("[JetDatabaseReader] ✓ Found '\(tableName)' (ASCII) on page \(pageNum) (type 0x\(String(format: "%02X", pageType)))")
                    #endif
                    return pageNum
                }
                
                // Also try UTF-16LE (Jet 4 uses Unicode)
                if let utf16Name = tableName.data(using: .utf16LittleEndian),
                   let _ = pageData.range(of: utf16Name) {
                    #if DEBUG
                    print("[JetDatabaseReader] ✓ Found '\(tableName)' (UTF-16LE) on page \(pageNum) (type 0x\(String(format: "%02X", pageType)))")
                    #endif
                    return pageNum
                }
                
                // Also try to extract any readable table names for debugging
                if let pageString = String(data: pageData, encoding: .ascii) {
                    let words = pageString.components(separatedBy: CharacterSet.alphanumerics.inverted)
                    for word in words where word.count >= 3 && word.count <= 20 && word.allSatisfy({ $0.isASCII }) {
                        if !tableNamesFound.contains(word) && word.uppercased() == word {
                            tableNamesFound.append(word)
                        }
                    }
                }
            }
        }
        
        #if DEBUG
        print("[JetDatabaseReader] ❌ Table '\(tableName)' not found")
        print("[JetDatabaseReader] Scanned \(pagesScanned) pages")
        print("[JetDatabaseReader] Page types found: \(pageTypesFound)")
        print("[JetDatabaseReader] Possible table names found: \(tableNamesFound.prefix(20))")
        #endif
        
        throw JetError.tableNotFound(tableName)
    }
    
    private func parseTableDefinition(at pageNum: Int, pageSize: Int, tableName: String) throws -> TableDefinition {
        let pageOffset = pageNum * pageSize
        guard pageOffset + pageSize <= data.count else {
            throw JetError.invalidTableDefinition
        }
        
        // Jet 4 table definition structure:
        // Offset 0: Page type (0x02)
        // Offset 1: Free space
        // Offset 4: Number of columns (2 bytes)
        // Offset 8: Variable columns count
        
        let numCols = Int(readUInt16(at: pageOffset + 0x2B))
        let varColCount = Int(readUInt16(at: pageOffset + 0x2D))
        
        var columns: [ColumnDefinition] = []
        
        // Column definitions start at offset 0x3F typically
        var colOffset = pageOffset + 0x3F
        
        for i in 0..<numCols {
            guard colOffset + 18 <= data.count else { break }
            
            let colType = data[colOffset]
            let colFlags = data[colOffset + 0x0F]
            
            // Column name offset and length
            let nameOffset = Int(readUInt16(at: colOffset + 0x03))
            let nameLen = Int(data[colOffset + 0x05])
            
            var colName = ""
            if pageOffset + nameOffset + nameLen <= data.count {
                if let name = String(data: data.subdata(in: (pageOffset + nameOffset)..<(pageOffset + nameOffset + nameLen)), encoding: .utf16LittleEndian) {
                    colName = name
                }
            }
            
            let fixedOffset = (colFlags & 0x01) == 0 ? Int(readUInt16(at: colOffset + 0x15)) : nil
            let colSize = Int(readUInt16(at: colOffset + 0x17))
            
            columns.append(ColumnDefinition(
                name: colName,
                type: colType,
                index: i,
                fixedOffset: fixedOffset,
                varLenOffset: nil,
                size: colSize,
                flags: colFlags
            ))
            
            colOffset += 25 // Move to next column definition
        }
        
        return TableDefinition(name: tableName, columns: columns, dataPagePointer: nil)
    }
    
    // MARK: - Data Reading
    
    private func readTableData(tableDef: TableDefinition, pageSize: Int) throws -> [[String: Any]] {
        var rows: [[String: Any]] = []
        
        // Scan all pages for data pages (type 0x01)
        for pageNum in 0..<min(1000, data.count / pageSize) {
            let pageOffset = pageNum * pageSize
            guard pageOffset + pageSize <= data.count else { continue }
            
            let pageType = data[pageOffset]
            
            // Data page
            if pageType == 0x01 {
                let pageRows = try readDataPage(at: pageOffset, pageSize: pageSize, tableDef: tableDef)
                rows.append(contentsOf: pageRows)
            }
        }
        
        return rows
    }
    
    private func readDataPage(at pageOffset: Int, pageSize: Int, tableDef: TableDefinition) throws -> [[String: Any]] {
        var rows: [[String: Any]] = []
        
        // Jet 4 data page structure:
        // Offset 0: Page type (0x01)
        // Offset 1: Free space
        // Offset 2-3: Free space offset (from start of page)
        
        let freeSpaceOffset = Int(readUInt16(at: pageOffset + 2))
        
        // Record count is stored differently in Jet 4
        // We'll try to parse records until we hit free space
        
        var recordOffset = pageOffset + 0x0E // Records typically start here
        
        while recordOffset < pageOffset + freeSpaceOffset && recordOffset < pageOffset + pageSize {
            guard recordOffset + 4 < data.count else { break }
            
            // Check for deleted record marker
            let recordFlags = data[recordOffset]
            if recordFlags == 0 || recordFlags == 0xFF {
                recordOffset += 1
                continue
            }
            
            // Try to read a record
            if let row = try? readRecord(at: recordOffset, tableDef: tableDef) {
                rows.append(row)
                recordOffset += estimateRecordSize(tableDef: tableDef)
            } else {
                recordOffset += 1
            }
            
            // Safety limit
            if rows.count > 10000 {
                break
            }
        }
        
        return rows
    }
    
    private func readRecord(at offset: Int, tableDef: TableDefinition) throws -> [String: Any] {
        var row: [String: Any] = [:]
        
        // Read fixed-length columns first
        for column in tableDef.columns {
            guard let fixedOffset = column.fixedOffset else { continue }
            
            let valueOffset = offset + fixedOffset
            guard valueOffset < data.count else { continue }
            
            let value = readColumnValue(at: valueOffset, column: column)
            row[column.name] = value
        }
        
        return row
    }
    
    private func readColumnValue(at offset: Int, column: ColumnDefinition) -> Any? {
        guard offset + column.size <= data.count else { return nil }
        
        switch column.type {
        case 0x03: // Int16
            return Int(readInt16(at: offset))
        case 0x04: // Int32 (Long)
            return Int(readInt32(at: offset))
        case 0x05: // Currency (Money) - 8 bytes, scaled by 10000
            let scaled = readInt64(at: offset)
            return Decimal(scaled) / 10000
        case 0x06: // Single (Float)
            return readFloat32(at: offset)
        case 0x07: // Double
            return readFloat64(at: offset)
        case 0x08: // DateTime - OLE Date (double)
            let oleDate = readFloat64(at: offset)
            return dateFromOLEDate(oleDate)
        case 0x0A: // Text - length-prefixed
            return readText(at: offset, maxLength: column.size)
        case 0x01: // Boolean
            return data[offset] != 0
        case 0x02: // Byte
            return Int(data[offset])
        default:
            return nil
        }
    }
    
    private func estimateRecordSize(tableDef: TableDefinition) -> Int {
        var size = 0
        for column in tableDef.columns {
            if let fixedOffset = column.fixedOffset {
                size = max(size, fixedOffset + column.size)
            }
        }
        return max(size, 20) // Minimum record size
    }
    
    // MARK: - Data Type Readers
    
    private func readUInt16(at offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return data.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: offset, as: UInt16.self)
        }
    }
    
    private func readInt16(at offset: Int) -> Int16 {
        guard offset + 2 <= data.count else { return 0 }
        return data.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: offset, as: Int16.self)
        }
    }
    
    private func readInt32(at offset: Int) -> Int32 {
        guard offset + 4 <= data.count else { return 0 }
        return data.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: offset, as: Int32.self)
        }
    }
    
    private func readInt64(at offset: Int) -> Int64 {
        guard offset + 8 <= data.count else { return 0 }
        return data.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: offset, as: Int64.self)
        }
    }
    
    private func readFloat32(at offset: Int) -> Float {
        guard offset + 4 <= data.count else { return 0 }
        return data.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: offset, as: Float.self)
        }
    }
    
    private func readFloat64(at offset: Int) -> Double {
        guard offset + 8 <= data.count else { return 0 }
        return data.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: offset, as: Double.self)
        }
    }
    
    private func readText(at offset: Int, maxLength: Int) -> String? {
        guard offset < data.count else { return nil }
        
        // Try to find null terminator
        var length = 0
        while offset + length < data.count && length < maxLength && data[offset + length] != 0 {
            length += 1
        }
        
        guard length > 0 else { return nil }
        
        // Try UTF-16 LE first (Jet 4 uses Unicode)
        if let text = String(data: data.subdata(in: offset..<(offset + length)), encoding: .utf16LittleEndian) {
            return text.trimmingCharacters(in: .controlCharacters.union(.whitespaces))
        }
        
        // Fallback to ASCII
        if let text = String(data: data.subdata(in: offset..<(offset + length)), encoding: .ascii) {
            return text.trimmingCharacters(in: .controlCharacters.union(.whitespaces))
        }
        
        return nil
    }
    
    private func dateFromOLEDate(_ oleDate: Double) -> Date {
        // OLE dates are days since December 30, 1899
        let oleEpoch = Date(timeIntervalSince1970: -2209161600) // Dec 30, 1899
        return oleEpoch.addingTimeInterval(oleDate * 86400) // 86400 seconds per day
    }
}
