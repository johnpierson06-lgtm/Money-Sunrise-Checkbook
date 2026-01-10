import Foundation

import Foundation

// MARK: - Account Summary (with calculated balance)

/// Represents an account with its calculated current balance
public struct AccountSummary: Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let beginningBalance: Decimal
    public let currentBalance: Decimal
    public let isFavorite: Bool
    
    public init(id: Int, name: String, beginningBalance: Decimal, currentBalance: Decimal, isFavorite: Bool) {
        self.id = id
        self.name = name
        self.beginningBalance = beginningBalance
        self.currentBalance = currentBalance
        self.isFavorite = isFavorite
    }
}

// MARK: - Errors

/// Errors that can occur when working with Money files
public enum MoneyFileServiceError: Error, LocalizedError {
    case noSelectedFile
    case localFileMissing
    case readFailed
    case badPassword
    case unsupportedFormat(String)
    case fileNotFound
    case parsingFailed(String)
    case mdbToolsNotAvailable
    
    public var errorDescription: String? {
        switch self {
        case .noSelectedFile:
            return "No file has been selected. Please pick a .mny file from OneDrive."
        case .localFileMissing:
            return "Local file missing. Try selecting the file again or refreshing the download."
        case .readFailed:
            return "Failed to read the downloaded file."
        case .badPassword:
            return "Invalid password for Money file"
        case .unsupportedFormat(let msg):
            return "Unsupported format: \(msg)"
        case .fileNotFound:
            return "Money file not found - please select a file from OneDrive"
        case .parsingFailed(let msg):
            return "Failed to parse Money file: \(msg)"
        case .mdbToolsNotAvailable:
            return "MDB Tools library is not properly configured. Please ensure libmdb is linked to the app."
        }
    }
}

// MARK: - Money File Service

/// Main service for working with Microsoft Money files
public enum MoneyFileService {
    
    // MARK: - Download (used by MainCheckbookView)
    
    /// Downloads a Money file from OneDrive
    public static func download(accessToken: String, fileRef: OneDriveModels.FileRef, completion: @escaping (Result<Data, Error>) -> Void) {
        AuthManager.shared.downloadFile(accessToken: accessToken, fileId: fileRef.id, suggestedFileName: fileRef.name, parentFolderId: fileRef.parentId) { url, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let url = url else {
                completion(.failure(MoneyFileServiceError.localFileMissing))
                return
            }
            do {
                let data = try Data(contentsOf: url)
                completion(.success(data))
            } catch {
                completion(.failure(MoneyFileServiceError.readFailed))
            }
        }
    }

    // MARK: - Simple decrypt wrapper (non-throwing) used by some views
    
    /// Decrypts Money file data (non-throwing variant)
    public static func decrypt(_ data: Data) -> Data {
        do {
            let password = (try? PasswordStore.shared.load()) ?? ""
            let decrypter = MoneyDecrypter(config: MoneyDecrypterConfig(password: password))
            return try decrypter.decrypt(raw: data)
        } catch {
            // If decryption fails, return original data so caller can decide next steps
            return data
        }
    }

    // MARK: - Ensure local file exists (used by TransactionsView)
    
    /// Ensures a local Money file exists and returns its URL
    @discardableResult
    public static func ensureLocalFile() throws -> URL {
        if let url = OneDriveFileManager.shared.localURLForSavedFile() {
            return url
        }
        if let url = FileStore.localFileURLIfExists() {
            return url
        }
        throw MoneyFileServiceError.localFileMissing
    }

    // MARK: - Decrypt local file fully (throwing)
    
    /// Decrypts the local Money file and returns the decrypted data
    public static func decryptFile() throws -> Data {
        let url = try ensureLocalFile()
        let raw = try Data(contentsOf: url)
        
        #if DEBUG
        print("[MoneyFileService] Raw size: \(raw.count) bytes")
        print("[MoneyFileService] Raw header (first 64 bytes): \(raw.prefix(64).map { String(format: "%02X", $0) }.joined(separator: " "))")
        #endif

        // Load saved password (blank or nil allowed for Money Plus Sunset)
        let password = (try? PasswordStore.shared.load()) ?? ""

        #if DEBUG
        print("[MoneyFileService] Using MoneyDecryptorBridge.decryptToTempFile")
        #endif
        
        do {
            let decryptedPath = try MoneyDecryptorBridge.decryptToTempFile(fromFile: url.path, password: password)
            
            #if DEBUG
            print("[MoneyFileService] Decrypted temp path: \(decryptedPath)")
            #endif
            
            let decrypted = try Data(contentsOf: URL(fileURLWithPath: decryptedPath))
            
            #if DEBUG
            print("[MoneyFileService] Decrypted size: \(decrypted.count) bytes")
            print("[MoneyFileService] Decrypted header (first 64 bytes): \(decrypted.prefix(64).map { String(format: "%02X", $0) }.joined(separator: " "))")
            #endif

            return decrypted
        } catch {
            // Map errors to MoneyFileServiceError when possible
            let desc = String(describing: error).lowercased()
            if desc.contains("badpassword") || desc.contains("bad password") {
                throw MoneyFileServiceError.badPassword
            } else if desc.contains("moduleunavailable") || desc.contains("module unavailable") {
                throw MoneyFileServiceError.unsupportedFormat("mdbtools_c module unavailable in this build")
            } else if desc.contains("unsupportedformat") || desc.contains("unsupported format") {
                throw MoneyFileServiceError.unsupportedFormat("MSISAM decryption failed or unsupported variant")
            } else {
                throw error
            }
        }
    }
    
    // MARK: - Account Summaries
    
    /// Reads account summaries with calculated balances from the Money file
    /// - Returns: Array of AccountSummary with current balances
    public static func readAccountSummaries() throws -> [AccountSummary] {
        print("[MoneyFileService] Reading account summaries...")
        
        // Get the local money file path
        let url = try ensureLocalFile()
        
        print("[MoneyFileService] Local file path: \(url.path)")
        
        // Load saved password
        let password = (try? PasswordStore.shared.load()) ?? ""
        
        // Decrypt the file first
        let decryptedPath = try MoneyDecryptorBridge.decryptToTempFile(fromFile: url.path, password: password)
        print("[MoneyFileService] Decrypted file path: \(decryptedPath)")
        
        // TODO: MDBToolsWrapper requires Process API which doesn't work on iOS device
        // Using SimpleMDBParser with mdbtools library compiled for iOS
        print("[MoneyFileService] Using MoneyFileParser (mdbtools)")
        let parser = MoneyFileParser(filePath: decryptedPath)
        
        // Read ACCT table
        let accounts = try parser.parseAccounts()
        print("[MoneyFileService] Found \(accounts.count) accounts")
        
        // Read TRN table
        let transactions = try parser.parseTransactions()
        print("[MoneyFileService] Found \(transactions.count) transactions")
        
        // Calculate balances for each account
        var accountBalances: [Int: Decimal] = [:]
        
        // Start with beginning balances
        for account in accounts {
            accountBalances[account.id] = account.beginningBalance
        }
        
        // Add transaction amounts
        for transaction in transactions {
            if let currentBalance = accountBalances[transaction.accountId] {
                accountBalances[transaction.accountId] = currentBalance + transaction.amount
            }
        }
        
        // Create summaries
        let summaries = accounts.map { account in
            AccountSummary(
                id: account.id,
                name: account.name,
                beginningBalance: account.beginningBalance,
                currentBalance: accountBalances[account.id] ?? account.beginningBalance,
                isFavorite: false  // TODO: Read from ACCT.fFavorite
            )
        }
        
        print("[MoneyFileService] Returning \(summaries.count) account summaries")
        return summaries
    }
    
    // MARK: - Transactions
    
    /// Reads transactions for a specific account
    /// - Parameter accountId: The account ID to filter by
    /// - Returns: Array of transactions for the account
    static func readTransactions(forAccount accountId: Int) throws -> [MoneyTransaction] {
        let url = try ensureLocalFile()
        let password = (try? PasswordStore.shared.load()) ?? ""
        
        let decryptedPath = try MoneyDecryptorBridge.decryptToTempFile(fromFile: url.path, password: password)
        let parser = try MDBParser(filePath: decryptedPath)
        
        let allTransactions = try parser.readTransactions()
        return allTransactions.filter { $0.accountId == accountId }
    }

    // MARK: - Parsing stubs (to be implemented with Jet/ACE parser or mdbtools wrapper)

    /// Parses accounts from decrypted MDB data (non-throwing variant)
    static func parseAccounts(from data: Data) -> [MoneyAccount] {
        // Use JetDatabaseReader to parse accounts
        do {
            let reader = JetDatabaseReader(data: data)
            let rows = try reader.readTable(named: "ACCT")
            
            var accounts: [MoneyAccount] = []
            for row in rows {
                guard let id = row["hacct"] as? Int,
                      let name = row["szFull"] as? String else {
                    continue
                }
                
                let beginningBalance: Decimal
                if let amt = row["amtOpen"] as? Decimal {
                    beginningBalance = amt
                } else if let amt = row["amtOpen"] as? Double {
                    beginningBalance = Decimal(amt)
                } else {
                    beginningBalance = 0
                }
                
                accounts.append(MoneyAccount(id: id, name: name, beginningBalance: beginningBalance))
            }
            
            return accounts
        } catch {
            print("[MoneyFileService] Failed to parse accounts: \(error)")
            return []
        }
    }

    /// Parses transactions from decrypted MDB data (throwing variant)
    static func parseTransactions(from data: Data) throws -> [MoneyTransaction] {
        let reader = JetDatabaseReader(data: data)
        let rows = try reader.readTable(named: "TRN")
        
        var transactions: [MoneyTransaction] = []
        for row in rows {
            guard let id = row["htrn"] as? Int,
                  let accountId = row["hacct"] as? Int else {
                continue
            }
            
            let amount: Decimal
            if let amt = row["amt"] as? Decimal {
                amount = amt
            } else if let amt = row["amt"] as? Double {
                amount = Decimal(amt)
            } else {
                amount = 0
            }
            
            let date: Date
            if let dt = row["dt"] as? Date {
                date = dt
            } else {
                date = Date()
            }
            
            let payeeId = row["hpay"] as? Int
            let categoryId = row["hcat"] as? Int
            let memo = row["szMemo"] as? String
            
            transactions.append(MoneyTransaction(
                id: id,
                accountId: accountId,
                date: date,
                amount: amount,
                payeeId: payeeId,
                categoryId: categoryId,
                memo: memo
            ))
        }
        
        return transactions
    }
}

// MARK: - MDB Parser (reads decrypted MDB files)

/// A simple MDB file parser that reads the raw database format
/// This uses the JetDatabaseReader for actual parsing
struct MDBParser {
    let filePath: String
    let data: Data
    
    init(filePath: String) throws {
        self.filePath = filePath
        self.data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        
        guard data.count > 0 else {
            throw MoneyFileServiceError.parsingFailed("Empty file")
        }
        
        print("[MDBParser] Loaded file: \(data.count) bytes")
        print("[MDBParser] First 32 bytes: \(data.prefix(32).map { String(format: "%02x", $0) }.joined())")
    }
    
    /// Reads accounts from the ACCT table
    func readAccounts() throws -> [MoneyAccount] {
        print("[MDBParser] Reading ACCT table using JetDatabaseReader...")
        
        let reader = JetDatabaseReader(data: data)
        let rows = try reader.readTable(named: "ACCT")
        
        var accounts: [MoneyAccount] = []
        for row in rows {
            guard let id = row["hacct"] as? Int,
                  let name = row["szFull"] as? String else {
                continue
            }
            
            let beginningBalance: Decimal
            if let amt = row["amtOpen"] as? Decimal {
                beginningBalance = amt
            } else if let amt = row["amtOpen"] as? Double {
                beginningBalance = Decimal(amt)
            } else {
                beginningBalance = 0
            }
            
            accounts.append(MoneyAccount(id: id, name: name, beginningBalance: beginningBalance))
        }
        
        print("[MDBParser] Parsed \(accounts.count) accounts")
        return accounts
    }
    
    /// Reads transactions from the TRN table
    func readTransactions() throws -> [MoneyTransaction] {
        print("[MDBParser] Reading TRN table using JetDatabaseReader...")
        
        let reader = JetDatabaseReader(data: data)
        let rows = try reader.readTable(named: "TRN")
        
        var transactions: [MoneyTransaction] = []
        for row in rows {
            guard let id = row["htrn"] as? Int,
                  let accountId = row["hacct"] as? Int else {
                continue
            }
            
            let amount: Decimal
            if let amt = row["amt"] as? Decimal {
                amount = amt
            } else if let amt = row["amt"] as? Double {
                amount = Decimal(amt)
            } else {
                amount = 0
            }
            
            let date: Date
            if let dt = row["dt"] as? Date {
                date = dt
            } else {
                date = Date()
            }
            
            let payeeId = row["hpay"] as? Int
            let categoryId = row["hcat"] as? Int
            let memo = row["szMemo"] as? String
            
            transactions.append(MoneyTransaction(
                id: id,
                accountId: accountId,
                date: date,
                amount: amount,
                payeeId: payeeId,
                categoryId: categoryId,
                memo: memo
            ))
        }
        
        print("[MDBParser] Parsed \(transactions.count) transactions")
        return transactions
    }
}
