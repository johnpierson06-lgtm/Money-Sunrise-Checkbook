import Foundation
import Security

enum PasswordStoreError: Error {
    case keychainError(OSStatus)
}

final class PasswordStore {
    static let shared = PasswordStore()
    private init() {}
    
    private let service = "MoneyFilePasswordService"
    private let account = "MoneyFilePassword"
    
    func save(password: String) throws {
        guard let passwordData = password.data(using: .utf8) else {
            throw PasswordStoreError.keychainError(errSecParam)
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        
        let attributes: [String: Any] = [
            kSecValueData as String: passwordData
        ]
        
        let statusAdd = SecItemAdd(query.merging(attributes) { (_, new) in new } as CFDictionary, nil)
        if statusAdd == errSecDuplicateItem {
            let statusUpdate = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if statusUpdate != errSecSuccess {
                throw PasswordStoreError.keychainError(statusUpdate)
            }
        } else if statusAdd != errSecSuccess {
            throw PasswordStoreError.keychainError(statusAdd)
        }
    }
    
    func load() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        if status == errSecItemNotFound {
            return nil
        }
        
        guard status == errSecSuccess else {
            throw PasswordStoreError.keychainError(status)
        }
        
        guard let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return password
    }
    
    func clear() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw PasswordStoreError.keychainError(status)
        }
    }
}
