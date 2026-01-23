import Foundation
import MSAL

extension MSALPublicClientApplication {
    // Helper to get current account (wraps MSAL API)
    func getCurrentAccount(completion: @escaping (MSALAccount?, MSALAccount?, Error?) -> Void) {
        do {
            let accounts = try self.allAccounts()
            if let first = accounts.first {
                completion(first, nil, nil)
            } else {
                completion(nil, nil, nil)
            }
        } catch {
            completion(nil, nil, error)
        }
    }
}
