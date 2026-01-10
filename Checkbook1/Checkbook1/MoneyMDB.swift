import Foundation

#if canImport(mdbtools_c)
import mdbtools_c
#endif

enum MoneyMDBError: Error {
    case moduleUnavailable
    case openFailed
    case acctTableMissing
}

struct MoneyMDB {
    struct Account: Hashable, Codable, Sendable {
        let id: Int
        let name: String
        let beginningBalance: Decimal
    }

    /// Reads account summaries from a Microsoft Money file.
    /// This will decrypt to a temporary MDB first, then attempt to open and locate the ACCT table.
    /// For now, this returns an empty array until row iteration helpers are added.
    static func readAccounts(fromFile path: String, password: String?) throws -> [Account] {
        // Decrypt to temp MDB (supports blank or provided password)
        let decryptedPath = try MoneyDecryptorBridge.decryptToTempFile(fromFile: path, password: password)

        #if canImport(mdbtools_c)
        guard let mdb = money_mdb_open(decryptedPath) else {
            throw MoneyMDBError.openFailed
        }
        defer { money_mdb_close(mdb) }

        // Ensure ACCT table exists
        guard let _ = money_mdb_open_acct(mdb) else {
            throw MoneyMDBError.acctTableMissing
        }

        // TODO: Add C helpers to iterate rows/columns and populate real accounts
        return []
        #else
        // mdbtools_c module not available in this build
        throw MoneyMDBError.moduleUnavailable
        #endif
    }
}
