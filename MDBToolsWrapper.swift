import Foundation

/// Wrapper for mdbtools - iOS device support TODO
/// Currently not used - MoneyFileService uses MDBParser fallback instead
struct MDBToolsWrapper {
    
    enum MDBError: Error {
        case cannotOpenFile
        case tableNotFound(String)
        case readError(String)
        case libraryNotAvailable
        case mdbToolsNotInstalled
    }
    
    /// Read a table from an MDB file and return rows as dictionaries
    /// NOTE: This is not currently working on iOS - use MDBParser instead
    static func readTable(filePath: String, tableName: String) throws -> [[String: Any]] {
        #if DEBUG
        print("[MDBToolsWrapper] ⚠️ Not yet implemented for iOS")
        #endif
        throw MDBError.libraryNotAvailable
    }
}

