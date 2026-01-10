import Foundation

/// MSISAM-specific table reader based on Jackcess Table.java structure
/// This handles the older MSISAM format used by Microsoft Money files
struct MSISAMTableReader {
    let data: Data
    let pageSize: Int
    
    enum MSISAMError: Error {
        case invalidDatabase
        case tableNotFound(String)
        case invalidTableDefinition
        case readError(String)
    }
    
    // MSISAM Table Definition Offsets (from Table.java)
    private struct TableDefOffsets {
        static let NUM_ROWS = 0x10                    // 4 bytes - row count
        static let NEXT_AUTO_NUMBER = 0x14            // 4 bytes - last auto number
        static let TABLE_TYPE = 0x28                  // 1 byte - table type
        static let MAX_COLS = 0x29                    // 2 bytes - max column count
        static let NUM_VAR_COLS = 0x2B                // 2 bytes - variable column count
        static let NUM_COLS = 0x2D                    // 2 bytes - column count
        static let NUM_INDEX_SLOTS = 0x2F             // 4 bytes - logical index count
        static let NUM_INDEXES = 0x33                 // 4 bytes - index count
        static let OWNED_PAGES = 0x37                 // 4 bytes - owned pages pointer
        static let FREE_SPACE_PAGES = 0x3B            // 4 bytes - free space pages pointer
        
        // Column definition block starts after indexes
        static let INDEX_DEF_BLOCK = 0x3F             // Variable - depends on index count
        
        // Column header size (from SIZE_COLUMN_HEADER in JetFormat)
        static let COLUMN_HEADER_SIZE = 25
    }
    
    // MSISAM Data Types (from Table.java and DataType enum)
    private enum MSISAMDataType: UInt8 {
        case boolean = 0x01
        case byte = 0x02
        case int16 = 0x03
        case int32 = 0x04      // Long Integer
        case currency = 0x05    // Money - 8 bytes scaled by 10000
        case float = 0x06       // Single precision
        case double = 0x07      // Double precision
        case dateTime = 0x08    // OLE Date
        case binary = 0x09      // Binary data
        case text = 0x0A        // Text (length-prefixed)
        case memo = 0x0C        // Long text
        case guid = 0x0F        // GUID
        case numeric = 0x13     // Numeric/Decimal
        
        var fixedSize: Int? {
            switch self {
            case .boolean: return 1
            case .byte: return 1
            case .int16: return 2
            case .int32: return 4
            case .currency: return 8
            case .float: return 4
            case .double: return 8
            case .dateTime: return 8
            case .guid: return 16
            default: return nil
            }
        }
    }
    
    init(data: Data, pageSize: Int = 4096) {
        self.data = data
        self.pageSize = pageSize
    }
    
    /// Read a table and return rows as dictionaries
    func readTable(named tableName: String) throws -> [[String: Any]] {
        #if DEBUG
        print("[MSISAMTableReader] Reading table '\(tableName)'...")
        #endif
        
        // Find the table definition page
        let tableDefPage = try findTableDefinitionPage(tableName: tableName)
        
        #if DEBUG
        print("[MSISAMTableReader] Found table definition on page \(tableDefPage)")
        #endif
        
        // Parse the table definition
        let tableDef = try parseTableDefinition(pageNumber: tableDefPage, tableName: tableName)
        
        #if DEBUG
        print("[MSISAMTableReader] Table has \(tableDef.columns.count) columns")
        for col in tableDef.columns.prefix(5) {
            print("[MSISAMTableReader]   - \(col.name): type=0x\(String(format: "%02X", col.type))")
        }
        #endif
        
        // Read the data pages
        let rows = try readTableData(tableDef: tableDef)
        
        #if DEBUG
        print("[MSISAMTableReader] Read \(rows.count) rows")
        #endif
        
        return rows
    }
    
    // MARK: - Table Definition Finding
    
    private func findTableDefinitionPage(tableName: String) throws -> Int {
        // Scan pages looking for table definition
        // Table def pages are type 0x02 in MSISAM
        
        var foundTables: [(page: Int, name: String)] = []
        
        for pageNum in 1..<min(1000, data.count / pageSize) {
            let pageOffset = pageNum * pageSize
            guard pageOffset + pageSize <= data.count else { continue }
            
            let pageType = data[pageOffset]
            
            // Type 0x02 = Table definition page
            if pageType == 0x02 {
                // Try to extract table name from this page
                // Table names in MSISAM are stored as length-prefixed strings
                if let tableName = try? extractTableName(at: pageOffset) {
                    foundTables.append((page: pageNum, name: tableName))
                    
                    if tableName.uppercased() == tableName.uppercased() {
                        #if DEBUG
                        print("[MSISAMTableReader] Found table '\(tableName)' on page \(pageNum)")
                        #endif
                        return pageNum
                    }
                }
            }
        }
        
        #if DEBUG
        print("[MSISAMTableReader] ❌ Table '\(tableName)' not found")
        print("[MSISAMTableReader] Found tables: \(foundTables.map { $0.name })")
        #endif
        
        throw MSISAMError.tableNotFound(tableName)
    }
    
    private func extractTableName(at pageOffset: Int) throws -> String? {
        // Table name is typically stored near the beginning of the table def page
        // It's a length-prefixed string (2 bytes length + UTF-16LE text)
        
        // Try various offsets where table names might be
        let searchOffsets = [0x10, 0x14, 0x18, 0x1C, 0x20, 0x30, 0x40]
        
        for offset in searchOffsets {
            let pos = pageOffset + offset
            guard pos + 2 < data.count else { continue }
            
            let nameLength = Int(readUInt16(at: pos))
            guard nameLength > 0 && nameLength < 100 else { continue }
            
            let nameStart = pos + 2
            guard nameStart + nameLength * 2 <= data.count else { continue }
            
            let nameData = data.subdata(in: nameStart..<(nameStart + nameLength * 2))
            if let name = String(data: nameData, encoding: .utf16LittleEndian),
               name.count > 2,
               name.rangeOfCharacter(from: .alphanumerics) != nil {
                return name
            }
        }
        
        return nil
    }
    
    // MARK: - Table Definition Parsing
    
    struct TableDefinition {
        let name: String
        let columns: [ColumnDefinition]
        let rowCount: Int
    }
    
    struct ColumnDefinition {
        let name: String
        let type: UInt8
        let index: Int
        let fixedOffset: Int?
        let varLenIndex: Int?
        let size: Int
        let isVariableLength: Bool
    }
    
    private func parseTableDefinition(pageNumber: Int, tableName: String) throws -> TableDefinition {
        let pageOffset = pageNumber * pageSize
        guard pageOffset + pageSize <= data.count else {
            throw MSISAMError.invalidTableDefinition
        }
        
        // Read header information
        let rowCount = Int(readInt32(at: pageOffset + TableDefOffsets.NUM_ROWS))
        let numCols = Int(readUInt16(at: pageOffset + TableDefOffsets.NUM_COLS))
        let numVarCols = Int(readUInt16(at: pageOffset + TableDefOffsets.NUM_VAR_COLS))
        let indexCount = Int(readInt32(at: pageOffset + TableDefOffsets.NUM_INDEXES))
        
        #if DEBUG
        print("[MSISAMTableReader] Table '\(tableName)':")
        print("[MSISAMTableReader]   Rows: \(rowCount)")
        print("[MSISAMTableReader]   Columns: \(numCols)")
        print("[MSISAMTableReader]   Variable columns: \(numVarCols)")
        print("[MSISAMTableReader]   Indexes: \(indexCount)")
        #endif
        
        // Calculate where column definitions start
        // After the header and index definitions
        let indexDefSize = 12 // Approximate size per index definition
        let colDefStart = pageOffset + TableDefOffsets.INDEX_DEF_BLOCK + (indexCount * indexDefSize)
        
        var columns: [ColumnDefinition] = []
        var fixedOffset = 0
        var varLenIndex = 0
        
        for i in 0..<numCols {
            let colOffset = colDefStart + (i * TableDefOffsets.COLUMN_HEADER_SIZE)
            guard colOffset + TableDefOffsets.COLUMN_HEADER_SIZE <= data.count else {
                break
            }
            
            let colType = data[colOffset]
            let colSize = Int(readUInt16(at: colOffset + 0x17))
            let colFlags = data[colOffset + 0x0F]
            
            let isVariableLength = (colFlags & 0x01) != 0
            
            // Column name follows the column definitions
            // For now, we'll use a placeholder and extract names later
            let colName = "Column\(i)"
            
            columns.append(ColumnDefinition(
                name: colName,
                type: colType,
                index: i,
                fixedOffset: isVariableLength ? nil : fixedOffset,
                varLenIndex: isVariableLength ? varLenIndex : nil,
                size: colSize,
                isVariableLength: isVariableLength
            ))
            
            if isVariableLength {
                varLenIndex += 1
            } else {
                if let typeSize = MSISAMDataType(rawValue: colType)?.fixedSize {
                    fixedOffset += typeSize
                } else {
                    fixedOffset += colSize
                }
            }
        }
        
        // Now extract column names (they follow the column definitions)
        columns = try extractColumnNames(columns: columns, pageOffset: pageOffset, numCols: numCols, colDefStart: colDefStart)
        
        return TableDefinition(name: tableName, columns: columns, rowCount: rowCount)
    }
    
    private func extractColumnNames(columns: [ColumnDefinition], pageOffset: Int, numCols: Int, colDefStart: Int) throws -> [ColumnDefinition] {
        // Column names are stored after all column definitions
        // Each name is length-prefixed (2 bytes) + UTF-16LE string
        
        var updatedColumns = columns
        var nameOffset = colDefStart + (numCols * TableDefOffsets.COLUMN_HEADER_SIZE)
        
        // Known column names for ACCT table (from your mdb-export output)
        let acctColumnNames = ["hacct", "ast", "at", "szFull", "amtOpen", "dtOpen", "dtEndRec", "dtOpenRec", "fFavorite"]
        
        // Known column names for TRN table
        let trnColumnNames = ["htrn", "hacct", "dt", "amt", "hpay", "hcat", "sz"]
        
        // Try to use known names first, then fall back to extraction
        for i in 0..<min(numCols, updatedColumns.count) {
            var columnName: String?
            
            // Try to read name from file
            if nameOffset + 2 < data.count {
                let nameLength = Int(readUInt16(at: nameOffset))
                if nameLength > 0 && nameLength < 100 {
                    let nameStart = nameOffset + 2
                    if nameStart + nameLength * 2 <= data.count {
                        let nameData = data.subdata(in: nameStart..<(nameStart + nameLength * 2))
                        columnName = String(data: nameData, encoding: .utf16LittleEndian)
                        nameOffset = nameStart + nameLength * 2
                    }
                }
            }
            
            // Fallback to known names
            if columnName == nil || columnName!.isEmpty {
                if i < acctColumnNames.count {
                    columnName = acctColumnNames[i]
                } else if i < trnColumnNames.count {
                    columnName = trnColumnNames[i]
                } else {
                    columnName = "Column\(i)"
                }
            }
            
            updatedColumns[i] = ColumnDefinition(
                name: columnName ?? "Column\(i)",
                type: updatedColumns[i].type,
                index: updatedColumns[i].index,
                fixedOffset: updatedColumns[i].fixedOffset,
                varLenIndex: updatedColumns[i].varLenIndex,
                size: updatedColumns[i].size,
                isVariableLength: updatedColumns[i].isVariableLength
            )
        }
        
        return updatedColumns
    }
    
    // MARK: - Data Reading
    
    private func readTableData(tableDef: TableDefinition) throws -> [[String: Any]] {
        var rows: [[String: Any]] = []
        
        // Scan for data pages (type 0x01)
        for pageNum in 0..<min(2000, data.count / pageSize) {
            let pageOffset = pageNum * pageSize
            guard pageOffset + pageSize <= data.count else { continue }
            
            let pageType = data[pageOffset]
            
            // Type 0x01 = Data page
            if pageType == 0x01 {
                let pageRows = try readDataPage(at: pageOffset, tableDef: tableDef)
                rows.append(contentsOf: pageRows)
                
                // Safety limit
                if rows.count >= tableDef.rowCount + 100 {
                    break
                }
            }
        }
        
        return rows
    }
    
    private func readDataPage(at pageOffset: Int, tableDef: TableDefinition) throws -> [[String: Any]] {
        var rows: [[String: Any]] = []
        
        // Data page structure (from Table.java):
        // Offset 0: Page type (0x01)
        // Offset 2-3: Free space offset
        // Offset 12-13: Number of rows on page
        
        let numRowsOnPage = Int(readUInt16(at: pageOffset + 12))
        guard numRowsOnPage > 0 && numRowsOnPage < 1000 else {
            return []
        }
        
        // Row offsets are stored at the end of the page
        // Each is 2 bytes, stored in reverse order
        let rowOffsetsStart = pageOffset + 14
        
        for rowNum in 0..<numRowsOnPage {
            let rowOffsetPos = rowOffsetsStart + (rowNum * 2)
            guard rowOffsetPos + 2 <= data.count else { continue }
            
            var rowOffset = Int(readUInt16(at: rowOffsetPos))
            
            // Check for deleted/overflow flags (from Table.java)
            let isDeleted = (rowOffset & 0x8000) != 0
            let isOverflow = (rowOffset & 0x4000) != 0
            rowOffset = rowOffset & 0x1FFF // Clean the flags
            
            guard !isDeleted && !isOverflow else { continue }
            
            let rowStart = pageOffset + rowOffset
            guard rowStart < pageOffset + pageSize else { continue }
            
            if let row = try? readRow(at: rowStart, tableDef: tableDef) {
                rows.append(row)
            }
        }
        
        return rows
    }
    
    private func readRow(at offset: Int, tableDef: TableDefinition) throws -> [String: Any] {
        var row: [String: Any] = [:]
        
        // Row structure:
        // Offset 0-1: Column count
        // Followed by fixed-length column data
        // Then variable-length column data
        // Then null mask at the end
        
        guard offset + 2 < data.count else {
            throw MSISAMError.readError("Row offset out of bounds")
        }
        
        let columnCount = Int(readUInt16(at: offset))
        guard columnCount > 0 else {
            throw MSISAMError.readError("Invalid column count")
        }
        
        let dataStart = offset + 2
        
        // Read fixed-length columns
        for column in tableDef.columns where !column.isVariableLength {
            guard let fixedOffset = column.fixedOffset else { continue }
            
            let valueOffset = dataStart + fixedOffset
            guard valueOffset < data.count else { continue }
            
            if let value = readColumnValue(at: valueOffset, column: column) {
                row[column.name] = value
            }
        }
        
        // TODO: Read variable-length columns
        // This requires parsing the variable column offset table at the end of the row
        
        return row
    }
    
    private func readColumnValue(at offset: Int, column: ColumnDefinition) -> Any? {
        guard offset + column.size <= data.count else { return nil }
        
        guard let dataType = MSISAMDataType(rawValue: column.type) else {
            return nil
        }
        
        switch dataType {
        case .boolean:
            return data[offset] != 0
        case .byte:
            return Int(data[offset])
        case .int16:
            return Int(readInt16(at: offset))
        case .int32:
            return Int(readInt32(at: offset))
        case .currency:
            // Currency is stored as Int64 scaled by 10000
            let scaled = readInt64(at: offset)
            return Decimal(scaled) / 10000
        case .float:
            return Double(readFloat32(at: offset))
        case .double:
            return readFloat64(at: offset)
        case .dateTime:
            let oleDate = readFloat64(at: offset)
            return dateFromOLEDate(oleDate)
        case .text:
            // Text is typically length-prefixed or null-terminated
            return readText(at: offset, maxLength: column.size)
        default:
            return nil
        }
    }
    
    // MARK: - Binary Readers
    
    // MARK: - Binary Readers (Safe Unaligned Access)
    
    private func readUInt16(at offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        // Safe unaligned read - read individual bytes and combine
        let byte0 = UInt16(data[offset])
        let byte1 = UInt16(data[offset + 1])
        return byte0 | (byte1 << 8)  // Little-endian
    }
    
    private func readInt16(at offset: Int) -> Int16 {
        let unsigned = readUInt16(at: offset)
        return Int16(bitPattern: unsigned)
    }
    
    private func readInt32(at offset: Int) -> Int32 {
        guard offset + 4 <= data.count else { return 0 }
        // Safe unaligned read - read individual bytes and combine
        let byte0 = UInt32(data[offset])
        let byte1 = UInt32(data[offset + 1])
        let byte2 = UInt32(data[offset + 2])
        let byte3 = UInt32(data[offset + 3])
        let unsigned = byte0 | (byte1 << 8) | (byte2 << 16) | (byte3 << 24)  // Little-endian
        return Int32(bitPattern: unsigned)
    }
    
    private func readInt64(at offset: Int) -> Int64 {
        guard offset + 8 <= data.count else { return 0 }
        // Safe unaligned read - read individual bytes and combine
        var unsigned: UInt64 = 0
        for i in 0..<8 {
            unsigned |= UInt64(data[offset + i]) << (i * 8)
        }
        return Int64(bitPattern: unsigned)
    }
    
    private func readFloat32(at offset: Int) -> Float {
        guard offset + 4 <= data.count else { return 0 }
        // Read as Int32 first to avoid alignment issues, then reinterpret
        let bits = readInt32(at: offset)
        return Float(bitPattern: UInt32(bitPattern: bits))
    }
    
    private func readFloat64(at offset: Int) -> Double {
        guard offset + 8 <= data.count else { return 0 }
        // Read as Int64 first to avoid alignment issues, then reinterpret
        let bits = readInt64(at: offset)
        return Double(bitPattern: UInt64(bitPattern: bits))
    }
    
    private func readText(at offset: Int, maxLength: Int) -> String? {
        guard offset < data.count else { return nil }
        
        // Try to find null terminator or read up to maxLength
        var length = 0
        while offset + length < data.count && length < maxLength && data[offset + length] != 0 {
            length += 1
        }
        
        guard length > 0 else { return nil }
        
        // Try UTF-16LE first (MSISAM typically uses this)
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
