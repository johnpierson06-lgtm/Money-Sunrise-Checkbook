import SwiftUI
import Foundation

struct UIAccount: Identifiable, Hashable {
    let id: Int
    let name: String
    let openingBalance: Decimal
    var currentBalance: Decimal
    var hasUnsyncedTransactions: Bool = false
    var isFavorite: Bool = false
}

struct AccountsView: View {
    var hasLRDFile: Bool = false  // Flag to indicate .lrd file exists
    var isReadOnly: Bool = false  // Flag to prevent edits
    
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var accounts: [UIAccount] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    @State private var showPasswordPrompt = true  // Show immediately on file open
    @State private var enteredPassword = ""
    @State private var isProcessingPassword = false
    @State private var presenterVC: UIViewController? = nil
    @State private var passwordErrorMessage: String? = nil  // Track password errors
    @State private var showFavoritesOnly = false  // Toggle for favorites filter

    var filteredAccounts: [UIAccount] {
        let filtered = showFavoritesOnly ? accounts.filter { $0.isFavorite } : accounts
        return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading || isProcessingPassword {
                    VStack(spacing: 16) {
                        ProgressView()
                        if isProcessingPassword {
                            Text("Decrypting file...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                } else if let errorMessage = errorMessage {
                    VStack(spacing: 20) {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding()
                        
                        Button("Try Again") {
                            // Clear error and show password prompt again
                            self.errorMessage = nil
                            self.showPasswordPrompt = true
                            self.enteredPassword = ""
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if accounts.isEmpty && !showPasswordPrompt {
                    VStack(spacing: 20) {
                        Text("No accounts loaded")
                            .font(.headline)
                        Text("Please enter the password to decrypt your Money file")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button("Enter Password") {
                            self.showPasswordPrompt = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else if filteredAccounts.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "star.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("No Favorite Accounts")
                            .font(.headline)
                        Text("You haven't marked any accounts as favorites yet")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    VStack(spacing: 0) {
                        // Filter toggle
                        Picker("View", selection: $showFavoritesOnly) {
                            Text("Show All").tag(false)
                            Text("Show Favorites").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        
                        List(filteredAccounts) { account in
                            NavigationLink(destination: TransactionsView(account: account)) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(account.name)
                                        
                                        if account.hasUnsyncedTransactions {
                                            HStack(spacing: 4) {
                                                Image(systemName: "exclamationmark.triangle.fill")
                                                    .font(.caption2)
                                                Text("includes unsynced transactions")
                                                    .font(.caption2)
                                            }
                                            .foregroundColor(.orange)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    Text(NSDecimalNumber(decimal: account.currentBalance).doubleValue, format: .currency(code: Locale.current.currencyCode ?? "USD"))
                                        .foregroundColor(
                                            account.currentBalance < 0 ? .red :
                                            account.hasUnsyncedTransactions ? .orange : .primary
                                        )
                                }
                            }
                        }
                        .refreshable {
                            await refreshAccountsAsync()
                        }
                    }
                }
            }
            .navigationTitle("Accounts")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if hasLRDFile {
                        Text("(Read Only)")
                            .font(.headline)
                            .foregroundColor(.orange)
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button(role: .destructive) {
                            changeFile()
                        } label: {
                            Label("Change File", systemImage: "folder")
                        }
                        
                        Button(role: .destructive) {
                            signOut()
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        if hasLRDFile {
                            // Show disabled sync button with tooltip
                            Button {
                                // No action - disabled
                            } label: {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            .disabled(true)
                            .foregroundColor(.gray)
                            .help("Sync is disabled because the file may be open on another device")
                        } else {
                            NavigationLink(destination: SyncView(onSyncComplete: {
                                // After sync, refresh the file from OneDrive
                                // The sync service already cleared the local file, so this will download fresh copy
                                refreshAccounts()
                            }).environmentObject(coordinator)) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                        }
                        
                        Button("Refresh") {
                            refreshAccounts()
                        }
                        .disabled(isLoading || isProcessingPassword)
                    }
                }
            }
            .sheet(isPresented: $showPasswordPrompt) {
                PasswordPromptView(
                    password: $enteredPassword,
                    errorMessage: passwordErrorMessage,  // Pass error message
                    hasLRDWarning: hasLRDFile,  // Pass LRD warning flag
                    isReadOnly: isReadOnly,  // Pass read-only flag
                    onSubmit: { password in
                        passwordErrorMessage = nil  // Clear error on new attempt
                        handlePasswordSubmit(password: password)
                    },
                    onCancel: {
                        showPasswordPrompt = false
                        passwordErrorMessage = nil
                        if accounts.isEmpty {
                            errorMessage = "Password required to access Money file"
                        }
                    }
                )
            }
        }
        .background(ViewControllerResolver { vc in self.presenterVC = vc })
        .onAppear {
            // Refresh accounts when view appears (e.g., navigating back from TransactionsView)
            // Only refresh if we already have accounts loaded (to avoid duplicate initial load)
            if !accounts.isEmpty {
                #if DEBUG
                print("[AccountsView] 🔄 View appeared - refreshing account balances")
                #endif
                loadAccountBalancesOnly()
            }
        }
    }
    
    private func handlePasswordSubmit(password: String) {
        showPasswordPrompt = false
        isProcessingPassword = true
        errorMessage = nil
        
        // Save password to keychain
        do {
            try PasswordStore.shared.save(password: password)
            #if DEBUG
            print("[AccountsView] Password saved to keychain")
            #endif
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Failed to save password: \(error.localizedDescription)"
                self.isProcessingPassword = false
            }
            return
        }
        
        // Load accounts with the new password
        loadAccounts()
    }
    
    private func loadAccounts() {
        if !isProcessingPassword {
            isLoading = true
        }
        errorMessage = nil
        
        OneDriveFileManager.shared.ensureLocalMnyFile(presentingViewController: presenterVC) { url, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.errorMessage = "Failed to get file URL: \(error.localizedDescription)"
                    self.isLoading = false
                    self.isProcessingPassword = false
                    return
                }
                if url == nil {
                    self.errorMessage = "No file selected. Go to OneDrive and pick a .mny file."
                    self.isLoading = false
                    self.isProcessingPassword = false
                    return
                }
                
                // Proceed to decrypt and parse
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        // Use AccountBalanceService to get balances with local transactions
                        let enhancedSummaries = try AccountBalanceService.readAccountSummariesWithLocal()
                        
                        // Map to UIAccount
                        let uiAccounts = enhancedSummaries.map { s in
                            UIAccount(
                                id: s.id,
                                name: s.name,
                                openingBalance: s.beginningBalance,
                                currentBalance: s.currentBalance,
                                hasUnsyncedTransactions: s.hasUnsyncedTransactions,
                                isFavorite: s.isFavorite
                            )
                        }
                        
                        DispatchQueue.main.async {
                            self.accounts = uiAccounts
                            self.isLoading = false
                            self.isProcessingPassword = false
                            
                            #if DEBUG
                            print("[AccountsView] ✅ Successfully loaded \(uiAccounts.count) accounts")
                            let totalUnsynced = uiAccounts.filter { $0.hasUnsyncedTransactions }.count
                            if totalUnsynced > 0 {
                                print("[AccountsView] ⚠️ \(totalUnsynced) accounts have unsynced transactions")
                            }
                            #endif
                        }
                    } catch {
                        DispatchQueue.main.async {
                            // Check if it's a specific password error
                            if let decryptError = error as? MoneyDecryptorBridgeError,
                               decryptError == .badPassword {
                                // Password verification failed - re-prompt immediately
                                self.passwordErrorMessage = "Incorrect password. Please try again."
                                self.enteredPassword = ""  // Clear the wrong password
                                self.showPasswordPrompt = true  // Show prompt again
                                self.isLoading = false
                                self.isProcessingPassword = false
                                
                                #if DEBUG
                                print("[AccountsView] ❌ Password verification failed - re-prompting user")
                                #endif
                            } else {
                                // Other errors - show error screen
                                let errorDesc = error.localizedDescription.lowercased()
                                if errorDesc.contains("password") || errorDesc.contains("decrypt") {
                                    self.errorMessage = "Incorrect password. Please try again."
                                } else {
                                    self.errorMessage = error.localizedDescription
                                }
                                
                                self.isLoading = false
                                self.isProcessingPassword = false
                                
                                #if DEBUG
                                print("[AccountsView] ❌ Error loading accounts: \(error)")
                                #endif
                            }
                        }
                    }
                }
            }
        }
    }

    private func refreshAccounts() {
        isLoading = true
        errorMessage = nil
        
        OneDriveFileManager.shared.refreshLocalMnyFile { url, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.errorMessage = "Failed to refresh file: \(error.localizedDescription)"
                    self.isLoading = false
                } else {
                    // After refresh, check for LRD file again (in case it changed)
                    self.checkForLRDFile()
                    
                    // Check if we have a saved password in keychain
                    if let savedPassword = try? PasswordStore.shared.load() {
                        // Use saved password automatically - no prompt needed
                        #if DEBUG
                        print("[AccountsView] 🔑 Using saved password for automatic reload")
                        #endif
                        self.enteredPassword = savedPassword
                        self.handlePasswordSubmit(password: savedPassword)
                    } else {
                        // No saved password - prompt user
                        #if DEBUG
                        print("[AccountsView] 🔑 No saved password - prompting user")
                        #endif
                        self.showPasswordPrompt = true
                    }
                }
            }
        }
    }
    
    private func changeFile() {
        print("[AccountsView] 🔄 Change file requested")
        
        // Use coordinator to reset back to file selection
        coordinator.requestChangeFile()
    }
    
    private func signOut() {
        print("[AccountsView] 🚪 Sign out requested")
        coordinator.requestSignOut()
    }
    
    private func checkForLRDFile() {
        guard let fileName = OneDriveFileManager.shared.getSavedFileName(),
              let parentFolderId = OneDriveFileManager.shared.getSavedParentFolderId() else {
            return
        }
        
        // Create the .lrd filename
        let lrdFileName = fileName.replacingOccurrences(of: ".mny", with: ".lrd")
        
        // Get token and check for LRD file
        AuthManager.shared.acquireTokenSilent(scopes: ["Files.Read", "Files.ReadWrite"]) { token, error in
            guard let token = token else { return }
            
            OneDriveAPI.listChildren(accessToken: token, folderId: parentFolderId) { result in
                // Note: We can't update hasLRDFile and isReadOnly because they're let properties
                // This check is informational - the actual LRD check happens before navigating here
                #if DEBUG
                switch result {
                case .success(let items):
                    let hasLRD = items.contains(where: { $0.name.lowercased() == lrdFileName.lowercased() })
                    print("[AccountsView] LRD file refresh check: \(hasLRD ? "Found" : "Not found")")
                case .failure(let error):
                    print("[AccountsView] Error checking for LRD file: \(error.localizedDescription)")
                }
                #endif
            }
        }
    }
    
    /// Refresh account balances only (lightweight refresh when returning from detail views)
    private func loadAccountBalancesOnly() {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Use AccountBalanceService to get balances with local transactions
                let enhancedSummaries = try AccountBalanceService.readAccountSummariesWithLocal()
                
                // Map to UIAccount
                let uiAccounts = enhancedSummaries.map { s in
                    UIAccount(
                        id: s.id,
                        name: s.name,
                        openingBalance: s.beginningBalance,
                        currentBalance: s.currentBalance,
                        hasUnsyncedTransactions: s.hasUnsyncedTransactions,
                        isFavorite: s.isFavorite
                    )
                }
                
                DispatchQueue.main.async {
                    self.accounts = uiAccounts
                    
                    #if DEBUG
                    print("[AccountsView] ✅ Refreshed \(uiAccounts.count) account balances")
                    let totalUnsynced = uiAccounts.filter { $0.hasUnsyncedTransactions }.count
                    if totalUnsynced > 0 {
                        print("[AccountsView] ⚠️ \(totalUnsynced) accounts have unsynced transactions")
                    }
                    #endif
                }
            } catch {
                #if DEBUG
                print("[AccountsView] ❌ Error refreshing account balances: \(error)")
                #endif
            }
        }
    }
    
    /// Async version of refresh for pull-to-refresh
    private func refreshAccountsAsync() async {
        await withCheckedContinuation { continuation in
            loadAccountBalancesOnly()
            // Give it a moment to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                continuation.resume()
            }
        }
    }
}

// MARK: - Password Prompt View

struct PasswordPromptView: View {
    @Binding var password: String
    let errorMessage: String?  // Optional error message to display
    let hasLRDWarning: Bool  // NEW: Flag to show .lrd file warning
    let isReadOnly: Bool  // NEW: Flag indicating read-only mode
    let onSubmit: (String) -> Void
    let onCancel: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isPasswordFieldFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Icon
                Image(systemName: errorMessage != nil ? "exclamationmark.triangle.fill" : (hasLRDWarning ? "exclamationmark.lock.fill" : "lock.shield.fill"))
                    .font(.system(size: 60))
                    .foregroundColor(errorMessage != nil ? .red : (hasLRDWarning ? .orange : .blue))
                    .padding(.top, 40)
                
                // Title and description
                VStack(spacing: 8) {
                    Text(errorMessage != nil ? "Incorrect Password" : "Enter File Password")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    } else {
                        Text("This Money file is password-protected.\nEnter your password to decrypt and open it.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                
                // LRD Warning (if applicable)
                if hasLRDWarning {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("File May Be Open on Another Device")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                            
                            if isReadOnly {
                                Text("This file will be opened in read-only mode.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(10)
                    .padding(.horizontal)
                }
                
                // Password field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Password")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    SecureField("Enter password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isPasswordFieldFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            handleSubmit()
                        }
                }
                .padding(.horizontal)
                
                // Info text
                VStack(spacing: 4) {
                    Text("💡 Tip")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                    
                    Text("If your file doesn't have a password, leave this field blank and tap Continue.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                
                Spacer()
                
                // Buttons
                VStack(spacing: 12) {
                    Button {
                        handleSubmit()
                    } label: {
                        Text(isReadOnly ? "Open (Read-Only)" : "Continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isReadOnly ? Color.orange : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    
                    Button("Cancel") {
                        dismiss()
                        onCancel()
                    }
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                        onCancel()
                    }
                }
            }
        }
        .onAppear {
            // Auto-focus the password field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isPasswordFieldFocused = true
            }
        }
    }
    
    private func handleSubmit() {
        dismiss()
        onSubmit(password)
    }
}

struct AccountsView_Previews: PreviewProvider {
    static var previews: some View {
        AccountsView()
    }
}

