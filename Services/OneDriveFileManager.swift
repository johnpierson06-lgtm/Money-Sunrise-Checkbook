// OneDriveFileManager.swift
// Responsible for persisting selected OneDrive file id/name and downloading the file into Documents.
// Add this file to your app target.

import Foundation
import UIKit

public enum OneDriveFileManagerError: Error {
    case noSavedFile
    case tokenAcquisitionFailed(String)
    case downloadFailed(String)
    case documentsUnavailable
}

/// Simple manager to persist OneDrive file metadata and ensure a local copy exists.
public final class OneDriveFileManager {
    public static let shared = OneDriveFileManager()

    private init() {}

    // MARK: - Keys

    private let fileIdKey = "OneDrive_SelectedFileId"
    private let fileNameKey = "OneDrive_SelectedFileName"
    private let parentFolderIdKey = "OneDrive_SelectedParentFolderId"

    // MARK: - Persisting selection

    /// Save the selected OneDrive file metadata so the app can re-download later.
    public func saveSelectedFile(fileId: String, fileName: String, parentFolderId: String? = nil) {
        UserDefaults.standard.set(fileId, forKey: fileIdKey)
        UserDefaults.standard.set(fileName, forKey: fileNameKey)
        if let parent = parentFolderId {
            UserDefaults.standard.set(parent, forKey: parentFolderIdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: parentFolderIdKey)
        }
        UserDefaults.standard.synchronize()
    }

    /// Remove saved selection (use when user chooses to change file)
    public func clearSavedFile() {
        UserDefaults.standard.removeObject(forKey: fileIdKey)
        UserDefaults.standard.removeObject(forKey: fileNameKey)
        UserDefaults.standard.removeObject(forKey: parentFolderIdKey)
        UserDefaults.standard.synchronize()
    }

    /// Get saved file id if present
    public func getSavedFileId() -> String? {
        return UserDefaults.standard.string(forKey: fileIdKey)
    }

    /// Get saved file name if present
    public func getSavedFileName() -> String? {
        return UserDefaults.standard.string(forKey: fileNameKey)
    }

    /// Get saved parent folder id if present
    public func getSavedParentFolderId() -> String? {
        return UserDefaults.standard.string(forKey: parentFolderIdKey)
    }

    // MARK: - Local Documents helpers

    /// Returns the Documents directory URL for the app
    private func documentsDirectory() throws -> URL {
        let fm = FileManager.default
        if let docs = try? fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            return docs
        }
        throw OneDriveFileManagerError.documentsUnavailable
    }

    /// Local file URL in Documents for the saved file name
    public func localURLForSavedFile() -> URL? {
        guard let name = getSavedFileName() else { return nil }
        guard let docs = try? documentsDirectory() else { return nil }
        let url = docs.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    
    /// Local file path in Documents for the saved file name (convenience property)
    public var localMnyFilePath: String? {
        return localURLForSavedFile()?.path
    }

    // MARK: - Ensure local copy (main entry for step 1)

    /**
     Ensure the saved OneDrive file is present locally in Documents.

     - If there is no saved OneDrive file id, completion is called with (nil, nil).
     - If there is a saved id, this method attempts to acquire a silent token and download the file.
     - On success completion(localURL, nil) is called.
     - On failure completion(nil, error) is called.

     Note: This method uses AuthManager.shared.acquireTokenSilent and AuthManager.shared.downloadFile.
     */
    public func ensureLocalMnyFile(completion: @escaping (URL?, Error?) -> Void) {
        if let local = self.localURLForSavedFile() {
            completion(local, nil)
            return
        }
        guard let fileId = getSavedFileId(), let fileName = getSavedFileName() else {
            // No saved file; caller should present file picker
            completion(nil, nil)
            return
        }

        // Acquire token silently
        AuthManager.shared.acquireTokenSilent(scopes: ["Files.Read", "Files.ReadWrite"]) { token, err in
            DispatchQueue.main.async {
                if let err = err {
                    completion(nil, OneDriveFileManagerError.tokenAcquisitionFailed(err.localizedDescription))
                    return
                }
                guard let token = token else {
                    completion(nil, OneDriveFileManagerError.tokenAcquisitionFailed("No token returned"))
                    return
                }

                // Use AuthManager to download the file and move it into Documents
                let parentId = self.getSavedParentFolderId()
                AuthManager.shared.downloadFile(accessToken: token, fileId: fileId, suggestedFileName: fileName, parentFolderId: parentId) { localURL, downloadErr in
                    DispatchQueue.main.async {
                        if let downloadErr = downloadErr {
                            completion(nil, OneDriveFileManagerError.downloadFailed(downloadErr.localizedDescription))
                        } else if let localURL = localURL {
                            completion(localURL, nil)
                        } else {
                            completion(nil, OneDriveFileManagerError.downloadFailed("Unknown download error"))
                        }
                    }
                }
            }
        }
    }

    public func ensureLocalMnyFile(presentingViewController: UIViewController?, completion: @escaping (URL?, Error?) -> Void) {
        if let local = self.localURLForSavedFile() {
            completion(local, nil)
            return
        }
        guard let fileId = getSavedFileId(), let fileName = getSavedFileName() else {
            completion(nil, OneDriveFileManagerError.noSavedFile)
            return
        }
        AuthManager.shared.acquireTokenSilent(scopes: ["Files.Read", "Files.ReadWrite"]) { token, err in
            if let _ = err {
                // Fallback to interactive sign-in
                AuthManager.shared.signIn(scopes: ["Files.Read", "Files.ReadWrite"], presentingViewController: presentingViewController) { token, signInErr in
                    if let signInErr = signInErr {
                        completion(nil, OneDriveFileManagerError.tokenAcquisitionFailed(signInErr.localizedDescription))
                        return
                    }
                    guard let token = token else {
                        completion(nil, OneDriveFileManagerError.tokenAcquisitionFailed("No token returned"))
                        return
                    }
                    let parentId = self.getSavedParentFolderId()
                    AuthManager.shared.downloadFile(accessToken: token, fileId: fileId, suggestedFileName: fileName, parentFolderId: parentId) { localURL, downloadErr in
                        if let downloadErr = downloadErr {
                            completion(nil, OneDriveFileManagerError.downloadFailed(downloadErr.localizedDescription))
                        } else {
                            completion(localURL, nil)
                        }
                    }
                }
                return
            }
            guard let token = token else {
                completion(nil, OneDriveFileManagerError.tokenAcquisitionFailed("No token returned"))
                return
            }
            let parentId = self.getSavedParentFolderId()
            AuthManager.shared.downloadFile(accessToken: token, fileId: fileId, suggestedFileName: fileName, parentFolderId: parentId) { localURL, downloadErr in
                if let downloadErr = downloadErr {
                    completion(nil, OneDriveFileManagerError.downloadFailed(downloadErr.localizedDescription))
                } else {
                    completion(localURL, nil)
                }
            }
        }
    }

    // MARK: - Convenience: download on demand (force download even if local exists)

    /**
     Force download the saved OneDrive file even if a local copy exists.
     Useful when you want to refresh the local copy.
     */
    public func refreshLocalMnyFile(completion: @escaping (URL?, Error?) -> Void) {
        guard let fileId = getSavedFileId(), let fileName = getSavedFileName() else {
            completion(nil, OneDriveFileManagerError.noSavedFile)
            return
        }

        AuthManager.shared.acquireTokenSilent(scopes: ["Files.Read", "Files.ReadWrite"]) { token, err in
            DispatchQueue.main.async {
                if let err = err {
                    completion(nil, OneDriveFileManagerError.tokenAcquisitionFailed(err.localizedDescription))
                    return
                }
                guard let token = token else {
                    completion(nil, OneDriveFileManagerError.tokenAcquisitionFailed("No token returned"))
                    return
                }

                let parentId = self.getSavedParentFolderId()
                AuthManager.shared.downloadFile(accessToken: token, fileId: fileId, suggestedFileName: fileName, parentFolderId: parentId) { localURL, downloadErr in
                    DispatchQueue.main.async {
                        if let downloadErr = downloadErr {
                            completion(nil, OneDriveFileManagerError.downloadFailed(downloadErr.localizedDescription))
                        } else {
                            completion(localURL, nil)
                        }
                    }
                }
            }
        }
    }

    public func refreshLocalMnyFile(presentingViewController: UIViewController?, completion: @escaping (URL?, Error?) -> Void) {
        guard let fileId = getSavedFileId(), let fileName = getSavedFileName() else {
            completion(nil, OneDriveFileManagerError.noSavedFile)
            return
        }
        AuthManager.shared.acquireTokenSilent(scopes: ["Files.Read", "Files.ReadWrite"]) { token, err in
            if let _ = err {
                AuthManager.shared.signIn(scopes: ["Files.Read", "Files.ReadWrite"], presentingViewController: presentingViewController) { token, signInErr in
                    if let signInErr = signInErr {
                        completion(nil, OneDriveFileManagerError.tokenAcquisitionFailed(signInErr.localizedDescription))
                        return
                    }
                    guard let token = token else {
                        completion(nil, OneDriveFileManagerError.tokenAcquisitionFailed("No token returned"))
                        return
                    }
                    let parentId = self.getSavedParentFolderId()
                    AuthManager.shared.downloadFile(accessToken: token, fileId: fileId, suggestedFileName: fileName, parentFolderId: parentId) { localURL, downloadErr in
                        if let downloadErr = downloadErr {
                            completion(nil, OneDriveFileManagerError.downloadFailed(downloadErr.localizedDescription))
                        } else {
                            completion(localURL, nil)
                        }
                    }
                }
                return
            }
            guard let token = token else {
                completion(nil, OneDriveFileManagerError.tokenAcquisitionFailed("No token returned"))
                return
            }
            let parentId = self.getSavedParentFolderId()
            AuthManager.shared.downloadFile(accessToken: token, fileId: fileId, suggestedFileName: fileName, parentFolderId: parentId) { localURL, downloadErr in
                if let downloadErr = downloadErr {
                    completion(nil, OneDriveFileManagerError.downloadFailed(downloadErr.localizedDescription))
                } else {
                    completion(localURL, nil)
                }
            }
        }
    }

    public func refreshLocalMnyFile(accessToken: String, completion: @escaping (URL?, Error?) -> Void) {
        guard let fileId = getSavedFileId(), let fileName = getSavedFileName() else {
            completion(nil, OneDriveFileManagerError.noSavedFile)
            return
        }
        let parentId = self.getSavedParentFolderId()
        AuthManager.shared.downloadFile(accessToken: accessToken, fileId: fileId, suggestedFileName: fileName, parentFolderId: parentId) { localURL, downloadErr in
            if let downloadErr = downloadErr {
                completion(nil, OneDriveFileManagerError.downloadFailed(downloadErr.localizedDescription))
            } else {
                completion(localURL, nil)
            }
        }
    }
    
    // MARK: - File Cleanup
    
    /// Delete the local copy of the Money file from Documents directory
    /// This releases any file locks and forces a fresh download on next access
    /// Useful after syncing to ensure we don't have stale or locked files
    public func clearLocalFile() {
        guard let localURL = localURLForSavedFile() else {
            #if DEBUG
            print("[OneDriveFileManager] No local file to clear")
            #endif
            return
        }
        
        do {
            try FileManager.default.removeItem(at: localURL)
            #if DEBUG
            print("[OneDriveFileManager] ✅ Cleared local file: \(localURL.path)")
            #endif
        } catch {
            #if DEBUG
            print("[OneDriveFileManager] ⚠️ Failed to clear local file: \(error.localizedDescription)")
            #endif
        }
    }
}
extension OneDriveFileManagerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noSavedFile:
            return "No OneDrive file has been selected."
        case .tokenAcquisitionFailed(let message):
            return "Failed to acquire token: \(message)"
        case .downloadFailed(let message):
            return "Failed to download file: \(message)"
        case .documentsUnavailable:
            return "Documents directory unavailable."
        }
    }
}

