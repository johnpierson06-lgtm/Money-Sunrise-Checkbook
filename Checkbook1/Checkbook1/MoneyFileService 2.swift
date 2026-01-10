import Foundation
// Ensure MoneyMDB is visible from this target
// (MoneyMDB is defined in MoneyMDB.swift)

enum MoneyFileServiceError: Error {
    case noSelectedFile
    case localFileMissing
    case readFailed
}

struct MoneyFileService {
    // MARK: - Download (used by MainCheckbookView)
    static func download(accessToken: String, fileRef: OneDriveModels.FileRef, completion: @escaping (Result<Data, Error>) -> Void) {
        // Use existing AuthManager to download into Documents, then read back as Data
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
    static func decrypt(_ data: Data) -> Data {
        do {
            let password = (try? PasswordStore.shared.load()) ?? nil
            let decrypter = MoneyDecrypter(config: MoneyDecrypterConfig(password: password))
            return try decrypter.decrypt(raw: data)
        } catch {
            // If decryption fails, return original data so caller can decide next steps
            return data
        }
    }

    // MARK: - Ensure local file exists (used by TransactionsView)
    @discardableResult
    static func ensureLocalFile() throws -> URL {
        if let url = OneDriveFileManager.shared.localURLForSavedFile() {
            return url
        }
        if let url = FileStore.localFileURLIfExists() {
            return url
        }
        throw MoneyFileServiceError.localFileMissing
    }

    // MARK: - Decrypt local file fully (throwing)
    static func decryptFile() throws -> Data {
        let url = try ensureLocalFile()
        let raw = try Data(contentsOf: url)
        #if DEBUG
        print("[MoneyFileService] Raw size: \(raw.count) bytes")
        print("[MoneyFileService] Raw header (first 64 bytes): \(raw.prefix(64).map { String(format: "%02X", $0) }.joined(separator: " "))")
        #endif

        // Load saved password (blank or nil allowed for Money Plus Sunset)
        let password = try PasswordStore.shared.load()

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

            #if DEBUG
            // Extra debug: verify FLAGS and SALT are cleared in the decrypted header
            let flagsOffset = 664
            let saltOffset = 114
            let flagsBytes = decrypted[flagsOffset..<(flagsOffset+4)]
            let saltBytes = decrypted[saltOffset..<(saltOffset+4)]
            print("[MoneyFileService] Decrypted FLAGS bytes @664: \(flagsBytes.map { String(format: "%02X", $0) }.joined(separator: " "))")
            print("[MoneyFileService] Decrypted SALT bytes @114: \(saltBytes.map { String(format: "%02X", $0) }.joined(separator: " "))")
            #endif

            // Save a copy of the decrypted MDB into Documents for inspection
            do {
                let fm = FileManager.default
                let docs = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                let baseName = url.deletingPathExtension().lastPathComponent
                let dest = docs.appendingPathComponent("\(baseName)-decrypted.mdb")
                if fm.fileExists(atPath: dest.path) {
                    try fm.removeItem(at: dest)
                }
                try fm.copyItem(at: URL(fileURLWithPath: decryptedPath), to: dest)
                #if DEBUG
                print("[MoneyFileService] Saved decrypted copy to Documents: \(dest.path)")
                #endif
            } catch {
                #if DEBUG
                print("[MoneyFileService] Failed to save decrypted copy to Documents: \(error)")
                #endif
            }

            return decrypted
        } catch {
            // Map errors to MoneyDecrypterError when possible
            let desc = String(describing: error).lowercased()
            if desc.contains("badpassword") || desc.contains("bad password") {
                throw MoneyDecrypterError.badPassword
            } else if desc.contains("moduleunavailable") || desc.contains("module unavailable") {
                throw MoneyDecrypterError.unsupportedFormat("mdbtools_c module unavailable in this build")
            } else if desc.contains("unsupportedformat") || desc.contains("unsupported format") {
                throw MoneyDecrypterError.unsupportedFormat("MSISAM decryption failed or unsupported variant")
            } else {
                throw error
            }
        }
    }

    // MARK: - MoneyMDB parsing helpers
    /// Reads account summaries (id, name, beginningBalance) using MoneyMDB. Requires mdbtools_c at runtime.
    static func readAccountSummaries() throws -> [(id: Int, name: String, beginningBalance: Decimal)] {
        let url = try ensureLocalFile()
        let password = try PasswordStore.shared.load()
        #if DEBUG
        print("[MoneyFileService] Reading accounts via MoneyMDB from \(url.path)")
        #endif
        do {
            let accounts = try MoneyMDB.readAccounts(fromFile: url.path, password: password)
            return accounts.map { (id: $0.id, name: $0.name, beginningBalance: $0.beginningBalance) }
        } catch {
            let desc = String(describing: error).lowercased()
            if desc.contains("moduleunavailable") || desc.contains("module unavailable") {
                throw MoneyDecrypterError.unsupportedFormat("mdbtools_c module unavailable in this build")
            }
            throw error
        }
    }

    // MARK: - Parsing stubs (to be implemented with Jet/ACE parser or mdbtools wrapper)

    // Non-throwing variant used in some older views
    static func parseAccounts(from data: Data) -> [UIAccount] {
        // TODO: Implement with Jet/ACE table reader. For now, return empty to avoid crashes.
        return []
    }

    // Throwing variant used by TransactionsView
    static func parseTransactions(from data: Data) throws -> [MoneyTransaction] {
        // TODO: Implement with Jet/ACE table reader. For now, return empty to avoid crashes.
        return []
    }
}
extension MoneyFileServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noSelectedFile:
            return "No file has been selected. Please pick a .mny file from OneDrive."
        case .localFileMissing:
            return "Local file missing. Try selecting the file again or refreshing the download."
        case .readFailed:
            return "Failed to read the downloaded file."
        }
    }
}

