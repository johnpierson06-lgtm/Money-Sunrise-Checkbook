import Foundation

// Namespace OneDrive-related models to avoid ambiguous type lookups when other files/targets
// accidentally declare similarly named types. Prefer using `OneDriveModels.FileRef` in new code.
public enum OneDriveModels {
    // Represents an item returned by OneDrive listing
    public struct Item: Identifiable, Codable, Hashable {
        public let id: String
        public let name: String
        public let isFolder: Bool

        public init(id: String, name: String, isFolder: Bool) {
            self.id = id
            self.name = name
            self.isFolder = isFolder
        }
    }

    // Represents the OneDrive file you selected
    public struct FileRef: Codable {
        let id: String       // OneDrive itemId
        let name: String
        let parentId: String?
    }

    // Handles saving/loading the selection
    public enum FileSelectionStore {
        private static let key = "selectedMoneyFile"

        public static func save(_ ref: FileRef) {
            if let data = try? JSONEncoder().encode(ref) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }

        public static func load() -> FileRef? {
            guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
            return try? JSONDecoder().decode(FileRef.self, from: data)
        }
    }
}

