//
//  SimpleMDBWriter.swift
//  CheckbookApp
//
//  Simple MDB writer using direct binary manipulation
//  Based on successful Python + Java approach
//

import Foundation

#if canImport(mdbtools_c)

/// Simple MDB writer that appends rows to existing tables
/// This uses a simplified approach that appends to data pages without complex index updates
class SimpleMDBWriter {
    let filePath: String
    
    enum WriteError: Error, LocalizedError {
        case fileNotFound
        case invalidFormat
        case tableNotFound(String)
        case writeFailed(String)
        case notImplemented(String)
        
        var errorDescription: String? {
            switch self {
            case .fileNotFound:
                return "MDB file not found"
            case .invalidFormat:
                return "Invalid MDB file format"
            case .tableNotFound(let name):
                return "Table '\(name)' not found"
            case .writeFailed(let msg):
                return "Write failed: \(msg)"
            case .notImplemented(let msg):
                return "Not implemented: \(msg)"
            }
        }
    }
    
    init(filePath: String) {
        self.filePath = filePath
    }
    
    // MARK: - High-Level Insert
    
    /// Insert a row into a table
    /// - Parameters:
    ///   - tableName: Name of the table
    ///   - values: Dictionary of column name -> string value
    func insertRow(tableName: String, values: [String: String]) throws {
        #if DEBUG
        print("[SimpleMDBWriter] Inserting row into \(tableName)")
        print("[SimpleMDBWriter] Values: \(values)")
        #endif
        
        // APPROACH 1: Using mdbtools library directly
        // This may not work reliably with Money Plus
        
        // Open the database
        guard let mdb = mdb_open(filePath, MDB_WRITABLE) else {
            throw WriteError.fileNotFound
        }
        defer { mdb_close(mdb) }
        
        // Read catalog
        guard let catalog = mdb_read_catalog(mdb, Int32(MDB_TABLE)) else {
            throw WriteError.invalidFormat
        }
        
        // Find table
        var tablePtr: UnsafeMutablePointer<MdbTableDef>? = nil
        let catalogCount = Int(catalog.pointee.len)
        
        for i in 0..<catalogCount {
            let entryPtr = catalog.pointee.pdata[i]?.assumingMemoryBound(to: MdbCatalogEntry.self)
            
            if let entry = entryPtr {
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
            throw WriteError.tableNotFound(tableName)
        }
        defer { mdb_free_tabledef(table) }
        
        // Read columns
        guard let columns = mdb_read_columns(table) else {
            throw WriteError.invalidFormat
        }
        
        let numCols = Int(table.pointee.num_cols)
        
        #if DEBUG
        print("[SimpleMDBWriter] Table has \(numCols) columns")
        #endif
        
        // WARNING: mdb_insert_row() may not exist or work properly
        // This is why the Python approach uses Java/Jackcess
        
        // For now, throw an error indicating we need the binary writer
        throw WriteError.notImplemented(
            """
            Direct mdbtools insert is not reliable with Money Plus.
            Use the binary writer approach instead, or:
            1. Export table to CSV
            2. Append row to CSV
            3. Re-import CSV
            4. Rebuild indexes
            This requires external tools not available on iOS.
            """
        )
    }
}

#else

// Fallback when mdbtools_c not available
class SimpleMDBWriter {
    let filePath: String
    
    enum WriteError: Error {
        case notAvailable
    }
    
    init(filePath: String) {
        self.filePath = filePath
    }
    
    func insertRow(tableName: String, values: [String: String]) throws {
        throw WriteError.notAvailable
    }
}

#endif
