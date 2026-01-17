//
//  MainFlowView.swift
//  Money Sunrise Checkbook
//

import SwiftUI
import UIKit

struct MainFlowView: View {
    enum Scenario {
        case firstTimeLogin
        case authenticatedNoFile
        case authenticatedWithFile
    }
    
    let scenario: Scenario
    
    @State private var flowState: FlowState = .initializing
    @State private var errorMessage: String?
    @State private var presenterVC: UIViewController?
    @State private var hasLRDFile: Bool = false
    @State private var isReadOnly: Bool = false
    
    enum FlowState {
        case initializing
        case needsLogin
        case needsFileSelection
        case needsPassword
        case showingAccounts
        case error(String)
    }
    
    var body: some View {
        Group {
            switch flowState {
            case .initializing:
                ProgressView("Initializing...")
                
            case .needsLogin:
                LoginView { success in
                    if success {
                        flowState = .needsFileSelection
                    } else {
                        flowState = .error("Login failed")
                    }
                }
                
            case .needsFileSelection:
                FileSelectionView()
                    .onDisappear {
                        // After file selection, check for LRD file
                        checkForLRDFile()
                    }
                
            case .needsPassword:
                PasswordPromptView(
                    password: .constant(""),
                    errorMessage: nil,
                    hasLRDWarning: hasLRDFile,
                    isReadOnly: isReadOnly,
                    onSubmit: { password in
                        // Password submitted, navigate to accounts
                        flowState = .showingAccounts
                    },
                    onCancel: {
                        flowState = .error("Password required")
                    }
                )
                
            case .showingAccounts:
                AccountsView(hasLRDFile: hasLRDFile, isReadOnly: isReadOnly)
                
            case .error(let message):
                ErrorView(message: message) {
                    // Retry - go back to initialization
                    flowState = .initializing
                    initializeFlow()
                }
            }
        }
        .background(ViewControllerResolver { vc in self.presenterVC = vc })
        .onAppear {
            initializeFlow()
        }
    }
    
    private func initializeFlow() {
        switch scenario {
        case .firstTimeLogin:
            // Start with Microsoft login prompt
            flowState = .needsLogin
            
        case .authenticatedNoFile:
            // Navigate OneDrive to select a file
            flowState = .needsFileSelection
            
        case .authenticatedWithFile:
            // Reload the file from OneDrive
            reloadFileFromOneDrive()
        }
    }
    
    private func reloadFileFromOneDrive() {
        flowState = .initializing
        
        OneDriveFileManager.shared.refreshLocalMnyFile(presentingViewController: presenterVC) { url, error in
            DispatchQueue.main.async {
                if let error = error {
                    flowState = .error("Failed to reload file: \(error.localizedDescription)")
                } else {
                    // File reloaded successfully, check for LRD file
                    checkForLRDFile()
                    flowState = .showingAccounts
                }
            }
        }
    }
    
    private func checkForLRDFile() {
        guard let fileName = OneDriveFileManager.shared.getSavedFileName(),
              let parentFolderId = OneDriveFileManager.shared.getSavedParentFolderId() else {
            hasLRDFile = false
            isReadOnly = false
            return
        }
        
        // Create the .lrd filename
        let lrdFileName = fileName.replacingOccurrences(of: ".mny", with: ".lrd")
        
        // Check if LRD file exists in the same directory
        AuthManager.shared.acquireTokenSilent(scopes: ["Files.Read", "Files.ReadWrite"]) { token, error in
            guard let token = token else {
                hasLRDFile = false
                isReadOnly = false
                return
            }
            
            OneDriveAPI.listChildren(accessToken: token, folderId: parentFolderId) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let items):
                        // Check if any item matches the .lrd filename
                        hasLRDFile = items.contains(where: { $0.name.lowercased() == lrdFileName.lowercased() })
                        isReadOnly = hasLRDFile
                        
                        #if DEBUG
                        print("[MainFlowView] LRD file check: \(hasLRDFile ? "Found" : "Not found") - \(lrdFileName)")
                        #endif
                        
                    case .failure(let error):
                        #if DEBUG
                        print("[MainFlowView] Error checking for LRD file: \(error.localizedDescription)")
                        #endif
                        hasLRDFile = false
                        isReadOnly = false
                    }
                }
            }
        }
    }
}

// MARK: - Login View

struct LoginView: View {
    let onComplete: (Bool) -> Void
    
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var presenterVC: UIViewController?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Icon
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                    .padding(.top, 40)
                
                // Title and description
                VStack(spacing: 8) {
                    Text("Welcome to Money Sunrise")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Sign in with your Microsoft account to access your Money files on OneDrive.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal)
                }
                
                Spacer()
                
                // Sign in button
                Button {
                    signIn()
                } label: {
                    HStack {
                        Image(systemName: "microsoft.logo")
                        Text("Sign in with Microsoft")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isLoading)
                .padding(.horizontal)
                .padding(.bottom, 32)
                
                if isLoading {
                    ProgressView()
                        .padding(.bottom, 32)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .background(ViewControllerResolver { vc in self.presenterVC = vc })
    }
    
    private func signIn() {
        isLoading = true
        errorMessage = nil
        
        AuthManager.shared.signIn(scopes: ["Files.Read", "Files.ReadWrite"], presentingViewController: presenterVC) { token, error in
            DispatchQueue.main.async {
                isLoading = false
                
                if let error = error {
                    errorMessage = error.localizedDescription
                    onComplete(false)
                } else if token != nil {
                    onComplete(true)
                } else {
                    errorMessage = "No token received"
                    onComplete(false)
                }
            }
        }
    }
}

// MARK: - Error View

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.red)
            
            Text("Error")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button {
                onRetry()
            } label: {
                Text("Try Again")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
        }
    }
}

#Preview {
    MainFlowView(scenario: .firstTimeLogin)
}
