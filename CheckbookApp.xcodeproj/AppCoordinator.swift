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
        // Clear the file ID first
        OneDriveFileManager.shared.clearSavedFile()
        
        // Signal that we need to restart
        shouldClearFile = true
        shouldRestart = true
    }
    
    func requestSignOut() {
        // Sign out of MSAL
        AuthManager.shared.signOut { error in
            if let error = error {
                print("[AppCoordinator] Error signing out: \(error.localizedDescription)")
            }
        }
        
        // Clear file ID
        OneDriveFileManager.shared.clearSavedFile()
        
        // Signal restart
        shouldSignOut = true
        shouldRestart = true
    }
    
    func reset() {
        shouldRestart = false
        shouldClearFile = false
        shouldSignOut = false
    }
}
