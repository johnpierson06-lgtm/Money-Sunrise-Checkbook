//
//  SplashScreenView.swift
//  Money Sunrise Checkbook
//

import SwiftUI
import UIKit

struct SplashScreenView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var isActive = false
    @State private var navigationDestination: NavigationDestination? = nil
    @State private var hasLRDFile = false
    @State private var isReadOnly = false
    
    enum NavigationDestination: Equatable {
        case login
        case fileSelection
        case accounts
    }
    
    var body: some View {
        ZStack {
            // Always check if we need to restart
            if coordinator.shouldRestart {
                Color.clear
                    .onAppear {
                        handleRestart()
                    }
            } else {
                NavigationStack {
                    Group {
                        if !isActive {
                            // Splash screen content
                            VStack(spacing: 20) {
                                Image(systemName: "dollarsign.circle.fill")
                                    .resizable()
                                    .frame(width: 120, height: 120)
                                    .foregroundColor(.green)
                                
                                Text("Money Sunrise")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                
                                Text("Checkbook")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                                
                                ProgressView()
                                    .padding(.top, 20)
                            }
                            .onAppear {
                                checkAuthenticationStatus()
                            }
                        } else {
                            // Navigate based on destination
                            destinationView
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var destinationView: some View {
        switch navigationDestination {
        case .login:
            LoginPromptView { success in
                if success {
                    // After successful login, go to file selection
                    navigationDestination = .fileSelection
                }
            }
            
        case .fileSelection:
            EnhancedFileSelectionView { hasLRD, readOnly in
                // File selected, update flags and navigate to accounts
                hasLRDFile = hasLRD
                isReadOnly = readOnly
                navigationDestination = .accounts
            }
            
        case .accounts:
            AccountsView(hasLRDFile: hasLRDFile, isReadOnly: isReadOnly)
            
        case .none:
            ProgressView()
        }
    }
    
    private func checkAuthenticationStatus() {
        print("[SplashScreenView] 🚀 Starting authentication check...")
        
        // Delay for splash screen visibility
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            print("[SplashScreenView] ⏰ Checking MSAL token...")
            
            // Check if user has authenticated (has MSAL account)
            AuthManager.shared.acquireTokenSilent(scopes: ["Files.Read", "Files.ReadWrite"]) { token, error in
                DispatchQueue.main.async {
                    if token != nil {
                        print("[SplashScreenView] ✅ User is authenticated")
                        // User is authenticated
                        let hasPersistedFile = OneDriveFileManager.shared.getSavedFileId() != nil
                        
                        if hasPersistedFile {
                            print("[SplashScreenView] 📁 Has persisted file - reloading...")
                            // User has authenticated AND has a persistent file ID
                            // Reload the file and check for LRD
                            reloadPersistedFile()
                        } else {
                            print("[SplashScreenView] 📂 No persisted file - showing file selection")
                            // User has authenticated but doesn't have a persistent file
                            navigationDestination = .fileSelection
                            isActive = true
                        }
                    } else {
                        print("[SplashScreenView] 🔐 User needs to authenticate - showing login")
                        // User needs to authenticate
                        navigationDestination = .login
                        isActive = true
                    }
                }
            }
        }
    }
    
    private func reloadPersistedFile() {
        print("[SplashScreenView] 🔄 Reloading persisted file from OneDrive...")
        // Reload the persisted file from OneDrive
        OneDriveFileManager.shared.refreshLocalMnyFile { url, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("[SplashScreenView] Error reloading file: \(error.localizedDescription)")
                    // If reload fails, let user select file again
                    navigationDestination = .fileSelection
                } else {
                    // File reloaded successfully, check for LRD file
                    checkForLRDFileInPersistedLocation { hasLRD in
                        hasLRDFile = hasLRD
                        isReadOnly = hasLRD
                        navigationDestination = .accounts
                    }
                }
                isActive = true
            }
        }
    }
    
    private func handleRestart() {
        print("[SplashScreenView] 🔄 Handling restart request...")
        
        // Reset the splash screen to initial state
        isActive = false
        navigationDestination = nil  // Clear the destination too!
        hasLRDFile = false
        isReadOnly = false
        
        // Reset coordinator
        coordinator.reset()
        
        // Immediately check auth status without splash delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.performAuthCheck()
        }
    }
    
    private func performAuthCheck() {
        print("[SplashScreenView] 🚀 Performing authentication check...")
        
        // Check if user has authenticated (has MSAL account)
        AuthManager.shared.acquireTokenSilent(scopes: ["Files.Read", "Files.ReadWrite"]) { token, error in
            DispatchQueue.main.async {
                if token != nil {
                    print("[SplashScreenView] ✅ User is authenticated")
                    // User is authenticated
                    let hasPersistedFile = OneDriveFileManager.shared.getSavedFileId() != nil
                    
                    if hasPersistedFile {
                        print("[SplashScreenView] 📁 Has persisted file - reloading...")
                        // User has authenticated AND has a persistent file ID
                        // Reload the file and check for LRD
                        self.reloadPersistedFile()
                    } else {
                        print("[SplashScreenView] 📂 No persisted file - showing file selection")
                        // User has authenticated but doesn't have a persistent file
                        self.navigationDestination = .fileSelection
                        self.isActive = true
                    }
                } else {
                    print("[SplashScreenView] 🔐 User needs to authenticate - showing login")
                    // User needs to authenticate
                    self.navigationDestination = .login
                    self.isActive = true
                }
            }
        }
    }
    
    private func checkForLRDFileInPersistedLocation(completion: @escaping (Bool) -> Void) {
        guard let fileName = OneDriveFileManager.shared.getSavedFileName(),
              let parentFolderId = OneDriveFileManager.shared.getSavedParentFolderId() else {
            completion(false)
            return
        }
        
        // Create the .lrd filename
        let lrdFileName = fileName.replacingOccurrences(of: ".mny", with: ".lrd")
        
        // Get token and check for LRD file
        AuthManager.shared.acquireTokenSilent(scopes: ["Files.Read", "Files.ReadWrite"]) { token, error in
            guard let token = token else {
                completion(false)
                return
            }
            
            OneDriveAPI.listChildren(accessToken: token, folderId: parentFolderId) { result in
                switch result {
                case .success(let items):
                    let hasLRD = items.contains(where: { $0.name.lowercased() == lrdFileName.lowercased() })
                    
                    #if DEBUG
                    print("[SplashScreenView] LRD file check: \(hasLRD ? "Found" : "Not found") - \(lrdFileName)")
                    #endif
                    
                    completion(hasLRD)
                    
                case .failure(let error):
                    #if DEBUG
                    print("[SplashScreenView] Error checking for LRD file: \(error.localizedDescription)")
                    #endif
                    completion(false)
                }
            }
        }
    }
}

// MARK: - Login Prompt View

struct LoginPromptView: View {
    let onComplete: (Bool) -> Void
    
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var presenterVC: UIViewController?
    
    var body: some View {
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

// MARK: - Enhanced File Selection View

struct EnhancedFileSelectionView: View {
    let onFileSelected: (Bool, Bool) -> Void  // (hasLRD, isReadOnly)
    
    @State private var items: [OneDriveModels.Item] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var breadcrumbs: [OneDriveModels.Item] = []
    @State private var currentFolderId: String? = nil
    @State private var accessToken: String? = nil
    @State private var presenterVC: UIViewController? = nil
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let errorMessage = errorMessage {
                VStack(spacing: 20) {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    
                    Button("Retry") {
                        loadChildren(folderId: currentFolderId)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                if items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "folder")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No items in this folder")
                            .foregroundColor(.secondary)
                    }
                } else {
                    List(items, id: \.id) { item in
                        if item.isFolder {
                            Button {
                                breadcrumbs.append(item)
                                currentFolderId = item.id
                                loadChildren(folderId: item.id)
                            } label: {
                                Label(item.name, systemImage: "folder")
                            }
                        } else if item.name.lowercased().hasSuffix(".mny") {
                            HStack {
                                Text(item.name)
                                Spacer()
                                Button("Select") {
                                    selectFile(item: item)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        } else {
                            Text(item.name)
                                .foregroundColor(.secondary)
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
        .navigationTitle(breadcrumbs.last?.name ?? "OneDrive")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Sign Out") {
                    AuthManager.shared.signOut { _ in
                        breadcrumbs = []
                        currentFolderId = nil
                        items = []
                    }
                }
            }
        }
        .onAppear {
            loadChildren(folderId: currentFolderId)
        }
        .background(ViewControllerResolver { vc in self.presenterVC = vc })
    }
    
    private func loadChildren(folderId: String?) {
        isLoading = true
        errorMessage = nil
        
        if let token = accessToken {
            fetchChildren(token: token, folderId: folderId)
            return
        }
        
        AuthManager.shared.acquireTokenSilent(scopes: ["Files.Read", "Files.ReadWrite"]) { token, err in
            if let err = err {
                AuthManager.shared.signIn(scopes: ["Files.Read", "Files.ReadWrite"], presentingViewController: presenterVC) { token, signInErr in
                    if let signInErr = signInErr {
                        DispatchQueue.main.async {
                            self.errorMessage = signInErr.localizedDescription
                            self.isLoading = false
                        }
                        return
                    }
                    guard let token = token else {
                        DispatchQueue.main.async {
                            self.errorMessage = "No access token"
                            self.isLoading = false
                        }
                        return
                    }
                    self.accessToken = token
                    self.fetchChildren(token: token, folderId: folderId)
                }
                return
            }
            guard let token = token else {
                DispatchQueue.main.async {
                    self.errorMessage = "No access token"
                    self.isLoading = false
                }
                return
            }
            self.accessToken = token
            self.fetchChildren(token: token, folderId: folderId)
        }
    }
    
    private func fetchChildren(token: String, folderId: String?) {
        OneDriveAPI.listChildren(accessToken: token, folderId: folderId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let children):
                    self.items = children
                    self.isLoading = false
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func selectFile(item: OneDriveModels.Item) {
        // Save the selected file with parent folder ID
        OneDriveFileManager.shared.saveSelectedFile(fileId: item.id, fileName: item.name, parentFolderId: currentFolderId)
        
        // Check for .lrd file in the current folder
        let lrdFileName = item.name.replacingOccurrences(of: ".mny", with: ".lrd")
        let hasLRDFile = items.contains(where: { $0.name.lowercased() == lrdFileName.lowercased() })
        let isReadOnly = hasLRDFile
        
        #if DEBUG
        print("[EnhancedFileSelectionView] LRD file check: \(hasLRDFile ? "Found" : "Not found") - \(lrdFileName)")
        #endif
        
        // Download the file
        if let token = self.accessToken {
            OneDriveFileManager.shared.refreshLocalMnyFile(accessToken: token) { _, error in
                DispatchQueue.main.async {
                    if let error = error {
                        self.errorMessage = error.localizedDescription
                    } else {
                        // File downloaded successfully
                        onFileSelected(hasLRDFile, isReadOnly)
                    }
                }
            }
        } else {
            OneDriveFileManager.shared.refreshLocalMnyFile(presentingViewController: presenterVC) { _, error in
                DispatchQueue.main.async {
                    if let error = error {
                        self.errorMessage = error.localizedDescription
                    } else {
                        // File downloaded successfully
                        onFileSelected(hasLRDFile, isReadOnly)
                    }
                }
            }
        }
    }
}

#Preview {
    SplashScreenView()
}
