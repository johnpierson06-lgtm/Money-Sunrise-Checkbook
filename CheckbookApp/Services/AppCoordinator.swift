//
//  AppCoordinator.swift
//  Money Sunrise Checkbook
//

import SwiftUI
import Combine

class AppCoordinator: ObservableObject {
    @Published var shouldRestart = false
    @Published var shouldClearFile = false
    @Published var shouldSignOut = false
    
    static let shared = AppCoordinator()
    
    private init() {}
    
    func requestChangeFile() {
        print("[AppCoordinator] 📂 requestChangeFile() called")
        // Clear the file ID first
        OneDriveFileManager.shared.clearSavedFile()
        print("[AppCoordinator] 🗑️ File ID cleared")
        
        // Clear password from keychain
        do {
            try PasswordStore.shared.clear()
            print("[AppCoordinator] 🔑 Password cleared from keychain")
        } catch {
            print("[AppCoordinator] ⚠️ Error clearing password: \(error.localizedDescription)")
        }
        
        // Signal that we need to restart
        shouldClearFile = true
        shouldRestart = true
        print("[AppCoordinator] ✅ shouldRestart set to true")
    }
    
    func requestSignOut() {
        print("[AppCoordinator] 🚪 requestSignOut() called")
        // Sign out of MSAL
        AuthManager.shared.signOut { error in
            if let error = error {
                print("[AppCoordinator] Error signing out: \(error.localizedDescription)")
            }
        }
        
        // Clear file ID
        OneDriveFileManager.shared.clearSavedFile()
        print("[AppCoordinator] 🗑️ File ID cleared")
        
        // Clear password from keychain
        do {
            try PasswordStore.shared.clear()
            print("[AppCoordinator] 🔑 Password cleared from keychain")
        } catch {
            print("[AppCoordinator] ⚠️ Error clearing password: \(error.localizedDescription)")
        }
        
        // Signal restart
        shouldSignOut = true
        shouldRestart = true
        print("[AppCoordinator] ✅ shouldRestart set to true")
    }
    
    func reset() {
        print("[AppCoordinator] 🔄 Resetting coordinator state")
        shouldRestart = false
        shouldClearFile = false
        shouldSignOut = false
    }
}
