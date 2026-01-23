import Foundation

enum FileStoreError: Error {
    case writeFailed
    case missingDocumentsDirectory
}

struct FileStore {
    private static let selectedFileIdKey = "selectedFileId"
    private static let selectedFileNameKey = "selectedFileName"
    private static let selectedFileParentIdKey = "selectedFileParentId"

    // Move the downloaded temp file into Documents and persist metadata
    static func saveDownloadedTempFile(tempURL: URL, suggestedFileName: String, parentFolderId: String?) throws -> URL {
        let fm = FileManager.default
        guard let docs = try? fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            throw FileStoreError.missingDocumentsDirectory
        }
        let dest = docs.appendingPathComponent(suggestedFileName)
        // Remove existing file if present
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        do {
            try fm.moveItem(at: tempURL, to: dest)
            // persist metadata
            UserDefaults.standard.set(suggestedFileName, forKey: selectedFileNameKey)
            if let parent = parentFolderId {
                UserDefaults.standard.set(parent, forKey: selectedFileParentIdKey)
            }
            return dest
        } catch {
            throw FileStoreError.writeFailed
        }
    }

    static func persistSelectedFileId(_ fileId: String) {
        UserDefaults.standard.set(fileId, forKey: selectedFileIdKey)
    }

    static func getSelectedFileName() -> String? {
        return UserDefaults.standard.string(forKey: selectedFileNameKey)
    }

    static func getSelectedFileId() -> String? {
        return UserDefaults.standard.string(forKey: selectedFileIdKey)
    }

    static func getSelectedFileParentId() -> String? {
        return UserDefaults.standard.string(forKey: selectedFileParentIdKey)
    }

    static func localFileURLIfExists() -> URL? {
        guard let name = getSelectedFileName() else { return nil }
        let fm = FileManager.default
        if let docs = try? fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false) {
            let url = docs.appendingPathComponent(name)
            return fm.fileExists(atPath: url.path) ? url : nil
        }
        return nil
    }

    static func removeSelectedFileMetadata() {
        UserDefaults.standard.removeObject(forKey: selectedFileIdKey)
        UserDefaults.standard.removeObject(forKey: selectedFileNameKey)
        UserDefaults.standard.removeObject(forKey: selectedFileParentIdKey)
    }
}
